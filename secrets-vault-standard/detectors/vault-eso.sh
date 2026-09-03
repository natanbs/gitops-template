#!/usr/bin/env bash
# secrets-vault-standard/detectors/vault-eso.sh — VS-001/VS-002/VS-003 detector.
# Evaluates the Vault-backed ESO store topology against the canonical standard:
#   VS-001  Vault-backed SecretStore/ClusterSecretStore declared
#   VS-002  Vault auth via Kubernetes method (not static token)
#   VS-003  ExternalSecret references a Vault-backed store
# Dual-topology aware: per-app SecretStore vs ClusterSecretStore consumer a repo
# may consume store declared elsewhere in the fleet. Comment/documentation lines
# are ignored (Detection Precision notes).
#
# Inputs (env + args):
#   $1  repo_root  path to the repo being scored
#   $2  app_path   subdir under repo_root with K8s manifests (e.g. k8s)
#   $3  repo_name  app name (used for evidence only)
#   env KNOWN_STORES  whitespace-separated set of fleet-wide known store names
#   env REPORT_UNRESOLVED_STORE  "1" to note unresolvable store refs (default off)
#
# Output: one line per rule: RULECODE<tab>VERDICT<tab>EVIDENCE<tab>FIX
# Verdicts: PASS / FAIL / N/A / UNKNOWN. Exit 0 always (caller aggregates).
set -euo pipefail

repo_root="${1:?repo-root required}"
app_path="${2:?app-path required}"
# shellcheck disable=SC2034
_repo_name="${3:-}"
scan_dir="$repo_root/$app_path"

emit() {
  # emit <code> <verdict> <evidence> <fix>
  printf '%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4"
}

# collapse whitespace in a possibly-empty value
clean() { printf '%s' "$1" | tr -s '[:space:]' ' ' | sed 's/^ //; s/ $//'; }

# --- scan surface: tracked manifests under app_path (existing files only) -----
scan_files=()
if [[ -d "$scan_dir" ]]; then
  while IFS= read -r f; do
    case "$f" in
      *.yaml|*.yml) scan_files+=("$f") ;;
    esac
  done < <(find "$scan_dir" -type f \( -name '*.yaml' -o -name '*.yml' \) | sort)
fi

# ---- collect manifest stats ---------------------------------------------------
store_hdr=""
store_provider_vault=""
store_kubernetes_auth=""
store_static_token=""
has_external_secret=0
has_manual_secret=0
has_manual_secret_literal=0
external_store_refs=""          # space-separated referenced store names
external_target_names=""        # space-separated ExternalSecret target.name

