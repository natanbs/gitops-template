#!/usr/bin/env bash
# standards-audit/checks/structure.sh — structure-files check (profile-adaptive).
# * required files present and well-formed per profile (Dockerfile; .env
#   name=value parseable when present; k8s/*.yaml YAML-well-formed for app-k8s)
# * a profile with no applicable inputs is reported N/A, never FAIL; a
#   partially-present input surface makes required-file gaps a FAIL (with fix).
set -euo pipefail

check_id="structure-files"
repo_root="${1:?repo-root required}"
profile="${2:?profile required}"

emit_pass() { printf '[PASS]\t%s\t%s\n' "$check_id" "$1"; exit 0; }
emit_na() { printf '[N/A]\t%s\t%s\n' "$check_id" "$1"; exit 0; }
emit_fail() { printf '[FAIL]\t%s\t%s\tfix: %s\n' "$check_id" "$1" "$2"; exit 1; }

case "$profile" in
  app-k8s|app|library) ;;
  *) emit_na "unknown profile '$profile' (structure check skipped)" ;;
esac

# --- presence probe ---------------------------------------------------------
has_dockerfile=0
has_env=0
has_k8s=0
if [[ -f "$repo_root/Dockerfile" ]]; then has_dockerfile=1; fi
if [[ -f "$repo_root/.env" ]]; then has_env=1; fi
if [[ -d "$repo_root/k8s" ]]; then has_k8s=1; fi

# --- N/A semantics: no applicable inputs for the declared profile -----------
if [[ "$profile" == "library" ]]; then
  emit_na "no applicative inputs for profile 'library'"
fi
if [[ "$profile" == "app" ]]; then
  if [[ "$has_dockerfile" -eq 0 && "$has_env" -eq 0 ]]; then
    emit_na "no 'app' inputs present (missing inputs are reported as N/A, never FAIL)"
  fi
fi
if [[ "$profile" == "app-k8s" ]]; then
  if [[ "$has_dockerfile" -eq 0 && "$has_env" -eq 0 && "$has_k8s" -eq 0 ]]; then
    emit_na "no 'app-k8s' inputs present (missing inputs are reported as N/A, never FAIL)"
  fi
fi

# --- required-file presence (surface present but a required file is missing) -
if [[ "$profile" == "app-k8s" && "$has_k8s" -eq 1 && ! -f "$repo_root/k8s/deploy.yaml" ]]; then
  emit_fail "k8s/deploy.yaml missing" "generate manifests (run build.sh) or add the file"
fi
if [[ "$profile" != "library" && "$has_dockerfile" -eq 0 ]]; then
  emit_fail "Dockerfile missing for '$profile' profile" "add a Dockerfile for the service"
fi

# --- .env format parse (name=value), when present ---------------------------
if [[ "$has_env" -eq 1 ]]; then
  bad_lines="$(awk '
    /^[[:space:]]*#/ { next }
    /^[[:space:]]*$/ { next }
    /^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*=/ { next }
    { print NR ": " $0 }
  ' "$repo_root/.env")"
  if [[ -n "$bad_lines" ]]; then
    first="$(printf '%s\n' "$bad_lines" | head -1)"
    count="$(printf '%s\n' "$bad_lines" | wc -l | tr -d ' ')"
    emit_fail ".env contains $count unparseable line(s) (first: $first)" "fix .env format: each line must be NAME=value per the documented schema"
  fi
fi

# --- k8s/*.yaml YAML well-formedness (app-k8s only) --------------------------
yaml_problem() {
  awk '
    { line++
      if (bad != "") next
      if (index($0, "\t") > 0) { bad = sprintf("tab character in indentation (line %d)", line); next }
      if ($0 ~ /^[[:space:]]*-/ || $0 ~ /^[[:space:]]*#/ || $0 ~ /^[[:space:]]*$/) next
      if ($0 ~ /^[[:space:]]*[A-Za-z0-9_.-]+:[[:space:]]*/) {
        if ($0 ~ /^[[:space:]]*kind:/ || $0 ~ /kind:[[:space:]]*$/) { kind = 1 }
        if ($0 ~ /^[[:space:]]*apiVersion:/) { api = 1 }
        next
      }
      bad = "unexpected line " line ": " $0
    }
    END {
      if (bad != "") print bad
      else if (line == 0) print "empty file"
      else if (kind == 0 || api == 0) print "missing kind:/apiVersion: mapping keys (not a k8s manifest)"
    }' "$1"
}

if [[ "$profile" == "app-k8s" && "$has_k8s" -eq 1 ]]; then
  for f in "$repo_root"/k8s/*.yaml; do
    [[ -e "$f" ]] || continue
    base="$(basename "$f")"
    reason="$(yaml_problem "$f")"
    if [[ -n "$reason" ]]; then
      emit_fail "k8s/$base: YAML parse failed ($reason)" "fix YAML in k8s/$base (or regenerate manifests with build.sh)"
    fi
  done
fi

emit_pass "required files present and well-formed for '$profile'"