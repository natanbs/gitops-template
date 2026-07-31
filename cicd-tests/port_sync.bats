load test_helper

setup() {
  setup_test_env
  cd "$TEST_TEMP_DIR"
}

teardown() {
  cleanup
}

# Shared fixtures: existing manifests at port 8080 with customizations
write_existing_manifests() {
  local app_dir="$1"
  mkdir -p "$app_dir/k8s"

  cat > "$app_dir/k8s/svc.yaml" <<'EOF'
apiVersion: v1
kind: Service
metadata:
  name: myapi
  annotations:
    custom: keep-me
spec:
  ports:
  - protocol: TCP
    port: 8080
    targetPort: 8080
    name: http
EOF

  cat > "$app_dir/k8s/deploy.yaml" <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: myapi
  annotations:
    custom: keep-me
spec:
  replicas: 3
  template:
    spec:
      containers:
      - name: myapi
        image: k3d-reg:5000/myapi:v1.0
        env:
        - name: IMAGE_TAG
          value: "v1.0"
        ports:
        - containerPort: 8080
        livenessProbe:
          httpGet:
            path: /healthz
            port: 8080
        readinessProbe:
          httpGet:
            path: /readyz
            port: 8080
EOF

  cat > "$app_dir/k8s/ingress.yaml" <<'EOF'
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: myapi
  annotations:
    custom: keep-me
spec:
  rules:
  - host: myapi.local
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: myapi
            port:
              number: 8080
EOF
}

# ── init.sh --build port sync ───────────────────────────────────

@test "init.sh --build syncs CONTAINER_PORT into existing k8s manifests" {
  # Sandboxed copy of init (no build.sh) so init.sh skips the docker build step
  mkdir -p "$TEST_TEMP_DIR/template/init"
  cp "$PROJECT_ROOT/init.sh" "$TEST_TEMP_DIR/template/"
  cp -R "$PROJECT_ROOT/init/." "$TEST_TEMP_DIR/template/init/"

  local app_dir="$TEST_TEMP_DIR/apps/myapi"
  write_existing_manifests "$app_dir"
  cat > "$app_dir/.env" <<'EOF'
APP_NAME=myapi
K8S_NAMESPACE=apps-ns
CONTAINER_PORT=9000
EOF

  cd "$app_dir"
  run "$TEST_TEMP_DIR/template/init.sh" --build
  [ "$status" -eq 0 ]

  assert_file_contains "$app_dir/k8s/svc.yaml" "port: 9000"
  assert_file_contains "$app_dir/k8s/svc.yaml" "targetPort: 9000"
  assert_file_contains "$app_dir/k8s/deploy.yaml" "containerPort: 9000"
  assert_file_contains "$app_dir/k8s/deploy.yaml" "port: 9000"
  assert_file_contains "$app_dir/k8s/ingress.yaml" "number: 9000"

  # customizations preserved
  assert_file_contains "$app_dir/k8s/svc.yaml" "custom: keep-me"
  assert_file_contains "$app_dir/k8s/deploy.yaml" "replicas: 3"
  assert_file_contains "$app_dir/k8s/deploy.yaml" "custom: keep-me"
  assert_file_contains "$app_dir/k8s/ingress.yaml" "custom: keep-me"

  # no sed backup files left behind
  [ ! -f "$app_dir/k8s/svc.yaml.bak" ]
  [ ! -f "$app_dir/k8s/deploy.yaml.bak" ]
  [ ! -f "$app_dir/k8s/ingress.yaml.bak" ]
}

@test "init.sh --build port sync is idempotent" {
  mkdir -p "$TEST_TEMP_DIR/template/init"
  cp "$PROJECT_ROOT/init.sh" "$TEST_TEMP_DIR/template/"
  cp -R "$PROJECT_ROOT/init/." "$TEST_TEMP_DIR/template/init/"

  local app_dir="$TEST_TEMP_DIR/apps/myapi"
  write_existing_manifests "$app_dir"
  cat > "$app_dir/.env" <<'EOF'
APP_NAME=myapi
K8S_NAMESPACE=apps-ns
CONTAINER_PORT=9000
EOF

  cd "$app_dir"
  run "$TEST_TEMP_DIR/template/init.sh" --build
  [ "$status" -eq 0 ]
  cp "$app_dir/k8s/svc.yaml" "$TEST_TEMP_DIR/svc.before"
  cp "$app_dir/k8s/deploy.yaml" "$TEST_TEMP_DIR/deploy.before"
  cp "$app_dir/k8s/ingress.yaml" "$TEST_TEMP_DIR/ingress.before"

  run "$TEST_TEMP_DIR/template/init.sh" --build
  [ "$status" -eq 0 ]
  cmp -s "$TEST_TEMP_DIR/svc.before" "$app_dir/k8s/svc.yaml"
  cmp -s "$TEST_TEMP_DIR/deploy.before" "$app_dir/k8s/deploy.yaml"
  cmp -s "$TEST_TEMP_DIR/ingress.before" "$app_dir/k8s/ingress.yaml"
}

