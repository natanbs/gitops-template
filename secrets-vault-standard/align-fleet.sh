#!/usr/bin/env bash
# secrets-vault-standard/align-fleet.sh — VS-004 path-convention alignment tool.
# Reads the same inventory/`--repo-root` interface as audit-fleet.sh and rewrites
# ExternalSecret `key:`/`extract:` references to the /<env>/<service>/<key>
# convention (leading slash, >=3 segments), then migrates the corresponding Vault
# KV data so running clusters keep syncing. VS-003 (unresolved store refs) and
# VS-006 (committed secrets) are reported as blockers — never auto-fixed.
#
# Reference transformations (line-number precise, comments preserved by
# align-plan.py):
#   remoteRef.key + property  ->  /<key-path>/<property>   (property kept)
#   dataFrom[].extract.key    ->  /<key-path>/<target-name>
#
# Modes:
#   (default) dry-run          print plan + vault ops, change nothing
#   --apply-manifests          rewrite manifests in place (creates .bak)
#   --apply-vault              execute vault KV migration (requires vault CLI + token)
#   --yes                      skip confirmations
#
# Exit codes:
#   0  no changes needed (dry-run) or everything applied cleanly
#   1  changes pending (dry-run produced a plan) OR apply left blockers/SKIP
#   2  usage / inventory error
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DETECTORS_DIR="$SCRIPT_DIR/detectors"
PLANNER="$SCRIPT_DIR/align-plan.py"
mount_path="secret"

usage() {
  cat <<'EOF'
Usage: secrets-vault-standard/align-fleet.sh [OPTIONS]

--inventory <path>       ArgoCD applicative inventory YAML file or directory
                         (default: <repo-root>/infra/argocd-infra/apps/applicative)
--repo-root <path>       base dir where repos are cloned (required)
--vault-mount <path>     Vault KV v2 mount declared by the stores (default: secret)
--apply-manifests        rewrite ExternalSecret key/extract values in place (.bak)
--apply-vault            execute `vault kv` migration against the live cluster
--yes                    skip confirmation prompts for apply modes
--verbose                print per-repo details to stderr
--help                   show this help and exit 0

Exit codes:
  0  dry-run with nothing to change, or apply completed cleanly
  1  dry-run with a pending plan, or apply left SKIP/blockers
  2  inventory not found or unparseable
EOF
}

usage_error() {
  echo "secrets-vault-standard/align-fleet: $1" >&2
  usage >&2
  exit 2
}

INVENTORY=""
REPO_ROOT=""
APPLY_MANIFESTS=0
APPLY_VAULT=0
YES=0
VERBOSE=0

if [[ "$#" -eq 1 && "$1" == "--help" ]]; then
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
    --vault-mount)
      [[ "$#" -ge 2 ]] || usage_error "--vault-mount requires an argument"
      mount_path="$2"; shift 2 ;;
    --apply-manifests)
      APPLY_MANIFESTS=1; shift ;;
    --apply-vault)
      APPLY_VAULT=1; shift ;;
    --yes)
      YES=1; shift ;;
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

if [[ -n "$INVENTORY" ]]; then
  INVENTORY_ARG=(--inventory "$INVENTORY")
else
  INVENTORY_ARG=()
fi

_tmp="$(mktemp -d 2>/dev/null || mktemp -d /tmp/sva-XXXXXX)"
trap 'rm -rf "$_tmp"' EXIT

# --- 1. enumerate fleet ----------------------------------------------------
IFS=$'\n' read -r -d '' -a apps < <( \
  "$SCRIPT_DIR/inventory.sh" --repo-root "$REPO_ROOT" ${INVENTORY_ARG[@]+"${INVENTORY_ARG[@]}"} --format tsv \
  || true ) || true
if [[ "${#apps[@]}" -eq 0 ]]; then
  echo "secrets-vault-standard/align-fleet: inventory yielded no apps" >&2
  exit 2
fi

