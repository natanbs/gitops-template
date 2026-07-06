load test_helper

setup() {
  setup_test_env
  cd "$TEST_TEMP_DIR"

  # Copy the full template structure
  mkdir -p "$TEST_TEMP_DIR/k8s"
  cp -r "$PROJECT_ROOT/init-templates" "$TEST_TEMP_DIR/"
  cp -r "$PROJECT_ROOT/argocd" "$TEST_TEMP_DIR/" 2>/dev/null || true

  # Create a real Dockerfile for a simple Go HTTP server
  cat > "$TEST_TEMP_DIR/Dockerfile" <<'DOCKERFILE'
FROM golang:1.23-alpine AS builder
WORKDIR /app
COPY <<-GOAPP main.go
package main

import (
	"fmt"
	"net/http"
)

func main() {
	http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		fmt.Fprintf(w, "Hello from test-app")
	})
	http.HandleFunc("/healthz", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
	})
	http.HandleFunc("/readyz", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
	})
	http.ListenAndServe(":8080", nil)
}
GOAPP
RUN go build -o server main.go

FROM alpine:3.21
WORKDIR /app
COPY --from=builder /app/server .
EXPOSE 8080
CMD ["./server"]
DOCKERFILE
}

teardown() {
  cleanup
}

@test "full pipeline: build, template, and validate" {
  # ── 1. Build image ──────────────────────────────────────
  run docker build -t "e2e-test-app:v1.0" "$TEST_TEMP_DIR"
  [ "$status" -eq 0 ] || {
    echo "Docker build failed: $output" >&2
    return 1
  }
  assert_image_exists "e2e-test-app:v1.0"

  # ── 2. Tag image ────────────────────────────────────────
  run docker tag "e2e-test-app:v1.0" "localhost:5000/e2e-test-app:v1.0"
  [ "$status" -eq 0 ]

  # ── 3. Process templates with envsubst ───────────────────
  export APP_NAME="e2e-test-app"
  export IMAGE_TAG="v1.0"
  export REGISTRY_URL="localhost"
  export REGISTRY_PORT="5000"
  export REGISTRY_CLUSTER_URL="localhost"
  export REGISTRY_CLUSTER_PORT="5000"
  export K8S_NAMESPACE="e2e-ns"
  export CONTAINER_PORT="8080"

  for tmpl in "$TEST_TEMP_DIR"/init-templates/*.tmpl.yaml; do
    [ -f "$tmpl" ] || continue
    filename=$(basename "$tmpl" .tmpl.yaml)
    output="$TEST_TEMP_DIR/k8s/${filename}.yaml"
    envsubst < "$tmpl" > "$output"
    [ -f "$output" ] || {
      echo "Failed to generate $(basename "$output")" >&2
      return 1
    }
  done

  # ── 4. Validate generated manifests ──────────────────────
  for manifest in "$TEST_TEMP_DIR"/k8s/*.yaml; do
    [[ "$manifest" == *.tmpl.yaml ]] && continue
    [ -f "$manifest" ] || continue

    # Validate YAML structure
    python3 -c "
import yaml, sys
try:
    with open('$manifest') as f:
        yaml.safe_load(f)
except Exception as e:
    print(f'Invalid YAML in $(basename $manifest): {e}', file=sys.stderr)
    sys.exit(1)
" || return 1

    # kubectl dry-run if a cluster is available
    if command -v kubectl &>/dev/null && kubectl cluster-info 2>/dev/null >/dev/null; then
      run kubectl apply --dry-run=client -f "$manifest" 2>&1
      if echo "$output" | grep -qv "unable to recognize"; then
        [ "$status" -eq 0 ] || {
          echo "kubectl dry-run failed for $(basename $manifest)" >&2
          return 1
        }
      fi
    fi
  done

  # ── 5. Verify expected content ───────────────────────────
  assert_file_contains "$TEST_TEMP_DIR/k8s/deploy.yaml" "name: e2e-test-app"
  assert_file_contains "$TEST_TEMP_DIR/k8s/deploy.yaml" "namespace: e2e-ns"
  assert_file_contains "$TEST_TEMP_DIR/k8s/deploy.yaml" "localhost:5000/e2e-test-app:v1.0"
  assert_file_contains "$TEST_TEMP_DIR/k8s/svc.yaml" "name: e2e-test-app"
  assert_file_contains "$TEST_TEMP_DIR/k8s/svc.yaml" "port: 8080"

  # ── 6. Process ArgoCD template if present ────────────────
  if [ -f "$TEST_TEMP_DIR/argocd/application.tmpl.yaml" ]; then
    export APP_REPO_URL="https://github.com/org/e2e-test-app.git"
    envsubst < "$TEST_TEMP_DIR/argocd/application.tmpl.yaml" > "$TEST_TEMP_DIR/argocd/application.yaml"
    [ -f "$TEST_TEMP_DIR/argocd/application.yaml" ]
    assert_file_contains "$TEST_TEMP_DIR/argocd/application.yaml" "name: e2e-test-app"
    assert_file_contains "$TEST_TEMP_DIR/argocd/application.yaml" "selfHeal: true"

    # Validate YAML
    python3 -c "
import yaml
yaml.safe_load(open('$TEST_TEMP_DIR/argocd/application.yaml'))
" || {
      echo "Invalid ArgoCD YAML" >&2
      return 1
    }
  fi

  # ── 7. Cleanup test image ────────────────────────────────
  docker rmi "e2e-test-app:v1.0" >/dev/null 2>&1 || true
  docker rmi "localhost:5000/e2e-test-app:v1.0" >/dev/null 2>&1 || true
}

@test "build.sh integrates e2e-test-app end-to-end" {
  # Clean previous generated output
  rm -f "$PROJECT_ROOT/k8s/deploy.yaml" "$PROJECT_ROOT/k8s/svc.yaml" "$PROJECT_ROOT/k8s/ingress.yaml" "$PROJECT_ROOT/argocd/application.yaml"

  run env REGISTRY_CLUSTER_URL=localhost REGISTRY_CLUSTER_PORT=5000 \
    "$PROJECT_ROOT/build.sh" \
    --app-name e2e-test-app --image-tag v1.0 \
    --registry-url localhost --registry-port 5000 \
    --k8s-ns e2e-ns --container-port 8080 \
    --app-repo-url https://github.com/org/e2e-test-app.git \
    --continue-on-error

  # Should have built and tagged the image
  assert_image_exists "e2e-test-app:v1.0"

  # Should have processed templates (output goes to PROJECT_ROOT/k8s/)
  [ -f "$PROJECT_ROOT/k8s/deploy.yaml" ] && \
    assert_file_contains "$PROJECT_ROOT/k8s/deploy.yaml" "e2e-test-app"

  # Cleanup
  docker rmi "e2e-test-app:v1.0" >/dev/null 2>&1 || true
  docker rmi "localhost:5000/e2e-test-app:v1.0" >/dev/null 2>&1 || true
  rm -f "$PROJECT_ROOT/k8s/deploy.yaml" "$PROJECT_ROOT/k8s/svc.yaml" "$PROJECT_ROOT/k8s/ingress.yaml" "$PROJECT_ROOT/argocd/application.yaml"
}
