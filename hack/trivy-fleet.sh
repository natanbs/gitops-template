#!/usr/bin/env bash
set -euo pipefail

# trivy-fleet.sh — scan every repository under a GitHub account/org with the
# ONE centralized policy (trivy.yaml).
#
# Why this exists: a gate that only runs inside gitops-template protects
# gitops-template. Repos are cloned shallowly, scanned with the same policy
# file the template uses, and aggregated into one report — so "what is the
# security posture of the account" has a single answer instead of N answers
# that each depend on which repos someone remembered to wire up.
#
# Requires: trivy, gh (authenticated via GH_TOKEN or `gh auth login`), python3.
#
# Usage:
#   ./hack/trivy-fleet.sh                      # scan all repos in $GITHUB_OWNER (or natanbs)
#   ./hack/trivy-fleet.sh --owner my-org
#   ./hack/trivy-fleet.sh --repo gitops-template --repo vault
#   ./hack/trivy-fleet.sh --list               # show what would be scanned, scan nothing
#   ./hack/trivy-fleet.sh --include-forks --include-archived
#   ./hack/trivy-fleet.sh --no-fail            # report-only: always exit 0
#
# Exit codes: 0 pass, 1 findings exceeded the gate, 2 usage/prereq error.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

OWNER="${GITHUB_OWNER:-natanbs}"
CONFIG="$REPO_ROOT/trivy.yaml"
OUT_DIR="$REPO_ROOT/trivy-fleet-out"
JOBS=4
FAIL_ON_FINDINGS=1
INCLUDE_FORKS=0
INCLUDE_ARCHIVED=0
LIST_ONLY=0
ONLY_REPOS=()

# Logs go to stderr: discover_repos runs in $(...), and any stdout it emits
# would be captured as a repository name. stdout stays reserved for data
# (`--list` output). error() already targeted stderr.
info()  { printf '\033[36m[INFO]\033[0m %s\n' "$*" >&2; }
warn()  { printf '\033[33m[WARN]\033[0m %s\n' "$*" >&2; }
error() { printf '\033[31m[ERROR]\033[0m %s\n' "$*" >&2; }
pass()  { printf '\033[32m[PASS]\033[0m %s\n' "$*" >&2; }
fail()  { printf '\033[31m[FAIL]\033[0m %s\n' "$*" >&2; }

# Print the leading comment block (everything from line 4 up to the first
# non-comment line) — self-maintaining, so editing the header cannot desync it.
usage() {
  awk 'NR < 4 { next }
       /^#/ { sub(/^# ?/, ""); print; next }
       { exit }' "${BASH_SOURCE[0]}"
}

# `${2:?...}` would abort with exit 1, but usage errors are documented as 2.
need_val() {
  if [ -z "${2:-}" ]; then
    error "$1 requires a value"
    exit 2
  fi
}

while [ $# -gt 0 ]; do
  case "$1" in
    --owner)             need_val "$1" "${2:-}"; OWNER="$2"; shift 2 ;;
    --repo)              need_val "$1" "${2:-}"; ONLY_REPOS+=("$2"); shift 2 ;;
    --config)            need_val "$1" "${2:-}"; CONFIG="$2"; shift 2 ;;
    --out)               need_val "$1" "${2:-}"; OUT_DIR="$2"; shift 2 ;;
    --jobs)              need_val "$1" "${2:-}"; JOBS="$2"; shift 2 ;;
    --include-forks)     INCLUDE_FORKS=1; shift ;;
    --include-archived)  INCLUDE_ARCHIVED=1; shift ;;
    --no-fail)           FAIL_ON_FINDINGS=0; shift ;;
    --list)              LIST_ONLY=1; shift ;;
    -h|--help)           usage; exit 0 ;;
    *) error "unknown argument: $1"; usage >&2; exit 2 ;;
  esac
done

