#!/usr/bin/env bats

# secrets-vault-standard/tests/align-fleet.bats
# Offline tests for the VS-004 alignment tool. These exercise the planner and
# the manifest-rewrite path against isolated sandbox fixtures only; no Vault
# cluster or real fleet repo is every touched.

ALIGN="secrets-vault-standard/align-fleet.sh"
PLANNER="secrets-vault-standard/align-plan.py"

setup() {
  SBX="$(mktemp -d)"
  mkdir -p "$SBX/infra/argocd-infra/apps/applicative" "$SBX/app-one/k8s"

  cat > "$SBX/infra/argocd-infra/apps/applicative/app-one.yaml" <<'EOF'
name: app-one
repoURL: https://example.invalid/app-one.git
appPath: k8s
namespace: apps-ns
syncWave: "10"
EOF

  cat > "$SBX/app-one/k8s/external-secret.yaml" <<'EOF'
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: app-one-secrets
  namespace: apps-ns
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: vault-store
    kind: SecretStore
  target:
    name: app-one-secrets
    creationPolicy: Owner
  data:
    - secretKey: API_KEY
      remoteRef:
        key: app/env
        property: API_KEY
        # comment must survive the rewrite
        decodingStrategy: None
EOF
}

teardown() {
  rm -rf "$SBX"
}

# ── planner ─────────────────────────────────────────────────────────────────

@test "align-plan: key+property -> /<env>/<service>/<key> with property kept" {
  run python3 "$PLANNER" "$SBX/app-one/k8s"
  [ "$status" -eq 0 ]
  [[ "$output" == *"external-secret.yaml"* ]]
  [[ "$output" == *"key"* ]]
  [[ "$output" == *"app/env"* ]]
  [[ "$output" == *"/app/env/API_KEY"* ]]
  [[ "$output" == *"ALIGN"* ]]
}

@test "align-plan: extract key gets target-name leaf appended" {
  cat > "$SBX/app-one/k8s/extract.yaml" <<'EOF'
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: app-auth
  namespace: apps-ns
spec:
  secretStoreRef:
    name: vault-store
    kind: ClusterSecretStore
  target:
    name: app-auth
    creationPolicy: Owner
  dataFrom:
  - extract:
      key: app/auth
EOF
  run python3 "$PLANNER" "$SBX/app-one/k8s"
  [ "$status" -eq 0 ]
  [[ "$output" == *"extract"* ]]
  [[ "$output" == *"/app/auth/app-auth"* ]]
}

@test "align-plan: already-conventional 3-segment key is CONFORM" {
  cat > "$SBX/app-one/k8s/conform.yaml" <<'EOF'
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: c
spec:
  secretStoreRef:
    name: vault-store
    kind: SecretStore
  target:
    name: c
  data:
  - secretKey: K
    remoteRef:
      key: /prod/app/KEY
      property: KEY
EOF
  run python3 "$PLANNER" "$SBX/app-one/k8s"
  [ "$status" -eq 0 ]
  [[ "$output" == *"/prod/app/KEY"* ]]
  [[ "$output" == *"CONFORM"* ]]
}

# ── dry-run / apply-manifests through the orchestrator ───────────────────────

@test "align-fleet: dry-run reports plan and exits 1 (pending)" {
  run bash "$ALIGN" --repo-root "$SBX"
  [ "$status" -eq 1 ]
  [[ "$output" == *"ALIGN:"*"1"* ]]
  [[ "$output" == *"/app/env/API_KEY"* ]]
}

@test "align-fleet: dry-run does not modify files" {
  before="$(sha256sum "$SBX/app-one/k8s/external-secret.yaml")"
  run bash "$ALIGN" --repo-root "$SBX"
  after="$(sha256sum "$SBX/app-one/k8s/external-secret.yaml")"
  [ "$before" == "$after" ]
}

@test "align-fleet: --apply-manifests rewrites key line, keeps comment, makes .bak" {
  run bash "$ALIGN" --repo-root "$SBX" --apply-manifests --yes
  [ "$status" -eq 1 ]
  run grep -E "key:" "$SBX/app-one/k8s/external-secret.yaml"
  [[ "$output" == *"key: /app/env/API_KEY"* ]]
  run grep -F "# comment must survive the rewrite" "$SBX/app-one/k8s/external-secret.yaml"
  [ "$status" -eq 0 ]
  [ -f "$SBX/app-one/k8s/external-secret.yaml.bak" ]
}

