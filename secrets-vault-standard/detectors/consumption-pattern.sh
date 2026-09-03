#!/usr/bin/env bash
# secrets-vault-standard/detectors/consumption-pattern.sh — VS-005 detector.
# Validates the Secret consumption pattern: Deployments and CronJobs must consume
# secrets via env.valueFrom.secretKeyRef or envFrom[].secretRef, referencing the
# ExternalSecret-created K8s Secret (i.e. ExternalSecret.spec.target.name). A
# Deployment consuming a manually-declared `kind: Secret` does NOT satisfy the rule.
# Advisory (scoring) weight: a FAIL here is reported but does not by itself flip
# the repo to NON-CONFORMING.
#
# Inputs:
#   $1  repo_root  path to the repo being scored
#   $2  app_path   subdir under repo_root with manifests (e.g. k8s)
#
# Output: one line per rule: VS-005<tab>VERDICT<tab>EVIDENCE<tab>FIX
# VERDICT: PASS / FAIL / N/A. Exit 0 always (caller aggregates).
set -euo pipefail

repo_root="${1:?repo-root required}"
app_path="${2:?app-path required}"
scan_dir="$repo_root/$app_path"

emit() { printf '%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4"; }

# --- collect yaml/yml manifests -----------------------------------------------
manifests=()
if [[ -d "$scan_dir" ]]; then
  while IFS= read -r f; do
    case "$f" in
      *.yaml|*.yml) manifests+=("$f") ;;
    esac
  done < <(find "$scan_dir" -type f \( -name '*.yaml' -o -name '*.yml' \) | sort)
fi

# --- collect ExternalSecret target.name values (ESO-created Secrets) -----------
target_names=""
for f in "${manifests[@]}"; do
  body="$(sed -E '/^[[:space:]]*#/d' "$f" || true)"
  [[ -n "$(printf '%s' "$body" | grep -E '^kind:[[:space:]]+ExternalSecret' || true)" ]] || continue
  # target.name: the name directly under a target: block (before data:/dataFrom:)
  while IFS= read -r tn; do
    [[ -n "$tn" ]] || continue
    target_names="${target_names} $tn"
  done < <(printf '%s' "$body" | awk '
    /^[[:space:]]*target:/ { in_target=1; next }
    /^[[:space:]]*name:/ && in_target { print; }
    /^[[:space:]]*data:/ || /^[[:space:]]*dataFrom:/ { in_target=0 }
  ' | sed -E 's/^[[:space:]]*name:[[:space:]]*//; s/["'"'"']//g')
done

# --- collect Deployment/CronJob consumers --------------------------------------
# consumed holds "<file>|<secret>|<refkind>" tuples; refkind is secretKeyRef|envFrom
consumed=()
consumers=()
for f in "${manifests[@]}"; do
  body="$(sed -E '/^[[:space:]]*#/d' "$f" || true)"
  [[ -n "$(printf '%s' "$body" | grep -E '^kind:[[:space:]]+(Deployment|CronJob)' || true)" ]] || continue
  consumers+=("$f")
  # env[].valueFrom.secretKeyRef.name
  while IFS= read -r secret; do
    [[ -n "$secret" ]] || continue
    consumed+=("$f|$secret|secretKeyRef")
  done < <(printf '%s' "$body" | awk '
    /^[[:space:]]*secretKeyRef:/ { in_keyref=1; next }
    /^[[:space:]]*name:/ && in_keyref { print; in_keyref=0 }
    /^[[:space:]]*secretKey:/ { in_keyref=0 }
  ' | sed -E 's/^[[:space:]]*name:[[:space:]]*//; s/["'"'"']//g')
  # envFrom[].secretRef.name (secretRef may be a list item: "- secretRef:")
  while IFS= read -r secret; do
    [[ -n "$secret" ]] || continue
    consumed+=("$f|$secret|envFrom")
  done < <(printf '%s' "$body" | awk '
    /^[[:space:]]*-[[:space:]]*secretRef:/ { in_envref=1; next }
    /^[[:space:]]*name:/ && in_envref { print; in_envref=0 }
  ' | sed -E 's/^[[:space:]]*name:[[:space:]]*//; s/["'"'"']//g')
done

# --- verdict ------------------------------------------------------------------
if [[ "${#consumers[@]}" -eq 0 ]]; then
  emit "VS-005" "N/A" "no Deployment/CronJob consuming secrets to validate" ""
  exit 0
fi

if [[ "${#consumed[@]}" -eq 0 ]]; then
  emit "VS-005" "N/A" "no secrets consumed by Deployment/CronJob to validate" ""
  exit 0
fi

# normalize ESO target set for membership test
eso_targets=" $(printf '\n%s\n' "$target_names" | sed '/^$/d' | sort -u | tr '\n' ' ') "

bad=""
good=0
for entry in "${consumed[@]}"; do
  IFS='|' read -r file secret refkind <<<"$entry"
  case "$eso_targets" in
    *" $secret "*) good=$((good + 1)) ;;
    *) bad="${bad}${bad:+$'\n'}${file##*/}: secret '$secret' consumed via $refkind but not created by an ExternalSecret" ;;
  esac
done

if [[ -n "$bad" ]]; then
  first="$(printf '%s\n' "$bad" | head -1)"
  emit "VS-005" "FAIL" "$first" \
    "fix: Wire Deployment/CronJob env to the ExternalSecret-created Secret via secretKeyRef or envFrom.secretRef"
  exit 0
fi

emit "VS-005" "PASS" "$good secret(s) consumed via secretKeyRef/envFrom from ExternalSecret-created Secrets" ""
exit 0
