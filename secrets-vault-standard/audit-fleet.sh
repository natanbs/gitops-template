#!/usr/bin/env bash
# secrets-vault-standard/audit-fleet.sh — fleet-wide secrets & Vault standard audit.
# Orchestrates: inventory enumeration -> per-repo detection -> verdict aggregation
# -> markdown/json report. See contracts/audit-cli.md and contracts/report.md.
#
# Verdicts per repo (data-model.md + standard.md):
#   CONFORMING     every Primary rule PASS (VS-001/002/003/006) and no advisory FAIL
#   NON-CONFORMING at least one Primary rule FAIL
#   N/A            no secrets infrastructure (all evaluated rules N/A)
#   UNKNOWN        a rule verdict is UNKNOWN (unresolvable store ref) with no Primary FAIL
# Advisory rules (VS-004) are scored/reported but never flip the verdict alone.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DETECTORS_DIR="$SCRIPT_DIR/detectors"

usage() {
  cat <<'EOF'
Usage: secrets-vault-standard/audit-fleet.sh [OPTIONS]

--inventory <path>       ArgoCD applicative inventory YAML file or directory
                         (default: <repo-root>/infra/argocd-infra/apps/applicative)
--repo-root <path>       base dir where repos are cloned (required)
--output <path>          write report to file instead of stdout
--format <fmt>           markdown (default) | json
--standard-version <ver> standard version to score against (default: 1.0.0)
--scan-root              also scan repo-root non-appPath config files (VS-006)
--verbose                print per-file detection details to stderr
--help                   show this help and exit 0

Exit codes:
  0  all repos CONFORMING or N/A (nonConforming = 0)
  1  one or more repos NON-CONFORMING
  2  inventory not found or unparseable
  3  one or more repos not found locally (resolution failure)
EOF
}

usage_error() {
  echo "secrets-vault-standard/audit-fleet: $1" >&2
  usage >&2
  exit 2
}

INVENTORY=""
REPO_ROOT=""
OUTPUT=""
FORMAT="markdown"
STANDARD_VERSION="1.0.0"
SCAN_ROOT=0
VERBOSE=0

if [[ "$#" -eq 1 && ("$1" == "--help" || "$1" == "-h") ]]; then
  usage
  exit 0
fi

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --inventory)
      [[ "$#" -ge 2 ]] || usage_error "--inventory requires an argument"
      INVENTORY="$2"; shift 2 ;;
    --repo-root)
      [[ "$#" -ge 2 ]] || usage_error "--repo-root requires an argument"
      REPO_ROOT="$2"; shift 2 ;;
    --output)
      [[ "$#" -ge 2 ]] || usage_error "--output requires an argument"
      OUTPUT="$2"; shift 2 ;;
    --format)
      [[ "$#" -ge 2 ]] || usage_error "--format requires an argument"
      FORMAT="$2"; shift 2 ;;
    --standard-version)
      [[ "$#" -ge 2 ]] || usage_error "--standard-version requires an argument"
      STANDARD_VERSION="$2"; shift 2 ;;
    --scan-root)
      SCAN_ROOT=1; shift ;;
    --verbose)
      VERBOSE=1; shift ;;
    --help|-h)
      usage; exit 0 ;;
    *)
      usage_error "unknown argument: $1" ;;
  esac
done

[[ -n "$REPO_ROOT" ]] || usage_error "--repo-root is required"
[[ -d "$REPO_ROOT" ]] || usage_error "--repo-root is not a directory: $REPO_ROOT"
case "$FORMAT" in
  markdown|json) ;;
  *) usage_error "invalid --format '$FORMAT' (expected markdown or json)" ;;
esac

if [[ -n "$INVENTORY" ]]; then
  INVENTORY_ARG=(--inventory "$INVENTORY")
else
  INVENTORY_ARG=()
fi

# --- 1. enumerate fleet -------------------------------------------------------
IFS=$'\n' read -r -d '' -a apps < <( \
  "$SCRIPT_DIR/inventory.sh" --repo-root "$REPO_ROOT" ${INVENTORY_ARG[@]+"${INVENTORY_ARG[@]}"} --format tsv \
  || true ) || true

# empty/invalid inventory -> exit 2 (inventory.sh already printed the reason)
if [[ "${#apps[@]}" -eq 0 ]]; then
  echo "secrets-vault-standard/audit-fleet: inventory yielded no apps" >&2
  exit 2
fi

# Inventory path for the report header
if [[ -z "$INVENTORY" ]]; then
  HEADER_INVENTORY="$REPO_ROOT/infra/argocd-infra/apps/applicative"
else
  HEADER_INVENTORY="$INVENTORY"
fi

