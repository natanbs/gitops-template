#!/usr/bin/env bash
# secrets-vault-standard/detectors/committed-secrets.sh — VS-006 detector.
# Scans for committed secret material in git-tracked YAML/TOML/JSON/.env files
# within appPath (and, when SCAN_ROOT=1, selected repo-root files). High-signal
# patterns per standard.md VS-006; comment and documentation lines are ignored.
#
# Inputs (args/env):
#   $1  repo_root  path to the repo being scored
#   $2  app_path   subdir under repo_root (e.g. k8s)
#   env SCAN_ROOT  "1" to also scan repo-root config files (VS-006 opt-in)
#
# Output: one line per rule: VS-006<tab>VERDICT<tab>EVIDENCE<tab>FIX
# VERDICT: PASS / FAIL / N/A. Exit 0 always (caller aggregates).
set -euo pipefail

repo_root="${1:?repo-root required}"
app_path="${2:?app-path required}"

emit() { printf '%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4"; }

# --- pattern ruleset (ERE, single combined alternation) -------------------------
# Armed as a bash array of named patterns so we can report the matched type.
declare -a PAT_NAME PAT_ERE
add_pat() { PAT_NAME+=("$1"); PAT_ERE+=("$2"); }

add_pat "bcrypt hash" '\$2[aby]\$'
add_pat "argon2 hash" '\$argon2'
add_pat "sha-crypt hash" '\$(5|6)\$'
add_pat "AWS access key" 'AKIA[0-9A-Z]{16}'
add_pat "AWS session token" 'ASIA[0-9A-Z]{16}'
add_pat "OpenAI API key" 'sk-[a-zA-Z0-9]{20,}'
add_pat "GitHub PAT" 'ghp_[a-zA-Z0-9]{36}'
add_pat "GitHub fine-grained PAT" 'github_pat_'
add_pat "JWT" 'eyJ[a-zA-Z0-9_-]{20,}\.[a-zA-Z0-9_-]{10,}'
add_pat "GCP service account key" 'AIza[0-9A-Za-z_-]{35}'
add_pat "private key" '-----BEGIN.*PRIVATE KEY-----'
add_pat "Vault token" 'VAULT_TOKEN'

# combine into a single alternation preserving order
combined=""
sep=""
for ere in "${PAT_ERE[@]}"; do
  combined="${combined}${sep}(${ere})"
  sep="|"
done

# --- build scan file list -------------------------------------------------------
scan_files=()
collect_dir() {
  local base="$1"
  if [[ -d "$base" ]]; then
    while IFS= read -r f; do
      case "$f" in
        *.yaml|*.yml|*.toml|*.json|*.env) scan_files+=("$f") ;;
      esac
    done < <(find "$base" -type f \( -name '*.yaml' -o -name '*.yml' -o -name '*.toml' -o -name '*.json' -o -name '*.env' \) | sort)
  fi
}

collect_dir "$repo_root/$app_path"
if [[ "${SCAN_ROOT:-}" == "1" ]]; then
  # repo-root config files (top-level only), not the whole tree
  if [[ -d "$repo_root" ]]; then
    for f in "$repo_root"/*.yaml "$repo_root"/*.yml "$repo_root"/*.toml "$repo_root"/*.json "$repo_root"/.env; do
      [[ -f "$f" ]] || continue
      scan_files+=("$f")
    done
  fi
fi

if [[ "${#scan_files[@]}" -eq 0 ]]; then
  emit "VS-006" "N/A" "no YAML/TOML/JSON/.env scan surface in appPath (and scan-root off)" ""
  exit 0
fi

# --- scan each file, ignore comment/doc contexts --------------------------------
dets=""
for f in "${scan_files[@]}"; do
  base="$(basename "$f")"
  # documentation immunity: skip example/docs/README files and dotpath dirs
  case "$f" in
    */examples/*|*/example/*|*/docs/*|*/doc/*|*/README*|*/readme*) continue ;;
  esac
  [[ -f "$f" ]] || continue
  # strip comment lines and full-line commented blocks per file type
  # yaml/toml use '#', json may not, but we drop lines starting with //
  body="$(sed -E '/^[[:space:]]*#/d; /^[[:space:]]*\/\//d' "$f" || true)"
  [[ -n "$body" ]] || continue
  # Single grep pass over the whole (comment-stripped) body. This performs one
  # grep per file instead of one grep per line per pattern (which was
  # pathologically slow on real repos — ~10s for a single small appPath).
  matches="$(printf '%s\n' "$body" | grep -nE "$combined" || true)"
  [[ -n "$matches" ]] || continue
  # name the first matched line's pattern (first pattern in declared order)
  first_line="$(printf '%s\n' "$matches" | head -1)"
  first_content="${first_line#*:}"
  match_name="pattern matched"
  for i in "${!PAT_ERE[@]}"; do
    if printf '%s' "$first_content" | grep -qE -e "${PAT_ERE[$i]}"; then
      match_name="${PAT_NAME[$i]}"
      break
    fi
  done
  while IFS= read -r m; do
    [[ -n "$m" ]] || continue
    dets="${dets}${dets:+$'\n'}${f}:${m%%:*}: ${match_name}"
  done <<<"$matches"
done

# de-duplicate detections, deterministic order
dets="$(printf '%s\n' "$dets" | sed '/^$/d' | sort -u)"

# --- verdict ---------------------------------------------------------------------
if [[ -n "$dets" ]]; then
  first="$(printf '%s\n' "$dets" | head -1)"
  count="$(printf '%s\n' "$dets" | wc -l | tr -d ' ')"
  emit "VS-006" "FAIL" "$count committed secret pattern(s) in tracked files (e.g. $first)" \
    "fix: Remove committed ${match_name:-secret material} from the tracked file; add it to .gitignore; manage via Vault/ESO at runtime"
  exit 0
fi

emit "VS-006" "PASS" "no committed secret patterns in tracked files" ""
exit 0
