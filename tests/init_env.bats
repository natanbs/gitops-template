load test_helper

setup() {
  setup_test_env
  # cd into a subdir so init.sh creates the app in $TEST_TEMP_DIR (parent)
  mkdir -p "$TEST_TEMP_DIR/init"
  cd "$TEST_TEMP_DIR/init"
}

teardown() {
  cleanup
}

# ── .env loading in build.sh ──────────────────────────────────────

@test "build.sh reads APP_NAME from .env file" {
  cat > .env <<'EOF'
APP_NAME=env-test-app
REGISTRY_URL=localhost
REGISTRY_PORT=50000
K8S_NAMESPACE=env-test-ns
CONTAINER_PORT=8080
EOF

  run "$PROJECT_ROOT/build.sh" --image-tag v1.0 --continue-on-error
  [[ "$output" == *"Application: env-test-app"* ]]
}

@test "build.sh reads registry config from .env file" {
  cat > .env <<'EOF'
APP_NAME=env-app
REGISTRY_URL=my-registry.example.com
REGISTRY_PORT=12345
K8S_NAMESPACE=custom-ns
CONTAINER_PORT=9000
EOF

  run "$PROJECT_ROOT/build.sh" --image-tag v1.0 --continue-on-error
  [[ "$output" == *"Registry:    my-registry.example.com:12345"* ]]
  [[ "$output" == *"Namespace:   custom-ns"* ]]
}

@test "build.sh CLI flags override .env values" {
  cat > .env <<'EOF'
APP_NAME=env-app
REGISTRY_URL=should-be-overridden
REGISTRY_PORT=50000
K8S_NAMESPACE=should-be-overridden
EOF

  run "$PROJECT_ROOT/build.sh" \
    --app-name cli-override \
    --image-tag v1.0 \
    --registry-url actual-registry \
    --k8s-namespace actual-ns \
    --continue-on-error
  [ "$status" -eq 1 ]
  [[ "$output" == *"cli-override"* ]]
  [[ "$output" == *"actual-registry"* ]]
  [[ "$output" == *"actual-ns"* ]]
}

@test "build.sh works without .env file" {
  run "$PROJECT_ROOT/build.sh" --app-name no-env-app --image-tag v1.0 --continue-on-error
  [ "$status" -eq 1 ]
  [[ "$output" == *"no-env-app"* ]]
}

# ── init.sh scaffolding ──────────────────────────────────────────

@test "init.sh --app-name creates project directory" {
  run "$PROJECT_ROOT/init.sh" --app-name scaffold-test
  [ "$status" -eq 0 ]
  [ -d "$TEST_TEMP_DIR/scaffold-test" ]
}

@test "init.sh writes .env with correct APP_NAME" {
  run "$PROJECT_ROOT/init.sh" --app-name my-scaffold
  [ "$status" -eq 0 ]
  assert_file_contains "$TEST_TEMP_DIR/my-scaffold/.env" "APP_NAME=my-scaffold"
}

@test "init.sh writes .env with custom registry" {
  run "$PROJECT_ROOT/init.sh" \
    --app-name reg-app \
    --registry-url custom.io \
    --registry-port 7777
  [ "$status" -eq 0 ]
  assert_file_contains "$TEST_TEMP_DIR/reg-app/.env" "REGISTRY_URL=custom.io"
  assert_file_contains "$TEST_TEMP_DIR/reg-app/.env" "REGISTRY_PORT=7777"
}

@test "init.sh writes .env with custom namespace" {
  run "$PROJECT_ROOT/init.sh" --app-name ns-app --k8s-namespace my-ns
  [ "$status" -eq 0 ]
  assert_file_contains "$TEST_TEMP_DIR/ns-app/.env" "K8S_NAMESPACE=my-ns"
}

@test "init.sh k8s-namespace defaults to app name" {
  run "$PROJECT_ROOT/init.sh" --app-name default-ns-app
  [ "$status" -eq 0 ]
  assert_file_contains "$TEST_TEMP_DIR/default-ns-app/.env" "K8S_NAMESPACE=default-ns-app"
}

@test "init.sh --app-name with hyphen name succeeds" {
  run "$PROJECT_ROOT/init.sh" --app-name my-api-server
  [ "$status" -eq 0 ]
  [ -d "$TEST_TEMP_DIR/my-api-server" ]
}

@test "init.sh rejects invalid app name" {
  run "$PROJECT_ROOT/init.sh" --app-name "InvalidName"
  [ "$status" -eq 1 ]
  [[ "$output" == *"k8s-safe"* ]]
}