# --- 2. separate found from not-found; build known-store set --------------------
# Known stores = all SecretStore/ClusterSecretStore names declared across the
# audited (RESOLVED) repos' appPaths, resolved fleet-wide per standard.md VS-001.
declare -a resolved_apps
declare -a not_found_apps
not_found=0
known_stores=""
for app in "${apps[@]}"; do
  IFS=$'\t' read -r name _repo _path _ns _wave local_path status <<<"$app"
  if [[ "$status" != "RESOLVED" ]]; then
    not_found=$((not_found + 1))
    not_found_apps+=("$name"$'\t'"$local_path")
    echo "secrets-vault-standard/audit-fleet: repo '$name' not found locally ($local_path) — flagged UNKNOWN (manual review)" >&2
    continue
  fi
  resolved_apps+=("$app")
  # gather store names: only from files containing kind: SecretStore or ClusterSecretStore
  if [[ -d "$local_path/$_path" ]]; then
    while IFS= read -r f; do
      [[ -f "$f" ]] || continue
      # strip comments for immunity
      body="$(sed -E '/^[[:space:]]*#/d; /^[[:space:]]*\/\//d' "$f" 2>/dev/null || true)"
      # must contain a Store kind
      printf '%s\n' "$body" | grep -qE '^kind:[[:space:]]+(SecretStore|ClusterSecretStore)' || continue
      # extract metadata.name (first name: in a standard K8s YAML appears under metadata, before kind:)
      sn="$(printf '%s\n' "$body" | awk '/^[[:space:]]*name:/{ sub(/^[[:space:]]*name:[[:space:]]*/, ""); sub(/[[:space:]]+$/, ""); sub(/^["'"'"']/, ""); sub(/["'"'"']$/, ""); print; exit }')"
      [[ -n "$sn" ]] || continue
      case " $known_stores " in
        *" $sn "*) : ;;
        *) known_stores="$known_stores $sn" ;;
      esac
    done < <(find "$local_path/$_path" -maxdepth 1 -type f \( -name '*.yaml' -o -name '*.yml' \) | sort)
  fi
done

if [[ "${#resolved_apps[@]}" -eq 0 && "${#not_found_apps[@]}" -eq 0 ]]; then
  echo "secrets-vault-standard/audit-fleet: no repos resolved locally" >&2
  exit 3
fi

# --- 3. per-repo scoring ---------------------------------------------------------
# Build a temp results dir; each repo writes '<name>.tsv' of detector lines.
_tmp="$(mktemp -d 2>/dev/null || mktemp -d /tmp/sva-XXXXXX)"
trap 'rm -rf "$_tmp"' EXIT

conforming=0; non_conforming=0; na_repos=0; unknown_repos=0
: > "$_tmp/_verdicts.tsv"

for app in ${resolved_apps[@]+"${resolved_apps[@]}"}; do
  IFS=$'\t' read -r name _repo app_path _ns _wave local_path _status <<<"$app"
  : > "$_tmp/results-$name.tsv"

  [[ "$VERBOSE" -eq 1 ]] && echo "secrets-vault-standard/audit-fleet: scanning $name ($local_path/$app_path)" >&2

  # vault-eso.sh : VS-001/002/003
  KNOWN_STORES="$known_stores" "$DETECTORS_DIR/vault-eso.sh" "$local_path" "$app_path" "$name" \
    >> "$_tmp/results-$name.tsv" 2>/dev/null || true
  # committed-secrets.sh : VS-006
  if [[ "$SCAN_ROOT" -eq 1 ]]; then
    SCAN_ROOT=1 "$DETECTORS_DIR/committed-secrets.sh" "$local_path" "$app_path" \
      >> "$_tmp/results-$name.tsv" 2>/dev/null || true
  else
    SCAN_ROOT=0 "$DETECTORS_DIR/committed-secrets.sh" "$local_path" "$app_path" \
      >> "$_tmp/results-$name.tsv" 2>/dev/null || true
  fi
  # static-tokens.sh : VS-007 (primary/blocking)
  if [[ "$SCAN_ROOT" -eq 1 ]]; then
    SCAN_ROOT=1 "$DETECTORS_DIR/static-tokens.sh" "$local_path" "$app_path" \
      >> "$_tmp/results-$name.tsv" 2>/dev/null || true
  else
    SCAN_ROOT=0 "$DETECTORS_DIR/static-tokens.sh" "$local_path" "$app_path" \
      >> "$_tmp/results-$name.tsv" 2>/dev/null || true
  fi
  # path-convention.sh : VS-004
  "$DETECTORS_DIR/path-convention.sh" "$local_path" "$app_path" \
    >> "$_tmp/results-$name.tsv" 2>/dev/null || true
  # consumption-pattern.sh : VS-005
  "$DETECTORS_DIR/consumption-pattern.sh" "$local_path" "$app_path" \
    >> "$_tmp/results-$name.tsv" 2>/dev/null || true

  # aggregate verdicts using rules that actually gate (data-model + standard.md):
  #   primary: VS-001, VS-002, VS-003, VS-006, VS-007 (fail flips verdict)
  #   advisory: VS-004, VS-005                      (scored, never gates alone)
  #   VS-002 UNKNOWN → contributes UNKNOWN (unresolved store)
  #   N/A: VS-001 AND VS-003 both N/A → no secrets infrastructure detected
  has_fail=0; has_unknown=0
  vs001_v="N/A"; vs003_v="N/A"
  while IFS=$'\t' read -r code v _ev _fx; do
    [[ -n "$code" ]] || continue
    # capture store/external-secret infra state for N/A detection
    case "$code" in
      VS-001) vs001_v="$v" ;;
      VS-003) vs003_v="$v" ;;
    esac
    case "$code" in
      VS-004|VS-005) ;; # advisory — never gate
      *)      # primary rules gate the verdict
        case "$v" in
          FAIL)    has_fail=1 ;;
          UNKNOWN) has_unknown=1 ;;
        esac ;;
    esac
  done < "$_tmp/results-$name.tsv"

  if [[ "$has_fail" -eq 1 ]]; then
    verdict="NON-CONFORMING"
    non_conforming=$((non_conforming + 1))
  elif [[ "$has_unknown" -eq 1 ]]; then
    verdict="UNKNOWN"
    unknown_repos=$((unknown_repos + 1))
  elif [[ "$vs001_v" == "N/A" && "$vs003_v" == "N/A" ]]; then
    verdict="N/A"
    na_repos=$((na_repos + 1))
  else
    verdict="CONFORMING"
    conforming=$((conforming + 1))
  fi
  printf '%s\t%s\t%s\n' "$name" "$verdict" "$local_path" >> "$_tmp/_verdicts.tsv"
