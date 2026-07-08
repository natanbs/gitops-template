package main

import (
	"fmt"
	"os"
	"os/exec"
	"strings"
)

type registryType int

const (
	registryDockerHub registryType = iota
	registryGHCR
	registryECR
	registryGCR
	registryLocal
	registryGeneric
)

func detectRegistry(imageRef string) registryType {
	switch {
	case strings.Contains(imageRef, "ghcr.io"):
		return registryGHCR
	case strings.Contains(imageRef, "amazonaws.com") || strings.Contains(imageRef, "dkr.ecr"):
		return registryECR
	case strings.Contains(imageRef, "gcr.io") || strings.Contains(imageRef, "pkg.dev"):
		return registryGCR
	case strings.HasPrefix(imageRef, "localhost:") || strings.Contains(imageRef, "k3d"):
		return registryLocal
	case !strings.Contains(imageRef, "."):
		return registryDockerHub
	default:
		return registryGeneric
	}
}

func deleteImage(imageRef string, cfg *Config) error {
	rt := detectRegistry(imageRef)

	switch rt {
	case registryDockerHub:
		return execDockerDelete(imageRef)
	case registryGHCR:
		return execGHCRDelete(imageRef)
	case registryECR:
		return execECRDelete(imageRef)
	case registryGCR:
		return execGCRDelete(imageRef)
	case registryLocal:
		return execLocalDelete(imageRef)
	default:
		return fmt.Errorf("%w: no CLI available for registry type %s; delete manually via web UI", ErrRegistryCleanup, imageRef)
	}
}

func execDockerDelete(imageRef string) error {
	cmd := exec.Command("docker", "rmi", imageRef)
	if out, err := cmd.CombinedOutput(); err != nil {
		return fmt.Errorf("%w: docker rmi: %s", ErrRegistryCleanup, strings.TrimSpace(string(out)))
	}
	return nil
}

func execGHCRDelete(imageRef string) error {
	parts := strings.SplitN(imageRef, "/", 3)
	if len(parts) < 3 {
		return fmt.Errorf("%w: invalid GHCR reference: %s", ErrRegistryCleanup, imageRef)
	}
	cmd := exec.Command("gh", "api", "-X", "DELETE", fmt.Sprintf("/user/packages/container/%s/versions", strings.TrimSuffix(parts[2], ":latest")))
	if out, err := cmd.CombinedOutput(); err != nil {
		return fmt.Errorf("%w: gh api delete: %s", ErrRegistryCleanup, strings.TrimSpace(string(out)))
	}
	return nil
}

func execECRDelete(imageRef string) error {
	parts := strings.SplitN(imageRef, "/", 2)
	if len(parts) < 2 {
		return fmt.Errorf("%w: invalid ECR reference: %s", ErrRegistryCleanup, imageRef)
	}
	repoName := strings.Split(parts[1], ":")[0]
	tag := "latest"
	if t := strings.Split(parts[1], ":"); len(t) > 1 {
		tag = t[1]
	}

	cmd := exec.Command("aws", "ecr", "batch-delete-image",
		"--repository-name", repoName,
		"--image-ids", fmt.Sprintf("imageTag=%s", tag))
	if out, err := cmd.CombinedOutput(); err != nil {
		return fmt.Errorf("%w: aws ecr batch-delete-image: %s", ErrRegistryCleanup, strings.TrimSpace(string(out)))
	}
	return nil
}

func execGCRDelete(imageRef string) error {
	cmd := exec.Command("gcloud", "container", "images", "delete", imageRef, "--quiet")
	if out, err := cmd.CombinedOutput(); err != nil {
		return fmt.Errorf("%w: gcloud container images delete: %s", ErrRegistryCleanup, strings.TrimSpace(string(out)))
	}
	return nil
}

func execLocalDelete(imageRef string) error {
	repo := imageRef
	if idx := strings.Index(repo, "/"); idx >= 0 {
		repo = repo[idx+1:]
	}
	if idx := strings.LastIndex(repo, ":"); idx >= 0 {
		repo = repo[:idx]
	}

	container := findRegistryContainer()
	if container == "" {
		return fmt.Errorf("%w: no registry container (k3d-reg or *registry*) found running; delete manually", ErrRegistryCleanup)
	}

	tagDir := fmt.Sprintf("/var/lib/registry/docker/registry/v2/repositories/%s/_manifests/tags", repo)
	out, err := exec.Command("docker", "exec", container, "ls", tagDir).Output()
	if err != nil {
		return fmt.Errorf("%w: cannot list tags in registry container: %s", ErrRegistryCleanup, strings.TrimSpace(string(out)))
	}

	tags := strings.Fields(string(out))
	if len(tags) == 0 {
		return nil
	}

	for _, tag := range tags {
		tagPath := fmt.Sprintf("%s/%s", tagDir, tag)
		rmCmd := exec.Command("docker", "exec", container, "rm", "-rf", tagPath)
		if rOut, rErr := rmCmd.CombinedOutput(); rErr != nil {
			fmt.Fprintf(os.Stderr, "  Warning: failed to delete tag %s: %s\n", tag, strings.TrimSpace(string(rOut)))
		} else {
			fmt.Printf("  → Deleted tag %s:%s\n", repo, tag)
		}
	}

	repoDir := fmt.Sprintf("/var/lib/registry/docker/registry/v2/repositories/%s", repo)
	exec.Command("docker", "exec", container, "rm", "-rf", repoDir).Run()

	return nil
}

func findRegistryContainer() string {
	cmd := exec.Command("docker", "ps", "--format", "{{.Names}}")
	out, err := cmd.Output()
	if err != nil {
		return ""
	}
	for _, name := range strings.Fields(string(out)) {
		if strings.Contains(name, "registry") || strings.Contains(name, "-reg") || strings.Contains(name, "-registry") {
			return name
		}
	}
	return ""
}
