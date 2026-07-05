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
  # build.sh processes templates from PROJECT_ROOT/k8s/ (the real template dir)
  # Verify the built-in deploy template is processed with correct variables
  run "$PROJECT_ROOT/build.sh" \
    --app-name test-app --image-tag v1.0 \
    --registry-url k3d-registry.localhost --registry-port 5000 \
    --container-port 8080 \
    --k8s-ns default \
    --continue-on-error

  # Template output goes to PROJECT_ROOT/k8s/ (the real template directory)
  [ -f "$PROJECT_ROOT/k8s/deploy.yaml" ]
  assert_file_contains "$PROJECT_ROOT/k8s/deploy.yaml" "name: test-app"
  assert_file_contains "$PROJECT_ROOT/k8s/deploy.yaml" "k3d-reg:5000/test-app:v1.0"
  assert_file_contains "$PROJECT_ROOT/k8s/deploy.yaml" "containerPort: 8080"
  assert_file_contains "$PROJECT_ROOT/k8s/deploy.yaml" "namespace: default"
}

@test "build.sh --auto-deploy invokes kubectl apply" {
  # Verify that --auto-deploy flag triggers deploy step messaging
  run "$PROJECT_ROOT/build.sh" \
    --app-name test-app --image-tag v1.0 \
    --registry-url k3d-registry.localhost --registry-port 5000 \
    --auto-deploy \
    --continue-on-error

  [[ "$output" == *"Applying"* ]]
}

@test "build.sh without --auto-deploy skips deploy step" {
  run "$PROJECT_ROOT/build.sh" \
    --app-name test-app --image-tag v1.0 \
    --registry-url k3d-registry.localhost --registry-port 5000 \
    --continue-on-error

  [[ "$output" == *"Skipping deploy"* ]]
}
