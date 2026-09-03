#!/usr/bin/env bash
# secrets-vault-standard/report.sh — render the fleet audit report.
# Consumes the per-repo rule verdict TSVs and fleet meta produced by
# audit-fleet.sh and emits markdown (default) or JSON per contracts/report.md.
set -euo pipefail

usage_error() { echo "secrets-vault-standard/report: $1" >&2; exit 2; }

RESULTS_DIR=""
INVENTORY=""
REPO_ROOT=""
FORMAT="markdown"
STANDARD_VERSION="1.0.0"
SCAN_ROOT=0

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --results-dir) [[ "$#" -ge 2 ]] || usage_error "--results-dir requires an argument"; RESULTS_DIR="$2"; shift 2 ;;
    --inventory)   [[ "$#" -ge 2 ]] || usage_error "--inventory requires an argument"; INVENTORY="$2"; shift 2 ;;
    --repo-root)   [[ "$#" -ge 2 ]] || usage_error "--repo-root requires an argument"; REPO_ROOT="$2"; shift 2 ;;
    --format)      [[ "$#" -ge 2 ]] || usage_error "--format requires an argument"; FORMAT="$2"; shift 2 ;;
    --standard-version) [[ "$#" -ge 2 ]] || usage_error "--standard-version requires an argument"; STANDARD_VERSION="$2"; shift 2 ;;
    --scan-root)   SCAN_ROOT=1; shift ;;
    --help|-h)     echo "Usage: report.sh --results-dir <dir> [--inventory <p>] [--repo-root <p>] [--format markdown|json]"; exit 0 ;;
    *) usage_error "unknown argument: $1" ;;
  esac
done

[[ -n "$RESULTS_DIR" && -d "$RESULTS_DIR" ]] || usage_error "--results-dir must be a directory"
case "$FORMAT" in
  markdown|json) ;;
  *) usage_error "invalid --format '$FORMAT'" ;;
esac

# --- read meta -----------------------------------------------------------------
summary_file="$RESULTS_DIR/_summary.tsv"
fleet_file="$RESULTS_DIR/_fleet.tsv"
# summary counters as plain vars (bash 3.2-safe); read <key>\t<value> lines
s_conforming=0; s_nonconforming=0; s_na=0; s_unknown=0; s_total=0; s_exitcode=0
if [[ -f "$summary_file" ]]; then
  while IFS=$'\t' read -r k v; do
    [[ -n "$k" ]] || continue
    case "$k" in
      conforming) s_conforming="$v" ;;
      nonConforming) s_nonconforming="$v" ;;
      na) s_na="$v" ;;
      unknown) s_unknown="$v" ;;
      total) s_total="$v" ;;
      exitCode) s_exitcode="$v" ;;
    esac
  done < "$summary_file"
fi

# fleet rows sorted by name
fleet_rows=()
if [[ -f "$fleet_file" ]]; then
  while IFS= read -r line; do [[ -n "$line" ]] && fleet_rows+=("$line"); done < "$fleet_file"
fi

# not-found repos: <name>\t<localPath> — surfaced as UNKNOWN with the reason
notfound_file="$RESULTS_DIR/_notfound.tsv"
notfound_names=""
if [[ -f "$notfound_file" ]]; then
  while IFS=$'\t' read -r nname _npath; do
    [[ -n "$nname" ]] || continue
    notfound_names="$notfound_names $nname"
  done < "$notfound_file"
fi
is_notfound() { case " $notfound_names " in *" $1 "*) return 0 ;; *) return 1 ;; esac; }

