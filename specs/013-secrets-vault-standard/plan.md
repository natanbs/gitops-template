# Implementation Plan: Secrets & Vault Standard Conformance

**Branch**: `013-secrets-vault-standard` | **Date**: 2026-08-31 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/013-secrets-vault-standard/spec.md`
(+ clarification session 2026-08-31), Fleet Alignment Constitution
(`.specify/memory/constitution.md` v1.0.0)

## Summary

Point-in-time fleet audit of the ArgoCD applicative inventory (6 repos) that
scores each repo's secrets management against the canonical Vault-backed ESO
standard (CDR-2026-017 + user-selected Vault). The audit is offline, read-only,
and deterministic: it scans each repo's tracked files for Vault/ESO indicators
(SecretStore/ClusterSecretStore + ExternalSecret), committed secrets, hardcoded
credentials, and path-convention adherence, then produces a per-repo verdict
(CONFORMING / NON-CONFORMING / N/A / UNKNOWN) with `fix:` remediation lines
and a fleet summary report. Gate integration (continuous enforcement) is a gated
RFC follow-on per the constitution's Pending Decision Log ("Ownership").

## Technical Context

**Language/Version**: Bash (`set -euo pipefail`; macOS BSD + Linux GNU grep/awk compatible)
**Primary Dependencies**: `grep`, `awk`, `git`, `yq` (YAML parsing for Argo inventory + manifests)
**Storage**: Filesystem only — reads git-tracked files; writes markdown report to stdout/file
**Testing**: Bats (`cicd-tests/`) + ShellCheck
**Target Platform**: macOS / Linux dev machines; GitHub Actions (reusable workflow)
**Project Type**: Shell CLI tooling + fleet audit report (standalone, not wired to gate)
**Performance Goals**: Per-repo scan < 5s; fleet scan (6 repos) < 30s; deterministic output
**Constraints**: Offline (no live Vault reads); read-only; POSIX-bash-portable (grep/awk); BSD/GNU compatible; `fix:` lines on every FAIL (Gate Ergonomics II-2); deterministic sort order; N/A semantics for repos with no secrets
**Scale/Scope**: 6 repos audited per run; ~10 files added (audit script, detectors, fixtures, tests, docs, contracts)

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

**Fleet Alignment Constitution v1.0.0** (`.specify/memory/constitution.md`)

| Principle | Implication for this change | Status |
|-----------|-----------------------------|--------|
| I-1 Gate Compliance First | Audit is point-in-time; gate integration is gated RFC (Q3: C). No gate changes shipped. | PASS |
| I-2 Shared Versioned Artifacts @vX.Y.Z | No new unpinned refs introduced; no workflow changes | PASS |
| I-3 Tracked Re-Sync | P1 audit is point-in-time; continuous enforcement gated by PDL | PASS |
| II-1 Blast-Radius Isolation | Audit is read-only + offline; cannot break builds or modify repos | PASS |
| II-2 Gate Ergonomics | Every FAIL line embeds `fix:` remediation (mirrors 001 pattern) | PASS |
| II-3 Bypass Auditing | Audit report is plain markdown; no bypass mechanism | PASS |
| Pending Decision Log | Gate integration deferred to RFC after Ownership resolves | PASS |

**Gate result (pre-research)**: PASS — no violations.
**Gate result (post-design)**: PASS — unchanged; no new gates introduced.

## Project Structure

### Documentation (this feature)

```text
specs/013-secrets-vault-standard/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/
│   ├── standard.md      # Canonical Vault-backed ESO standard definition
│   ├── audit-cli.md     # Audit CLI interface contract
│   └── report.md        # Report output schema
├── spec.md              # Feature spec (from /spec.specify)
├── team-context.md      # Team discovery artifact
└── tasks.md             # Phase 2 output (/spec.tasks)
```

### Source Code (repository root)

```text
secrets-vault-standard/
├── audit-fleet.sh                       # new: fleet audit entrypoint
├── detectors/
│   ├── vault-eso.sh                     # new: Vault-backed ESO pattern detection
│   ├── committed-secrets.sh             # new: git-tracked secret/hardcoded cred scan
│   └── path-convention.sh              # new: DRY path convention scoring
├── fixtures/
│   ├── conformant-vault-eso/            # new: repo with per-app SecretStore
│   ├── conformant-cluster-store/        # new: repo consuming ClusterSecretStore
│   ├── non-conformant-no-vault/         # new: repo with no Vault/ESO
│   ├── non-conformant-hardcoded/        # new: repo with committed secrets
│   ├── na-no-secrets/                   # new: repo with zero secrets (argo-app-go-server analog)
│   └── unknown-manual-review/           # new: edge case needing human judgment
└── tests/
    ├── audit-fleet.bats                 # new: integration tests
    └── detectors.bats                   # new: unit tests for detectors
