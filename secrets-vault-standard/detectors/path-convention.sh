#!/usr/bin/env bash
# secrets-vault-standard/detectors/path-convention.sh — VS-004 detector.
# Extracts Vault KV paths from ExternalSecret remoteRef.key and dataFrom[].extract
# and validates the /<env>/<service>/<key> convention. Advisory (scoring) weight:
# a FAIL here is reported but does not by itself flip the repo to NON-CONFORMING.
#
# Inputs:
#   $1  repo_root  path to the repo being scored
#   $2  app_path   subdir under repo_root with manifests (e.g. k8s)
#
# Output: one line per rule: VS-004<tab>VERDICT<tab>EVIDENCE<tab>FIX
# VERDICT: PASS / FAIL / N/A. Exit 0 always (caller aggregates).
set -euo pipefail

repo_root="${1:?repo-root required}"
app_path="${2:?app-path required}"
scan_dir="$repo_root/$app_path"

emit() { printf '%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4"; }

# --- collect ExternalSecret files -------------------------------------------------
es_files=()
if [[ -d "$scan_dir" ]]; then
  while IFS= read -r f; do
    case "$f" in
      *.yaml|*.yml) es_files+=("$f") ;;
    esac
  done < <(find "$scan_dir" -type f \( -name '*.yaml' -o -name '*.yml' \) | sort)
fi

paths=()
for f in "${es_files[@]}"; do
  body="$(sed -E '/^[[:space:]]*#/d' "$f" || true)"
  [[ -n "$(printf '%s' "$body" | grep -E '^kind:[[:space:]]+ExternalSecret' || true)" ]] || continue
  # remoteRef.key: and dataFrom[].extract:
  while IFS= read -r p; do
    [[ -n "$p" ]] || continue
    p="$(printf '%s' "$p" | sed -E 's/^[[:space:]]*(key|extract):[[:space:]]*//; s/["'"'"']//g; s/[[:space:]]+$//')"
    [[ -n "$p" ]] && paths+=("$p")
  done < <(printf '%s' "$body" | grep -E '^\s+(key|extract):' | grep -vE 'secretKey:|remoteRef|^\s*#[[:space:]]*' || true)
done

if [[ "${#paths[@]}" -eq 0 ]]; then
  emit "VS-004" "N/A" "no ExternalSecret remoteRef paths to validate" ""
  exit 0
fi

# --- validate /<env>/<service>/<key> ----------------------------------------------
# Convention: path must be of shape '/<segment>/<segment>/<segment' with leading
# slash and at least three segments (env/service/key). Leading 'v1/' or 'kv/' data
# mount prefixes are tolerated where org convention allows; we accept >=3 segments.
bad=""
good_count=0
for p in "${paths[@]}"; do
  # strip leading mount notion like 'v1/gitops-01/' handled by accepting segment count
  norm="${p#/}"
  segs="$( { printf '%s' "$norm" | tr '/' '\n'; printf '\n'; } | sed '/^$/d' | wc -l | tr -d ' ')"
  case "$p" in
    /*) ;;
    *) bad="${bad}${bad:+$'\n'}${p} (no leading slash)"; continue ;;
  esac
  if [[ "$segs" -ge 3 ]]; then
    good_count=$((good_count + 1))
  else
    bad="${bad}${bad:+$'\n'}${p} (expected /<env>/<service>/<key>)"
  fi
done

if [[ -n "$bad" ]]; then
  first="$(printf '%s\n' "$bad" | head -1)"
  emit "VS-004" "FAIL" "non-conventional Vault path(s): $first (${#paths[@]} total)" \
    "fix: Reorganize Vault KV paths to follow /<env>/<service>/<key> instead of flat or ad-hoc structures"
  exit 0
fi

emit "VS-004" "PASS" "${#paths[@]} path(s) follow /<env>/<service>/<key>" ""
exit 0