# --- 2. gather known stores fleet-wide (same basis as audit-fleet VS-003) ----
known_stores=""
resolve_mount=""
resolve_apps=()
for app in "${apps[@]}"; do
  IFS=$'\t' read -r name _repo app_path _ns _wave local_path status <<<"$app"
  [[ "$status" == "RESOLVED" ]] || continue
  resolve_apps+=("$app")
  if [[ -d "$local_path/$app_path" ]]; then
    while IFS= read -r f; do
      [[ -f "$f" ]] || continue
      body="$(sed -E '/^[[:space:]]*#/d' "$f" 2>/dev/null || true)"
      printf '%s\n' "$body" | grep -qE '^kind:[[:space:]]+(SecretStore|ClusterSecretStore)' || continue
      sn="$(printf '%s\n' "$body" | awk '/^[[:space:]]*name:/{ sub(/^[[:space:]]*name:[[:space:]]*/, ""); sub(/[[:space:]]+$/, ""); sub(/^["'"'"']/, ""); sub(/["'"'"']$/, ""); print; exit }')"
      [[ -n "$sn" ]] || continue
      case " $known_stores " in
        *" $sn "*) : ;;
        *) known_stores="$known_stores $sn" ;;
      esac
      store_mount="$(printf '%s\n' "$body" | awk '/^[[:space:]]*path:[[:space:]]*["'"'"']?*(secret|kv|vault)[^[:space:]"'"'"']*["'"'"']?*$/{ sub(/^[[:space:]]*path:[[:space:]]*/, ""); sub(/["'"'"']/, ""); print; exit }')"
      if [[ -n "$store_mount" && -z "$resolve_mount" ]]; then
        resolve_mount="$store_mount"
      fi
    done < <(find "$local_path/$app_path" -maxdepth 1 -type f \( -name '*.yaml' -o -name '*.yml' \) | sort)
  fi
done
if [[ -z "$mount_path" ]]; then
  mount_path="${resolve_mount:-secret}"
fi

# --- 3. plan: run the planner per app ---------------------------------------
: > "$_tmp/plan.tsv"
: > "$_tmp/blockers.tsv"
blocker_count=0
for app in "${resolve_apps[@]}"; do
  IFS=$'\t' read -r name _repo app_path _ns _wave local_path _status <<<"$app"
  # VS-003 blocker (store resolution)
  KNOWN_STORES="$known_stores" "$DETECTORS_DIR/vault-eso.sh" "$local_path" "$app_path" "$name" \
    >> "$_tmp/results-$name.tsv" 2>/dev/null || true
  # VS-006 blocker (committed secrets) — always scan root so repo-root findings surface
  SCAN_ROOT=1 "$DETECTORS_DIR/committed-secrets.sh" "$local_path" "$app_path" \
    >> "$_tmp/results-$name.tsv" 2>/dev/null || true
  while IFS=$'\t' read -r code v ev _fx; do
    [[ "$code" == "VS-003" || "$code" == "VS-006" ]] || continue
    if [[ "$v" == "FAIL" || "$v" == "UNKNOWN" ]]; then
      printf '%s\t%s\t%s\t%s\n' "$name" "$code" "$v" "$ev" >> "$_tmp/blockers.tsv"
      blocker_count=$((blocker_count + 1))
    fi
  done < "$_tmp/results-$name.tsv"
  # VS-004 plan rows
  if [[ -d "$local_path/$app_path" ]]; then
    while IFS= read -r row; do
      [[ -n "$row" ]] || continue
      printf '%s\t%s\n' "$name" "$row" >> "$_tmp/plan.tsv"
    done < <("$PLANNER" "$local_path/$app_path" 2>/dev/null || true)
  fi
done

[[ "$VERBOSE" -eq 1 ]] && echo "secrets-vault-standard/align-fleet: $(wc -l < "$_tmp/plan.tsv" | tr -d ' ') VS-004 refs, $blocker_count blocker(s)" >&2

# --- 4. classify plan --------------------------------------------------------
# plan.tsv row: <repo>	<file>	<line>	<kind>	<old>	<prop>	<target>	<new>	<status>
align=0; skip=0; conform=0
: > "$_tmp/action.tsv"
: > "$_tmp/skip.tsv"
while IFS=$'\t' read -r repo file line kind old prop target new status; do
  [[ -n "$file" ]] || continue
  case "$status" in
    CONFORM) conform=$((conform + 1)) ;;
    ALIGN)
      printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$repo" "$file" "$line" "$kind" "$old" "$prop" "$target" "$new" >> "$_tmp/action.tsv"
      align=$((align + 1)) ;;
    SKIP)
      printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$repo" "$file" "$line" "$kind" "$old" "$prop" "$target" "$new" >> "$_tmp/skip.tsv"
      skip=$((skip + 1)) ;;
  esac