for cmd in trivy gh python3; do
  command -v "$cmd" >/dev/null 2>&1 || { error "required command not found: $cmd"; exit 2; }
done
[ -f "$CONFIG" ] || { error "policy file not found: $CONFIG"; exit 2; }
case "$JOBS" in ''|*[!0-9]*) error "--jobs must be a positive integer"; exit 2 ;; esac
[ "$JOBS" -ge 1 ] || { error "--jobs must be >= 1"; exit 2; }

# gh auth: a workflow passes GITHUB_TOKEN; locally `gh auth login` supplies one.
if [ -z "${GH_TOKEN:-}" ] && [ -n "${GITHUB_TOKEN:-}" ]; then
  export GH_TOKEN="$GITHUB_TOKEN"
fi
if ! gh auth status >/dev/null 2>&1; then
  error "gh is not authenticated (run 'gh auth login' or set GH_TOKEN)"
  exit 2
fi

mkdir -p "$OUT_DIR"
# Absolute cache path: trivy resolves a relative cache.dir against the CWD, and
# every worker below runs from a different clone directory.
CACHE_DIR="${TRIVY_CACHE_DIR:-$OUT_DIR/.trivycache}"
mkdir -p "$CACHE_DIR"

# --- discover repos ---------------------------------------------------------
discover_repos() {
  local json
  if [ "${#ONLY_REPOS[@]}" -gt 0 ]; then
    printf '%s\n' "${ONLY_REPOS[@]}"
    return
  fi
  # Note: `gh repo list` exposes no "disabled" field, so disabled repos are not
  # filtered here — they fail to clone, which the worker already reports.
  json="$(gh repo list "$OWNER" --limit 500 \
    --json name,isEmpty,isFork,isArchived \
    --jq ".[] | [.name, (.isEmpty|tostring), (.isFork|tostring), (.isArchived|tostring)] | @tsv")"
  # TSV: name isEmpty isFork isArchived
  while IFS=$'\t' read -r name empty fork archived; do
    [ -n "$name" ] || continue
    if [ "$empty" = "true" ]; then
      info "skip $name (empty repository)"
      continue
    fi
    if [ "$archived" = "true" ] && [ "$INCLUDE_ARCHIVED" -ne 1 ]; then
      info "skip $name (archived — pass --include-archived to scan)"
      continue
    fi
    if [ "$fork" = "true" ] && [ "$INCLUDE_FORKS" -ne 1 ]; then
      info "skip $name (fork — pass --include-forks to scan)"
      continue
    fi
    printf '%s\n' "$name"
  done <<<"$json"
}

# --- worker: clone + scan one repo -----------------------------------------
# Invoked in a subshell per repo via xargs. Writes $OUT_DIR/<repo>.json and
# $OUT_DIR/<repo>.status so the aggregator never parses human output.
# shellcheck disable=SC2329  # called indirectly: `bash -c 'scan_one "$@"'` after export -f
scan_one() {
  local name="$1"
  local clone_dir status=0 detail="" tmp_root clone_err
  tmp_root="${TMPDIR:-/tmp}"
  tmp_root="${tmp_root%/}"
  clone_dir="$(mktemp -d "$tmp_root/trivy-fleet.XXXXXX")"
  # shellcheck disable=SC2064  # expand now: clone_dir must not be re-read later
  trap "rm -rf '$clone_dir'" RETURN

  # Capture stderr in a variable: writing it into $clone_dir would make that
  # directory non-empty and git would refuse to clone into it.
  if ! clone_err="$(gh repo clone "$OWNER/$name" "$clone_dir" -- --depth 1 --quiet 2>&1)"; then
    detail="clone failed: $(printf '%s' "$clone_err" | tr '\n' ' ' | cut -c1-300)"
    printf 'FAIL\t%s\t%s\n' "$name" "$detail" >"$OUT_DIR/$name.status"
    return 0
  fi

  local sarif="$OUT_DIR/$name.sarif" json="$OUT_DIR/$name.json"
  # SC2086 is disabled repo-wide for Docker args; here CONFIG/CACHE_DIR are
  # intentionally unquoted-adjacent via --config "$CONFIG" which IS quoted.
  if TRIVY_CACHE_DIR="$CACHE_DIR" trivy --config "$CONFIG" fs \
        --format sarif --output "$sarif" \
        --exit-code 0 "$clone_dir" >"$OUT_DIR/$name.log" 2>&1; then
    : # trivy exits 0 here by design; the gate is evaluated in the aggregator
  else
    status=1
    detail="trivy exited non-zero (see $name.log)"
  fi
  # Keep the JSON too: the aggregator counts severities from it, and jq-free
  # python3 does the counting below.
  cp -f "$sarif" "$json" 2>/dev/null || true

  if [ "$status" -eq 0 ]; then
    printf 'OK\t%s\t\n' "$name" >"$OUT_DIR/$name.status"
  else
    printf 'FAIL\t%s\t%s\n' "$name" "$detail" >"$OUT_DIR/$name.status"
  fi
}

