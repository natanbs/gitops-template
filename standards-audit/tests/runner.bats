#!/usr/bin/env bats

# runner.bats — US5 offline determinism + no-new-dependency tests.
#
# Regressions the audit must never introduce:
#   - no network calls in check/runner paths (no git fetch/pull/clone/ls-remote,
#     curl, wget, or cluster tooling docker/kubectl/helm/argocd)
#   - byte-for-byte deterministic output for a fixed repo state
#   - offline-only: no remote required to audit a repo

PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"
[ -n "$PROJECT_ROOT" ] || PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RUNNER="$PROJECT_ROOT/standards-audit/runner.sh"
FIXTURES="$PROJECT_ROOT/standards-audit/fixtures"

@test "check and runner sources never invoke network or cluster tooling" {
  run grep -nE \
    '(^|[;&|[:space:]])(git[[:space:]]+(fetch|pull|push|clone|ls-remote|submodule)|curl|wget|docker|kubectl|helm|argocd)([[:space:]]|$)' \
    "$PROJECT_ROOT/standards-audit/runner.sh" \
    "$PROJECT_ROOT"/standards-audit/checks/*.sh
  [ "$status" -ne 0 ]
}

@test "runner output is byte-for-byte deterministic across runs" {
  run "$RUNNER" --repo-root "$FIXTURES/conformant-app-k8s-noenv" --repo-profile app-k8s
  [ "$status" -eq 0 ]
  first="$output"

  run "$RUNNER" --repo-root "$FIXTURES/conformant-app-k8s-noenv" --repo-profile app-k8s
  [ "$status" -eq 0 ]
  [ "$first" = "$output" ]
}

@test "runner stays deterministic in FAIL state too" {
  run "$RUNNER" --repo-root "$FIXTURES/conformant-app-k8s-env" --repo-profile app-k8s --check policy-manifests
  [ "$status" -eq 0 ]
  first="$output"

  run "$RUNNER" --repo-root "$FIXTURES/conformant-app-k8s-env" --repo-profile app-k8s --check policy-manifests
  [ "$status" -eq 0 ]
  [ "$first" = "$output" ]
}

@test "audit succeeds offline: no remotes configured during scan" {
  tmp="$(mktemp -d)"
  cp -R "$FIXTURES/conformant-app-k8s-noenv/." "$tmp/"
  git -C "$tmp" init >/dev/null 2>&1
  git -C "$tmp" remote -v >/dev/null 2>&1 || true

  run "$RUNNER" --repo-root "$tmp" --repo-profile app-k8s
  [ "$status" -eq 0 ]
  [[ "$output" == *"AUDIT RESULT: PASS"* ]]
  rm -rf "$tmp"
}

@test "per-check invocation is deterministic and independent of run order" {
  run "$RUNNER" --repo-root "$FIXTURES/non-conformant-app-k8s" --repo-profile app-k8s --check secrets-scan
  [ "$status" -eq 1 ]
  first="$output"

  run "$RUNNER" --repo-root "$FIXTURES/non-conformant-app-k8s" --repo-profile app-k8s --check secrets-scan
  [ "$status" -eq 1 ]
  [ "$first" = "$output" ]
}

@test "repo-profile defaults to app-k8s when omitted (identical to explicit)" {
  run "$RUNNER" --repo-root "$FIXTURES/conformant-app-k8s-env"
  [ "$status" -eq 0 ]
  default_out="$output"

  run "$RUNNER" --repo-root "$FIXTURES/conformant-app-k8s-env" --repo-profile app-k8s
  [ "$status" -eq 0 ]
  [ "$default_out" = "$output" ]
}