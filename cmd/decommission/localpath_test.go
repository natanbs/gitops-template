package main

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

func TestNormalizeSuffix(t *testing.T) {
	tests := []struct {
		in   string
		want string
	}{
		{"apps/my-svc", "apps/my-svc"},
		{"apps/my-svc/", "apps/my-svc"},
		{"git@github.com:org/repo.git", "git@github.com:org/repo"},
		{"https://github.com/org/repo.git", "https://github.com/org/repo"},
		{"https://github.com/org/repo", "https://github.com/org/repo"},
	}
	for _, tt := range tests {
		if got := normalizeSuffix(tt.in); got != tt.want {
			t.Errorf("normalizeSuffix(%q) = %q, want %q", tt.in, got, tt.want)
		}
	}
}

func TestPathMatchesFragment(t *testing.T) {
	tests := []struct {
		path string
		frag string
		want bool
	}{
		{"apps/my-svc", "apps/my-svc", true},
		{"apps/my-svc", "my-svc", true},
		{"apps/other", "my-svc", false},
		{"apps/my-services", "svc", false},
	}
	for _, tt := range tests {
		if got := pathMatchesFragment(tt.path, tt.frag); got != tt.want {
			t.Errorf("pathMatchesFragment(%q, %q) = %v, want %v", tt.path, tt.frag, got, tt.want)
		}
	}
}

func TestResolveLocalPathNonRepo(t *testing.T) {
	if _, err := exec.LookPath("git"); err != nil {
		t.Skip("git not available")
	}

	dir := t.TempDir()
	nonRepo := filepath.Join(dir, "not-a-repo")
	if err := os.MkdirAll(nonRepo, 0o755); err != nil {
		t.Fatalf("mkdir: %v", err)
	}

	t.Setenv("GIT_CEILING_DIRECTORIES", filepath.Clean(os.TempDir()))
	if _, err := resolveLocalPath(nonRepo); err == nil {
		t.Error("resolveLocalPath on a non-git path = nil, want error")
	}
}

func TestResolveLocalPathGitCheckout(t *testing.T) {
	if _, err := exec.LookPath("git"); err != nil {
		t.Skip("git not available")
	}

	gp := "git"
	base := t.TempDir()

	if out, err := exec.Command(gp, "-C", base, "init", "-q").CombinedOutput(); err != nil {
		t.Fatalf("git init: %s", out)
	}
	err := os.WriteFile(filepath.Join(base, "README.md"), []byte("x"), 0o644)
	if err != nil {
		t.Fatalf("write README: %v", err)
	}
	if out, err := exec.Command(gp, "-C", base, "add", ".").CombinedOutput(); err != nil {
		t.Fatalf("git add: %s", out)
	}
	if out, err := exec.Command(gp, "-C", base, "commit", "-q", "-m", "init").CombinedOutput(); err != nil {
		t.Fatalf("git commit: %s", out)
	}

	wt := filepath.Join(t.TempDir(), "wt")
	out, err := exec.Command(gp, "-C", base, "worktree", "add", "-q", "--detach", wt).CombinedOutput()
	if err != nil {
		t.Fatalf("git worktree add: %s", out)
	}

	sub := filepath.Join(wt, "apps", "my-svc")
	if err := os.MkdirAll(sub, 0o755); err != nil {
		t.Fatalf("mkdir: %v", err)
	}

	t.Setenv("GIT_CEILING_DIRECTORIES", filepath.Clean(os.TempDir()))
	loc, err := resolveLocalPath(sub)
	if err != nil {
		t.Fatalf("resolveLocalPath(%s) = %v", sub, err)
	}
	if !strings.HasSuffix(loc.Fragment, "apps/my-svc") {
		t.Errorf("Fragment = %q, want suffix %q", loc.Fragment, "apps/my-svc")
	}
	if loc.ServiceName != "my-svc" {
		t.Errorf("ServiceName = %q, want %q", loc.ServiceName, "my-svc")
	}

	rootLoc, err := resolveLocalPath(wt)
	if err != nil {
		t.Fatalf("resolveLocalPath(worktree root) = %v", err)
	}
	if !strings.HasSuffix(rootLoc.Fragment, "wt") {
		t.Errorf("repo-root Fragment = %q, want to end with %q", rootLoc.Fragment, "wt")
	}
}