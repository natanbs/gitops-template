# Data Model: Repo Standards Alignment

Ground truth for the P1 audit runner, its workflow wrapper, and the provenance
stamp. Modeled for a Bash + GitHub Actions project; kept intentionally small.

## Entities

### RepoProfile

Represents the declared shape of a consumer repo. Declared explicitly by the
caller — never auto-detected.

| Field | Type | Values / Rules |
|-------|------|----------------|
| id | enum | `app-k8s` | `app` | `library` (mandatory input to runner and workflow) |
| applicable checks | derived | `app-k8s` → structure, secrets, manifest-policy; `app` → structure, secrets; `library` → structure, secrets (no Dockerfile requirement) |
| default | const | `app-k8s` (scaffolded default) |

Identity/uniqueness: one profile per AuditRun. Lifecycle: declared at run start,
fixed for the run.

### AuditCheck

A single check unit with deterministic outcome.

| Field | Type | Rules |
|-------|------|-------|
| id | string | canonical kebab id, e.g. `structure-files`, `secrets-scan`, `policy-manifests` |
| category | enum | `structure` | `secrets` | `manifest-policy` |
| profiles | list[RepoProfile] | which profiles the check runs for |
| status | enum | `PASS` | `FAIL` | `N/A` |
| detail | string | human text; on FAIL must name violating file(s) |
| remediation | string | required for FAIL (Gate Ergonomics); optional for N/A |

Validation rule: a check whose inputs are not applicable to the declared profile
MUST have status `N/A` — never `FAIL`, never skipped silently.

### CheckResult (per-file / per-scope evidence)

Captured inside an AuditCheck; each FAIL references at least one evidence row so
the remediation line points at a concrete file.

| Field | Type | Rules |
|-------|------|-------|
| file | path | repo-relative path of the violating artifact |
| finding | string | what is wrong |
| suggested_fix | string | actionable deterministic remediation |

### AuditRun

One invocation of the runner.

| Field | Type | Rules |
|-------|------|-------|
| repo_root | path | absolute or relative repo root to audit |
| repo_profile | RepoProfile | mandatory CLI arg / workflow input |
| checks | list[AuditCheck] | all applicable checks, each with one status line |
| aggregate | enum | `PASS` iff `FAIL == 0`; `N/A` lines never affect outcome |
| exit_code | int | `0` PASS, `1` FAIL |
| scan_surface | const | git-tracked files only (see SecretRuleset) |

Lifecycle/state transitions:

```text
Collect inputs → Run checks (deterministic order) → Emit per-check line
  → Emit aggregate  → exit PASS(0) | FAIL(1)
```

### SecretRuleset

The pinned, reviewable detection rules for the secrets check (git-tracked files
only).

| Field | Type | Rules |
|-------|------|-------|
| name | string | stable id, e.g. `aws-access-key`, `private-key`, `generic-keyvalue` |
| pattern | regex (BRE/ERE portable) | POSIX grep-compatible; BSD/GNU-safe |
| allowlist (optional) | file path | exemptions file (`standards-audit/allowlist`) — line/file-based, committed by reviewer |

Validation: patterns portability-tested on macOS BSD and GNU grep via bats.

### TemplateVersion

The provenance stamp written by `init.sh` into scaffolded apps.

| Field | Value / Rule |
|-------|--------------|
| source | `init/template-version` — single canonical constant (content `1.0.0`) |
| artifact | `.template-version` in the scaffolded app root, copied verbatim |
| format | plain semver line, e.g. `1.0.0`; trailing newline, no other content |
| identity | one per app repo; consumed by future P3 re-sync tooling |
| lifecycle | created at scaffold; never mutated by P1 |

## Validation Rules (from spec FRs)

- FR2/F R3: every check yields exactly one `[PASS|FAIL|N/A]` line plus aggregate; no
  silent skips.
- FR6: any `FAIL` line MUST include remediation naming the file; a gate without a
  remedy is a defect (Constitution II — Gate Ergonomics).
- FR4: `.template-version` content is byte-for-byte the canonical constant.
- P2 fingerprinting (future): manifest-policy may later add image-digest pins; model
  reserved, not implemented in P1.

## Exclusions (P1)

- No org-level enforcement topology (P2). No re-sync mechanics (P3). No cronjob
  drift scanning beyond `.env` port/tag/pvc agreement. No cluster connectivity.