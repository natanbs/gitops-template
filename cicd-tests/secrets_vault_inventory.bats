load test_helper

setup() {
  setup_test_env
  TEST_INVENTORY=$(mktemp -d)
  export TEST_INVENTORY
}

teardown() {
  rm -rf "$TEST_INVENTORY"
  cleanup
}

# ── inventory.sh parsing ──────────────────────────────────────

@test "inventory.sh emits correct TSV fields for a single YAML" {
  cat > "$TEST_INVENTORY/app.yaml" <<'EOF'
name: "my-app"
repoURL: "https://example.com/repo.git"
appPath: "deploy"
namespace: "prod"
syncWave: "3"
EOF

  run "$PROJECT_ROOT/secrets-vault-standard/inventory.sh" \
    --repo-root "$TEST_TEMP_DIR" \
    --inventory "$TEST_INVENTORY"
  [ "$status" -eq 0 ]
  [ "$output" = "my-app	https://example.com/repo.git	deploy	prod	3	$TEST_TEMP_DIR/my-app	NOT_FOUND" ]
}

@test "inventory.sh marks RESOLVED when {repo-root}/{name} dir exists" {
  mkdir -p "$TEST_TEMP_DIR/my-app"
  cat > "$TEST_INVENTORY/app.yaml" <<'EOF'
name: "my-app"
repoURL: "https://example.com/repo.git"
appPath: "deploy"
namespace: "prod"
syncWave: "1"
EOF

  run "$PROJECT_ROOT/secrets-vault-standard/inventory.sh" \
    --repo-root "$TEST_TEMP_DIR" \
    --inventory "$TEST_INVENTORY"
  [ "$status" -eq 0 ]
  [ "$output" = "my-app	https://example.com/repo.git	deploy	prod	1	$TEST_TEMP_DIR/my-app	RESOLVED" ]
}

@test "inventory.sh marks NOT_FOUND when {repo-root}/{name} dir does not exist" {
  cat > "$TEST_INVENTORY/app.yaml" <<'EOF'
name: "ghost-app"
repoURL: "https://example.com/repo.git"
appPath: "deploy"
namespace: "dev"
syncWave: "2"
EOF

  run "$PROJECT_ROOT/secrets-vault-standard/inventory.sh" \
    --repo-root "$TEST_TEMP_DIR" \
    --inventory "$TEST_INVENTORY"
  [ "$status" -eq 0 ]
  [ "$output" = "ghost-app	https://example.com/repo.git	deploy	dev	2	$TEST_TEMP_DIR/ghost-app	NOT_FOUND" ]
  [ ! -d "$TEST_TEMP_DIR/ghost-app" ]
}

@test "inventory.sh sorts multiple YAML files alphabetically by name" {
  cat > "$TEST_INVENTORY/zeta.yaml" <<'EOF'
name: "zeta-app"
repoURL: "https://example.com/zeta.git"
appPath: "deploy"
namespace: "prod"
syncWave: "3"
EOF
  cat > "$TEST_INVENTORY/alpha.yaml" <<'EOF'
name: "alpha-app"
repoURL: "https://example.com/alpha.git"
appPath: "deploy"
namespace: "dev"
syncWave: "1"
EOF
  cat > "$TEST_INVENTORY/mid.yaml" <<'EOF'
name: "mid-app"
repoURL: "https://example.com/mid.git"
appPath: "deploy"
namespace: "stage"
syncWave: "2"
EOF

  run "$PROJECT_ROOT/secrets-vault-standard/inventory.sh" \
    --repo-root "$TEST_TEMP_DIR" \
    --inventory "$TEST_INVENTORY"
  [ "$status" -eq 0 ]
  first=$(echo "$output" | head -1 | cut -f1)
  last=$(echo "$output" | tail -1 | cut -f1)
  [ "$first" = "alpha-app" ]
  [ "$last" = "zeta-app" ]
  echo "$output" | grep -q 'alpha-app'
  echo "$output" | grep -q 'mid-app'
  echo "$output" | grep -q 'zeta-app'
}

@test "inventory.sh --format json emits parseable JSON with expected fields" {
  cat > "$TEST_INVENTORY/app.yaml" <<'EOF'
name: "json-app"
repoURL: "https://example.com/json.git"
appPath: "deploy"
namespace: "prod"
syncWave: "5"
EOF

  run "$PROJECT_ROOT/secrets-vault-standard/inventory.sh" \
    --repo-root "$TEST_TEMP_DIR" \
    --inventory "$TEST_INVENTORY" \
    --format json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.name == "json-app" and .repoURL == "https://example.com/json.git" and .appPath == "deploy" and .namespace == "prod" and .syncWave == "5" and .localPath == "'"$TEST_TEMP_DIR"'/json-app" and .status == "NOT_FOUND"' >/dev/null
}

# ── inventory.sh argument / inventory errors ─────────────────

@test "inventory.sh exits 2 when inventory path is missing" {
  run "$PROJECT_ROOT/secrets-vault-standard/inventory.sh" \
    --repo-root "$TEST_TEMP_DIR" \
    --inventory "$TEST_INVENTORY/nonexistent"
  [ "$status" -eq 2 ]
  [[ "$output" == *"inventory not found"* ]]
}

@test "inventory.sh exits 2 when --repo-root is missing" {
  run "$PROJECT_ROOT/secrets-vault-standard/inventory.sh" \
    --inventory "$TEST_INVENTORY"
  [ "$status" -eq 2 ]
  [[ "$output" == *"--repo-root is required"* ]]
}

@test "inventory.sh exits 2 on empty inventory directory" {
  run "$PROJECT_ROOT/secrets-vault-standard/inventory.sh" \
    --repo-root "$TEST_TEMP_DIR" \
    --inventory "$TEST_INVENTORY"
  [ "$status" -eq 2 ]
  [[ "$output" == *"no YAML inventory files found"* ]]
}