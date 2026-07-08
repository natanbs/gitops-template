package main

import (
	"fmt"
	"os"
	"os/exec"
	"strings"
)

type directDecommissioner struct {
	cfg *Config
}

func (d *directDecommissioner) run() (removed []string, imageRef string, err error) {
	return deleteResourcesDirectly(d.cfg.ServiceName, d.cfg.Namespace, d.cfg.Force)
}

func deleteResourcesDirectly(serviceName, namespace string, force bool) (removed []string, imageRef string, err error) {
	imageRef, err = getImageRef(serviceName, namespace)
	if err != nil {
		return nil, "", fmt.Errorf("get image ref: %w", err)
	}

	resTypes := []string{"deployment", "service", "ingress", "configmap", "secret"}
	for _, rt := range resTypes {
		exists, _ := resourceExists(rt, serviceName, namespace)
		if !exists {
			continue
		}
		fmt.Printf("  → Deleting %s/%s (ns=%s)\n", rt, serviceName, namespace)
		if err := deleteK8sResource(rt, serviceName, namespace, force); err != nil {
			return nil, "", fmt.Errorf("%w: delete %s: %s", ErrDeletionFailed, rt, err)
		}
		removed = append(removed, rt)
	}

	return removed, imageRef, nil
}

func getImageRef(serviceName, namespace string) (string, error) {
	cmd := exec.Command("kubectl", "get", "deployment", serviceName,
		"-n", namespace,
		"-o", "jsonpath={.spec.template.spec.containers[0].image}")
	out, err := cmd.Output()
	if err != nil {
		return "", nil
	}
	return strings.TrimSpace(string(out)), nil
}

func deleteK8sResource(kind, name, namespace string, force bool) error {
	args := []string{"delete", kind, name, "-n", namespace, "--ignore-not-found"}
	if force {
		args = append(args, "--grace-period=0", "--force")
	}
	cmd := exec.Command("kubectl", args...)
	cmd.Stderr = os.Stderr
	return cmd.Run()
}

func (d *directDecommissioner) getImageRef() (string, error) {
	return getImageRef(d.cfg.ServiceName, d.cfg.Namespace)
}

func (d *directDecommissioner) resourceExists(rt string) (bool, error) {
	return resourceExists(rt, d.cfg.ServiceName, d.cfg.Namespace)
}

func (d *directDecommissioner) deleteResource(rt string) error {
	return deleteK8sResource(rt, d.cfg.ServiceName, d.cfg.Namespace, d.cfg.Force)
}