done

# --- 3b. surface unresolved (NOT_FOUND) repos as UNKNOWN ---------------------------
# Per the spec edge case (spec.md:99) and SC-001, no inventory URL may be left
# unassessed: an unreachable/no-local-checkout repo is reported UNKNOWN with the
# reason and included in the fleet total (never silently dropped). Resolution
# failure is still communicated via exit code 3 (audit-cli.md).
if [[ "$not_found" -gt 0 ]]; then
  : > "$_tmp/_notfound.tsv"
  for nf in "${not_found_apps[@]}"; do
    IFS=$'\t' read -r nname npath <<<"$nf"
    printf '%s\tUNKNOWN\t%s\n' "$nname" "$npath" >> "$_tmp/_verdicts.tsv"
    printf '%s\t%s\n' "$nname" "$npath" >> "$_tmp/_notfound.tsv"
    unknown_repos=$((unknown_repos + 1))
  done
fi

# --- 4. exit code -----------------------------------------------------------------
if [[ "$non_conforming" -gt 0 ]]; then
  exit_code=1
else
  exit_code=0
fi

# --- 4b. emit fleet meta for report.sh ----------------------------------------------
# _fleet.tsv : <name>\t<verdict>\t<localPath>  (sorted by name)
sort -k1,1 < "$_tmp/_verdicts.tsv" > "$_tmp/_fleet.tsv"

# _summary.tsv : <key>\t<value>
{
  printf 'conforming\t%s\n' "$conforming"
  printf 'nonConforming\t%s\n' "$non_conforming"
  printf 'na\t%s\n' "$na_repos"
  printf 'unknown\t%s\n' "$unknown_repos"
  printf 'total\t%s\n' "$((conforming + non_conforming + na_repos + unknown_repos))"
  printf 'exitCode\t%s\n' "$exit_code"
  printf 'notFound\t%s\n' "$not_found"
} > "$_tmp/_summary.tsv"

# --- 5. render report ---------------------------------------------------------------
# report.sh consumes the per-repo results TSVs. If not found, emit the report inline.
if [[ -x "$SCRIPT_DIR/report.sh" ]]; then
  report_args=(
    --inventory "$HEADER_INVENTORY"
    --repo-root "$REPO_ROOT"
    --standard-version "$STANDARD_VERSION"
    --format "$FORMAT"
    --results-dir "$_tmp"
  )
  if [[ "$SCAN_ROOT" -eq 1 ]]; then
    report_args+=(--scan-root)
  fi
  body="$("$SCRIPT_DIR/report.sh" "${report_args[@]}" 2>/dev/null || true)"
else
  body="# Secrets &amp; Vault Standard Fleet Report

**Standard**: secrets-vault-standard v$STANDARD_VERSION
**Inventory**: $HEADER_INVENTORY
**Date**: $(date -u +%Y-%m-%dT%H:%M:%SZ)

## Fleet Summary

| Verdict | Count |
|---------|-------|
| CONFORMING | $conforming |
| NON-CONFORMING | $non_conforming |
| N/A | $na_repos |
| UNKNOWN | $unknown_repos |
| **Total** | $((conforming + non_conforming + na_repos + unknown_repos)) |

**Exit code**: $exit_code"
fi

# --- 6. write output ------------------------------------------------------------------
if [[ -n "$OUTPUT" ]]; then
  printf '%s\n' "$body" > "$OUTPUT"
else
  printf '%s\n' "$body"
fi

# Exit code 3 takes precedence over non-conforming if any repo was unresolved
if [[ "$not_found" -gt 0 ]]; then
  exit 3
fi
exit "$exit_code"
