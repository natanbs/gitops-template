#!/usr/bin/env bash
# secrets-vault-standard/detectors/static-tokens.sh — VS-007 detector.
# Scans tracked files for static/long-lived Vault tokens per standard.md VS-007
# (Primary, blocking). Detects raw Vault root/child tokens (s.<base62>),
# committed `VAULT_TOKEN` values, and `vault login` / `vault.token` usage.
#
# Note: a static `token:`/`tokenSecretRef` field inside a SecretStore
# provider.vault is already enforced by VS-002 (Vault auth method), which FAILs
# on static token auth; VS-007 focuses on raw token material and CLI/env usage
# so the two rules complement without double-counting store config.
#
# Overlap with VS-006: a committed `VAULT_TOKEN` literal satisfies BOTH VS-006
# (committed secret) and VS-007 (static vault token). Each emits its own FAIL /
# fix: line; the repo is classified NON-CONFORMING once (single verdict).
#
# Inputs (args/env):
#   $1  repo_root  path to the repo being scored
#   $2  app_path   subdir under repo_root (e.g. k8s)
#   env SCAN_ROOT  "1" to also scan repo-root config/script files (opt-in)
#
# Output: one line per rule: VS-007<tab>VERDICT<tab>EVIDENCE<tab>FIX
# VERDICT: PASS / FAIL / N/A. Exit 0 always (caller aggregates).
set -euo pipefail

repo_root="${1:?repo-root required}"
app_path="${2:?app-path required}"

emit() { printf '%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4"; }

# --- pattern ruleset (ERE, named for classifiable reporting) --------------------
declare -a PAT_NAME PAT_ERE
add_pat() { PAT_NAME+=("$1"); PAT_ERE+=("$2"); }

add_pat "raw Vault root/child token" 's\.[A-Za-z0-9_\-]{20,}'
add_pat "VAULT_TOKEN env" 'VAULT_TOKEN'
add_pat "vault login" 'vault[[:space:]]+login'
add_pat "vault.token" 'vault\.token'

# --- build scan file list -------------------------------------------------------
scan_files=()
collect_dir() {
  local base="$1"
  if [[ -d "$base" ]]; then
    while IFS= read -r f; do
      case "$f" in
        *.yaml|*.yml|*.toml|*.json|*.env|*.sh) scan_files+=("$f") ;;
      esac
    done < <(find "$base" -type f \
      \( -name '*.yaml' -o -name '*.yml' -o -name '*.toml' -o -name '*.json' -o -name '*.env' -o -name '*.sh' \) \
      | sort)
  fi
}

collect_dir "$repo_root/$app_path"
if [[ "${SCAN_ROOT:-}" == "1" ]]; then
  if [[ -d "$repo_root" ]]; then
    for f in "$repo_root"/*.yaml "$repo_root"/*.yml "$repo_root"/*.toml "$repo_root"/*.json "$repo_root"/.env "$repo_root"/*.sh; do
      [[ -f "$f" ]] || continue
      scan_files+=("$f")
    done
  fi
fi

if [[ "${#scan_files[@]}" -eq 0 ]]; then
  emit "VS-007" "N/A" "no YAML/TOML/JSON/script scan surface in appPath" ""
  exit 0
fi

# --- scan each file, ignore comment/doc contexts --------------------------------
# Combine patterns into a single alternation for one grep pass per file.
combined=""
sep=""
for ere in "${PAT_ERE[@]}"; do
  combined="${combined}${sep}(${ere})"
  sep="|"
done

dets=""
for f in "${scan_files[@]}"; do
  # documentation immunity: skip example/docs/README files
  case "$f" in
    */examples/*|*/example/*|*/docs/*|*/doc/*|*/README*|*/readme*) continue ;;
  esac
  [[ -f "$f" ]] || continue
  body="$(sed -E '/^[[:space:]]*#/d' "$f" || true)"
  [[ -n "$body" ]] || continue
  # single grep pass over the whole (comment-stripped) body; avoids spawning one
  # grep per line per pattern (pathologically slow on real repos)
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

dets="$(printf '%s\n' "$dets" | sed '/^$/d' | sort -u)"

# --- verdict ---------------------------------------------------------------------
if [[ -n "$dets" ]]; then
  first="$(printf '%s\n' "$dets" | head -1)"
  count="$(printf '%s\n' "$dets" | wc -l | tr -d ' ')"
  emit "VS-007" "FAIL" "$count static Vault token pattern(s) in tracked files (e.g. $first)" \
    "fix: Remove static/long-lived Vault tokens; use Kubernetes auth (VS-002): provider.vault.auth.kubernetes.role: <role> + mountPath: /v1/auth/kubernetes"
  exit 0
fi

emit "VS-007" "PASS" "no static Vault tokens (s.<token>, VAULT_TOKEN, vault login, vault.token)" ""
exit 0
