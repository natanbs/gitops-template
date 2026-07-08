# Implementation Plan: Decommission CLI

**Branch**: `003-decommission-cli` | **Date**: 2026-07-07 | **Spec**: specs/003-decommission-cli/spec.md
**Input**: Feature specification from `/specs/003-decommission-cli/spec.md`

## Summary

Build a Go CLI binary (`decommission`) that automates the decommission procedure for services deployed via the GitOps template. The CLI auto-detects the deployment model (GitOps vs Direct Deploy), runs mandatory pre-checks (bypassable with `--force`), executes the appropriate resource deletion workflow, cleans up the container image, records an audit entry, and supports `--dry-run` mode.

## Technical Context

**Language/Version**: Go 1.22+
**Primary Dependencies**: Go standard library (flag, fmt, os/exec, encoding/json), client-go for K8s API discovery, git CLI (exec'd), argocd CLI (exec'd), Docker/registry CLI (exec'd)
**Storage**: N/A (no persistent storage — stateless CLI reading cluster/registry state)
**Testing**: Go test (unit tests + integration tests against k3d sandbox)
**Target Platform**: macOS, Linux (operator workstation)
**Project Type**: CLI tool
**Performance Goals**: N/A (interactive CLI; SC-001 targets <60s operator interaction)
**Constraints**: Go single binary; runs from operator workstation (no cluster-internal access); supports both GitOps and Direct Deploy models
**Scale/Scope**: Single CLI binary in repository root at `cmd/decommission/`

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

Constitution file is a template (unpopulated) — no specific principles to evaluate. Gate: **PASS**.

## Project Structure

### Documentation (this feature)

```text
specs/003-decommission-cli/
├── plan.md              # This file
├── spec.md              # Feature specification
├── research.md          # Phase 0 — design decisions and alternatives
├── data-model.md        # Phase 1 — entities, state transitions, validation rules
├── quickstart.md        # Phase 1 — condensed usage guide
└── contracts/           # Phase 1 — CLI command schema and exit codes
```

### Source Code (repository root)

```text
cmd/decommission/
├── main.go              # Entry point, flag parsing, top-level dispatch
├── precheck.go          # Safety check logic (service exists, connections, etc.)
├── detect.go            # Deployment model detection (GitOps vs Direct Deploy)
├── gitops.go            # GitOps decommission workflow
├── direct.go            # Direct Deploy decommission workflow
├── pvc.go               # PVC detection and retention prompt
├── registry.go          # Container image cleanup
├── audit.go             # Audit record creation and output
├── dryrun.go            # Dry-run mode (display + skip destructive ops)
└── types.go             # Shared types, constants, error definitions

cmd/decommission/decommission_test.go  # Unit tests

hack/decommission/          # Integration test scripts (optional)
```

**Structure Decision**: Single Go module at repository root with all source in `cmd/decommission/`. No library split needed — this is a standalone operational tool. Tests co-located in the same package.

## Triage Framework: [SYNC] vs [ASYNC] Classification

**Execution Strategy**: This feature will use a hybrid execution model combining human expertise ([SYNC]) with autonomous agent delegation ([ASYNC]).

### Preliminary Task Classification

| Task Category | Estimated [SYNC] Tasks | Estimated [ASYNC] Tasks | Rationale |
|---------------|----------------------|----------------------|-----------|
| Project Setup | 1 | 1 | Go mod init + file creation is ASYNC; build/CI config needs SYNC review |
| Core Logic | 2 | 5 | Pre-checks and GitOps workflow are safety-critical (SYNC); Direct Deploy, PVC, registry are well-defined (ASYNC) |
| Output/Reporting | 0 | 2 | Progress output and audit trail are straightforward (ASYNC) |
| Integration | 1 | 1 | K8s API integration needs SYNC review; CLI exec wrappers are ASYNC |
| Verification | 1 | 1 | Sandbox validation is ASYNC; safety review is SYNC |

### Triage Decision Criteria Applied

**High-Risk [SYNC] Classifications:**
- Pre-check enforcement logic and --force bypass (safety-critical, data loss risk)
- GitOps workflow: git operations + ArgoCD interaction (irreversible changes to repo and cluster)
- K8s resource deletion orchestration (deletion order correctness)

**Agent-Delegated [ASYNC] Classifications:**
- Boilerplate: main.go, flag parsing, help text
- Registry cleanup per type (well-known commands, reference material)
- PVC detection and prompt logic (conditional, no side effects)
- Audit record template (simple data structure)
- Dry-run implementation (follows same structure, skips destructive calls)

### Triage Audit Trail

| Task | Classification | Primary Criteria | Risk Level | Rationale |
|------|----------------|------------------|------------|-----------|
| Pre-check logic | SYNC | Safety-critical | High | Data loss risk; must be human-reviewed |
| GitOps workflow | SYNC | Irreversible | High | Modifies git history and K8s state |
| Direct Deploy | ASYNC | Well-defined | Medium | Deterministic kubectl sequence |
| Registry cleanup | ASYNC | Reference material | Low | Well-known commands per registry type |
| PVC handling | ASYNC | Conditional logic | Low | Simple prompt + conditional delete |
| Audit trail | ASYNC | Simple data | Low | Struct + file output |
| Dry-run mode | ASYNC | Mirror of exec logic | Low | Wraps same code paths |
| Build/CI config | SYNC | Structural | Medium | Go module, Makefile, CI integration |
| Sandbox validation | ASYNC | Executable | Medium | Script-driven test against k3d |
| Safety review | SYNC | Human judgement | High | Final accuracy review |

## Complexity Tracking

No constitution violations to justify. Feature is a straightforward Go CLI.
