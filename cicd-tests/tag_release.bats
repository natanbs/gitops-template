load test_helper

setup() {
  setup_test_env
  cd "$TEST_TEMP_DIR"

  mkdir -p "$TEST_TEMP_DIR/k8s"

  cat > "$TEST_TEMP_DIR/.env" <<'EOF'
APP_NAME=test-app
REGISTRY_URL=localhost
REGISTRY_PORT=50000
K8S_NAMESPACE=apps-ns
CONTAINER_PORT=8080
CURRENT_TAG=v1.0.0
EOF

  cat > "$TEST_TEMP_DIR/k8s/deploy.yaml" <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: test-app
spec:
  template:
    spec:
      initContainers:
      - name: wait
        image: busybox:1.36
      containers:
      - name: test-app
        image: k3d-reg:5000/test-app:v1.0.0
        env:
        - name: IMAGE_TAG
          value: "v1.0.0"
        - name: OTHER
          value: "v1.0.0"
EOF
}

teardown() {
  cleanup
}

# Run tag.sh's manifest updater in isolation (no docker / git / push side effects)
run_tag_update() {
  sed -n '/^# Function to update image tags in YAML files/,/^}/p' \
    "$PROJECT_ROOT/tag.sh" > "$TEST_TEMP_DIR/_fn.sh"
  NEW_VERSION="$1" bash -c '
    set -e
    . "$0/_fn.sh"
    update_yaml_image_tags "$0/k8s/deploy.yaml"
  ' "$TEST_TEMP_DIR"
}

@test "tag.sh rewrites the image tag and the IMAGE_TAG env var" {
  run run_tag_update v2.0.0

  assert_file_contains "$TEST_TEMP_DIR/k8s/deploy.yaml" "image: k3d-reg:5000/test-app:v2.0.0"
  assert_file_contains "$TEST_TEMP_DIR/k8s/deploy.yaml" 'value: "v2.0.0"'
}

@test "tag.sh leaves unrelated env values and comments alone" {
  run run_tag_update v2.0.0

  assert_file_contains "$TEST_TEMP_DIR/k8s/deploy.yaml" "name: OTHER"
  assert_file_contains "$TEST_TEMP_DIR/k8s/deploy.yaml" '          value: "v1.0.0"'
  [ "$(grep -c 'value: "v2.0.0"' "$TEST_TEMP_DIR/k8s/deploy.yaml")" -eq 1 ]
}

@test "tag.sh retags every image reference including init containers" {
  run run_tag_update v2.0.0

  assert_file_contains "$TEST_TEMP_DIR/k8s/deploy.yaml" "image: busybox:v2.0.0"
}

@test "tag.sh preserves quoting and trailing comments in image refs" {
  cat >> "$TEST_TEMP_DIR/k8s/deploy.yaml" <<'EOF'
      - name: quoted
        image: "ghcr.io/acme/side:v0.9.1"
      - name: noted
        image: test-app:v1.0.0 # release note
EOF

  run run_tag_update v2.0.0

  assert_file_contains "$TEST_TEMP_DIR/k8s/deploy.yaml" 'image: "ghcr.io/acme/side:v2.0.0"'
  assert_file_contains "$TEST_TEMP_DIR/k8s/deploy.yaml" "image: test-app:v2.0.0 # release note"
}

@test "tag.sh leaves digest-pinned and untagged image refs untouched" {
  cat >> "$TEST_TEMP_DIR/k8s/deploy.yaml" <<'EOF'
      - name: pinned
        image: k3d-reg:5000/test-app@sha256:abcdef123456
      - name: untagged
        image: test-app
EOF

  run run_tag_update v2.0.0

  assert_file_contains "$TEST_TEMP_DIR/k8s/deploy.yaml" "image: k3d-reg:5000/test-app@sha256:abcdef123456"
  assert_file_contains "$TEST_TEMP_DIR/k8s/deploy.yaml" "image: test-app"
}

@test "tag.sh produces parseable YAML after the retag" {
  run run_tag_update v2.0.0

  run python3 -c "import yaml,sys; yaml.safe_load(open(sys.argv[1]))" \
    "$TEST_TEMP_DIR/k8s/deploy.yaml"
  [ "$status" -eq 0 ]
}

@test "tag.sh --help documents the manifest commit step" {
  run "$PROJECT_ROOT/tag.sh" --help

  assert_file_contains "$TEST_TEMP_DIR/k8s/deploy.yaml" "image: k3d-reg:5000/test-app:v1.0.0"
  [[ "$output" == *"Commit and push the k8s/ manifest changes"* ]]
  [[ "$output" == *"IMAGE_TAG env var"* ]]
}