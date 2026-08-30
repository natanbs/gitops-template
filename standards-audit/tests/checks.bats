#!/usr/bin/env bats

# checks.bats — US1 fixture-driven tests for standards-audit/runner.sh + checks.
#
# Uses the committed fixtures under standards-audit/fixtures/ (git-tracked so
# the secrets-scan sees the planted credential).

PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"
[ -n "$PROJECT_ROOT" ] || PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RUNNER="$PROJECT_ROOT/standards-audit/runner.sh"
FIXTURES="$PROJECT_ROOT/standards-audit/fixtures"

# Assert that every emit-format FAIL line (starting with "[FAIL]") carries a
# "fix: ..." remediation, and that at least one FAIL is present.
assert_fails_have_fix() {
  local line fails_found=0
  while IFS= read -r line; do
    [[ "$line" == \[FAIL\]* ]] || continue
    fails_found=$((fails_found + 1))
    if [[ "$line" != *"fix:"* ]]; then
      echo "FAIL line missing 'fix:' remediation: $line" >&2
      return 1
    fi
  done
  if [ "$fails_found" -eq 0 ]; then
    echo "expected at least one [FAIL] line" >&2
    return 1
  fi
  return 0
}

assert_has_no_fail() {
  if printf '%s\n' "$output" | grep -q '^\[FAIL\]'; then
    echo "expected no [FAIL] lines, got: $output" >&2
    return 1
  fi
  return 0
}

# ── conformant, .env absent (cross-manifest consistency fallback) ──

@test "conformant-app-k8s-noenv passes app-k8s audit via fallback consistency" {
  run "$RUNNER" --repo-root "$FIXTURES/conformant-app-k8s-noenv" --repo-profile app-k8s
  [ "$status" -eq 0 ]
  [[ "$output" == *"AUDIT RESULT: PASS"* ]]
  [[ "$output" == *"[PASS]	structure-files"* ]]
  [[ "$output" == *"[PASS]	policy-manifests"* ]]
  [[ "$output" == *"[PASS]	secrets-scan"* ]]
  assert_has_no_fail
}

# ── non-conformant: missing file + planted credential + .env conflict ──

@test "non-conformant-app-k8s fails structure (missing Dockerfile) with fix:" {
  run "$RUNNER" --repo-root "$FIXTURES/non-conformant-app-k8s" --repo-profile app-k8s
  [ "$status" -eq 1 ]
  [[ "$output" == *"AUDIT RESULT: FAIL"* ]]
  [[ "$output" == *"Dockerfile missing"* ]]
  [[ "$output" == *"fix:"* ]]
  assert_fails_have_fix <<<"$output"
}

@test "non-conformant-app-k8s secrets-scan flags planted git-tracked credential" {
  run "$RUNNER" --repo-root "$FIXTURES/non-conformant-app-k8s" --repo-profile app-k8s
  [ "$status" -eq 1 ]
  [[ "$output" == *"secrets-scan"* ]]
  [[ "$output" == *"AKIAIOSFODNN7EXAMPLE"* ]]
  [[ "$output" == *"planted.env"* ]]
  [[ "$output" == *"fix:"* ]]
}

@test "non-conformant-app-k8s policy flags .env vs manifest port conflict" {
  run "$RUNNER" --repo-root "$FIXTURES/non-conformant-app-k8s" --repo-profile app-k8s
  [ "$status" -eq 1 ]
  [[ "$output" == *"CONTAINER_PORT=9090"* ]]
  [[ "$output" == *"8080"* ]]
  [[ "$output" == *"fix:"* ]]
}

# ── app-profile N/A semantics: absent inputs never FAIL ──

@test "app-only fixture is N/A for missing app inputs and never fails" {
  run "$RUNNER" --repo-root "$FIXTURES/app-only" --repo-profile app
  [ "$status" -eq 0 ]
  [[ "$output" == *"[N/A]	structure-files"* ]]
  [[ "$output" == *"AUDIT RESULT: PASS"* ]]
  assert_has_no_fail
}

@test "app-k8s profile on an input-less directory is N/A (never FAIL)" {
  run "$RUNNER" --repo-root "$FIXTURES/app-only" --repo-profile app-k8s
  [ "$status" -eq 0 ]
  [[ "$output" == *"[N/A]	structure-files"* ]]
  [[ "$output" == *"[N/A]	policy-manifests"* ]]
  [[ "$output" == *"AUDIT RESULT: PASS"* ]]
  assert_has_no_fail
}

# ── library profile ──

@test "library fixture is N/A and passes (never FAIL)" {
  run "$RUNNER" --repo-root "$FIXTURES/library" --repo-profile library
  [ "$status" -eq 0 ]
  [[ "$output" == *"[N/A]	structure-files"* ]]
  [[ "$output" == *"[N/A]	policy-manifests"* ]]
  [[ "$output" == *"AUDIT RESULT: PASS"* ]]
  assert_has_no_fail
}

