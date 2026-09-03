#!/usr/bin/env bats

FIXTURES="secrets-vault-standard/fixtures"
DETECTORS="secrets-vault-standard/detectors"

setup() {
  FLAT_FIXTURE="$(mktemp -d)"
  mkdir -p "$FLAT_FIXTURE/k8s"
  cat > "$FLAT_FIXTURE/k8s/external-secret.yaml" <<'EOF'
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: flat-path-secret
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: vault-store
    kind: SecretStore
  target:
    name: flat-secret
  data:
    - secretKey: KEY
      remoteRef:
        key: justonekey
EOF
}

teardown() {
  rm -rf "$FLAT_FIXTURE"
}

# ── vault-eso.sh (VS-001 / VS-002 / VS-003) ──────────────────────────────────

@test "vault-eso: conformant fixture — VS-001 PASS, VS-002 PASS, VS-003 PASS" {
  export KNOWN_STORES="vault-store"
  run bash "$DETECTORS/vault-eso.sh" "$FIXTURES/conformant-vault-eso" k8s
  [ "$status" -eq 0 ]
  [[ "$output" == *"VS-001"*"PASS"* ]]
  [[ "$output" == *"VS-002"*"PASS"* ]]
  [[ "$output" == *"VS-003"*"PASS"* ]]
}

@test "vault-eso: non-conformant-no-vault — VS-001 FAIL, VS-002 FAIL, VS-003 FAIL" {
  export KNOWN_STORES="vault-store"
  run bash "$DETECTORS/vault-eso.sh" "$FIXTURES/non-conformant-no-vault" k8s
  [ "$status" -eq 0 ]
  [[ "$output" == *"VS-001"*"FAIL"* ]]
  [[ "$output" == *"VS-002"*"FAIL"* ]]
  [[ "$output" == *"VS-003"*"FAIL"* ]]
}

@test "vault-eso: unknown-manual-review with missing store — VS-001 UNKNOWN" {
  export KNOWN_STORES=""
  run bash "$DETECTORS/vault-eso.sh" "$FIXTURES/unknown-manual-review" k8s
  [ "$status" -eq 0 ]
  [[ "$output" == *"VS-001"*"UNKNOWN"* ]]
}

@test "vault-eso: na-no-secrets — VS-001 N/A, VS-003 N/A" {
  export KNOWN_STORES=""
  run bash "$DETECTORS/vault-eso.sh" "$FIXTURES/na-no-secrets" k8s
  [ "$status" -eq 0 ]
  [[ "$output" == *"VS-001"*"N/A"* ]]
  [[ "$output" == *"VS-003"*"N/A"* ]]
}

@test "vault-eso: conformant-cluster-store — VS-001 N/A, VS-003 PASS" {
  export KNOWN_STORES="vault-cluster-store"
  run bash "$DETECTORS/vault-eso.sh" "$FIXTURES/conformant-cluster-store" k8s
  [ "$status" -eq 0 ]
  [[ "$output" == *"VS-001"*"N/A"* ]]
  [[ "$output" == *"VS-003"*"PASS"* ]]
}

@test "vault-eso: mixed ESO + manual literal Secret — VS-001 FAIL (FR-004)" {
  MIXED_FIXTURE="$(mktemp -d)"
  mkdir -p "$MIXED_FIXTURE/k8s"
  cat > "$MIXED_FIXTURE/k8s/secret-store.yaml" <<'EOF'
apiVersion: external-secrets.io/v1beta1
kind: SecretStore
metadata:
  name: vault-store
spec:
  provider:
    vault:
      server: https://vault.example.com
      auth:
        kubernetes:
          mountPath: /v1/auth/kubernetes
          role: app
EOF
  cat > "$MIXED_FIXTURE/k8s/external-secret.yaml" <<'EOF'
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: db
spec:
  secretStoreRef:
    name: vault-store
  target:
    name: db-secret
  data:
    - secretKey: password
      remoteRef:
        key: /prod/db/password
EOF
  cat > "$MIXED_FIXTURE/k8s/manual.yaml" <<'EOF'
apiVersion: v1
kind: Secret
metadata:
  name: manual-creds
type: Opaque
stringData:
  apiKey: "literal-static-value"
EOF
  export KNOWN_STORES="vault-store"
  run bash "$DETECTORS/vault-eso.sh" "$MIXED_FIXTURE" k8s
  [ "$status" -eq 0 ]
  [[ "$output" == *"VS-001"*"FAIL"*"mixed patterns"* ]]
  rm -rf "$MIXED_FIXTURE"
}

# ── committed-secrets.sh (VS-006) ─────────────────────────────────────────────

