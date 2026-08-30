#!/usr/bin/env bats

# workflow.bats — contract checks for the reusable standards-audit workflow
# (.github/workflows/standards-audit.yml) and its documented caller example
# (examples/standards-audit-caller.yml).

PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"
[ -n "$PROJECT_ROOT" ] || PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WORKFLOW="$PROJECT_ROOT/.github/workflows/standards-audit.yml"
CALLER="$PROJECT_ROOT/examples/standards-audit-caller.yml"

yqq() { # yqq <query> <file>
  yq eval "$1" "$2"
}

# Assert that every `uses:` reference in the given file is a full 40-hex SHA
# (optionally with a trailing `# version` comment) — no mutable tag/branch refs.
assert_all_uses_pinned_to_sha() {
  local file="$1" line ref
  local count=0
  while IFS= read -r line; do
    ref="${line#*@}"
    if [[ ! "$ref" =~ ^[0-9a-f]{40}([[:space:]]*#.*)?$ ]]; then
      echo "unpinned uses: $line" >&2
      return 1
    fi
    count=$((count + 1))
  done < <(grep -E '^[[:space:]]*uses:' "$file" | sed -E 's/^[[:space:]]*uses:[[:space:]]*//')
  if [ "$count" -eq 0 ]; then
    echo "expected at least one uses: reference in $file" >&2
    return 1
  fi
  return 0
}

# ── reusable workflow: shape & inputs ─────────────────────────────

@test "workflow YAML parses" {
  run yqq '.' "$WORKFLOW"
  [ "$status" -eq 0 ]
}

@test "workflow declares exactly one job, the audit job" {
  run yqq '.jobs | keys | length' "$WORKFLOW"
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]
  run yqq '.jobs.audit.runs-on' "$WORKFLOW"
  [ "$output" = "ubuntu-latest" ]
}

@test "workflow exposes repo-profile (required) and repo-root (default '.')" {
  run yqq '.on.workflow_call.inputs["repo-profile"].required' "$WORKFLOW"
  [ "$output" = "true" ]
  run yqq '.on.workflow_call.inputs["repo-profile"].type' "$WORKFLOW"
  [ "$output" = "string" ]
  run yqq '.on.workflow_call.inputs["repo-root"].required' "$WORKFLOW"
  [ "$output" = "false" ]
  run yqq '.on.workflow_call.inputs["repo-root"].default' "$WORKFLOW"
  [ "$output" = "." ]
}

@test "workflow carries minimal permissions and no secrets/id-token" {
  run yqq '.permissions["contents"]' "$WORKFLOW"
  [ "$output" = "read" ]
  run yqq '.permissions | has("id-token")' "$WORKFLOW"
  [ "$output" = "false" ]
  run yqq '.on.workflow_call | has("secrets")' "$WORKFLOW"
  [ "$output" = "false" ]
}

@test "workflow references actions/checkout: SHA-pinned, no mutable refs" {
  assert_all_uses_pinned_to_sha "$WORKFLOW"
}

@test "workflow invokes the runner with repo-root and repo-profile" {
  grep -q 'standards-audit/runner.sh' "$WORKFLOW"
  grep -q -- '--repo-root' "$WORKFLOW"
  grep -q -- '--repo-profile' "$WORKFLOW"
}

# ── caller example ────────────────────────────────────────────────

@test "caller example YAML parses" {
  run yqq '.' "$CALLER"
  [ "$status" -eq 0 ]
}

@test "caller imports the reusable workflow on a pinned (non-mutable) ref" {
  grep -q 'standards-audit.yml@' "$CALLER"
  local uses_line
  uses_line="$(grep -E '^[[:space:]]*uses:' "$CALLER")"
  ! echo "$uses_line" | grep -qE '@(main|master|latest|[vV][0-9])'
}

@test "caller passes repo-profile and job permissions contents: read" {
  run yqq '.jobs.standards.with["repo-profile"]' "$CALLER"
  [ "$output" = "app-k8s" ]
  run yqq '.jobs.standards.permissions["contents"]' "$CALLER"
  [ "$output" = "read" ]
  run yqq '.jobs.standards | has("secrets")' "$CALLER"
  [ "$output" = "false" ]
}