for f in "${scan_files[@]}"; do
  # strip comment lines to enforce comment/doc immunity for detection
  body="$(sed -E '/^[[:space:]]*#/d; /^[[:space:]]*\/\//d' "$f" || true)"
  if [[ -n "$(printf '%s' "$body" | grep -E '^kind:[[:space:]]+SecretStore' || true)" ]]; then
    store_hdr="${store_hdr} $f"
  fi
  if [[ -n "$(printf '%s' "$body" | grep -E '^kind:[[:space:]]+ClusterSecretStore' || true)" ]]; then
    store_hdr="${store_hdr} $f"
  fi
  if [[ -n "$(printf '%s' "$body" | grep -E 'provider:[[:space:]]*$|provider:.*' || true)" ]] \
     && printf '%s' "$body" | grep -qE 'vault'; then
    store_provider_vault="${store_provider_vault} $f"
  fi
  if printf '%s' "$body" | grep -qE 'kubernetes:'; then
    store_kubernetes_auth="${store_kubernetes_auth} $f"
  fi
  # static token detection within provider.vault (tokenSecretRef or token:)
  if printf '%s' "$body" | grep -qE 'tokenSecretRef|token:[[:space:]]*[^$\[\]<]'; then
    store_static_token="${store_static_token} $f"
  fi
  if printf '%s' "$body" | grep -qE '^kind:[[:space:]]+Secret'; then
    has_manual_secret=1
    # a manual Secret carrying literal values (data:/stringData: with content)
    # is the "static mechanism" the standard flags in mixed-pattern detection
    if printf '%s' "$body" | grep -qE '^[[:space:]]*(stringData|data):' \
       && printf '%s' "$body" | grep -Eq '[[:space:]][A-Za-z0-9_./+-]+:[[:space:]]+[^[:space:]]'; then
      has_manual_secret_literal=1
    fi
  fi
  if printf '%s' "$body" | grep -qE '^kind:[[:space:]]+ExternalSecret'; then
    has_external_secret=1
    # secretStoreRef.name: the name directly under a secretStoreRef: block.
    # awk: on a line matching '^[[:space:]]*secretStoreRef:' set a flag; capture
    # the next 'name:' inside that block; clear the flag when a sibling block
    # key at 0-indent appears (e.g. 'target:').
    while IFS= read -r ref; do
      [[ -n "$ref" ]] || continue
      external_store_refs="${external_store_refs} $ref"
    done < <(printf '%s' "$body" | awk '
      /^[[:space:]]*secretStoreRef:/ { in_ssref=1; next }
      /^[[:space:]]*target:/ { target_block=1; in_ssref=0; next }
      /^[[:space:]]*name:/ && in_ssref && !target_block { print; }
      /^[[:space:]]*data:/ || /^[[:space:]]*dataFrom:/ { in_ssref=0 }
    ' | sed -E 's/^[[:space:]]*name:[[:space:]]*//; s/["'"'"']//g')
    # target.name: the name directly under a target: block (before data:/dataFrom:)
    while IFS= read -r tn; do
      [[ -n "$tn" ]] || continue
      external_target_names="${external_target_names} $tn"
    done < <(printf '%s' "$body" | awk '
      /^[[:space:]]*target:/ { in_target=1; next }
      /^[[:space:]]*name:/ && in_target { print; }
      /^[[:space:]]*data:/ || /^[[:space:]]*dataFrom:/ { in_target=0 }
    ' | sed -E 's/^[[:space:]]*name:[[:space:]]*//; s/["'"'"']//g')
  fi
done

store_provider_vault="$(clean "$store_provider_vault")"
has_store="$([[ -n "$store_hdr" ]] && echo 1 || echo 0)"
has_vault_provider="$([[ -n "$store_provider_vault" ]] && echo 1 || echo 0)"
has_kubernetes_auth="$([[ -n "$store_kubernetes_auth" ]] && echo 1 || echo 0)"
has_static_token="$([[ -n "$store_static_token" ]] && echo 1 || echo 0)"
external_store_refs="$(clean "$external_store_refs")"
external_target_names="$(clean "$external_target_names")"

# ---- VS-001: Vault-backed store declared --------------------------------------
if [[ "$has_store" -eq 1 && "$has_vault_provider" -eq 1 ]]; then
  if [[ "$has_manual_secret_literal" -eq 1 ]]; then
    emit "VS-001" "FAIL" "mixed patterns: provider.vault store declared AND manual kind: Secret with literal values (not all secrets sourced from Vault)" \
      "fix: Remove the manual kind: Secret and source those values via an ExternalSecret referencing the Vault-backed store"
  else
    emit "VS-001" "PASS" "$(clean "$store_provider_vault"): provider.vault" ""
  fi
elif [[ "$has_store" -eq 1 ]]; then
  emit "VS-001" "FAIL" "store declared without provider.vault" \
    "fix: Add a SecretStore/ClusterSecretStore with provider.vault pointing to the org's Vault cluster"
elif [[ "$has_external_secret" -eq 1 && -n "$external_store_refs" ]]; then
  # ClusterSecretStore consumer: no own store, references a fleet store
  unresolved=""
  resolved=1
  for ref in $external_store_refs; do
    case " $KNOWN_STORES " in
      *" $ref "*) : ;;
      *) resolved=0; unresolved="$unresolved $ref" ;;
    esac
  done
  unresolved="$(clean "$unresolved")"
  if [[ "$resolved" -eq 1 ]]; then
    if [[ "$has_manual_secret_literal" -eq 1 ]]; then
      emit "VS-001" "FAIL" "mixed patterns: consumes ClusterSecretStore AND manual kind: Secret with literal values (not all secrets sourced from Vault)" \
        "fix: Remove the manual kind: Secret and source those values via an ExternalSecret referencing the Vault-backed store"
    else
      emit "VS-001" "N/A" "consumes external ClusterSecretStore (no own store); reference confirmed in fleet" ""
    fi
  else
    # store ref not resolvable fleet-wide -> UNKNOWN (never assume conforming)
    emit "VS-001" "UNKNOWN" "references unresolved store(s):$unresolved (cannot confirm Vault-backed; manual review)" \
      "fix: declare a provider.vault store, or ensure the referenced ClusterSecretStore exists fleet-wide"
  fi
elif [[ "$has_external_secret" -eq 1 ]]; then
  emit "VS-001" "FAIL" "ExternalSecret(s) present but no Vault-backed store declared" \
    "fix: Add a SecretStore/ClusterSecretStore with provider.vault pointing to the org's Vault cluster"
