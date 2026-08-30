#!/usr/bin/env bash
# standards-audit/runner.sh — local, offline standards audit runner.
# Single source of check logic: the reusable Copier/GitHub workflow and
# developers invoke exactly this script. See contracts/cli.md.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECKS_DIR="$SCRIPT_DIR/checks"

usage() {
  cat <<'EOF'
Usage: standards-audit/runner.sh --repo-root <PATH> --repo-profile <app-k8s|app|library>
                                 [--check <id>] [--allowlist <FILE>] [--help]

--repo-root <PATH>       repository root to audit (files resolved relative to it)
--repo-profile <PROFILE> declared profile (default: app-k8s): app-k8s | app | library
--check <id>             run only this check (structure-files|secrets-scan|policy-manifests)
--allowlist <FILE>       exemptions file for the secrets check
                         (default: <repo-root>/standards-audit/allowlist if present)
--help                   show this help and exit 0

Exit codes: 0 = PASS (zero failing checks), 1 = FAIL, 2 = usage/argument error
EOF
}

check_script() {
  case "$1" in
    structure-files) echo "structure.sh" ;;
    secrets-scan) echo "secrets.sh" ;;
    policy-manifests) echo "manifest-policy.sh" ;;
    *) echo "" ;;
  esac
}

usage_error() {
  echo "standards-audit: $1" >&2
  usage >&2
  exit 2
}

REPO_ROOT=""
PROFILE=""
CHECK=""
ALLOWLIST=""

if [[ "$#" -eq 1 && ("$1" == "--help" || "$1" == "-h") ]]; then
  usage
  exit 0
fi

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --repo-root)
      [[ "$#" -ge 2 ]] || usage_error "--repo-root requires an argument"
      REPO_ROOT="$2"
      shift 2
      ;;
    --repo-profile)
      [[ "$#" -ge 2 ]] || usage_error "--repo-profile requires an argument"
      PROFILE="$2"
      shift 2
      ;;
    --check)
      [[ "$#" -ge 2 ]] || usage_error "--check requires an argument"
      CHECK="$2"
      shift 2
      ;;
    --allowlist)
      [[ "$#" -ge 2 ]] || usage_error "--allowlist requires an argument"
      ALLOWLIST="$2"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      usage_error "unknown argument: $1"
      ;;
  esac
done

[[ -n "$REPO_ROOT" ]] || usage_error "--repo-root is required"
[[ -n "$PROFILE" ]] || PROFILE="app-k8s"
case "$PROFILE" in
  app-k8s|app|library) ;;
  *) usage_error "invalid --repo-profile '$PROFILE' (expected app-k8s, app, or library)" ;;
esac
[[ -d "$REPO_ROOT" ]] || usage_error "--repo-root is not a directory: $REPO_ROOT"
if [[ -n "$ALLOWLIST" ]]; then
  [[ -r "$ALLOWLIST" ]] || usage_error "--allowlist is not a readable file: $ALLOWLIST"
fi

CHECK_IDS=()
if [[ -n "$CHECK" ]]; then
  if [[ -z "$(check_script "$CHECK")" ]]; then
    usage_error "unknown --check id '$CHECK' (expected structure-files, secrets-scan, or policy-manifests)"
  fi
  CHECK_IDS=("$CHECK")
else
  CHECK_IDS=(structure-files secrets-scan policy-manifests)
fi

pass=0
fail=0
n_a=0

for check_id in "${CHECK_IDS[@]}"; do
  script="$CHECKS_DIR/$(check_script "$check_id")"
  set +e
  line="$(bash "$script" "$REPO_ROOT" "$PROFILE" "$ALLOWLIST")"
  set -e
  if [[ -n "$line" ]]; then
    printf '%s\n' "$line"
  fi
  case "$line" in
    \[PASS\]*) pass=$((pass + 1)) ;;
    \[N/A\]*) n_a=$((n_a + 1)) ;;
    *) fail=$((fail + 1)) ;;
  esac
done

if [[ "$fail" -eq 0 ]]; then
  verdict="PASS"
else
  verdict="FAIL"
fi

printf 'AUDIT RESULT: %s (%d pass, %d fail, %d n/a)\n' "$verdict" "$pass" "$fail" "$n_a"

if [[ "$verdict" == "FAIL" ]]; then
  exit 1
fi
exit 0