done < "$_tmp/plan.tsv"

# --- 4b. effective vault migration rows --------------------------------------
# Normal case: the ALIGN rows from the live plan (action.tsv).
# Recovery case: manifests already rewritten (align==0). The old key for each
# row is read back from git HEAD at the same line number — the in-place rewrite
# preserves lines, so the pre-rewrite value at `file:line` is the old path.
: > "$_tmp/vault.tsv"
if [[ "$align" -gt 0 ]]; then
  cat "$_tmp/action.tsv" > "$_tmp/vault.tsv"
else
  while IFS=$'\t' read -r repo file line kind old prop target new status; do
    [[ "$status" == "CONFORM" && -n "$file" ]] || continue
    dir="$(git -C "$(dirname "$file")" rev-parse --show-toplevel 2>/dev/null || true)"
    [[ -n "$dir" ]] || continue
    rel="$(git -C "$dir" ls-files --full-name "$file" 2>/dev/null || true)"
    [[ -n "$rel" ]] || continue
    headtext="$(git -C "$dir" show "HEAD:$rel" 2>/dev/null || true)"
    [[ -n "$headtext" ]] || continue
    oldk="$(printf '%s\n' "$headtext" | sed -n "${line}p" \
      | sed -E 's/^[[:space:]]*(key|extract):[[:space:]]*"?([^"[:space:]]+)"?.*/\2/')"
    [[ -n "$oldk" && "$oldk" != "$old" ]] || continue
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
      "$repo" "$file" "$line" "$kind" "$oldk" "$prop" "$target" "$new" >> "$_tmp/vault.tsv"
  done < "$_tmp/plan.tsv"
fi
vault_ops="$(wc -l < "$_tmp/vault.tsv" | tr -d ' ')"

# --- 5. render the report -----------------------------------------------------
cat <<EOF
# VS-004 Path-Alignment Report

**Vault mount**: $mount_path
**Inventory**: ${INVENTORY:-$REPO_ROOT/infra/argocd-infra/apps/applicative}

## Alignment plan

- ALIGN:   $align reference(s) to rewrite
- SKIP:    $skip reference(s) (need env/service context — manual)
- CONFORM: $conform reference(s) already /<env>/<service>/<key>
EOF

if [[ "$align" -gt 0 ]]; then
  echo
  echo "## References to rewrite"
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "repo" "file:line" "kind" "old" "prop" "target" "new"
  while IFS=$'\t' read -r repo file line kind old prop target new; do
    printf '%s\t%s:%s\t%s\t%s\t%s\t%s\t%s\n' "$repo" "$file" "$line" "$kind" "$old" "$prop" "$target" "$new"
  done < "$_tmp/action.tsv"
fi

if [[ "$skip" -gt 0 ]]; then
  echo
  echo "## SKIP (manual)"
  printf '%s\t%s\n' "reason" "reference"
  while IFS=$'\t' read -r repo file line kind old prop target new; do
    printf '%s\t%s (%s)\n' "needs env/service context" "$repo/$file:$line $old" "$prop"
  done < "$_tmp/skip.tsv"
fi

if [[ "$blocker_count" -gt 0 ]]; then
  echo
  echo "## Blockers (not auto-fixed)"
  printf '%s\t%s\t%s\t%s\n' "repo" "rule" "verdict" "evidence"
  while IFS=$'\t' read -r name code v ev; do
    printf '%s\t%s\t%s\t%s\n' "$name" "$code" "$v" "$ev"
  done < "$_tmp/blockers.tsv"
fi

if [[ "$APPLY_VAULT" -eq 1 && "$align" -eq 0 && "$skip" -eq 0 && "$vault_ops" -eq 0 ]]; then
  echo
  echo "No Vault migration needed (nothing to align)."
fi

# --- 6. vault ops preview -----------------------------------------------------
if [[ "$vault_ops" -gt 0 ]]; then
  echo
  if [[ "$align" -eq 0 ]]; then
    echo "## Vault KV migration recovered from git HEAD (manifests already rewritten)"
    echo "# Re-run with: ./secrets-vault-standard/align-fleet.sh --apply-vault --yes"
  else
    echo "## Vault KV migration (KV v2, mount '$mount_path')"
    echo "# Run with: ./secrets-vault-standard/align-fleet.sh --apply-vault (after --apply-manifests)"
  fi
  while IFS=$'\t' read -r repo file line kind old prop target new; do
    rel="${new#/}"
    if [[ "$kind" == "extract" ]]; then
      printf '  vault kv mv %s/%s %s/%s     # %s\n' "$mount_path" "$old" "$mount_path" "$rel" "$file:$line"
    else
      printf '  vault kv get -format=json %s/%s | jq -c --arg f "%s" "{(\\$f): .data.data[\\$f]}" | vault kv put %s/%s -   # %s\n' \
        "$mount_path" "$old" "$prop" "$mount_path" "$rel" "$file:$line"
    fi
  done < "$_tmp/vault.tsv"
  echo "# then (single field via kv mv is kept; shared-source paths split per property)"
fi

# --- 7. dry-run vs apply --------------------------------------------------------
if [[ "$APPLY_MANIFESTS" -eq 0 && "$APPLY_VAULT" -eq 0 ]]; then
  if [[ "$align" -gt 0 || "$skip" -gt 0 || "$vault_ops" -gt 0 ]]; then
    exit 1
  fi
  exit 0
fi

# --apply-manifests: rewrite key/extract lines in place --------------------------
if [[ "$APPLY_MANIFESTS" -eq 1 ]]; then
  if [[ "$YES" -eq 0 && "$align" -gt 0 ]]; then
    read -r -p "Rewrite $align manifest reference(s)? [y/N] " ans
    [[ "$ans" == "y" || "$ans" == "Y" ]] || { echo "aborted"; exit 1; }
  fi
  applied=0
  : > "$_tmp/.backedup"
  while IFS=$'\t' read -r repo file line kind old prop target new; do
    [[ -n "$file" ]] || continue
    [[ -f "$file" ]] || { echo "align: missing file $file" >&2; continue; }
    if ! grep -qxF "$file" "$_tmp/.backedup"; then
      cp -p "$file" "$file.bak"
      printf '%s\n' "$file" >> "$_tmp/.backedup"
    fi
    rel="${new#/}"
    sed -i '' -E "${line}s|(.*key:[[:space:]]*)([^[:space:]]+)(.*)|\1$rel\3|" "$file"
    applied=$((applied + 1))
  done < "$_tmp/action.tsv"
  echo "wrote $applied manifest edit(s) ($align planned); backups saved as *.bak"
fi

# --apply-vault: execute Vault migrations ----------------------------------------
if [[ "$APPLY_VAULT" -eq 1 ]]; then
  if [[ "$vault_ops" -eq 0 ]]; then
    echo "align-fleet: no Vault migration to run"
    exit 0
  fi
  if ! command -v vault >/dev/null 2>&1; then
    echo "align-fleet: vault CLI not found — cannot --apply-vault" >&2
    exit 2
  fi
  if [[ "$YES" -eq 0 ]]; then
    read -r -p "Execute $vault_ops Vault KV operation(s) against '$mount_path'? [y/N] " ans
    [[ "$ans" == "y" || "$ans" == "Y" ]] || { echo "aborted"; exit 1; }
  fi
  ops=0
  while IFS=$'\t' read -r repo file line kind old prop target new; do
    [[ -n "$file" ]] || continue
    rel="${new#/}"
    if [[ "$kind" == "extract" ]]; then
      vault kv mv "$mount_path/$old" "$mount_path/$rel" || { echo "align-fleet: vault kv mv failed for $old" >&2; exit 1; }
    else
      payload="$(vault kv get -format=json "$mount_path/$old" 2>/dev/null \
        | jq -c --arg f "$prop" '{($f): .data.data[$f]}' || true)"
      if [[ -z "$payload" || "$payload" == "null" ]]; then
        echo "align-fleet: could not read $prop from $mount_path/$old (skipping)" >&2
        continue
      fi
      printf '%s' "$payload" | vault kv put "$mount_path/$rel" - || { echo "align-fleet: vault kv put failed for $rel" >&2; exit 1; }
    fi
    ops=$((ops + 1))
  done < "$_tmp/vault.tsv"
  echo "ran $ops Vault KV operation(s)"
fi

echo
echo "Done. Re-run in dry-run mode to confirm no plan remains."
exit 1