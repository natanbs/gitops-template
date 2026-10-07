load test_helper

setup() {
  setup_test_env
  cd "$TEST_TEMP_DIR"
}

teardown() {
  cleanup
}

@test "build.sh builds a valid Docker image with --app-name and --image-tag" {
  # Build with test Dockerfile
  run "$PROJECT_ROOT/build.sh" \
    --app-name test-app --image-tag v1.0 \
    --registry-url k3d-registry.localhost --registry-port 5000 \
    --continue-on-error

  # Verify the Docker image was created locally
  assert_image_exists "test-app:v1.0"
}

@test "build.sh creates generated K8s manifests from templates" {
  # build.sh renders templates into the app repo — a sibling of the template repo
  local app_dir="$(dirname "$PROJECT_ROOT")/test-app"

  run "$PROJECT_ROOT/build.sh" \
    --app-name test-app --image-tag v1.0 \
    --registry-url k3d-registry.localhost --registry-port 5000 \
    --container-port 8080 \
    --k8s-ns default \
    --continue-on-error

  [ -f "$app_dir/k8s/deploy.yaml" ]
  assert_file_contains "$app_dir/k8s/deploy.yaml" "name: test-app"
  assert_file_contains "$app_dir/k8s/deploy.yaml" "k3d-reg:5000/test-app:v1.0"
  assert_file_contains "$app_dir/k8s/deploy.yaml" "containerPort: 8080"
  assert_file_contains "$app_dir/k8s/deploy.yaml" "namespace: default"
}

@test "build.sh --auto-deploy prepares GitOps manifests" {
  # Deploy is GitOps-only: manifests are committed and applied by ArgoCD
  run "$PROJECT_ROOT/build.sh" \
    --app-name test-app --image-tag v1.0 \
    --registry-url k3d-registry.localhost --registry-port 5000 \
    --auto-deploy \
    --continue-on-error

  [[ "$output" == *"Preparing Manifests for GitOps Deploy"* ]]
}

@test "build.sh without --auto-deploy skips deploy step" {
  run "$PROJECT_ROOT/build.sh" \
    --app-name test-app --image-tag v1.0 \
    --registry-url k3d-registry.localhost --registry-port 5000 \
    --continue-on-error

  [[ "$output" == *"Skipping deploy"* ]]
}
