package main

import (
	"os"
	"testing"
)

func TestDeploymentModelString(t *testing.T) {
	tests := []struct {
		model DeploymentModel
		want  string
	}{
		{ModelUnknown, "unknown"},
		{ModelGitOps, "gitops"},
		{ModelDirect, "direct"},
	}

	for _, tt := range tests {
		if got := tt.model.String(); got != tt.want {
			t.Errorf("DeploymentModel(%d).String() = %q, want %q", tt.model, got, tt.want)
		}
	}
}

func TestDetectRegistry(t *testing.T) {
	tests := []struct {
		ref  string
		want registryType
	}{
		{"alpine:latest", registryDockerHub},
		{"nginx", registryDockerHub},
		{"ghcr.io/org/app:v1", registryGHCR},
		{"12345.dkr.ecr.us-east-1.amazonaws.com/app:latest", registryECR},
		{"gcr.io/project/app:v1", registryGCR},
		{"localhost:5000/app:latest", registryLocal},
		{"k3d-myregistry.localhost:5000/app:v1", registryLocal},
		{"unknown.registry.io/app:v1", registryGeneric},
	}

	for _, tt := range tests {
		if got := detectRegistry(tt.ref); got != tt.want {
			t.Errorf("detectRegistry(%q) = %d, want %d", tt.ref, got, tt.want)
		}
	}
}

func TestIsInteractive(t *testing.T) {
	// When stdin is not a terminal (e.g. in test runner), isInteractive returns false
	if got := isInteractive(); got {
		t.Error("isInteractive() = true when stdin is not a terminal, want false")
	}
}

func TestCheckBinary(t *testing.T) {
	if err := checkBinary("sh"); err != nil {
		t.Errorf("checkBinary(sh) = %v, want nil", err)
	}
	if err := checkBinary("nonexistent-binary-xyz"); err == nil {
		t.Error("checkBinary(nonexistent-binary-xyz) = nil, want error")
	}
}

func TestRegistryTypeConstants(t *testing.T) {
	if registryDockerHub != 0 {
		t.Errorf("registryDockerHub = %d, want 0", registryDockerHub)
	}
	if registryGHCR != 1 {
		t.Errorf("registryGHCR = %d, want 1", registryGHCR)
	}
	if registryECR != 2 {
		t.Errorf("registryECR = %d, want 2", registryECR)
	}
	if registryGCR != 3 {
		t.Errorf("registryGCR = %d, want 3", registryGCR)
	}
	if registryLocal != 4 {
		t.Errorf("registryLocal = %d, want 4", registryLocal)
	}
}

func TestAuditRecordFields(t *testing.T) {
	rec := AuditRecord{
		ServiceName:      "test-svc",
		Namespace:        "default",
		DeploymentModel:  "gitops",
		Operator:         "tester",
		PreChecksPassed:  true,
		ResourcesRemoved: []string{"deployment", "service"},
		ImageDeleted:     false,
		Status:           "success",
	}

	if rec.ServiceName != "test-svc" {
		t.Errorf("ServiceName = %q, want %q", rec.ServiceName, "test-svc")
	}
	if rec.Namespace != "default" {
		t.Errorf("Namespace = %q, want %q", rec.Namespace, "default")
	}
	if rec.DeploymentModel != "gitops" {
		t.Errorf("DeploymentModel = %q, want %q", rec.DeploymentModel, "gitops")
	}
	if rec.Operator != "tester" {
		t.Errorf("Operator = %q, want %q", rec.Operator, "tester")
	}
	if !rec.PreChecksPassed {
		t.Error("PreChecksPassed = false, want true")
	}
	if len(rec.ResourcesRemoved) != 2 {
		t.Errorf("len(ResourcesRemoved) = %d, want 2", len(rec.ResourcesRemoved))
	}
	if rec.ImageDeleted {
		t.Error("ImageDeleted = true, want false")
	}
	if rec.Status != "success" {
		t.Errorf("Status = %q, want %q", rec.Status, "success")
	}
}

func TestAuditRecordTimestamp(t *testing.T) {
	rec := AuditRecord{ServiceName: "test"}
	if rec.Timestamp != "" {
		t.Errorf("initial Timestamp = %q, want empty", rec.Timestamp)
	}
}

