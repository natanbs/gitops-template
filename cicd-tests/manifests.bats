load test_helper

setup() {
  setup_test_env
  cd "$TEST_TEMP_DIR"

  # Copy templates to test dir and process them with envsubst
  cp "$PROJECT_ROOT/init-templates/deploy.tmpl.yaml" "$TEST_TEMP_DIR/"
  cp "$PROJECT_ROOT/init-templates/svc.tmpl.yaml" "$TEST_TEMP_DIR/"
  if [ -f "$PROJECT_ROOT/init-templates/ingress.tmpl.yaml" ]; then
    cp "$PROJECT_ROOT/init-templates/ingress.tmpl.yaml" "$TEST_TEMP_DIR/"
  fi

  export APP_NAME="test-app"
  export IMAGE_TAG="v1.0"
  export REGISTRY_URL="k3d-registry.localhost"
  export REGISTRY_PORT="5000"
  export REGISTRY_CLUSTER_URL="k3d-registry.localhost"
  export REGISTRY_CLUSTER_PORT="5000"
  export K8S_NAMESPACE="default"
  export CONTAINER_PORT="8080"
}

teardown() {
  cleanup
}

@test "deploy.tmpl.yaml generates valid Deployment with envsubst" {
  envsubst < "$TEST_TEMP_DIR/deploy.tmpl.yaml" > "$TEST_TEMP_DIR/deploy.yaml"
  [ -f "$TEST_TEMP_DIR/deploy.yaml" ]

  assert_file_contains "$TEST_TEMP_DIR/deploy.yaml" "name: test-app"
  assert_file_contains "$TEST_TEMP_DIR/deploy.yaml" "namespace: default"
  assert_file_contains "$TEST_TEMP_DIR/deploy.yaml" "k3d-registry.localhost:5000/test-app:v1.0"
  assert_file_contains "$TEST_TEMP_DIR/deploy.yaml" "containerPort: 8080"
  assert_file_contains "$TEST_TEMP_DIR/deploy.yaml" "kind: Deployment"
}

@test "svc.tmpl.yaml generates valid Service with envsubst" {
  envsubst < "$TEST_TEMP_DIR/svc.tmpl.yaml" > "$TEST_TEMP_DIR/svc.yaml"
  [ -f "$TEST_TEMP_DIR/svc.yaml" ]

  assert_file_contains "$TEST_TEMP_DIR/svc.yaml" "name: test-app"
  assert_file_contains "$TEST_TEMP_DIR/svc.yaml" "namespace: default"
  assert_file_contains "$TEST_TEMP_DIR/svc.yaml" "port: 8080"
  assert_file_contains "$TEST_TEMP_DIR/svc.yaml" "kind: Service"
}

@test "ingress.tmpl.yaml generates valid Ingress with envsubst" {
  if [ ! -f "$TEST_TEMP_DIR/ingress.tmpl.yaml" ]; then
    skip "ingress template not yet created"
  fi
  envsubst < "$TEST_TEMP_DIR/ingress.tmpl.yaml" > "$TEST_TEMP_DIR/ingress.yaml"
  [ -f "$TEST_TEMP_DIR/ingress.yaml" ]

  assert_file_contains "$TEST_TEMP_DIR/ingress.yaml" "name: test-app"
  assert_file_contains "$TEST_TEMP_DIR/ingress.yaml" "test-app.local"
  assert_file_contains "$TEST_TEMP_DIR/ingress.yaml" "kind: Ingress"
}

@test "all templates produce valid YAML" {
  for tmpl in "$TEST_TEMP_DIR"/*.tmpl.yaml; do
    [ -f "$tmpl" ] || continue
    output="${tmpl%.tmpl.yaml}.yaml"
    envsubst < "$tmpl" > "$output"

    # Validate YAML structure (python3 yaml check)
    python3 -c "import yaml; yaml.safe_load(open('$output'))" || {
      echo "Invalid YAML in $(basename $output)" >&2
      return 1
    }
  done
}

@test "kubectl dry-run validates generated manifests" {
  if ! command -v kubectl &>/dev/null; then
    skip "kubectl not available"
  fi

  # Check if kubectl can connect to a cluster
  if ! kubectl cluster-info 2>/dev/null >/dev/null; then
    skip "No Kubernetes cluster available"
  fi

  for tmpl in "$TEST_TEMP_DIR"/*.tmpl.yaml; do
    [ -f "$tmpl" ] || continue
    output="${tmpl%.tmpl.yaml}.yaml"
    envsubst < "$tmpl" > "$output"

    run kubectl apply --dry-run=client -f "$output"
    [ "$status" -eq 0 ] || {
      echo "kubectl dry-run failed for $(basename $output): $output" >&2
      return 1
    }
  done
}