# ── .env-present authoritative agreement (T027/T030) ──

@test "conformant-app-k8s-env passes with .env-authoritative equality" {
  run "$RUNNER" --repo-root "$FIXTURES/conformant-app-k8s-env" --repo-profile app-k8s
  [ "$status" -eq 0 ]
  [[ "$output" == *"AUDIT RESULT: PASS"* ]]
  [[ "$output" == *"[PASS]	policy-manifests"* ]]
  assert_has_no_fail
}

@test ".env vs manifest port mismatch fails with fix: (authoritative mode)" {
  tmp="$(mktemp -d)"
  cp -R "$FIXTURES/conformant-app-k8s-env/." "$tmp/"
  sed -i '' 's/containerPort: 8080/containerPort: 8081/' "$tmp/k8s/deploy.yaml"

  run "$RUNNER" --repo-root "$tmp" --repo-profile app-k8s
  [ "$status" -eq 1 ]
  [[ "$output" == *"AUDIT RESULT: FAIL"* ]]
  [[ "$output" == *"CONTAINER_PORT=8080"* ]]
  [[ "$output" == *"8081"* ]]
  [[ "$output" == *"fix:"* ]]
  assert_fails_have_fix <<<"$output"

  rm -rf "$tmp"
}

# ── allowlist exemption (T016/T017) ───────────────────────────────

pair_tmp=""
setup_allowlist_pair() {
  pair_tmp="$(mktemp -d)"
  cp -R "$FIXTURES/non-conformant-app-k8s/." "$pair_tmp/"
}

teardown_allowlist_pair() {
  rm -rf "$pair_tmp"
}

@test "allowlist substring pattern clears the secrets finding" {
  setup_allowlist_pair
  printf '%s\n' 'AKIAIOSFODNN7EXAMPLE   # planted fixture credential' > "$pair_tmp/allowlist.txt"

  run "$RUNNER" --repo-root "$pair_tmp" --repo-profile app-k8s --allowlist "$pair_tmp/allowlist.txt"
  [ "$status" -eq 1 ]
  [[ "$output" != *"secrets-scan"* ]]
  [[ "$output" == *"[FAIL]"* ]]           # structure + policy still fail
  [[ "$output" == *"Dockerfile missing"* ]]
  [[ "$output" == *"[PASS]	secrets-scan"* ]]
  assert_fails_have_fix <<<"$output"
  teardown_allowlist_pair
}

@test "allowlist path pattern (trailing # justification) clears the secrets finding" {
  setup_allowlist_pair
  printf '%s\n' 'standards-audit/fixtures/non-conformant-app-k8s/secrets/planted.env # planted fixture credential' > "$pair_tmp/allowlist.txt"

  run "$RUNNER" --repo-root "$pair_tmp" --repo-profile app-k8s --allowlist "$pair_tmp/allowlist.txt"
  [ "$status" -eq 1 ]
  [[ "$output" == *"[PASS]	secrets-scan"* ]]
  [[ "$output" != *"[FAIL]	secrets-scan"* ]]
  assert_fails_have_fix <<<"$output"
  teardown_allowlist_pair
}

@test "default allowlist at standards-audit/allowlist is auto-discovered" {
  setup_allowlist_pair
  mkdir -p "$pair_tmp/standards-audit"
  printf '%s\n' 'AKIAIOSFODNN7EXAMPLE   # auto-discovered default' > "$pair_tmp/standards-audit/allowlist"

  run "$RUNNER" --repo-root "$pair_tmp" --repo-profile app-k8s
  [ "$status" -eq 1 ]
  [[ "$output" == *"[PASS]	secrets-scan"* ]]
  [[ "$output" != *"[FAIL]	secrets-scan"* ]]
  assert_fails_have_fix <<<"$output"
  teardown_allowlist_pair
}

# ── template-awareness: raw *.tmpl.yaml is never scored as a manifest ──

@test "structure-files skips source templates (*.tmpl.yaml) in k8s/" {
  tmp="$(mktemp -d)"
  cp -R "$FIXTURES/conformant-app-k8s-noenv/." "$tmp/"
  printf '%s\n' '${VOLUME_MOUNTS}' 'image: ${REGISTRY_CLUSTER_URL}:${REGISTRY_CLUSTER_PORT}/${APP_NAME}' > "$tmp/k8s/deploy.tmpl.yaml"

  run "$RUNNER" --repo-root "$tmp" --repo-profile app-k8s --check structure-files
  [ "$status" -eq 0 ]
  [[ "$output" == *"[PASS]	structure-files"* ]]
  [[ "$output" != *"deploy.tmpl.yaml"* ]]
  rm -rf "$tmp"
}

