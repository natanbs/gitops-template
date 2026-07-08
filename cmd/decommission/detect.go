package main

import (
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
