load test_helper

setup() {
  setup_test_env
  cd "$TEST_TEMP_DIR"
}

teardown() {
  cleanup
}

@test "build.sh shows help with --help flag" {
  run "$PROJECT_ROOT/build.sh" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: build.sh"* ]]
  [[ "$output" == *"--app-name"* ]]
  [[ "$output" == *"--image-tag"* ]]
}

@test "build.sh shows help with no arguments" {
  run "$PROJECT_ROOT/build.sh"
  [ "$status" -eq 1 ]
}

@test "build.sh errors when --app-name is missing" {
  run "$PROJECT_ROOT/build.sh" --image-tag v1.0
  [ "$status" -eq 1 ]
  [[ "$output" == *"--app-name is required"* ]]
}

@test "build.sh errors when --image-tag is missing" {
  run "$PROJECT_ROOT/build.sh" --app-name my-app
  [ "$status" -eq 1 ]
  [[ "$output" == *"--image-tag is required"* ]]
}

@test "build.sh rejects invalid --app-name with uppercase" {
  run "$PROJECT_ROOT/build.sh" --app-name "MyApp" --image-tag v1.0
  [ "$status" -eq 1 ]
  [[ "$output" == *"k8s-safe"* ]]
}

@test "build.sh rejects invalid --app-name with underscores" {
  run "$PROJECT_ROOT/build.sh" --app-name "my_app" --image-tag v1.0
  [ "$status" -eq 1 ]
  [[ "$output" == *"k8s-safe"* ]]
}

@test "build.sh rejects invalid --app-name starting with digit" {
  run "$PROJECT_ROOT/build.sh" --app-name "1app" --image-tag v1.0
  [ "$status" -eq 1 ]
  [[ "$output" == *"k8s-safe"* ]]
}

@test "build.sh accepts valid --app-name with hyphens" {
  run "$PROJECT_ROOT/build.sh" --app-name "my-app" --image-tag v1.0 --continue-on-error
  [ "$status" -eq 1 ]
  [[ "$output" == *"Building"* ]]
}

@test "build.sh rejects invalid --image-tag starting with dot" {
  run "$PROJECT_ROOT/build.sh" --app-name my-app --image-tag ".v1.0"
  [ "$status" -eq 1 ]
  [[ "$output" == *"image-tag"* ]]
}

@test "build.sh accepts --registry-port as number" {
  run "$PROJECT_ROOT/build.sh" --app-name my-app --image-tag v1.0 --registry-port 5000 --continue-on-error
  [ "$status" -eq 1 ]
  [[ "$output" != *"must be a number"* ]]
}

@test "build.sh rejects non-numeric --registry-port" {
  run "$PROJECT_ROOT/build.sh" --app-name my-app --image-tag v1.0 --registry-port abc
  [ "$status" -eq 1 ]
  [[ "$output" == *"must be a number"* ]]
}

@test "build.sh accepts --auto-deploy flag" {
  run "$PROJECT_ROOT/build.sh" --app-name my-app --image-tag v1.0 --auto-deploy --continue-on-error
  [ "$status" -eq 1 ]
  [[ "$output" != *"Unknown argument"* ]]
}

@test "build.sh accepts --continue-on-error flag" {
  run "$PROJECT_ROOT/build.sh" --app-name my-app --image-tag v1.0 --continue-on-error
  [ "$status" -eq 1 ]
  [[ "$output" != *"Unknown argument"* ]]
}