@test "policy-manifests ignores placeholders in tmpl files (no fallback false-positive)" {
  tmp="$(mktemp -d)"
  cp -R "$FIXTURES/conformant-app-k8s-noenv/." "$tmp/"
  printf '%s\n' 'apiVersion: apps/v1' '  namespace: ${K8S_NAMESPACE}' 'image: ${REGISTRY_CLUSTER_URL}:${REGISTRY_CLUSTER_PORT}/${APP_NAME}:${IMAGE_TAG}' > "$tmp/k8s/deploy.tmpl.yaml"

  run "$RUNNER" --repo-root "$tmp" --repo-profile app-k8s --check policy-manifests
  [ "$status" -eq 0 ]
  [[ "$output" == *"[PASS]	policy-manifests"* ]]
  [[ "$output" != *"[FAIL]"* ]]
  rm -rf "$tmp"
}

@test "structure-files still flags malformed non-template manifests" {
  tmp="$(mktemp -d)"
  cp -R "$FIXTURES/conformant-app-k8s-noenv/." "$tmp/"
  printf '%s\n' 'not a mapping key line' > "$tmp/k8s/deploy.yaml"

  run "$RUNNER" --repo-root "$tmp" --repo-profile app-k8s --check structure-files
  [ "$status" -eq 1 ]
  [[ "$output" == *"[FAIL]	k8s/deploy.yaml"* ]]
  [[ "$output" == *"fix:"* ]]
  rm -rf "$tmp"
}

# ── manifest template render contract: PVC=true output stays gate-clean ──

@test "deploy.tmpl.yaml PVC=true render is valid YAML and passes the full audit" {
  tmp="$(mktemp -d)"
  mkdir -p "$tmp/k8s"
  cp "$FIXTURES/conformant-app-k8s-env/.env" "$tmp/.env"
  cp "$FIXTURES/conformant-app-k8s-env/Dockerfile" "$tmp/Dockerfile"

  APP_NAME=audit-demo \
  K8S_NAMESPACE=apps-ns \
  CONTAINER_PORT=8080 \
  IMAGE_TAG=v1.0.0 \
  REGISTRY_CLUSTER_URL=registry.local \
  REGISTRY_CLUSTER_PORT=5000 \
  VOLUME_MOUNTS=$'        volumeMounts:\n        - name: data\n          mountPath: /data' \
  VOLUMES=$'      volumes:\n      - name: data\n        persistentVolumeClaim:\n          claimName: data-pvc' \
    envsubst < "$PROJECT_ROOT/init/k8s/deploy.tmpl.yaml" > "$tmp/k8s/deploy.yaml"

  python3 -c "import yaml; yaml.safe_load(open('$tmp/k8s/deploy.yaml'))"
  grep -q 'claimName: data-pvc' "$tmp/k8s/deploy.yaml"

  run "$RUNNER" --repo-root "$tmp" --repo-profile app-k8s
  [ "$status" -eq 0 ]
  [[ "$output" == *"AUDIT RESULT: PASS"* ]]
  assert_has_no_fail
  rm -rf "$tmp"
}

# ── real-world ConfigMap/NetworkPolicy content must not false-fail ──

@test "structure-files: block-scalar configmap data (config.toml: |) parses cleanly" {
  tmp="$(mktemp -d)"
  touch "$tmp/Dockerfile"
  printf 'CONTAINER_PORT=8888\nK8S_NAMESPACE=apps-ns\n' > "$tmp/.env"
  mkdir -p "$tmp/k8s"
  cat > "$tmp/k8s/deploy.yaml" <<'YAML'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: svc
  namespace: apps-ns
spec:
  template:
    spec:
      containers:
        - name: svc
          image: registry/svc:1.0.0
          ports:
            - containerPort: 8888
YAML
  cat > "$tmp/k8s/configmap.yaml" <<'YAML'
apiVersion: v1
kind: ConfigMap
metadata:
  name: svc-config
  namespace: apps-ns
data:
  config.toml: |
    [auth]
    id = "028873800"
    [scrape]
    min_report_year = 2025
    nested: still-a-value-line
YAML

  run "$RUNNER" --repo-root "$tmp" --repo-profile app-k8s
  [ "$status" -eq 0 ]
  [[ "$output" == *"AUDIT RESULT: PASS"* ]]
  [[ "$output" != *"unexpected line"* ]]
  rm -rf "$tmp"
}