@test "committed-secrets: non-conformant-hardcoded — VS-006 FAIL" {
  run bash "$DETECTORS/committed-secrets.sh" "$FIXTURES/non-conformant-hardcoded" k8s
  [ "$status" -eq 0 ]
  [[ "$output" == *"VS-006"*"FAIL"* ]]
}

@test "committed-secrets: conformant-vault-eso — VS-006 PASS" {
  run bash "$DETECTORS/committed-secrets.sh" "$FIXTURES/conformant-vault-eso" k8s
  [ "$status" -eq 0 ]
  [[ "$output" == *"VS-006"*"PASS"* ]]
}

# ── path-convention.sh (VS-004) ───────────────────────────────────────────────

@test "path-convention: conformant-vault-eso — VS-004 PASS" {
  run bash "$DETECTORS/path-convention.sh" "$FIXTURES/conformant-vault-eso" k8s
  [ "$status" -eq 0 ]
  [[ "$output" == *"VS-004"*"PASS"* ]]
}

@test "path-convention: unknown-manual-review — VS-004 PASS" {
  run bash "$DETECTORS/path-convention.sh" "$FIXTURES/unknown-manual-review" k8s
  [ "$status" -eq 0 ]
  [[ "$output" == *"VS-004"*"PASS"* ]]
}

@test "path-convention: flat path (no leading slash) — VS-004 FAIL" {
  run bash "$DETECTORS/path-convention.sh" "$FLAT_FIXTURE" k8s
  [ "$status" -eq 0 ]
  [[ "$output" == *"VS-004"*"FAIL"* ]]
}

# ── static-tokens.sh (VS-007) ─────────────────────────────────────────────────

@test "static-tokens: conformant-vault-eso — VS-007 PASS" {
  run bash "$DETECTORS/static-tokens.sh" "$FIXTURES/conformant-vault-eso" k8s
  [ "$status" -eq 0 ]
  [[ "$output" == *"VS-007"*"PASS"* ]]
}

@test "static-tokens: raw vault root token — VS-007 FAIL" {
  STATIC_FIXTURE="$(mktemp -d)"
  mkdir -p "$STATIC_FIXTURE/k8s"
  cat > "$STATIC_FIXTURE/k8s/creds.yaml" <<'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: vault-creds
data:
  root-token: "s.abcdefghijklmnopqrstuvwxy1234567890"
EOF
  run bash "$DETECTORS/static-tokens.sh" "$STATIC_FIXTURE" k8s
  [ "$status" -eq 0 ]
  [[ "$output" == *"VS-007"*"FAIL"* ]]
  rm -rf "$STATIC_FIXTURE"
}

@test "static-tokens: VAULT_TOKEN env var — VS-007 FAIL" {
  STATIC_FIXTURE="$(mktemp -d)"
  mkdir -p "$STATIC_FIXTURE/k8s"
  cat > "$STATIC_FIXTURE/k8s/deploy.yaml" <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app
spec:
  template:
    spec:
      containers:
      - name: app
        env:
        - name: VAULT_TOKEN
          value: "hvs.somevalue123456789"
EOF
  run bash "$DETECTORS/static-tokens.sh" "$STATIC_FIXTURE" k8s
  [ "$status" -eq 0 ]
  [[ "$output" == *"VS-007"*"FAIL"* ]]
  rm -rf "$STATIC_FIXTURE"
}

# ── consumption-pattern.sh (VS-005) ───────────────────────────────────────────

@test "consumption-pattern: conformant-vault-eso — VS-005 PASS" {
  run bash "$DETECTORS/consumption-pattern.sh" "$FIXTURES/conformant-vault-eso" k8s
  [ "$status" -eq 0 ]
  [[ "$output" == *"VS-005"*"PASS"* ]]
}

@test "consumption-pattern: deployment consumes manual Secret (not ESO) — VS-005 FAIL" {
  CONSUME_FIXTURE="$(mktemp -d)"
  mkdir -p "$CONSUME_FIXTURE/k8s"
  cat > "$CONSUME_FIXTURE/k8s/external-secret.yaml" <<'EOF'
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: db
spec:
  secretStoreRef:
    name: vault-store
    kind: SecretStore
  target:
    name: db-secret
  data:
    - secretKey: password
      remoteRef:
        key: /prod/db/password
EOF
  cat > "$CONSUME_FIXTURE/k8s/deployment.yaml" <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app
spec:
  template:
    spec:
      containers:
      - name: app
        env:
        - name: DB_PASSWORD
          valueFrom:
            secretKeyRef:
              name: manual-secret
              key: password
EOF
  run bash "$DETECTORS/consumption-pattern.sh" "$CONSUME_FIXTURE" k8s
  [ "$status" -eq 0 ]
  [[ "$output" == *"VS-005"*"FAIL"* ]]
  rm -rf "$CONSUME_FIXTURE"
}
