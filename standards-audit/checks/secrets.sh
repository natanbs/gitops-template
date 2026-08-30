#!/usr/bin/env bash
# standards-audit/checks/secrets.sh — secrets-scan check.
# Deterministic, offline scan of git-tracked files only for pinned credential
# patterns (reviewer-owned ruleset). Documented exemptions via an allowlist file
# (contracts/cli.md): one pattern per line, `#` comments, inline trailing comment
# accepted as justification. Patterns match a git-tracked file path (fixed string)
# or any scanned content line (substring).
set -euo pipefail

check_id="secrets-scan"
repo_root="${1:?repo-root required}"
# shellcheck disable=SC2034
profile="${2:?profile required}"   # shared check signature; scan covers every profile
allowlist="${3:-}"

# --- scan surface: git-tracked files under repo_root -------------------------
if ! git -C "$repo_root" rev-parse --git-dir >/dev/null 2>&1; then
  printf '[N/A]\t%s\trepo-root is not inside a git work tree (scan surface unavailable)\n' "$check_id"
  exit 0
fi

repo_toplevel="$(git -C "$repo_root" rev-parse --show-toplevel)"
prefix="$(git -C "$repo_root" rev-parse --show-prefix)"

tracked="$(git -C "$repo_root" ls-files --full-name | sort)"
surface="$(printf '%s\n' "$tracked" | awk -v p="$prefix" '{ if (p == "" || substr($0, 1, length(p)) == p) print }')"

# ls-files --full-name yields toplevel-relative paths; scan from the toplevel.
cd "$repo_toplevel"

# --- pinned ruleset (credential patterns, ERE, both BSD and GNU grep) --------
ruleset="AKIA[0-9A-Z]{16}
ASIA[0-9A-Z]{16}
-----BEGIN [A-Z ]*PRIVATE KEY-----
gh[pousr]_[A-Za-z0-9]{20,}
github_pat_[A-Za-z0-9_]{20,}
xox[baprs]-[A-Za-z0-9-]{10,}
sk_live_[0-9A-Za-z]{20,}
rk_live_[0-9A-Za-z]{20,}
AIza[0-9A-Za-z_-]{35}
a[Ww][Ss][_-]?[sS]ecret[_ -]?[kK]ey[[:space:]]*[:=]
a[Ww][Ss][_-]?[aA]ccess[_ -]?[kK]ey[[:space:]]*[:=]"

combined="$(printf '%s\n' "$ruleset" | awk 'NF { printf "%s%s", sep, $0; sep="|" } END { print "" }')"

dets=""
while IFS= read -r f; do
  [[ -n "$f" ]] || continue
  [[ -f "$f" ]] || continue
  hits="$(grep -inHE "$combined" "$f" 2>/dev/null || true)"
  if [[ -n "$hits" ]]; then
    dets="${dets}${dets:+$'\n'}${hits}"
  fi
done <<<"$surface"

# --- allowlist filtering ------------------------------------------------------
if [[ -z "$allowlist" ]]; then
  if [[ -f "$repo_root/standards-audit/allowlist" ]]; then
    allowlist="$repo_root/standards-audit/allowlist"
  fi
fi

if [[ -n "$dets" && -n "$allowlist" && -r "$allowlist" ]]; then
  allow_pats="$(awk '
    { line = $0
      sub(/^[[:space:]]*/, "", line)
      if (line == "" || line ~ /^#/) next
      sub(/[[:space:]]+#.*$/, "", line)   # inline trailing comment = justification
      sub(/[[:space:]]+$/, "", line)
      if (line != "") print line
    }' "$allowlist")"

  kept=""
  while IFS= read -r det; do
    [[ -n "$det" ]] || continue
    f="${det%%:*}"
    content="${det#*:}"
    content="${content#*:}"
    exempt=0
    while IFS= read -r ap; do
      [[ -n "$ap" ]] || continue
      if [[ "$ap" == "$f" ]] || case "$content" in *"$ap"*) true ;; *) false ;; esac; then
        exempt=1
        break
      fi
    done <<<"$allow_pats"
    [[ "$exempt" -eq 1 ]] && continue
    kept="${kept}${kept:+$'\n'}${det}"
  done <<<"$dets"
  dets="$kept"
fi

# --- verdict ------------------------------------------------------------------
if [[ -n "$dets" ]]; then
  first="$(printf '%s\n' "$dets" | head -1)"
  count="$(printf '%s\n' "$dets" | wc -l | tr -d ' ')"
  printf '[FAIL]\t%s\t%d credential pattern(s) in git-tracked files (e.g. %s)\tfix: remove the leaked credential, revoke/rotate it, and commit the removal (or document a justified exemption in the allowlist)\n' "$check_id" "$count" "$first"
  exit 1
fi

printf '[PASS]\t%s\tno credential patterns in git-tracked files\n' "$check_id"
exit 0