package main

import (
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
)

type serviceLocator struct {
	Fragment    string
	ServiceName string
	RepoURL     string
}

func gitToplevel(path string) (string, error) {
	cmd := exec.Command("git", "-C", path, "rev-parse", "--show-toplevel")
	out, err := cmd.Output()
	if err != nil {
		return "", err
	}
	return strings.TrimSpace(string(out)), nil
}

func gitOriginURL(path string) string {
	cmd := exec.Command("git", "-C", path, "config", "--get", "remote.origin.url")
	out, err := cmd.Output()
	if err != nil {
		return ""
	}
	return strings.TrimSpace(string(out))
}

func resolveLocalPath(localPath string) (*serviceLocator, error) {
	abs, err := filepath.Abs(localPath)
	if err != nil {
		return nil, fmt.Errorf("resolve path %s: %w", localPath, err)
	}

	if _, err := os.Stat(abs); err != nil {
		return nil, fmt.Errorf("local path does not exist: %s", abs)
	}

	top, err := gitToplevel(abs)
	if err != nil {
		return nil, fmt.Errorf("%s is not inside a git repository (local repo path required)", abs)
	}

	rel, err := filepath.Rel(top, abs)
	if err != nil {
		return nil, fmt.Errorf("compute repo-relative path: %w", err)
	}

	loc := &serviceLocator{
		ServiceName: filepath.Base(abs),
		RepoURL:     gitOriginURL(abs),
	}

	rel = filepath.ToSlash(rel)
	if rel == "." {
		loc.Fragment = loc.ServiceName
	} else {
		loc.Fragment = rel
	}

	return loc, nil
}

func resolveLocalPathToService(localPath string) (*serviceLocator, string, bool, error) {
	loc, err := resolveLocalPath(localPath)
	if err != nil {
		return nil, "", false, err
	}

	appName, found := matchApplication(loc)
	return loc, appName, found, nil
}

func matchApplication(loc *serviceLocator) (string, bool) {
	apps := listArgoCDApplications()

	frag := normalizeSuffix(loc.Fragment)
	repo := normalizeSuffix(loc.RepoURL)

	best := ""
	bestScore := -1
	for _, app := range apps {
		if !matchesRepo(repo, app.RepoURL) {
			continue
		}
		for _, p := range app.Paths {
			if p == "" {
				continue
			}
			if pathMatchesFragment(p, frag) {
				if s := matchScore(p, frag); s > bestScore {
					bestScore = s
					best = app.Name
				}
			}
		}
	}

	return best, best != ""
}

func matchesRepo(repo, other string) bool {
	if repo == "" {
		return true
	}
	return repo == normalizeSuffix(other)
}

func pathMatchesFragment(path, frag string) bool {
	if path == frag {
		return true
	}
	if !strings.HasSuffix(path, frag) {
		return false
	}
	return len(path) > len(frag) && path[len(path)-len(frag)-1] == '/'
}

func matchScore(path, frag string) int {
	if path == frag {
		return 2
	}
	return 1
}

func normalizeSuffix(s string) string {
	s = strings.TrimSuffix(s, "/")
	s = strings.TrimSuffix(s, ".git")
	return s
}

func listArgoCDApplications() []argoApp {
	cmd := exec.Command("kubectl", "get", "applications", "-n", "argocd", "-o", "json")
	out, err := cmd.Output()
	if err != nil {
		return nil
	}

	var al applicationList
	if err := json.Unmarshal(out, &al); err != nil {
		return nil
	}

	apps := make([]argoApp, 0, len(al.Items))
	for _, item := range al.Items {
		apps = append(apps, argoApp{
			Name:    item.Metadata.Name,
			Paths:   []string{item.Spec.Source.Path},
			RepoURL: item.Spec.Source.RepoURL,
		})
	}
	return apps
}

type argoApp struct {
	Name    string
	Paths   []string
	RepoURL string
}