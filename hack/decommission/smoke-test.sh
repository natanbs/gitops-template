#!/usr/bin/env bash
set -euo pipefail

# End-to-end validation script for decommission CLI
# Requires: Go 1.22+, kubectl, k3d cluster, git, (argocd for GitOps path)
#
# Usage:
#   ./hack/decommission/test-gitops.sh    # GitOps decommission path
#   ./hack/decommission/test-direct.sh    # Direct Deploy decommission path

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
DECOMMISSION_BIN="${REPO_ROOT}/bin/decommission"
NAMESPACE="${NAMESPACE:-decom-test}"
SERVICE_NAME="${SERVICE_NAME:-decom-test-svc}"

info()  { printf "\033[36m[INFO]\033[0m %s\n" "$*"; }
pass()  { printf "\033[32m[PASS]\033[0m %s\n" "$*"; }
fail()  { printf "\033[31m[FAIL]\033[0m %s\n" "$*"; exit 1; }

check_prereqs() {
  for cmd in go kubectl git; do
    command -v "$cmd" >/dev/null 2>&1 || fail "$cmd not found on PATH"
  done
}

build_cli() {
  info "Building decommission CLI..."
  cd "$REPO_ROOT" && go build -o "$DECOMMISSION_BIN" ./cmd/decommission/
  pass "CLI built at $DECOMMISSION_BIN"
}

setup_namespace() {
  info "Creating test namespace: $NAMESPACE"
  kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
}

cleanup() {
  info "Cleaning up test namespace: $NAMESPACE"
  kubectl delete namespace "$NAMESPACE" --ignore-not-found --wait=false
}

test_help() {
  info "Test: --help flag"
  "$DECOMMISSION_BIN" --help 2>&1 | grep -q "Usage: decommission" || fail "help text missing"
  pass "--help"
}

test_version() {
  info "Test: --version flag"
  "$DECOMMISSION_BIN" --version 2>&1 | grep -q "decommission version" || fail "version text missing"
  pass "--version"
}

test_missing_service() {
  info "Test: service not found (no --force)"
  output=$("$DECOMMISSION_BIN" "nonexistent-svc-xyz" --namespace "$NAMESPACE" 2>&1 || true)
  echo "$output" | grep -qi "not found" || fail "expected 'not found' error"
  pass "missing-service pre-check"
}

test_dry_run() {
  info "Test: --dry-run (no actual changes)"
  output=$("$DECOMMISSION_BIN" "$SERVICE_NAME" --namespace "$NAMESPACE" --dry-run 2>&1)
  echo "$output" | grep -q "Dry-run" || fail "dry-run header missing"
  echo "$output" | grep -q "no changes made" || fail "dry-run footer missing"
  pass "--dry-run"
}

main() {
  echo "══════════════════════════════════════════════"
  echo "  Decommission CLI — Smoke Test Suite"
  echo "══════════════════════════════════════════════"
  echo ""

  check_prereqs
  build_cli

  echo ""
  info "Running smoke tests..."

  test_help
  test_version
  test_missing_service
  test_dry_run

  echo ""
  echo "══════════════════════════════════════════════"
  pass "All smoke tests passed"
  echo "══════════════════════════════════════════════"
}

main
