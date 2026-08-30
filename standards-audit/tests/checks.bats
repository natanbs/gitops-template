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