@test "init.sh without --build/--deploy leaves existing manifests untouched" {
  local app_dir="$TEST_TEMP_DIR/existing"
  write_existing_manifests "$app_dir"
  cat > "$app_dir/.env" <<'EOF'
APP_NAME=existing
CONTAINER_PORT=9000
EOF

  cd "$app_dir"
  run "$PROJECT_ROOT/init.sh"
  [ "$status" -eq 0 ]

  assert_file_contains "$app_dir/k8s/svc.yaml" "port: 8080"
  assert_file_contains "$app_dir/k8s/deploy.yaml" "containerPort: 8080"
  assert_file_contains "$app_dir/k8s/ingress.yaml" "number: 8080"
}

@test "new-app scaffolding renders default port 8080 unchanged" {
  mkdir -p "$TEST_TEMP_DIR/template/init"
  cp "$PROJECT_ROOT/init.sh" "$TEST_TEMP_DIR/template/"
  cp -R "$PROJECT_ROOT/init/." "$TEST_TEMP_DIR/template/init/"

  local parent="$TEST_TEMP_DIR/workspace"
  mkdir -p "$parent"
  local app_dir="$TEST_TEMP_DIR/fresh-app"

  cd "$parent"
  run "$TEST_TEMP_DIR/template/init.sh" --app-name fresh-app
  [ "$status" -eq 0 ]

  assert_file_contains "$app_dir/k8s/svc.yaml" "port: 8080"
  assert_file_contains "$app_dir/k8s/deploy.yaml" "containerPort: 8080"
  assert_file_contains "$app_dir/k8s/ingress.yaml" "number: 8080"
}

# ── build.sh port sync ──────────────────────────────────────────

@test "build.sh syncs CONTAINER_PORT into existing manifests" {
  # Sandboxed copy of the repo so build.sh resolves the app dir inside TEST_TEMP_DIR
  mkdir -p "$TEST_TEMP_DIR/repo/init/k8s" "$TEST_TEMP_DIR/repo/init/argocd"
  cp "$PROJECT_ROOT/build.sh" "$TEST_TEMP_DIR/repo/"
  cp "$PROJECT_ROOT/init/k8s/"*.tmpl.yaml "$TEST_TEMP_DIR/repo/init/k8s/"
  cp "$PROJECT_ROOT/init/argocd/"*.tmpl.yaml "$TEST_TEMP_DIR/repo/init/argocd/" 2>/dev/null || true

  cat > "$TEST_TEMP_DIR/repo/.env" <<'EOF'
APP_NAME=myapi
K8S_NAMESPACE=apps-ns
CONTAINER_PORT=9000
EOF

  local app_dir="$TEST_TEMP_DIR/myapi"
  write_existing_manifests "$app_dir"

  cd "$TEST_TEMP_DIR/repo"
  run "$TEST_TEMP_DIR/repo/build.sh" --app-name myapi --image-tag v1.0 --continue-on-error

  assert_file_contains "$app_dir/k8s/svc.yaml" "port: 9000"
  assert_file_contains "$app_dir/k8s/svc.yaml" "targetPort: 9000"
  assert_file_contains "$app_dir/k8s/deploy.yaml" "containerPort: 9000"
  assert_file_contains "$app_dir/k8s/deploy.yaml" "port: 9000"
  assert_file_contains "$app_dir/k8s/ingress.yaml" "number: 9000"

  # customizations preserved + image/IMAGE_TAG update still intact
  assert_file_contains "$app_dir/k8s/deploy.yaml" "replicas: 3"
  assert_file_contains "$app_dir/k8s/deploy.yaml" "custom: keep-me"
  assert_file_contains "$app_dir/k8s/deploy.yaml" "k3d-reg:5000/myapi:v1.0"
  assert_file_contains "$app_dir/k8s/deploy.yaml" "value: \"v1.0\""
}