func TestErrorVars(t *testing.T) {
	if ErrServiceNotFound == nil {
		t.Error("ErrServiceNotFound is nil")
	}
	if ErrNoKubectl == nil {
		t.Error("ErrNoKubectl is nil")
	}
	if ErrNoArgoCD == nil {
		t.Error("ErrNoArgoCD is nil")
	}
	if ErrNoGit == nil {
		t.Error("ErrNoGit is nil")
	}
	if ErrPreCheckFailed == nil {
		t.Error("ErrPreCheckFailed is nil")
	}
	if ErrDeletionFailed == nil {
		t.Error("ErrDeletionFailed is nil")
	}
	if ErrRegistryCleanup == nil {
		t.Error("ErrRegistryCleanup is nil")
	}
	if ErrInvalidArgs == nil {
		t.Error("ErrInvalidArgs is nil")
	}
	if ErrActiveTraffic == nil {
		t.Error("ErrActiveTraffic is nil")
	}
	if ErrUncommittedChange == nil {
		t.Error("ErrUncommittedChange is nil")
	}
}

func TestConfigDefaults(t *testing.T) {
	cfg := &Config{
		ServiceName: "test",
		Namespace:   "default",
	}

	if cfg.ServiceName != "test" {
		t.Errorf("ServiceName = %q, want %q", cfg.ServiceName, "test")
	}
	if cfg.Namespace != "default" {
		t.Errorf("Namespace = %q, want %q", cfg.Namespace, "default")
	}
	if cfg.Force {
		t.Error("Force = true, want false")
	}
	if cfg.DryRun {
		t.Error("DryRun = true, want false")
	}
	if cfg.JSON {
		t.Error("JSON = true, want false")
	}
	if cfg.AuditDir != "" {
		t.Errorf("AuditDir = %q, want empty", cfg.AuditDir)
	}
	if cfg.Operator != "" {
		t.Errorf("Operator = %q, want empty", cfg.Operator)
	}
}

func TestWriteAuditYAML(t *testing.T) {
	dir := t.TempDir()
	cfg := &Config{AuditDir: dir, JSON: false, ServiceName: "test-svc"}

	rec := AuditRecord{
		ServiceName:      "test-svc",
		Namespace:        "default",
		DeploymentModel:  "direct",
		Operator:         "test",
		PreChecksPassed:  true,
		ResourcesRemoved: []string{"deployment"},
		ImageDeleted:     false,
		Status:           "success",
	}

	if err := writeAudit(rec, cfg); err != nil {
		t.Fatalf("writeAudit() = %v", err)
	}

	entries, err := os.ReadDir(dir)
	if err != nil {
		t.Fatalf("ReadDir: %v", err)
	}
	if len(entries) != 1 {
		t.Errorf("got %d audit files, want 1", len(entries))
	}
}

func TestWriteAuditJSON(t *testing.T) {
	dir := t.TempDir()
	cfg := &Config{AuditDir: dir, JSON: true, ServiceName: "test-svc"}

	rec := AuditRecord{
		ServiceName:      "test-svc",
		Namespace:        "default",
		DeploymentModel:  "gitops",
		Operator:         "test",
		PreChecksPassed:  true,
		ResourcesRemoved: []string{"deployment", "service"},
		ImageDeleted:     true,
		Status:           "success",
	}

	if err := writeAudit(rec, cfg); err != nil {
		t.Fatalf("writeAudit() = %v", err)
	}

	entries, err := os.ReadDir(dir)
	if err != nil {
		t.Fatalf("ReadDir: %v", err)
	}
	if len(entries) != 1 {
		t.Errorf("got %d audit files, want 1", len(entries))
	}
}

func TestDryRunReturnsResult(t *testing.T) {
	cfg := &Config{
		ServiceName: "test-svc",
		Namespace:   "default",
		DryRun:      true,
		Force:       false,
		Operator:    "test",
	}

	result, err := dryRun(cfg)
	if err != nil {
		t.Fatalf("dryRun() = %v", err)
	}
	if result == nil {
		t.Fatal("dryRun() returned nil result")
	}
	if !result.PreChecksOK {
		t.Error("PreChecksOK = false, want true")
	}
}
