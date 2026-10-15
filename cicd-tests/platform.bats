load test_helper

setup() {
  setup_test_env
  cd "$TEST_TEMP_DIR"
}

teardown() {
  cleanup
}

@test "build.sh with .gitops-platform marker skips template generation" {
  # Platform repo: marker present, no k8s/argocd may be created.
  local app_dir="$APPS_DIR/test-app"
  mkdir -p "$app_dir"
  touch "$app_dir/.gitops-platform"

  run "$PROJECT_ROOT/build.sh" \
    --app-name test-app --image-tag v1.0 \
    --registry-url k3d-registry.localhost --registry-port 5000 \
    --continue-on-error

  [[ "$output" == *"Platform repo detected"* ]]
  [ ! -e "$app_dir/k8s" ]
  [ ! -e "$app_dir/argocd" ]
}

@test "build.sh without marker still generates templates (no regression)" {
  local app_dir="$APPS_DIR/test-app"

  run "$PROJECT_ROOT/build.sh" \
    --app-name test-app --image-tag v1.0 \
    --registry-url k3d-registry.localhost --registry-port 5000 \
    --container-port 8080 \
    --k8s-ns default \
    --continue-on-error

  [[ "$output" != *"Platform repo detected"* ]]
  [ -f "$app_dir/k8s/deploy.yaml" ]
  [ -f "$app_dir/argocd/application.yaml" ]
}

@test "init.sh with marker creates no k8s/argocd scaffold dirs" {
  local work="$TEST_TEMP_DIR/platform-app"
  mkdir -p "$work"
  cd "$work"
  touch .gitops-platform

  run "$PROJECT_ROOT/init/init.sh"

  [ "$status" -eq 0 ]
  [ ! -e "$work/k8s" ]
  [ ! -e "$work/argocd" ]
}
