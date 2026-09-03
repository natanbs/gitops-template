#!/usr/bin/env bash
# secrets-vault-standard/inventory.sh — ArgoCD applicative fleet inventory.
# Parses applicative Argo app YAML(s) into FleetApp entities and resolves each
# to a local clone path ({repo-root}/{name}). Emits one line per app as a
# tab-separated record:
#   <name>\t<repoURL>\t<appPath>\t<namespace>\t<syncWave>\t<localPath>\t<status>
# status is RESOLVED when {repo-root}/{name} exists and is a directory,
# otherwise NOT_FOUND.
#
# Deterministic and offline: parsing uses awk/grep (no yq dependency), records
# are emitted in stable (sorted) order. See contracts/audit-cli.md.
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: secrets-vault-standard/inventory.sh --repo-root <PATH>
                                            [--inventory <PATH>]
                                            [--format tsv|json]
                                            [--help]

--repo-root <PATH>       base directory where repos are cloned (required)
--inventory <PATH>       ArgoCD applicative inventory YAML file or directory of
                         YAML files (default: <repo-root>/infra/argocd-infra/apps/applicative)
--format <fmt>           tsv (default) | json
--help                   show this help and exit 0

Exit codes: 0 = ok, 2 = usage/argument error or inventory not found/unparseable
EOF
}

usage_error() {
  echo "secrets-vault-standard/inventory: $1" >&2
  usage >&2
  exit 2
}

REPO_ROOT=""
DEFAULT_INVENTORY=""
INVENTORY=""
FORMAT="tsv"

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
    --inventory)
      [[ "$#" -ge 2 ]] || usage_error "--inventory requires an argument"
      INVENTORY="$2"
      shift 2
      ;;
    --format)
      [[ "$#" -ge 2 ]] || usage_error "--format requires an argument"
      FORMAT="$2"
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
[[ -d "$REPO_ROOT" ]] || usage_error "--repo-root is not a directory: $REPO_ROOT"
DEFAULT_INVENTORY="$REPO_ROOT/infra/argocd-infra/apps/applicative"
if [[ -z "$INVENTORY" ]]; then
  INVENTORY="$DEFAULT_INVENTORY"
fi
case "$FORMAT" in
  tsv|json) ;;
  *) usage_error "invalid --format '$FORMAT' (expected tsv or json)" ;;
esac

# --- inventory resolution ----------------------------------------------------
YAML_FILES=()
if [[ -d "$INVENTORY" ]]; then
  while IFS= read -r f; do
    case "$f" in
      *.yaml|*.yml) YAML_FILES+=("$f") ;;
    esac
  done < <(find "$INVENTORY" -maxdepth 1 -type f \( -name '*.yaml' -o -name '*.yml' \) | sort)
elif [[ -f "$INVENTORY" ]]; then
  YAML_FILES+=("$INVENTORY")
else
  usage_error "inventory not found: $INVENTORY"
fi

if [[ "${#YAML_FILES[@]}" -eq 0 ]]; then
  usage_error "no YAML inventory files found in: $INVENTORY"
fi

# --- parse + resolve ----------------------------------------------------------
# Each app YAML defines: name, repoURL, appPath, namespace, syncWave.
# Extracted with awk (YAML top-level scalar fields), then resolved against
# {repo-root}/{name}.
declare -a NAMES REPO_URLS APP_PATHS NAMESPACES SYNC_WAVES

for f in "${YAML_FILES[@]}"; do
  name=""
  repo_url=""
  app_path=""
  namespace=""
  sync_wave=""
  while IFS= read -r line; do
    case "$line" in
      name:*)
        val="${line#name:}"
        val="${val# }"
        val="${val%\"}"
        val="${val#\"}"
        [[ -n "$val" ]] && name="$val"
        ;;
      repoURL:*)
        val="${line#repoURL:}"
        val="${val# }"
        val="${val%\"}"
        val="${val#\"}"
        [[ -n "$val" ]] && repo_url="$val"
        ;;
      appPath:*)
        val="${line#appPath:}"
        val="${val# }"
        val="${val%\"}"
        val="${val#\"}"
        [[ -n "$val" ]] && app_path="$val"
        ;;
      namespace:*)
        val="${line#namespace:}"
        val="${val# }"
        val="${val%\"}"
        val="${val#\"}"
        [[ -n "$val" ]] && namespace="$val"
        ;;
      syncWave:*)
        val="${line#syncWave:}"
        val="${val# }"
        val="${val%\"}"
        val="${val#\"}"
        [[ -n "$val" ]] && sync_wave="$val"
        ;;
    esac
  done < "$f"

  if [[ -z "$name" ]]; then
    echo "secrets-vault-standard/inventory: skipping ${f}: no 'name' field (unparseable)" >&2
    continue
  fi

  NAMES+=("$name")
  REPO_URLS+=("$repo_url")
  APP_PATHS+=("$app_path")
  NAMESPACES+=("$namespace")
  SYNC_WAVES+=("$sync_wave")
done

if [[ "${#NAMES[@]}" -eq 0 ]]; then
  echo "secrets-vault-standard/inventory: no parseable app records in: $INVENTORY" >&2
  exit 2
fi

# --- output --------------------------------------------------------------------
# Deterministic ordering by name. To keep TSV and JSON consistent we first build
# a sorted index list of names, then emit records in that order.
for name in "${NAMES[@]}"; do
  printf '%s\n' "$name"
done | sort -u | while IFS= read -r n; do
  idx=-1
  for i in "${!NAMES[@]}"; do
    if [[ "${NAMES[$i]}" == "$n" ]]; then
      idx=$i
      break
    fi
  done
  [[ "$idx" -ge 0 ]] || continue
  local_path="$REPO_ROOT/$n"
  if [[ -d "$local_path" ]]; then
    status="RESOLVED"
  else
    status="NOT_FOUND"
  fi
  if [[ "$FORMAT" == "json" ]]; then
    printf '{"name":%s,"repoURL":%s,"appPath":%s,"namespace":%s,"syncWave":%s,"localPath":%s,"status":%s}\n' \
      "$(printf '%s' "${NAMES[$idx]}" | jq -R .)" \
      "$(printf '%s' "${REPO_URLS[$idx]}" | jq -R .)" \
      "$(printf '%s' "${APP_PATHS[$idx]}" | jq -R .)" \
      "$(printf '%s' "${NAMESPACES[$idx]}" | jq -R .)" \
      "$(printf '%s' "${SYNC_WAVES[$idx]}" | jq -R .)" \
      "$(printf '%s' "$local_path" | jq -R .)" \
      "$(printf '%s' "$status" | jq -R .)"
  else
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
      "${NAMES[$idx]}" "${REPO_URLS[$idx]}" "${APP_PATHS[$idx]}" \
      "${NAMESPACES[$idx]}" "${SYNC_WAVES[$idx]}" "$local_path" "$status"
  fi
done
