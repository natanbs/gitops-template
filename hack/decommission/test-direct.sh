#!/usr/bin/env bash
set -euo pipefail

# End-to-end validation: Direct Deploy path
# Requires: k3d cluster "cluster-argo" (or set KUBECONFIG)
#
# Usage:
#   ./hack/decommission/test-direct.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
DECOMMISSION_BIN="${REPO_ROOT}/bin/decommission"
NAMESPACE="${NAMESPACE:-decom-e2e}"
SERVICE_NAME="${SERVICE_NAME:-e2e-nginx}"

info()  { printf "\033[36m[INFO]\033[0m %s\n" "$*"; }
pass()  { printf "\033[32m[PASS]\033[0m %s\n" "$*"; }
fail()  { printf "\033[31m[FAIL]\033[0m %s\n" "$*"; exit 1; }

build_cli() {
  info "Building decommission CLI..."
  cd "$REPO_ROOT" && go build -o "$DECOMMISSION_BIN" ./cmd/decommission/
}

deploy_test_svc() {
  info "Deploying test service: $SERVICE_NAME (ns=$NAMESPACE)"
  kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
  kubectl create deployment "$SERVICE_NAME" --image=nginx:alpine -n "$NAMESPACE"
  kubectl expose deployment "$SERVICE_NAME" --port=80 -n "$NAMESPACE"
  kubectl wait --for=condition=available deployment/"$SERVICE_NAME" -n "$NAMESPACE" --timeout=60s
  pass "Test service deployed"
}

verify_deleted() {
  local exists
  exists=$(kubectl get deployment "$SERVICE_NAME" -n "$NAMESPACE" --no-headers 2>/dev/null || true)
  if [ -n "$exists" ]; then
    fail "Deployment $SERVICE_NAME still exists"
  fi
  pass "Service resources deleted"
}

run_decommission() {
  info "Running decommission for $SERVICE_NAME..."
  "$DECOMMISSION_BIN" "$SERVICE_NAME" --namespace "$NAMESPACE" --operator "e2e-test"
  pass "Decommission completed"
}

cleanup() {
  info "Cleaning up..."
  kubectl delete namespace "$NAMESPACE" --ignore-not-found --wait=false
}

main() {
  echo "══════════════════════════════════════════════"
  echo "  E2E: Direct Deploy Path"
  echo "══════════════════════════════════════════════"
  echo ""

  build_cli
  deploy_test_svc
  run_decommission
  verify_deleted
  cleanup

  echo ""
  echo "══════════════════════════════════════════════"
  pass "Direct Deploy E2E passed"
  echo "══════════════════════════════════════════════"
}

main
