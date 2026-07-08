package main

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"time"
)

type gitopsDecommissioner struct {
	cfg       *Config
	repoURL   string
	manifests string
	tmpDir    string
}

func (g *gitopsDecommissioner) run() ([]string, error) {
	var removed []string
	var err error

	g.repoURL, g.manifests, err = getArgoCDSource(g.cfg.ServiceName)
	if err != nil {
		return nil, fmt.Errorf("get ArgoCD source: %w", err)
	}

	g.tmpDir, err = os.MkdirTemp("", "decommission-"+g.cfg.ServiceName+"-*")
	if err != nil {
		return nil, fmt.Errorf("create temp dir: %w", err)
	}
	defer os.RemoveAll(g.tmpDir)

	fmt.Printf("  → Cloning repo: %s\n", g.repoURL)
	if err := g.clone(); err != nil {
		return nil, err
	}

	fmt.Printf("  → Removing manifests from %s/\n", g.manifests)
	if err := g.removeManifests(); err != nil {
		return nil, err
	}

	hasChanges, _ := g.hasChanges()
	if hasChanges {
		fmt.Println("  → Committing and pushing")
		if err := g.commitAndPush(); err != nil {
			return nil, err
		}

		fmt.Println("  → Waiting for ArgoCD to prune resources")
		if err := g.waitForPrune(); err != nil {
			return nil, err
		}
	} else {
		fmt.Println("  → No changes to commit (manifests already removed)")
	}

	fmt.Println("  → Deleting ArgoCD Application")
	if err := g.deleteApplication(); err != nil {
		return nil, fmt.Errorf("delete ArgoCD Application: %w", err)
	}

	removed = append(removed, "Deployment", "Service", "Ingress", "ConfigMap", "Secret", "ArgoCD Application")

	return removed, nil
}

func (g *gitopsDecommissioner) clone() error {
	cloneDir := filepath.Join(g.tmpDir, "repo")
	cmd := exec.Command("git", "clone", g.repoURL, cloneDir)
	cmd.Stdout = nil
	cmd.Stderr = os.Stderr
	if err := cmd.Run(); err != nil {
		return fmt.Errorf("git clone: %w", err)
	}
	g.tmpDir = cloneDir
	return nil
}

func (g *gitopsDecommissioner) removeManifests() error {
	manDir := filepath.Join(g.tmpDir, g.manifests)

	dirents, err := os.ReadDir(manDir)
	if err != nil {
		if os.IsNotExist(err) {
			return nil
		}
		return fmt.Errorf("read manifests dir: %w", err)
	}

	for _, entry := range dirents {
		if entry.IsDir() {
			continue
		}
		path := filepath.Join(manDir, entry.Name())
		if err := os.Remove(path); err != nil {
			return fmt.Errorf("remove %s: %w", path, err)
		}
	}

	return nil
}

func (g *gitopsDecommissioner) hasChanges() (bool, error) {
	cmd := exec.Command("git", "-C", g.tmpDir, "status", "--porcelain")
	out, err := cmd.Output()
	if err != nil {
		return false, fmt.Errorf("git status: %w", err)
	}
	return len(out) > 0, nil
}

func (g *gitopsDecommissioner) stageChanges() error {
	cmd := exec.Command("git", "-C", g.tmpDir, "add", "-A")
	cmd.Stderr = os.Stderr
	return cmd.Run()
}

func (g *gitopsDecommissioner) commitAndPush() error {
	msg := fmt.Sprintf("decommission: remove manifests for %s", g.cfg.ServiceName)

	if err := g.stageChanges(); err != nil {
		return fmt.Errorf("git add: %w", err)
	}

	commitCmd := exec.Command("git", "-C", g.tmpDir, "commit", "-m", msg)
	commitCmd.Stderr = os.Stderr
	if err := commitCmd.Run(); err != nil {
		return fmt.Errorf("git commit: %w", err)
	}

	pushCmd := exec.Command("git", "-C", g.tmpDir, "push")
	pushCmd.Stderr = os.Stderr
	if err := pushCmd.Run(); err != nil {
		return fmt.Errorf("git push: %w", err)
	}

	return nil
}

func (g *gitopsDecommissioner) deleteApplication() error {
	cmd := exec.Command("argocd", "app", "delete", g.cfg.ServiceName)
	cmd.Stderr = os.Stderr
	if err := cmd.Run(); err != nil {
		cmd2 := exec.Command("kubectl", "delete", "application", g.cfg.ServiceName, "-n", "argocd", "--ignore-not-found")
		cmd2.Stderr = os.Stderr
		if err2 := cmd2.Run(); err2 != nil {
			return fmt.Errorf("argocd app delete failed (%w) and kubectl delete also failed (%w)", err, err2)
		}
	}
	return nil
}

func (g *gitopsDecommissioner) waitForPrune() error {
	timeout := 5 * time.Minute
	interval := 15 * time.Second
	start := time.Now()

	for time.Since(start) < timeout {
		cmd := exec.Command("argocd", "app", "get", g.cfg.ServiceName, "-o", "json")
		out, err := cmd.Output()
		if err != nil {
			return nil
		}
		_ = out
		time.Sleep(interval)
	}

	fmt.Println("  → Timed out waiting for ArgoCD prune; check status manually with:")
	fmt.Printf("    argocd app get %s\n", g.cfg.ServiceName)
	return nil
}
