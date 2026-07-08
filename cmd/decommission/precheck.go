package main

import (
	"fmt"
	"os/exec"
	"strings"
)

type preCheckResult struct {
	KubectlOK    bool
	GitOK        bool
	ArgoCDOK     bool
	ServiceFound bool
	TrafficOK    bool
}

func runPreChecks(cfg *Config) (*preCheckResult, error) {
	res := &preCheckResult{}

	if err := checkBinary("kubectl"); err != nil {
		return nil, fmt.Errorf("%w: kubectl not found on PATH", ErrNoKubectl)
	}
	res.KubectlOK = true

	if err := checkKubectlContext(); err != nil {
		return nil, fmt.Errorf("%w: %v", ErrPreCheckFailed, err)
	}

	if err := checkBinary("git"); err != nil {
		return nil, fmt.Errorf("%w: git not found on PATH", ErrNoGit)
	}
	res.GitOK = true

	model, _ := detectModel(cfg.ServiceName)
	if model == ModelGitOps {
		if err := checkBinary("argocd"); err != nil {
			return nil, fmt.Errorf("%w: argocd CLI not found on PATH (required for GitOps services)", ErrNoArgoCD)
		}
		res.ArgoCDOK = true
	}

	if err := checkDeletePermissions(cfg.Namespace); err != nil {
		fmt.Printf("  Warning: permission check: %v\n", err)
	}

	found, err := serviceExists(cfg.ServiceName, cfg.Namespace)
	if err != nil {
		return nil, fmt.Errorf("cannot verify service existence: %w", err)
	}
	if !found {
		return nil, fmt.Errorf("%w: service %q not found in namespace %q", ErrServiceNotFound, cfg.ServiceName, cfg.Namespace)
	}
	res.ServiceFound = true

	trafficOK, err := checkTraffic(cfg.ServiceName, cfg.Namespace)
	if err != nil {
		fmt.Printf("  Warning: traffic check failed: %v\n", err)
	} else if !trafficOK {
		return nil, fmt.Errorf("%w: service %q has active connections; use --force to bypass", ErrActiveTraffic, cfg.ServiceName)
	}
	res.TrafficOK = trafficOK

	return res, nil
}

func checkBinary(name string) error {
	_, err := exec.LookPath(name)
	return err
}

func checkDeletePermissions(namespace string) error {
	resources := []string{"deployments", "services", "ingresses", "configmaps", "secrets", "persistentvolumeclaims"}
	for _, r := range resources {
		cmd := exec.Command("kubectl", "auth", "can-i", "delete", r, "-n", namespace)
		out, err := cmd.Output()
		if err != nil {
			return fmt.Errorf("cannot check permission for %s: %w", r, err)
		}
		if strings.TrimSpace(string(out)) != "yes" {
			return fmt.Errorf("missing permission to delete %s in namespace %s", r, namespace)
		}
	}

	cmd := exec.Command("kubectl", "auth", "can-i", "delete", "application", "-n", "argocd")
	out, err := cmd.Output()
	if err == nil && strings.TrimSpace(string(out)) == "yes" {
		return nil
	}

	return nil
}

func checkKubectlContext() error {
	cmd := exec.Command("kubectl", "config", "current-context")
	out, err := cmd.Output()
	if err != nil {
		return fmt.Errorf("kubectl config current-context failed: is KUBECONFIG set and pointing to a valid cluster?")
	}
	if len(out) == 0 {
		return fmt.Errorf("kubectl context is empty; set a context with: kubectl config use-context <name>")
	}

	cmd2 := exec.Command("kubectl", "cluster-info", "--request-timeout", "5s")
	if err := cmd2.Run(); err != nil {
		return fmt.Errorf("kubectl cluster-info failed: cannot reach cluster (context: %s)", strings.TrimSpace(string(out)))
	}

	return nil
}

func serviceExists(name, namespace string) (bool, error) {
	cmd := exec.Command("kubectl", "get", "deployment", name, "-n", namespace, "--no-headers")
	out, err := cmd.Output()
	if err != nil {
		return false, nil
	}
	return len(out) > 0, nil
}

func checkTraffic(name, namespace string) (bool, error) {
	cmd := exec.Command("kubectl", "get", "endpoints", name, "-n", namespace, "-o", "jsonpath={.subsets[*].addresses[*].ip}")
	out, err := cmd.Output()
	if err != nil {
		return false, fmt.Errorf("check endpoints: %w", err)
	}
	return len(out) == 0, nil
}

func checkActiveConnections(name, namespace string) (int, error) {
	cmd := exec.Command("kubectl", "get", "endpoints", name, "-n", namespace, "-o", "jsonpath={.subsets[*].addresses[*].ip}")
	out, err := cmd.Output()
	if err != nil {
		return 0, nil
	}
	if len(out) == 0 {
		return 0, nil
	}
	return 1, nil
}
