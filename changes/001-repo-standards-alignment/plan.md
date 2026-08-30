# Implementation Plan: Repo Standards Alignment

**Branch**: `001-repo-standards-alignment` | **Date**: 2026-08-30 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `changes/001-repo-standards-alignment/spec.md`
(+ clarify session 2026-08-30), Fleet Alignment Constitution
(`.specify/memory/constitution.md` v1.0.0)

## Summary

P1 of the constitution-mandated phased alignment: (a) a reusable, opt-in,
offline standards-audit workflow (`standards-audit.yml` → `runner.sh`) that
validates repo structure, git-tracked secrets, and k8s manifest policy per an
explicit repo profile (with N/A semantics), and (b) template provenance — `init.sh`
stamps `.template-version` from the canonical `init/template-version` constant.
P2 (org-level shared versioned artifacts) and P3 (tracked re-sync) are recorded
as RFC tasks gated by the constitution's Pending Decision Log.

## Technical Context

**Language/Version**: Bash (`set -euo pipefail`; macOS BSD + Linux GNU grep/awk compatible)
**Primary Dependencies**: `grep`, `awk`, `git` (scan surface); bats + shellcheck (test only)
**Storage**: Filesystem only — `.env`, `k8s/*.yaml`, `.template-version`, `standards-audit/`
**Testing**: Bats (`bats standards-audit/tests/`, `bats cicd-tests/`) + ShellCheck
**Target Platform**: macOS / Linux dev machines; GitHub Actions (reusable workflow)
**Project Type**: Shell CLI tooling + CI/CD reusable workflow (gitops standalone)
**Performance Goals**: Deterministic, offline; per-check median < 1s on app-sized repos
**Constraints**: Profile-adaptive checks (N/A semantics); git-tracked secret scan; `.env`
best-effort policy with internal-consistency fallback; opt-in adoption; SHA-pinned actions;
Gate Ergonomics (FAIL lines embed `fix:`); BSD/GNU portable grep patterns
**Scale/Scope**: 1 repo audited per run; ~15 files added (workflow, runner, checks, fixtures,
tests, docs); init.sh + gitignore + README modified

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

**Fleet Alignment Constitution v1.0.0** (.specify/memory/constitution.md)

| Principle | Implication for this change | Status |
|-----------|-----------------------------|--------|
| I-1 Gate Compliance First | P1 delivers merge-time gates before any re-sync | PASS |
| I-2 Shared Versioned Artifacts @vX.Y.Z | No unpinned refs introduced; SHA pinning; P2 promotion documented | PASS |
| I-3 Tracked Re-Sync | Provenance `.template-version` shipped now; P3 RFC gated | PASS |
| II-1 Blast-Radius Isolation | P2 RFC mandates canary on pilot repos | PASS (n/a to P1) |
| II-2 Gate Ergonomics | FR6 — every FAIL line carries `fix:` remediation | PASS |
| II-3 Bypass Auditing | No override/bypass mechanism introduced in P1 | PASS (n/a) |
| Pending Decision Log | P2/P3 tasks blocked until Infra/Ownership/Tooling/Migration resolved | PASS |

**Gate result (pre-research)**: PASS — no violations.
**Gate result (post-design)**: PASS — unchanged; no new gates introduced.

## Project Structure

### Documentation (this feature)

```text
changes/001-repo-standards-alignment/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/
│   ├── cli.md           # runner.sh CLI + IO/exit-code contract
│   ├── workflow.md      # reusable workflow + caller contract
│   └── template-version.md
├── spec.md              # Feature spec (from /spec)
└── tasks.md             # Phase 2 output (/spec.tasks)
```

### Source Code (repository root)