elif [[ "$has_manual_secret" -eq 1 ]]; then
  emit "VS-001" "FAIL" "manual kind: Secret present but no Vault-backed store declared (secrets not sourced from Vault)" \
    "fix: Replace the manual Secret with a Vault-backed SecretStore/ClusterSecretStore + ExternalSecret"
else
  emit "VS-001" "N/A" "no secrets infrastructure (Vault store rule not applicable)" ""
fi

# ---- VS-002: Kubernetes auth method -------------------------------------------
if [[ "$has_kubernetes_auth" -eq 1 && "$has_static_token" -eq 0 ]]; then
  emit "VS-002" "PASS" "provider.vault.auth.kubernetes present (role + mountPath)" ""
elif [[ "$has_static_token" -eq 1 ]]; then
  emit "VS-002" "FAIL" "static token found in store config" \
    "fix: Replace static token auth with Kubernetes auth: provider.vault.auth.kubernetes.role: <role> + mountPath: /v1/auth/kubernetes"
elif [[ "$has_store" -eq 1 ]]; then
  emit "VS-002" "FAIL" "store declared but Vault auth method undetermined/not Kubernetes" \
    "fix: Replace static token auth with Kubernetes auth: provider.vault.auth.kubernetes.role: <role> + mountPath: /v1/auth/kubernetes"
elif [[ "$has_external_secret" -eq 1 ]]; then
  # ExternalSecret consumer (no own store): auth state follows store resolution
  unresolved=""
  for ref in $external_store_refs; do
    case " $KNOWN_STORES " in
      *" $ref "*) : ;;
      *) unresolved="$unresolved $ref" ;;
    esac
  done
  unresolved="$(clean "$unresolved")"
  if [[ -n "$unresolved" ]]; then
    emit "VS-002" "UNKNOWN" "Vault store auth method not determinable (store(s)$unresolved unresolvable; manual review)" \
      "fix: Ensure the referenced ClusterSecretStore is declared fleet-wide with provider.vault.auth.kubernetes"
  else
    emit "VS-002" "N/A" "consumes external store; auth method governed at the store declaration repo" ""
  fi
elif [[ "$has_manual_secret" -eq 1 ]]; then
  emit "VS-002" "FAIL" "manual Secret present but no Vault store with Kubernetes auth" \
    "fix: Replace static token auth with Kubernetes auth: provider.vault.auth.kubernetes.role: <role> + mountPath: /v1/auth/kubernetes"
else
  emit "VS-002" "N/A" "no store declared (auth rule not applicable)" ""
fi

# ---- VS-003: ExternalSecret references Vault store ----------------------------
if [[ "$has_external_secret" -eq 1 && -n "$external_store_refs" ]]; then
  unresolved=""
  resolved=1
  for ref in $external_store_refs; do
    case " $KNOWN_STORES " in
      *" $ref "*) : ;;
      *) resolved=0; unresolved="$unresolved $ref" ;;
    esac
  done
  unresolved="$(clean "$unresolved")"
  if [[ "$resolved" -eq 1 ]]; then
    emit "VS-003" "PASS" "ExternalSecret(s) reference known store(s):$external_store_refs" ""
  else
    emit "VS-003" "UNKNOWN" "ExternalSecret references unresolved store(s):$unresolved (manual review)" \
      "fix: Ensure ExternalSecret.secretStoreRef.name matches a declared Vault-backed store"
  fi
elif [[ "$has_external_secret" -eq 1 ]]; then
  emit "VS-003" "FAIL" "ExternalSecret present but no secretStoreRef found" \
    "fix: Add an ExternalSecret that references the Vault-backed store and maps Vault KV paths to K8s Secret keys"
elif [[ "$has_store" -eq 1 || "$has_vault_provider" -eq 1 ]]; then
  emit "VS-003" "FAIL" "Vault store declared but no ExternalSecret referencing it" \
    "fix: Add an ExternalSecret that references the Vault-backed store and maps Vault KV paths to K8s Secret keys"
elif [[ "$has_manual_secret" -eq 1 ]]; then
  emit "VS-003" "FAIL" "manual kind: Secret present instead of an ExternalSecret (not sourced from Vault standard)" \
    "fix: Add an ExternalSecret that references the Vault-backed store and maps Vault KV paths to K8s Secret keys"
else
  emit "VS-003" "N/A" "no secrets infrastructure (ExternalSecret rule not applicable)" ""
fi

exit 0
