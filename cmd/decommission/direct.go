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
	svc := d.cfg.ServiceName
	ns := d.cfg.Namespace

	imageRef, err = d.getImageRef()
	if err != nil {
		return nil, "", fmt.Errorf("get image ref: %w", err)
	}

	resTypes := []string{"deployment", "service", "ingress", "configmap", "secret"}
	for _, rt := range resTypes {
		exists, _ := d.resourceExists(rt)
		if !exists {
			continue
		}
		fmt.Printf("  → Deleting %s/%s (ns=%s)\n", rt, svc, ns)
		if err := d.deleteResource(rt); err != nil {
			return nil, "", fmt.Errorf("%w: delete %s: %s", ErrDeletionFailed, rt, err)
		}
		removed = append(removed, rt)
	}

	return removed, imageRef, nil
}

func (d *directDecommissioner) getImageRef() (string, error) {
	cmd := exec.Command("kubectl", "get", "deployment", d.cfg.ServiceName,
		"-n", d.cfg.Namespace,
		"-o", "jsonpath={.spec.template.spec.containers[0].image}")
	out, err := cmd.Output()
	if err != nil {
		return "", nil
	}
	return strings.TrimSpace(string(out)), nil
}

func (d *directDecommissioner) resourceExists(rt string) (bool, error) {
	cmd := exec.Command("kubectl", "get", rt, d.cfg.ServiceName, "-n", d.cfg.Namespace, "--no-headers")
	out, err := cmd.Output()
	if err != nil {
		return false, nil
	}
	return len(out) > 0, nil
}

func (d *directDecommissioner) deleteResource(rt string) error {
	args := []string{"delete", rt, d.cfg.ServiceName, "-n", d.cfg.Namespace, "--ignore-not-found"}
	if d.cfg.Force {
		args = append(args, "--grace-period=0", "--force")
	}
	cmd := exec.Command("kubectl", args...)
	cmd.Stderr = os.Stderr
	return cmd.Run()
}
