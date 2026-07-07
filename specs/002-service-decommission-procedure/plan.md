# Implementation Plan: Service Decommission Procedure

**Branch**: `002-service-decommission-procedure` | **Date**: 2026-07-07 | **Spec**: spec.md

**Input**: Feature specification from `/specs/002-service-decommission-procedure/spec.md`

## Summary

Document a repeatable procedure for safely decommissioning services managed via the GitOps template. The procedure covers two deployment models (GitOps/ArgoCD and Direct Deploy), with mandatory pre-checks, phase-specific recovery guidance, PVC data retention decisions, container image cleanup, and lightweight audit trail.

## Technical Context

**Language/Version**: N/A (documentation/runbook feature)

**Primary Dependencies**: N/A

**Storage**: N/A

**Testing**: The procedure's acceptance is verified by following it against a sandbox deployment — no automated test framework needed

**Target Platform**: N/A

**Project Type**: Documentation / Runbook

**Performance Goals**: N/A

**Constraints**: Must be a documented procedure, not an automated script; must work for both GitOps and Direct Deploy models

**Scale/Scope**: One procedure document covering both deployment models, with pre-checks, PVC handling, registry cleanup, recovery steps, and audit trail

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

Constitution file is a template (unpopulated) — no specific principles to evaluate. Gate: **PASS**.

## Project Structure

### Documentation (this feature)

```text
specs/002-service-decommission-procedure/
├── plan.md              # This file
├── spec.md              # Feature specification (from /spec.specify + /spec.clarify)
├── research.md          # Phase 0 — design decisions and alternatives
├── data-model.md        # Phase 1 — entities, state transitions, validation rules
├── quickstart.md        # Phase 1 — condensed decommission guide
├── team-context.md      # Discovered team context from team-ai-directives
├── brainstorm-context.md # Brainstorm exploration (consumed by spec)
└── checklists/
    └── requirements.md  # Spec quality checklist
```

### Source Code (no code changes — documentation only)

No source code changes. The deliverable is a documentation update to this template repository's `init/` or root docs directory. Exact location to be determined during implementation (options: `docs/decommission.md`, `DEcommission.md` in root, or a new `runbooks/` directory).

## Complexity Tracking

No constitution violations to justify. Procedure is straightforward documentation.

## Implementation Tasks

### Phase: Research & Design (Completed)

| Task | Status | Classification |
|------|--------|---------------|
| Generate research.md with design decisions | Done | [ASYNC] — research, no human review needed |
| Generate data-model.md with entities and state transitions | Done | [ASYNC] — design, no human review needed |
| Generate quickstart.md with condensed decommission guide | Done | [ASYNC] — design, no human review needed |

### Phase: Documentation Writing

| # | Task | Classification | Rationale |
|---|------|---------------|-----------|
| 1 | Write GitOps decommission procedure (full steps with pre-checks, verification, recovery, audit) | [SYNC] | Core deliverable — operator will follow this verbatim; requires human review for correctness |
| 2 | Write Direct Deploy decommission procedure (kubectl sequence, verification, recovery) | [SYNC] | Second path — human review needed to ensure deletion order is safe |
| 3 | Write PVC data retention guidance | [SYNC] | Data loss risk requires explicit human sign-off |
| 4 | Write registry cleanup guidance (common registry types) | [ASYNC] | Reference material — well-known information, no correctness risk |
| 5 | Write pre-decommission safety checklist | [SYNC] | Safety-critical — must be reviewed for completeness |
| 6 | Write recovery guidance for each decommission phase | [ASYNC] | Follows from the procedure structure — straightforward |
| 7 | Write audit trail template and instructions | [ASYNC] | Simple template, no material risk |
| 8 | Determine final file location and integrate with repo (e.g., update README or CI-CD-FLOW.md to reference procedure) | [SYNC] | Structural decision affecting discoverability |

### Phase: Verification

| # | Task | Classification | Rationale |
|---|------|---------------|-----------|
| 9 | Run through GitOps procedure against a sandbox deployment end-to-end | [ASYNC] | Can be executed autonomously; results logged for review |
| 10 | Run through Direct Deploy procedure against a sandbox deployment end-to-end | [ASYNC] | Same as above |
| 11 | Review all safety-critical sections for accuracy | [SYNC] | Human judgement required for safety |
| 12 | Update quality checklist with completion status | [ASYNC] | Housekeeping |

### Classification Count

- **[SYNC]**: 5 (tasks 1, 2, 3, 5, 8) — all involve safety-critical or structural decisions requiring human review
- **[ASYNC]**: 7 (tasks 4, 6, 7, 9, 10, 11, 12) — reference material, validation runs, or housekeeping