```text
.github/workflows/standards-audit.yml   # new: reusable workflow_call
examples/standards-audit-caller.yml     # new: documented opt-in caller
standards-audit/
├── runner.sh                           # new: offline audit runner
├── checks/
│   ├── structure.sh                    # new: profile-adaptive required files + YAML parse
│   ├── secrets.sh                      # new: git-tracked credential scan (pinned ruleset)
│   └── manifest-policy.sh              # new: .env best-effort + consistency fallback
├── allowlist.example                   # new: exemptions template
├── fixtures/
│   ├── conformant-app-k8s/             # new
│   ├── non-conformant-app-k8s/         # new
│   └── app-only/                       # new (N/A path fixture)
└── tests/*.bats                        # new: runner coverage
init/
├── template-version                    # new: canonical constant "1.0.0"
└── init.sh                             # modified: stamp .template-version
init/gitignore                          # modified: don't ignore .template-version
cicd-tests/init_env.bats                # modified: stamping test
README.md                               # modified: Standards Alignment section
```

**Structure Decision**: Follows the existing flat layout (root scripts + `init/`
templates + bats tests); the audit is a self-contained `standards-audit/` unit
mirroring `cicd-tests/` conventions, deliberately parallel to `init/`.

## Triage Framework: [SYNC] vs [ASYNC] Classification

Implementation is bash + YAML with correctness-critical sed/grep/awk portability;
classification prioritizes human review on logic, delegating deterministic test
and fixture work.

### Preliminary Task Classification

| Task Category | Estimated [SYNC] Tasks | Estimated [ASYNC] Tasks | Rationale |
|---------------|----------------------|----------------------|-----------|
| Business Logic | 5 | 0 | runner + checks (BSD/GNU portability, N/A semantics, .env fallback) |
| Integration | 3 | 1 | workflow + init.sh stamping + gitignore; caller example is doc-style |
| Testing | 0 | 5 | fixtures + bats — deterministic, delegable |
| Documentation | 0 | 2 | README roadmap, allowlist example |

### Triage Decision Criteria Applied

**High-Risk [SYNC] Classifications:**
- `checks/secrets.sh` + `manifest-policy.sh` — grep/awk portability and the
  `.env`-fallback branch are correctness-critical and silent-failure-prone.
- `runner.sh` — exit-code/aggregate contract + Gate Ergonomics output shape.
- `standards-audit.yml` — permissions/SHA-pinning; must not introduce unpinned refs.
- `init/init.sh` stamping + gitignore — must not clobber custom `.gitignore` edits.

**Agent-Delegated [ASYNC] Classifications:**
- Fixture construction and bats assertions (deterministic; format from cli.md).
- Caller example YAML and README section (documentation-quality, non-blocking).

### Triage Audit Trail

| Task | Classification | Primary Criteria | Risk Level | Rationale |
|------|----------------|------------------|------------|-----------|
| runner.sh core | SYNC | Correctness + portability | Med | exit codes + BSD/GNU grep conflict risk |
| secrets.sh ruleset | SYNC | Security correctness | High | false-negative (missed cred) or false-positive (block) |
| manifest-policy.sh | SYNC | Fallback branching | Med | `.env`-present vs absent divergence; value-level agreement only |
| structure.sh | SYNC | Profile semantics | Med | N/A must never FAIL; `.env` FORMAT parse only (value-level owned by manifest-policy.sh) |
| standards-audit.yml | SYNC | Security + pinning | Med | least privilege, SHA pins, opt-in only |
| init.sh/.gitignore stamping | SYNC | Regression safety | Med | must not break existing scaffold tests |
| fixtures + bats | ASYNC | Automation | Low | deterministic, no cluster/docker |
| caller example + README | ASYNC | Documentation | Low | non-blocking, reviewable later |

## Complexity Tracking

> **Not filled**: no constitution violations exist to justify.

## Verification

- `bats cicd-tests/` — all pre-existing suites pass (no new failures; known
  environmental failures unchanged).
- `bats standards-audit/tests/` — PASS/FAIL/N/A and remediation assertions green
  on conformant, non-conformant, and `app`-profile fixtures.
- `shellcheck standards-audit/runner.sh build.sh init/init.sh` — no new warnings.
- Manual scenarios from `quickstart.md` (1–5) run clean on macOS and Linux.
- Optional live smoke test of the reusable workflow (quickstart scenario 6) if a
  GitHub runner is reachable; otherwise documented manual invocation is the gate.