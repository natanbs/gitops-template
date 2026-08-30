<!--
# Sync Impact Report

**Version change**: (uninitialized placeholder template) → v1.0.0
**Modified principles**: none – initial ratification
**Added sections**: Core Principles (I. Phased Rollout Hierarchy, II. Operational Guardrails), Pending Decision Log, Governance
**Removed sections**: none (template's third section slot and example comments dropped as unfilled)
**Follow-up TODOs**:
  - Pending Decision Log: 5 unresolved parameters block gated phases (Scope, Infra, Tooling, Ownership, Migration).
  - AGENTS.md references /Users/natan/projects/agentic-sdlc-team-ai-directives/context_modules/constitution.md for inheritance; path not found — inheritance TODO(TEAM_CONSTITUTION): source missing, revisit when available.
-->

# Fleet Alignment Constitution

## Core Principles

### I. Phased Rollout Hierarchy

Fleet-wide changes MUST follow this strict sequence. Skipping a phase without a formal waiver (see Pending Decision Log) is a violation.

1. **Gate Compliance First** — Enforce automated PR/CI guardrails before attempting any code re-sync. Compliance gates MUST run at merge time on every consumer repo.
2. **Shared Versioned Artifacts** — Centralize shared workflows behind explicit semantic versioning. References MUST be pinned to `@vX.Y.Z`. Dynamic or unpinned refs (e.g. `@main`, floating `latest`) are PROHIBITED.
3. **Tracked Re-Sync** — Maintain upstream template lineage for ongoing sync. Each consumer repo MUST record the template version it was generated from so re-syncs stay auditable.

### II. Operational Guardrails

- **Blast-Radius Isolation** — Shared pipeline updates MUST undergo canary validation on pilot repositories prior to global release. No shared artifact reaches the fleet without a canary record.
- **Gate Ergonomics** — Every blocking compliance check MUST output an actionable, deterministic remediation path. Any check that fails without a remedy is a defect and MUST be fixed.
- **Bypass Auditing** — Emergency overrides REQUIRE auditable approval and an automatically tracked tech-debt expiration date. A bypass without an owner, approval record, or expiry date is a violation.

## Pending Decision Log

The following parameters are blocked until explicitly resolved. Each resolution MUST be recorded as a formal amendment to this constitution.

- [ ] **Scope**: Fleet size & language runtime bounds
- [ ] **Infra**: Provider constraint (GitHub-only vs. Multi-provider)
- [ ] **Tooling**: Approval of copier dependency for template sync
- [ ] **Ownership**: Designated maintainer team for security rule sets
- [ ] **Migration**: Brownfield repository onboarding path

## Governance

- This constitution supersedes all other practices and templates. Existing directives MUST be aligned with this document before they take effect.
- Amendments require documentation, explicit approval, and a migration plan.
- Versioning policy (Semantic Versioning):
  - MAJOR — backward-incompatible principle removals or redefinitions.
  - MINOR — new principle/section added or materially expanded guidance.
  - PATCH — clarifications, wording, and non-semantic refinements.
- Compliance review: PRs and reviews MUST verify alignment with the Core Principles.
- Pending Decision Log items block the phases they gate; rolling out a gated phase without resolution is a violation.

**Version**: 1.0.0 | **Ratified**: 2026-08-30 | **Last Amended**: 2026-08-30