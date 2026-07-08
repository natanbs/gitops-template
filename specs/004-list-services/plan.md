# Implementation Plan: List Available Services

**Branch**: `004-list-services` | **Date**: 2026-07-07 | **Spec**: specs/004-list-services/spec.md
**Input**: Feature specification from `specs/004-list-services/spec.md`

## Summary

Add a `--list` flag to the existing `decommission` CLI that discovers and displays all services in the cluster — both GitOps (ArgoCD Applications) and Direct Deploy (kubectl Deployments) — with their namespace, deployment model, and health status. The listing supports namespace filtering (`--namespace`) and JSON output (`--json`).

## Technical Context

**Language/Version**: Go 1.22+ (matching existing CLI at `cmd/decommission/`)
**Primary Dependencies**: Go standard library (flag, fmt, encoding/json, os/exec); kubectl (exec'd); existing decommission codebase (detect.go, types.go)
**Storage**: N/A (stateless CLI)
**Testing**: Go test (unit tests for list logic); manual verification against cluster
**Target Platform**: macOS, Linux (operator workstation)
**Project Type**: CLI tool — extension to existing `cmd/decommission/` package
**Performance Goals**: N/A (interactive CLI; SC-001 targets <5s interaction)
**Constraints**: Must extend the existing binary with a single new file; no new external dependencies; reuse existing `--namespace`, `--json` flag semantics
**Scale/Scope**: Single new file `cmd/decommission/list.go` plus minor update to `main.go`

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

Constitution file is an unfilled template — no specific principles to evaluate. Gate: **PASS**.

## Project Structure

### Documentation (this feature)

```text
specs/004-list-services/
├── plan.md              # This file
├── spec.md              # Feature specification
├── research.md          # Phase 0 — design decisions and alternatives
├── data-model.md        # Phase 1 — entities and fields
├── quickstart.md        # Phase 1 — condensed usage guide
└── contracts/           # Phase 1 — CLI command schema
```

### Source Code (repository root)

```text
cmd/decommission/
├── main.go              # Entry point — add --list flag dispatch (existing file)
├── list.go              # Service listing logic (NEW)
├── types.go             # Shared types — extend with ServiceInfo (existing file)
└── ...                  # All other existing files unchanged
```

**Structure Decision**: Single new file `list.go` in the existing `cmd/decommission/` package. No new modules, no library split. This is a minor extension to an existing operational tool.

## Triage Framework: [SYNC] vs [ASYNC] Classification

**Execution Strategy**: This feature will use a hybrid execution model combining human expertise ([SYNC]) with autonomous agent delegation ([ASYNC]).

### Preliminary Task Classification

| Task Category | Estimated [SYNC] Tasks | Estimated [ASYNC] Tasks | Rationale |
|---------------|----------------------|----------------------|-----------|
| Core Logic | 0 | 1 | List logic is straightforward kubectl exec + formatting |
| Output/Reporting | 0 | 1 | Table + JSON output follows existing audit.go patterns |
| Integration | 0 | 1 | CLI dispatch + flag wiring is boilerplate |

### Triage Decision Criteria Applied

**High-Risk [SYNC] Classifications:**
- None — listing is read-only; no destructive operations or data loss risk

**Agent-Delegated [ASYNC] Classifications:**
- All tasks: well-defined kubectl commands, deterministic output formatting, no irreversible actions

### Triage Audit Trail

| Task | Classification | Primary Criteria | Risk Level | Rationale |
|------|----------------|------------------|------------|-----------|
| Service discovery + listing | ASYNC | Well-defined | Low | Standard kubectl get + format; read-only |
| CLI flag wiring | ASYNC | Boilerplate | Low | Follows existing flag.Add + dispatch pattern |
| JSON output | ASYNC | Simple data | Low | json.Marshal pattern from audit.go |

## Complexity Tracking

No constitution violations to justify. Feature is a trivial extension to an existing CLI.
