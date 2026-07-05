load test_helper

setup() {
  setup_test_env
  cd "$TEST_TEMP_DIR"

  if [ -f "$PROJECT_ROOT/argocd/application.tmpl.yaml" ]; then
    cp "$PROJECT_ROOT/argocd/application.tmpl.yaml" "$TEST_TEMP_DIR/"
  fi

  export APP_NAME="test-app"
  export IMAGE_TAG="v1.0"
  export REGISTRY_URL="k3d-registry.localhost"
  export REGISTRY_PORT="5000"
  export K8S_NAMESPACE="default"
  export CONTAINER_PORT="8080"
  export APP_REPO_URL="https://github.com/org/test-app.git"
}

teardown() {
  cleanup
}

@test "application.tmpl.yaml generates valid ArgoCD Application manifest" {
  if [ ! -f "$TEST_TEMP_DIR/application.tmpl.yaml" ]; then
    skip "ArgoCD template not yet created"
  fi

  envsubst < "$TEST_TEMP_DIR/application.tmpl.yaml" > "$TEST_TEMP_DIR/application.yaml"
  [ -f "$TEST_TEMP_DIR/application.yaml" ]

  assert_file_contains "$TEST_TEMP_DIR/application.yaml" "name: test-app"
  assert_file_contains "$TEST_TEMP_DIR/application.yaml" "namespace: argocd"
  assert_file_contains "$TEST_TEMP_DIR/application.yaml" "repoURL: https://github.com/org/test-app.git"
  assert_file_contains "$TEST_TEMP_DIR/application.yaml" "namespace: default"
  assert_file_contains "$TEST_TEMP_DIR/application.yaml" "selfHeal: true"
  assert_file_contains "$TEST_TEMP_DIR/application.yaml" "prune: true"
  assert_file_contains "$TEST_TEMP_DIR/application.yaml" "CreateNamespace=true"
  assert_file_contains "$TEST_TEMP_DIR/application.yaml" "kind: Application"
}

@test "generated ArgoCD Application manifest is valid YAML" {
  if [ ! -f "$TEST_TEMP_DIR/application.tmpl.yaml" ]; then
    skip "ArgoCD template not yet created"
  fi

  envsubst < "$TEST_TEMP_DIR/application.tmpl.yaml" > "$TEST_TEMP_DIR/application.yaml"
  python3 -c "import yaml; yaml.safe_load(open('$TEST_TEMP_DIR/application.yaml'))" || {
    echo "Invalid YAML in application.yaml" >&2
    return 1
  }
}

@test "kubectl dry-run validates ArgoCD Application manifest" {
  if ! command -v kubectl &>/dev/null; then
    skip "kubectl not available"
  fi

  # Check if kubectl can connect to a cluster
  if ! kubectl cluster-info 2>/dev/null >/dev/null; then
    skip "No Kubernetes cluster available"
  fi

  envsubst < "$TEST_TEMP_DIR/application.tmpl.yaml" > "$TEST_TEMP_DIR/application.yaml"

  # ArgoCD CRDs may not be installed; dry-run may fail gracefully
  run kubectl apply --dry-run=client -f "$TEST_TEMP_DIR/application.yaml" 2>&1 || true
  if echo "$output" | grep -q "unable to recognize"; then
    skip "ArgoCD CRDs not installed in cluster"
  fi
  [ "$status" -eq 0 ]
}
