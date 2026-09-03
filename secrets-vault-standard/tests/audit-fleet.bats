#!/usr/bin/env bats
# secrets-vault-standard/tests/audit-fleet.bats — integration tests for audit-fleet.sh

AUDIT="$BATS_TEST_DIRNAME/../audit-fleet.sh"
FIXTURES="$BATS_TEST_DIRNAME/../fixtures"
INVENTORY_DIR="$BATS_TEST_DIRNAME/../../specs/013-secrets-vault-standard/checklists/fixture-inventory"

setup() {
  [ -d "$FIXTURES" ]
  [ -d "$INVENTORY_DIR" ]
  [ -x "$AUDIT" ]
}

# ── markdown output ──────────────────────────────────────────

@test "markdown: exits 1 for non-conforming repos" {
  run "$AUDIT" --repo-root "$FIXTURES" --inventory "$INVENTORY_DIR"
  [ "$status" -eq 1 ]
}

@test "markdown: summary contains NON-CONFORMING count 4" {
  run "$AUDIT" --repo-root "$FIXTURES" --inventory "$INVENTORY_DIR"
  [ "$status" -eq 1 ]
  [[ "$output" == *"NON-CONFORMING | 4"* ]]
}

@test "markdown: summary contains CONFORMING count 2" {
  run "$AUDIT" --repo-root "$FIXTURES" --inventory "$INVENTORY_DIR"
  [ "$status" -eq 1 ]
  [[ "$output" == *"CONFORMING | 2"* ]]
}

@test "markdown: summary contains N/A count 1" {
  run "$AUDIT" --repo-root "$FIXTURES" --inventory "$INVENTORY_DIR"
  [ "$status" -eq 1 ]
  [[ "$output" == *"N/A | 1"* ]]
}

@test "markdown: summary contains UNKNOWN count 1" {
  run "$AUDIT" --repo-root "$FIXTURES" --inventory "$INVENTORY_DIR"
  [ "$status" -eq 1 ]
  [[ "$output" == *"UNKNOWN | 1"* ]]
}

@test "markdown: conformant-vault-eso listed as CONFORMING" {
  run "$AUDIT" --repo-root "$FIXTURES" --inventory "$INVENTORY_DIR"
  [ "$status" -eq 1 ]
  [[ "$output" == *"conformant-vault-eso — CONFORMING"* ]]
}

@test "markdown: non-conformant-hardcoded listed as NON-CONFORMING" {
  run "$AUDIT" --repo-root "$FIXTURES" --inventory "$INVENTORY_DIR"
  [ "$status" -eq 1 ]
  [[ "$output" == *"non-conformant-hardcoded — NON-CONFORMING"* ]]
}

@test "markdown: unknown-manual-review listed as UNKNOWN" {
  run "$AUDIT" --repo-root "$FIXTURES" --inventory "$INVENTORY_DIR"
  [ "$status" -eq 1 ]
  [[ "$output" == *"unknown-manual-review — UNKNOWN"* ]]
}

# ── JSON output ──────────────────────────────────────────────

@test "json: exits 1 for non-conforming repos" {
  run "$AUDIT" --repo-root "$FIXTURES" --inventory "$INVENTORY_DIR" --format json
  [ "$status" -eq 1 ]
}

@test "json: summary contains conforming:2" {
  run "$AUDIT" --repo-root "$FIXTURES" --inventory "$INVENTORY_DIR" --format json
  [ "$status" -eq 1 ]
  [[ "$output" == *'"conforming":2'* ]]
}

@test "json: summary contains nonConforming:4" {
  run "$AUDIT" --repo-root "$FIXTURES" --inventory "$INVENTORY_DIR" --format json
  [ "$status" -eq 1 ]
  [[ "$output" == *'"nonConforming":4'* ]]
}

@test "json: output is valid JSON" {
  run "$AUDIT" --repo-root "$FIXTURES" --inventory "$INVENTORY_DIR" --format json
  [ "$status" -eq 1 ]
  echo "$output" | jq . >/dev/null 2>&1
  [ "$?" -eq 0 ]
}

# ── exit code 2 for bad inventory ────────────────────────────

@test "exits 2 for nonexistent inventory path" {
  run "$AUDIT" --repo-root "$FIXTURES" --inventory /nonexistent/path
  [ "$status" -eq 2 ]
}

# ── T033: default invocation (--repo-root only) does not crash ──────────────
# The default inventory resolves to <repo-root>/infra/argocd-infra/apps/applicative.
# This regression test guards against the empty-array expansion crash that
# previously aborted the default invocation on bash 3.2 (unbound variable).