# --- markdown body ---------------------------------------------------------------
render_markdown() {
  printf '%s\n' "# Secrets & Vault Standard Fleet Report"
  printf '%s\n' ""
  printf '%s\n' "**Standard**: secrets-vault-standard v$STANDARD_VERSION"
  printf '%s\n' "**Inventory**: $INVENTORY"
  printf '%s\n' "**Date**: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  if [[ "$SCAN_ROOT" -eq 1 ]]; then
    printf '%s\n' "**Scan scope**: appPath + repo-root config files (--scan-root)"
  else
    printf '%s\n' "**Scan scope**: appPath only (add --scan-root to include repo-root config files)"
  fi
  printf '%s\n' ""
  printf '%s\n' "## Fleet Summary"
  printf '%s\n' ""
  printf '%s\n' "| Verdict | Count |"
  printf '%s\n' "|---------|-------|"
  printf '%s\n' "| CONFORMING | ${s_conforming:-0} |"
  printf '%s\n' "| NON-CONFORMING | ${s_nonconforming:-0} |"
  printf '%s\n' "| N/A | ${s_na:-0} |"
  printf '%s\n' "| UNKNOWN | ${s_unknown:-0} |"
  printf '%s\n' "| **Total** | **${s_total}** |"
  printf '%s\n' ""
  printf '%s\n' "**Exit code**: ${s_exitcode}"
  printf '%s\n' ""
  printf '%s\n' "## Per-Repo Results"
  printf '%s\n' ""

  for row in ${fleet_rows[@]+"${fleet_rows[@]}"}; do
    IFS=$'\t' read -r name verdict local_path <<<"$row"
    printf '%s\n' "### $name — $verdict"
    printf '%s\n' ""
    if is_notfound "$name"; then
      printf '%s\n' "Repo not found locally ($local_path). Resolution failure — manual review required. Counted in the fleet total (SC-001: no inventory URL left unassessed)."
      printf '%s\n' ""
      continue
    fi
    results="$RESULTS_DIR/results-$name.tsv"
    if [[ "$verdict" == "N/A" && ! -s "$results" ]]; then
      printf '%s\n' "No secrets infrastructure detected. Vault standard is not applicable."
      printf '%s\n' ""
      continue
    fi
    printf '%s\n' "| Rule | Verdict | Evidence | Fix |"
    printf '%s\n' "|------|---------|----------|-----|"
    if [[ -s "$results" ]]; then
      while IFS=$'\t' read -r code v evidence fix; do
        [[ -n "$code" ]] || continue
        printf '| %s | %s | %s | %s |\n' "$code" "$v" "${evidence:- }" "${fix:--}"
      done < "$results" | sort -t' ' -k2,2 -k1,1
    else
      printf '| — | %s | — | — |\n' "$verdict"
    fi
    printf '%s\n' ""
  done
}

# --- json body -------------------------------------------------------------------
render_json() {
  {
    printf '{'
    printf '"standardVersion":"%s","inventoryPath":"%s","repoRoot":"%s","scanRoot":%s,' \
      "$STANDARD_VERSION" "$INVENTORY" "$REPO_ROOT" "$([[ "$SCAN_ROOT" -eq 1 ]] && echo true || echo false)"
    printf '"timestamp":"%s",' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf '"repoCount":%s,' "${s_total:-0}"
    printf '"summary":{"conforming":%s,"nonConforming":%s,"na":%s,"unknown":%s,"total":%s,"exitCode":%s},' \
      "${s_conforming:-0}" "${s_nonconforming:-0}" "${s_na:-0}" "${s_unknown:-0}" "${s_total:-0}" "${s_exitcode:-0}"
    printf '"repos":['
    first=1
    for row in ${fleet_rows[@]+"${fleet_rows[@]}"}; do
      IFS=$'\t' read -r name verdict local_path <<<"$row"
      [[ "$first" -eq 1 ]] || printf ','
      first=0
      if is_notfound "$name"; then
        printf '{"name":%s,"localPath":%s,"verdict":%s,"notFound":true,"reason":%s,"rules":[]}' \
          "$(printf '%s' "$name" | jq -R .)" \
          "$(printf '%s' "$local_path" | jq -R .)" \
          "$(printf '%s' "$verdict" | jq -R .)" \
          "$(printf '%s' 'Repo not found locally; resolution failure — manual review required (SC-001: no inventory URL left unassessed)' | jq -R .)"
        continue
      fi
      printf '{"name":%s,"localPath":%s,"verdict":%s,"notFound":false,"rules":[' \
        "$(printf '%s' "$name" | jq -R .)" \
        "$(printf '%s' "$local_path" | jq -R .)" \
        "$(printf '%s' "$verdict" | jq -R .)"
      rfirst=1
      results="$RESULTS_DIR/results-$name.tsv"
      if [[ -s "$results" ]]; then
        while IFS=$'\t' read -r code v evidence fix; do
          [[ -n "$code" ]] || continue
          [[ "$rfirst" -eq 1 ]] || printf ','
          rfirst=0
          printf '{"ruleId":%s,"verdict":%s,"evidence":%s,"fix":%s}' \
            "$(printf '%s' "$code" | jq -R .)" \
            "$(printf '%s' "$v" | jq -R .)" \
            "$(printf '%s' "${evidence:-}" | jq -R .)" \
            "$(if [[ -z "${fix:-}" ]]; then printf 'null'; else printf '%s' "$fix" | jq -R .; fi)"
        done < "$results"
      fi
      printf ']}'
    done
    printf ']}\n'
  }
}

if [[ "$FORMAT" == "json" ]]; then
  render_json
else
  render_markdown
fi

exit 0