@test "align-fleet: re-running after apply is clean (exit 0)" {
  run bash "$ALIGN" --repo-root "$SBX" --apply-manifests --yes
  run bash "$ALIGN" --repo-root "$SBX"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ALIGN:"*"0"* ]]
}

@test "align-fleet: missing --repo-root is a usage error (exit 2)" {
  run bash "$ALIGN"
  [ "$status" -eq 2 ]
}

@test "align-fleet: --help exits 0" {
  run bash "$ALIGN" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage:"* ]]
}

@test "align-fleet: --apply-vault recovers old keys from git HEAD when manifests already rewritten" {
  cat > "$SBX/app-one/k8s/extract.yaml" <<'EOF'
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: app-auth
  namespace: apps-ns
spec:
  secretStoreRef:
    name: vault-store
    kind: SecretStore
  target:
    name: app-auth
    creationPolicy: Owner
  dataFrom:
  - extract:
      key: app/auth
EOF
  # committed OLD keys, worktree rewritten (simulates apply-then-migrate ordering)
  git init -q "$SBX"
  git -C "$SBX" config user.email t@t
  git -C "$SBX" config user.name t
  git -C "$SBX" add -A
  git -C "$SBX" commit -qm initial
  run bash "$ALIGN" --repo-root "$SBX" --apply-manifests --yes
  [ "$status" -eq 1 ]

  # stub vault CLI that records calls and serves kv get payloads
  mkdir -p "$SBX/.bin"
  cat > "$SBX/.bin/vault" <<EOF
#!/usr/bin/env bash
echo "VAULT-CALL: \$*" >> "$SBX/vault.log"
if [[ "\$1" == "kv" && "\$2" == "get" ]]; then
  echo '{"data":{"data":{"API_KEY":"x"}}}'
fi
EOF
  chmod +x "$SBX/.bin/vault"
  : > "$SBX/vault.log"

  run env PATH="$SBX/.bin:$PATH" bash "$ALIGN" --repo-root "$SBX" --apply-vault --yes
  [ "$status" -eq 1 ]
  [[ "$output" == *"recovered from git HEAD"* ]]
  [[ "$output" == *"vault kv mv secret/app/auth secret/app/auth/app-auth"* ]]
  [[ "$output" == *"ran 2 Vault KV operation(s)"* ]]
  [[ "$(cat "$SBX/vault.log")" == *"kv get -format=json secret/app/env"* ]]
  [[ "$(cat "$SBX/vault.log")" == *"kv put secret/app/env/API_KEY"* ]]
  [[ "$(cat "$SBX/vault.log")" == *"kv mv secret/app/auth secret/app/auth/app-auth"* ]]
  [[ "$(cat "$SBX/vault.log")" != *"VAULT-CALL: 2"* ]]
}

@test "align-fleet: dry-run on already-rewritten git repo reports only recovery ops, no re-plan" {
  cat > "$SBX/app-one/k8s/extract.yaml" <<'EOF'
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: app-auth
  namespace: apps-ns
spec:
  secretStoreRef:
    name: vault-store
    kind: SecretStore
  target:
    name: app-auth
    creationPolicy: Owner
  dataFrom:
  - extract:
      key: app/auth
EOF
  git init -q "$SBX"
  git -C "$SBX" config user.email t@t
  git -C "$SBX" config user.name t
  git -C "$SBX" add -A
  git -C "$SBX" commit -qm initial
  run bash "$ALIGN" --repo-root "$SBX" --apply-manifests --yes
  [ "$status" -eq 1 ]

  # migration still pending against HEAD -> exit 1, plan shows recovery
  run bash "$ALIGN" --repo-root "$SBX"
  [ "$status" -eq 1 ]
  [[ "$output" == *"ALIGN:"*"0"* ]]
  [[ "$output" == *"recovered from git HEAD"* ]]

  # once the rewrite is committed, recovery ops vanish and dry-run is clean
  git -C "$SBX" add -A
  git -C "$SBX" commit -qm rewritten
  run bash "$ALIGN" --repo-root "$SBX"
  [ "$status" -eq 0 ]
  ! [[ "$output" == *"Vault KV migration"* ]]
  [[ "$output" == *"ALIGN:"*"0"* ]]
  [[ "$output" == *"CONFORM: 2"* ]]
}