export -f scan_one
export OWNER OUT_DIR CONFIG CACHE_DIR
# OWNER/CONFIG are read by the worker; export the two helpers it calls.
export -f info warn error pass fail

list="$(discover_repos)"
if [ -z "$list" ]; then
  warn "no repositories matched the given filters under '$OWNER'"
  exit 0
fi

# Portable array load: macOS ships bash 3.2, which has no `mapfile`.
REPOS=()
while IFS= read -r repo; do
  [ -n "$repo" ] || continue
  REPOS+=("$repo")
done <<<"$list"
info "${#REPOS[@]} repo(s) selected under '$OWNER'"

if [ "$LIST_ONLY" -eq 1 ]; then
  printf '%s\n' "${REPOS[@]}"
  exit 0
fi

rm -f "$OUT_DIR"/*.status "$OUT_DIR"/*.json "$OUT_DIR"/*.sarif "$OUT_DIR"/*.log 2>/dev/null || true

info "scanning with $CONFIG (${JOBS} parallel job(s)) — this clones every repo, allow a few minutes"
printf '%s\n' "${REPOS[@]}" | xargs -P "$JOBS" -I{} bash -c 'scan_one "$@"' _ {}

# --- aggregate --------------------------------------------------------------
# Assign first: `AGGREGATE=... cat >"$AGGREGATE"` would scope the variable to
# cat's environment only, leaving the redirect target unbound under `set -u`.
AGGREGATE="$OUT_DIR/aggregate.py"
cat >"$AGGREGATE" <<'PY'
import json, os, sys, glob

out = sys.argv[1]
owner = sys.argv[2]
fail_on_findings = sys.argv[3] == "1"

# SARIF is what trivy actually writes; severity lives in rule metadata, so we
# resolve rule id -> severity via the SARIF rule objects rather than trusting
# the result message text.
rows, total_by_sev = [], {"CRITICAL": 0, "HIGH": 0, "MEDIUM": 0, "LOW": 0}
failures = []

for status_file in sorted(glob.glob(os.path.join(out, "*.status"))):
    name = os.path.basename(status_file)[:-len(".status")]
    state, _, detail = open(status_file, encoding="utf-8").read().rstrip("\n").partition("\t")
    detail = detail.partition("\t")[2] if state != "OK" else ""
    if state != "OK":
        failures.append((name, detail or "scan failed"))
        rows.append((name, "-", "-", "-", detail or "scan failed"))
        continue

    sarif_path = os.path.join(out, name + ".sarif")
    counts = {"CRITICAL": 0, "HIGH": 0, "MEDIUM": 0, "LOW": 0}
    try:
        sarif = json.load(open(sarif_path, encoding="utf-8"))
        severities = {}
        for run in sarif.get("runs", []):
            for rule in run.get("tool", {}).get("driver", {}).get("rules", []):
                sev = (rule.get("properties") or {}).get("security-severity")
                # trivy also records level; prefer security-severity mapping
                level = rule.get("defaultConfiguration", {}).get("level")
                sev = sev if sev in counts else level
                severities[rule.get("id")] = sev if sev in counts else "MEDIUM"
        for run in sarif.get("runs", []):
            for res in run.get("results", []):
                rid = (res.get("ruleId") or "")
                sev = res.get("level")
                sev = severities.get(rid, sev if sev in counts else "MEDIUM")
                if sev in counts:
                    counts[sev] += 1
    except Exception as exc:  # noqa: BLE001 - a malformed report must not abort the sweep
        failures.append((name, f"could not read SARIF: {exc}"))
        rows.append((name, "-", "-", "-", "malformed SARIF"))
        continue

    for sev in counts:
        total_by_sev[sev] += counts[sev]
    blocking = counts["CRITICAL"] + counts["HIGH"]
    verdict = f"{blocking} blocking" if blocking else "clean"
    rows.append((name, str(counts["CRITICAL"]), str(counts["HIGH"]), str(blocking), verdict))

width = max([len(r[0]) for r in rows] + [4])
print(f"\n{'REPO':<{width}}  CRIT  HIGH  BLOCK  VERDICT")
print("-" * (width + 34))
for r in rows:
    # A failed scan has no counts; keep its detail in VERDICT only so the
    # BLOCK column stays numeric and aligned.
    block = "-" if r[1] == "-" else r[3]
    print(f"{r[0]:<{width}}  {r[1]:>4}  {r[2]:>4}  {block:>6}  {r[4]}")
print("-" * (width + 34))
print(f"{'TOTAL':<{width}}  {total_by_sev['CRITICAL']:>4}  {total_by_sev['HIGH']:>4}"
      f"  {total_by_sev['CRITICAL'] + total_by_sev['HIGH']:>6}")

summary = {
    "owner": owner,
    "repos_scanned": len(rows),
    "blocking_findings": total_by_sev["CRITICAL"] + total_by_sev["HIGH"],
    "severity_totals": total_by_sev,
    "scan_errors": [{"repo": n, "detail": d} for n, d in failures],
    "repos": [{"repo": r[0], "critical": r[1], "high": r[2], "verdict": r[4]} for r in rows],
}
json.dump(summary, open(os.path.join(out, "summary.json"), "w"), indent=2)

md = ["# Trivy fleet report", "",
      f"Owner: `{owner}` — {len(rows)} repos scanned.",
      "", "| Repo | CRITICAL | HIGH | Verdict |", "|---|---:|---:|---|"]
md += [f"| `{r[0]}` | {r[1]} | {r[2]} | {r[4]} |" for r in rows]
md += ["", f"**Blocking (CRITICAL+HIGH): {summary['blocking_findings']}**"]
if failures:
    md += ["", "## Scan errors", ""] + [f"- `{n}`: {d}" for n, d in failures]
open(os.path.join(out, "summary.md"), "w", encoding="utf-8").write("\n".join(md) + "\n")

blocking = summary["blocking_findings"]
if failures:
    sys.exit(2)
if fail_on_findings and blocking:
    sys.exit(1)
PY

set +e
python3 "$AGGREGATE" "$OUT_DIR" "$OWNER" "$FAIL_ON_FINDINGS"
agg_status=$?
set -e

if [ -f "$OUT_DIR/summary.json" ]; then
  info "report: $OUT_DIR/summary.md, $OUT_DIR/summary.json (SARIF per repo alongside)"
fi

case "$agg_status" in
  0) pass "fleet scan complete — no blocking findings" ;;
  1) fail "fleet scan found blocking (CRITICAL/HIGH) findings" ;;
  2) fail "one or more repos could not be scanned" ;;
esac
exit "$agg_status"