@test "init.sh errors when --app-name is missing" {
  run "$PROJECT_ROOT/init.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"--app-name is required"* ]]
}

@test "init.sh copies build.sh into scaffolded project" {
  run "$PROJECT_ROOT/init.sh" --app-name has-build
  [ "$status" -eq 0 ]
  [ -f "$TEST_TEMP_DIR/has-build/build.sh" ]
  [ -x "$TEST_TEMP_DIR/has-build/build.sh" ]
}

@test "init.sh copies k8s templates into scaffolded project" {
  run "$PROJECT_ROOT/init.sh" --app-name has-k8s
  [ "$status" -eq 0 ]
  [ -f "$TEST_TEMP_DIR/has-k8s/k8s/deploy.tmpl.yaml" ]
  [ -f "$TEST_TEMP_DIR/has-k8s/k8s/svc.tmpl.yaml" ]
}

@test "init.sh copies argocd templates into scaffolded project" {
  run "$PROJECT_ROOT/init.sh" --app-name has-argocd
  [ "$status" -eq 0 ]
  [ -f "$TEST_TEMP_DIR/has-argocd/argocd/application.tmpl.yaml" ]
}

@test "init.sh --dockerfile go scaffolds a Go Dockerfile and main.go" {
  run "$PROJECT_ROOT/init.sh" --app-name go-app --dockerfile go
  [ "$status" -eq 0 ]
  [ -f "$TEST_TEMP_DIR/go-app/Dockerfile" ]
  [ -f "$TEST_TEMP_DIR/go-app/main.go" ]
  assert_file_contains "$TEST_TEMP_DIR/go-app/Dockerfile" "golang"
  assert_file_contains "$TEST_TEMP_DIR/go-app/main.go" "package main"
}

@test "init.sh --dockerfile python scaffolds Python files" {
  run "$PROJECT_ROOT/init.sh" --app-name py-app --dockerfile python
  [ "$status" -eq 0 ]
  [ -f "$TEST_TEMP_DIR/py-app/Dockerfile" ]
  [ -f "$TEST_TEMP_DIR/py-app/app.py" ]
  assert_file_contains "$TEST_TEMP_DIR/py-app/Dockerfile" "python"
}

@test "init.sh --dockerfile node scaffolds Node.js files" {
  run "$PROJECT_ROOT/init.sh" --app-name node-app --dockerfile node
  [ "$status" -eq 0 ]
  [ -f "$TEST_TEMP_DIR/node-app/Dockerfile" ]
  [ -f "$TEST_TEMP_DIR/node-app/package.json" ]
  assert_file_contains "$TEST_TEMP_DIR/node-app/Dockerfile" "node"
}

@test "init.sh errors if target directory already exists" {
  mkdir -p "$TEST_TEMP_DIR/existing-app"
  run "$PROJECT_ROOT/init.sh" --app-name existing-app
  [ "$status" -eq 1 ]
  [[ "$output" == *"already exists"* ]]
}

@test "init.sh produces a valid git repo" {
  run "$PROJECT_ROOT/init.sh" --app-name git-repo
  [ "$status" -eq 0 ]

  run git -C "$TEST_TEMP_DIR/git-repo" log --oneline
  [ "$status" -eq 0 ]
  [[ "$output" == *"Initial scaffold"* ]]
}

@test "init.sh --container-port sets CONTAINER_PORT in .env" {
  run "$PROJECT_ROOT/init.sh" --app-name port-app --container-port 3000
  [ "$status" -eq 0 ]
  assert_file_contains "$TEST_TEMP_DIR/port-app/.env" "CONTAINER_PORT=3000"
}

@test "init.sh shows help with --help flag" {
  run "$PROJECT_ROOT/init.sh" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: init.sh"* ]]
  [[ "$output" == *"--app-name"* ]]
}

@test "scaffolded project uses .env with build.sh end-to-end" {
  # --local to test against the working tree (not the remote repo)
  run "$PROJECT_ROOT/init.sh" --app-name full-test --dockerfile go --local
  [ "$status" -eq 0 ]

  # build.sh reads APP_NAME and registry from .env, no --app-name needed
  run "$TEST_TEMP_DIR/full-test/build.sh" --image-tag v1.0 --continue-on-error
  [[ "$output" == *"Application: full-test"* ]]
  [[ "$output" == *"Registry:    localhost:50000"* ]]
}
