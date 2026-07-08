package main

import (
	"fmt"
	"os/exec"
	"strings"
)

type discoveredResource struct {
	Kind      string
	Name      string
	Namespace string
}

func dryRun(cfg *Config) (*runResult, error) {
	fmt.Printf("── Dry-run: decommission %s (ns=%s) ──\n", cfg.ServiceName, cfg.Namespace)

	model, err := detectModel(cfg.ServiceName)
	if err != nil {
		fmt.Printf("  ! Model detection failed: %v\n", err)
		model = ModelUnknown
	}

	fmt.Printf("  Service:        %s\n", cfg.ServiceName)
	fmt.Printf("  Namespace:      %s\n", cfg.Namespace)
	fmt.Printf("  Model:          %s\n", model)
	fmt.Printf("  Force:          %v\n", cfg.Force)
	fmt.Printf("  Operator:       %s\n", cfg.Operator)
	fmt.Printf("  Audit output:   %s\n", cfg.AuditDir)

	resources := discoverResources(cfg.ServiceName, cfg.Namespace)
	fmt.Printf("\n  Resources to delete (%d):\n", len(resources))
	if len(resources) == 0 {
		fmt.Println("    (none found)")
	} else {
		for _, r := range resources {
			fmt.Printf("    • %s/%s (ns=%s)\n", r.Kind, r.Name, r.Namespace)
		}
	}

	imageRef := getImageRefForDryRun(cfg.ServiceName, cfg.Namespace)
	if imageRef != "" {
		repo := imageRef
		if idx := strings.LastIndex(imageRef, ":"); idx >= 0 {
			repo = imageRef[:idx]
		}
		fmt.Printf("  Container image: %s (all tags)\n", repo)
	}

	switch model {
	case ModelGitOps:
		repo, path, err := getArgoCDSource(cfg.ServiceName)
		if err != nil {
			fmt.Printf("\n  ArgoCD source: (unavailable: %v)\n", err)
		} else {
			fmt.Printf("\n  ArgoCD source:\n")
			fmt.Printf("    Repo:  %s\n", repo)
			fmt.Printf("    Path:  %s\n", path)
		}
	case ModelDirect:
	default:
	}

	if !cfg.Force {
		fmt.Println("\n  Pre-checks that would run:")
		fmt.Println("    • Validate kubectl is available")
		fmt.Println("    • Validate git is available")
		if model == ModelGitOps {
			fmt.Println("    • Validate argocd CLI is available")
		}
		fmt.Println("    • Confirm service exists in cluster")
		fmt.Println("    • Check for active connections/traffic")
	}

	fmt.Println("\n  Audit record would be written with status: dry-run")
	fmt.Println("── Dry-run complete (no changes made) ──")

	return &runResult{
		Model:        model.String(),
		PreChecksOK:  true,
		Removed:      nil,
		ImageDeleted: false,
	}, nil
}

func discoverResources(name, namespace string) []discoveredResource {
	kinds := []string{"deployment", "service", "ingress", "configmap", "secret"}
	var resources []discoveredResource
	for _, kind := range kinds {
		exists, _ := resourceExists(kind, name, namespace)
		if exists {
			resources = append(resources, discoveredResource{Kind: kind, Name: name, Namespace: namespace})
		}
	}

	pvcs := discoverPVCs(name, namespace)
	resources = append(resources, pvcs...)

	return resources
}

func resourceExists(kind, name, namespace string) (bool, error) {
	cmd := exec.Command("kubectl", "get", kind, name, "-n", namespace, "--no-headers")
	out, err := cmd.Output()
	if err != nil {
		return false, nil
	}
	return len(out) > 0, nil
}

func discoverPVCs(name, namespace string) []discoveredResource {
	cmd := exec.Command("kubectl", "get", "pvc", "-n", namespace, "-o", "name")
	out, err := cmd.Output()
	if err != nil {
		return nil
	}
	var resources []discoveredResource
	for _, line := range strings.Split(string(out), "\n") {
		line = strings.TrimSpace(line)
		if strings.Contains(line, name) {
			resources = append(resources, discoveredResource{
				Kind:      "persistentvolumeclaim",
				Name:      strings.TrimPrefix(line, "persistentvolumeclaim/"),
				Namespace: namespace,
			})
		}
	}
	return resources
}

func getImageRefForDryRun(name, namespace string) string {
	cmd := exec.Command("kubectl", "get", "deployment", name,
		"-n", namespace,
		"-o", "jsonpath={.spec.template.spec.containers[0].image}")
	out, err := cmd.Output()
	if err != nil {
		return ""
	}
	return strings.TrimSpace(string(out))
}