@test "policy-manifests: NetworkPolicy DNS/proxy ports never compared to CONTAINER_PORT" {
  tmp="$(mktemp -d)"
  touch "$tmp/Dockerfile"
  printf 'CONTAINER_PORT=8888\nK8S_NAMESPACE=apps-ns\n' > "$tmp/.env"
  mkdir -p "$tmp/k8s"
  cat > "$tmp/k8s/deploy.yaml" <<'YAML'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: svc
  namespace: apps-ns
spec:
  template:
    spec:
      containers:
        - name: svc
          image: registry/svc:1.0.0
          ports:
            - containerPort: 8888
YAML
  cat > "$tmp/k8s/networkpolicy.yaml" <<'YAML'
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: svc-np
  namespace: apps-ns
spec:
  policyTypes:
  - Ingress
  - Egress
  ingress:
  - ports:
    - port: 8888
      protocol: TCP
  egress:
  - ports:
    - port: 53
      protocol: UDP
    - port: 53
      protocol: TCP
    - port: 443
      protocol: TCP
    to:
    - namespaceSelector: {}
YAML
  cat > "$tmp/k8s/svc.yaml" <<'YAML'
apiVersion: v1
kind: Service
metadata:
  name: svc
  namespace: apps-ns
spec:
  selector:
    app: svc
  ports:
    - port: 8888
      targetPort: 8888
      protocol: TCP
YAML

  run "$RUNNER" --repo-root "$tmp" --repo-profile app-k8s
  [ "$status" -eq 0 ]
  [[ "$output" == *"AUDIT RESULT: PASS"* ]]
  [[ "$output" != *"disagrees with CONTAINER_PORT"* ]]
  rm -rf "$tmp"
}

@test "policy-manifests: aux sidecar service pointing at an unexposed port FAILs with fix" {
  tmp="$(mktemp -d)"
  touch "$tmp/Dockerfile"
  printf 'CONTAINER_PORT=7020\nK8S_NAMESPACE=apps-ns\n' > "$tmp/.env"
  mkdir -p "$tmp/k8s"
  cat > "$tmp/k8s/deploy.yaml" <<'YAML'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: svc
  namespace: apps-ns
spec:
  template:
    spec:
      containers:
        - name: svc
          image: registry/svc:1.0.0
          ports:
            - containerPort: 7020
YAML
  cat > "$tmp/k8s/minio-deploy.yaml" <<'YAML'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: svc-minio
  namespace: apps-ns
spec:
  template:
    spec:
      containers:
        - name: minio
          image: minio/minio:latest
          ports:
            - containerPort: 9000
              name: s3
            - containerPort: 9001
              name: console
YAML
  cat > "$tmp/k8s/minio-svc.yaml" <<'YAML'
apiVersion: v1
kind: Service
metadata:
  name: svc-minio
  namespace: apps-ns
spec:
  selector:
    app: svc-minio
  ports:
    - port: 9000
      targetPort: 9999
      protocol: TCP
YAML

  run "$RUNNER" --repo-root "$tmp" --repo-profile app-k8s
  [ "$status" -eq 1 ]
  [[ "$output" == *"AUDIT RESULT: FAIL"* ]]
  [[ "$output" == *"minio-svc.yaml targetPort 9999 is not exposed by minio-deploy.yaml"* ]]
  [[ "$output" == *"fix:"* ]]
  assert_fails_have_fix <<<"$output"
  rm -rf "$tmp"
}

@test "policy-manifests: valid aux subsystem (minio deploy+svc+ingress) passes coherence" {
  tmp="$(mktemp -d)"
  touch "$tmp/Dockerfile"
  printf 'CONTAINER_PORT=7020\nK8S_NAMESPACE=apps-ns\n' > "$tmp/.env"
  mkdir -p "$tmp/k8s"
  cat > "$tmp/k8s/deploy.yaml" <<'YAML'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: svc
  namespace: apps-ns
spec:
  template:
    spec:
      containers:
        - name: svc
          image: registry/svc:1.0.0
          ports:
            - containerPort: 7020
YAML
  cat > "$tmp/k8s/minio-deploy.yaml" <<'YAML'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: svc-minio
  namespace: apps-ns
spec:
  template:
    spec:
      containers:
        - name: minio
          image: minio/minio:latest
          ports:
            - containerPort: 9000
              name: s3
            - containerPort: 9001
              name: console
YAML
  cat > "$tmp/k8s/minio-svc.yaml" <<'YAML'
apiVersion: v1
kind: Service
metadata:
  name: svc-minio
  namespace: apps-ns
spec:
  selector:
    app: svc-minio
  ports:
    - port: 9000
      targetPort: 9000
      protocol: TCP
YAML
  cat > "$tmp/k8s/minio-ingress.yaml" <<'YAML'
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: svc-minio
  namespace: apps-ns
spec:
  rules:
  - host: minio.lab
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: svc-minio
            port:
              number: 9000
YAML

  run "$RUNNER" --repo-root "$tmp" --repo-profile app-k8s
  [ "$status" -eq 0 ]
  [[ "$output" == *"AUDIT RESULT: PASS"* ]]
  rm -rf "$tmp"
}