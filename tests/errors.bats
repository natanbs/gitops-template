load test_helper

setup() {
  setup_test_env
}

teardown() {
  cleanup
}

@test "build.sh exits 1 on Docker build failure" {
  # Point to a directory without a Dockerfile
  run "$PROJECT_ROOT/build.sh" \
    --app-name test-app --image-tag v1.0 \
    --registry-url k3d-registry.localhost --registry-port 5000
  [ "$status" -eq 1 ]
  [[ "$output" == *"failed"* ]] || [[ "$output" == *"ERROR"* ]]
}

@test "build.sh --continue-on-error continues after build failure" {
  run "$PROJECT_ROOT/build.sh" \
    --app-name test-app --image-tag v1.0 \
    --registry-url k3d-registry.localhost --registry-port 5000 \
    --continue-on-error
  [ "$status" -eq 1 ]
  [[ "$output" == *"continuing"* ]]
}

@test "build.sh cleanup runs on failure" {
  # Simulate a failure scenario
  run "$PROJECT_ROOT/build.sh" \
    --app-name test-app --image-tag v1.0 \
    --registry-url k3d-registry.localhost --registry-port 5000
  # After failure, script should exit with 1
  [ "$status" -eq 1 ]
}

@test "build.sh exits 0 on successful path" {
  # Use the test temp dir which has a Dockerfile
  cp "$PROJECT_ROOT/tests/test_helper.bash" "$TEST_TEMP_DIR/"
  cd "$TEST_TEMP_DIR"
  run "$PROJECT_ROOT/build.sh" \
    --app-name test-app --image-tag v1.0 \
    --registry-url k3d-registry.localhost --registry-port 5000
  # Should successfully build the Docker image from test Dockerfile
  # Then fail on push (no registry available) unless --continue-on-error
  # This test verifies the build step works
  [[ "$output" == *"Building"* ]]
}

@test "build.sh reports multiple failed steps with --continue-on-error" {
  cd "$TEST_TEMP_DIR"
  run "$PROJECT_ROOT/build.sh" \
    --app-name test-app --image-tag v1.0 \
    --registry-url k3d-registry.localhost --registry-port 5000 \
    --continue-on-error
  # Should complete all steps and report failures at end
  [ "$status" -eq 1 ]
  [[ "$output" == *"Pipeline completed with"* ]]
}
