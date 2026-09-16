package main

import (
	"encoding/json"
	"fmt"
	"os/exec"
	"strings"
)

func detectModel(serviceName string) (DeploymentModel, error) {
	cmd := exec.Command("kubectl", "get", "application", serviceName, "-n", "argocd", "--no-headers")
	out, err := cmd.Output()
	if err != nil {
		return ModelDirect, nil
	}
	if len(out) > 0 {
		return ModelGitOps, nil
	}
	return ModelDirect, nil
}

func getArgoCDApplicationByPath(path string) (string, error) {
	cmd := exec.Command("kubectl", "get", "applications", "-n", "argocd", "-o", "json")
	out, err := cmd.Output()
	if err != nil {
		return "", fmt.Errorf("cannot list ArgoCD applications: %w", err)
	}

	var al applicationList
	if err := json.Unmarshal(out, &al); err != nil {
		return "", fmt.Errorf("parse application list: %w", err)
	}

	for _, item := range al.Items {
		if item.Spec.Source.Path == path {
			return item.Metadata.Name, nil
		}
	}

	return "", fmt.Errorf("no application found with source path %s", path)
}

func getArgoCDSource(serviceName string) (repoURL, path string, err error) {
	cmd := exec.Command("kubectl", "get", "application", serviceName, "-n", "argocd", "-o", "jsonpath={.spec.source.repoURL}")
	out, err := cmd.Output()
	if err != nil {
		return "", "", err
	}
	repoURL = strings.TrimSpace(string(out))

	cmd = exec.Command("kubectl", "get", "application", serviceName, "-n", "argocd", "-o", "jsonpath={.spec.source.path}")
	out, err = cmd.Output()
	if err != nil {
		return "", "", err
	}
	path = strings.TrimSpace(string(out))

	return repoURL, path, nil
}

func hasPruneEnabled(serviceName string) (bool, error) {
	cmd := exec.Command("kubectl", "get", "application", serviceName, "-n", "argocd", "-o", "jsonpath={.spec.syncPolicy.automated.prune}")
	out, err := cmd.Output()
	if err != nil {
		return false, err
	}
	return strings.TrimSpace(string(out)) == "true", nil
}