@test "default invocation resolves repo-root inventory without crashing (T033)" {
  DEFAULT_ROOT="$(mktemp -d)"
  mkdir -p "$DEFAULT_ROOT/infra/argocd-infra/apps/applicative"
  mkdir -p "$DEFAULT_ROOT/sample-app/k8s"
  cat > "$DEFAULT_ROOT/infra/argocd-infra/apps/applicative/sample-app.yaml" <<'EOF'
name: sample-app
repoURL: https://example.com/sample.git
appPath: k8s
namespace: prod
syncWave: "1"
EOF
  cat > "$DEFAULT_ROOT/sample-app/k8s/secret-store.yaml" <<'EOF'
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
  cat > "$DEFAULT_ROOT/sample-app/k8s/external-secret.yaml" <<'EOF'
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: sample
spec:
  secretStoreRef:
    name: vault-store
  target:
    name: sample-secret
  data:
    - secretKey: password
      remoteRef:
        key: /prod/sample/password
EOF
  # no --inventory: default path must resolve from --repo-root
  run "$AUDIT" --repo-root "$DEFAULT_ROOT"
  rm -rf "$DEFAULT_ROOT"
  [ "$status" -ne 2 ]
  [ "$status" -ne 126 ]
  [ "$status" -ne 127 ]
  [[ "$output" == *"sample-app"* ]]
}

# ── exit code 3 for repos not found locally ──────────────────

@test "exits 3 when inventory lists repos not present locally" {
  GHOST_DIR=$(mktemp -d)
  cat > "$GHOST_DIR/ghost.yaml" <<'EOF'
name: ghost-repo
repoURL: https://example.com/ghost.git
appPath: k8s
namespace: prod
syncWave: "1"
EOF
  run "$AUDIT" --repo-root "$FIXTURES" --inventory "$GHOST_DIR"
  rm -rf "$GHOST_DIR"
  [ "$status" -eq 3 ]
}

# ── T034: unreachable repo surfaced as UNKNOWN, not dropped from count ─────────
# spec.md edge case + SC-001: no inventory URL may be left unassessed.

@test "unreachable repo is surfaced as UNKNOWN with reason and counted (T034)" {
  GHOST_ROOT="$(mktemp -d)"
  mkdir -p "$GHOST_ROOT/present-app/k8s"
  cat > "$GHOST_ROOT/present-app.yaml" <<'EOF'
name: present-app
repoURL: https://example.com/present.git
appPath: k8s
namespace: prod
syncWave: "1"
EOF
  cat > "$GHOST_ROOT/ghost-app.yaml" <<'EOF'
name: ghost-app
repoURL: https://example.com/ghost.git
appPath: k8s
namespace: prod
syncWave: "1"
EOF
  cat > "$GHOST_ROOT/present-app/k8s/secret-store.yaml" <<'EOF'
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
  # present-app resolves (has no store ref issue -> CONFORMING); ghost-app is NOT_FOUND
  run "$AUDIT" --repo-root "$GHOST_ROOT" --inventory "$GHOST_ROOT"
  rm -rf "$GHOST_ROOT"
  [ "$status" -eq 3 ]
  [[ "$output" == *"ghost-app — UNKNOWN"* ]]
  [[ "$output" == *"Repo not found locally"* ]]
  [[ "$output" == *"UNKNOWN | 1"* ]]
  [[ "$output" == *"**Total** | **2**"* ]]
}

# ── verbose flag ─────────────────────────────────────────────

@test "verbose: stderr contains scanning messages" {
  run bash -c '"$0" --repo-root "$1" --inventory "$2" --verbose 2>&1' \
    "$AUDIT" "$FIXTURES" "$INVENTORY_DIR"
  [ "$status" -eq 1 ]
  [[ "$output" == *"scanning conformant-vault-eso"* ]]
}

# ── FR-004: mixed-pattern repo must be NON-CONFORMING ─────────────────────────

@test "mixed Vault-ESO + manual Secret is NON-CONFORMING (FR-004)" {
  MIXED_ROOT="$(mktemp -d)"
  mkdir -p "$MIXED_ROOT/mixed-repo/k8s"
  cat > "$MIXED_ROOT/mixed-repo/k8s/secret-store.yaml" <<'EOF'
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
  cat > "$MIXED_ROOT/mixed-repo/k8s/external-secret.yaml" <<'EOF'
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
  cat > "$MIXED_ROOT/mixed-repo/k8s/manual.yaml" <<'EOF'
apiVersion: v1
kind: Secret
metadata:
  name: manual-creds
type: Opaque
stringData:
  apiKey: "literal-static-value"
EOF
  cat > "$MIXED_ROOT/mixed-repo.yaml" <<'EOF'
name: mixed-repo
repoURL: https://example.com/mixed.git
appPath: k8s
namespace: prod
syncWave: "1"
EOF
  run "$AUDIT" --repo-root "$MIXED_ROOT" --inventory "$MIXED_ROOT/mixed-repo.yaml"
  rm -rf "$MIXED_ROOT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"mixed-repo — NON-CONFORMING"* ]]
  [[ "$output" == *"mixed patterns"* ]]
}
