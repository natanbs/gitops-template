# Contract: `standards-audit/runner.sh` CLI

Local, offline standards audit runner. Single source of check logic — the
GitHub reusable workflow invokes exactly this binary; developers run it directly.

## Invocation

```text
standards-audit/runner.sh --repo-root <PATH> --repo-profile <app-k8s|app|library>
                          [--check <id>] [--allowlist <FILE>] [--help]
```

| Arg | Required | Meaning |
|-----|----------|---------|
| `--repo-root PATH` | yes | repository root to audit (files resolved relative to it) |
| `--repo-profile PROFILE` | yes | declared profile; one of `app-k8s`, `app`, `library` |
| `--check id` | no | run only this check (debug/CI narrow use) |
| `--allowlist FILE` | no | exemptions file for secrets check (default: `<repo-root>/standards-audit/allowlist` if present) |
| `--help` | no | usage text, exit 0 |

Unknown flag / missing required arg → usage to stderr, exit `2`.

## I/O Contract

- **stdout**: audit lines only — machine-parseable (single source of truth for CI and tests).
- **stderr**: fatal errors / usage only.

### Output Format (stdout)

```text
[PASS] structure-files      required files present
[FAIL] structure-files      k8s/deploy.yaml missing            fix: generate manifests (run build.sh) or add the file
[PASS] secrets-scan         no credential patterns in git-tracked files
[N/A]  policy-manifests     no k8s/ manifests for profile 'library'
AUDIT RESULT: PASS (2 pass, 1 fail, 1 n/a)
```

Each check line: `[STATUS] <check-id>\t<detail>\tfix: <remediation>`. The
`fix:` part is mandatory on `FAIL` (Gate Ergonomics) and omitted/blank otherwise.

### Exit Codes

| Code | Meaning |
|------|---------|
| 0 | PASS — zero failing checks |
| 1 | FAIL — one or more failing checks |
| 2 | usage/argument error |

`N/A` lines never fail the run. Ordering of checks is deterministic:
`structure-files`, `secrets-scan`, `policy-manifests`.

## Environment & Portability

- Interpreter: bash, `set -euo pipefail`.
- Dependencies: `grep` (BSD/GNU portable patterns), `awk`, `find` `-maxdepth`
  usage guarded, `yq` NOT required (structure parsing stays grep/awk-based).
- Scan surface: git-tracked files only (secrets check).
- Deterministic: no network, no cluster, no timestamps in output.