cicd-tests/
├── secrets_vault_audit.bats             # new: bats for the fleet audit tool
└── ...
examples/
└── secrets-vault-standard-fleet-report.md  # new: sample fleet report
```

**Structure Decision**: Follows 001 conventions — flat `standards-audit/`-style
layout with detectors, fixtures, and bats tests; top-level `audit-fleet.sh`
entrypoint; detectors split by concern (Vault/ESO pattern, committed secrets,
path convention). Report is markdown (not JSON) for human readability; JSON
can be added later if the gate integration RFC requires machine-parseable output.

## Triage Framework: [SYNC] vs [ASYNC] Classification

Implementation is bash + YAML with correctness-critical grep/awk portability
and domain-specific detection logic; classification prioritizes human review on
detection heuristics, delegating deterministic fixture/test work.

### Preliminary Task Classification

| Task Category | Estimated [SYNC] Tasks | Estimated [ASYNC] Tasks | Rationale |
|---------------|----------------------|----------------------|-----------|
| Business Logic | 4 | 0 | audit-fleet.sh + detectors (Vault/ESO heuristics, committed secrets, path convention) |
| Integration | 1 | 0 | inventory parsing (Argo YAML → repo list) |
| Testing | 0 | 5 | fixtures + bats — deterministic, delegable |
| Documentation | 0 | 2 | sample report + quickstart |

### Triage Decision Criteria Applied

**High-Risk [SYNC] Classifications:**
- `detectors/vault-eso.sh` — correctness of Vault/ESO indicator detection across dual topology (per-app SecretStore vs ClusterSecretStore); false negatives miss real Vault usage, false positives mark non-Vault patterns as conforming.
- `detectors/committed-secrets.sh` — grep pattern accuracy (PII, bcrypt hashes, API keys, credentials); false negatives are security-critical.
- `detectors/path-convention.sh` — path convention scoring across different ExternalSecret `secretRef` shapes.
- `audit-fleet.sh` — aggregate verdict logic, deterministic output, inventory parsing.

**Agent-Delegated [ASYNC] Classifications:**
- Fixture construction and bats assertions (deterministic; patterns from 001).
- Sample report and quickstart documentation (non-blocking, reviewable later).

### Triage Audit Trail

| Task | Classification | Primary Criteria | Risk Level | Rationale |
|------|----------------|------------------|------------|-----------|
| audit-fleet.sh | SYNC | Correctness + inventory parsing | Med | Argo YAML parsing + aggregate verdict |
| vault-eso.sh detector | SYNC | Security correctness | High | Dual topology; ESO+Vault is the org standard |
| committed-secrets.sh | SYNC | Security correctness | High | False negatives = leaked secrets undetected |
| path-convention.sh | SYNC | Scoring accuracy | Med | Different ExternalSecret shapes across repos |
| fixtures + bats | ASYNC | Automation | Low | Deterministic, no cluster/docker |
| sample report + quickstart | ASYNC | Documentation | Low | Non-blocking |

## Complexity Tracking

> **Not filled**: no constitution violations exist to justify.

## Verification

- `bats cicd-tests/` — all pre-existing suites pass (no new failures).
- `bats secrets-vault-standard/tests/` — detectors pass on conformant, non-conformant, N/A, and UNKNOWN fixtures.
- `shellcheck secrets-vault-standard/*.sh secrets-vault-standard/detectors/*.sh` — no warnings.
- Manual: `./secrets-vault-standard/audit-fleet.sh --repo-root /Users/natan/projects/repos --inventory /Users/natan/projects/repos/infra/argocd-infra/apps/applicative` produces deterministic fleet report.
- Fleet report matches expected verdicts per the fleet survey (5/6 Vault repos, 1 N/A, 2 with committed secrets flagged).
