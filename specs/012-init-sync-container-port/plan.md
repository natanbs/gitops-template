# Implementation Plan: init.sh Syncs K8s Port from CONTAINER_PORT

**Branch**: `012-init-sync-container-port` | **Date**: 2026-07-31 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/012-init-sync-container-port/spec.md`

**Status note**: Implementation was completed and verified in this session. This plan documents the delivered approach so `/spec.tasks` can record it against the spec.

## Summary

When `init.sh --build` / `init.sh --deploy` runs against an **existing** app (the `../gitops-template/init.sh --deploy` workflow from any repo), the k8s manifests currently keep stale ports because templates are only re-rendered for new apps. This plan adds a targeted, in-place port sync driven by `CONTAINER_PORT` from `.env`:

- `init/init.sh` — new `sync_container_port()` runs when `RUN_BUILD=true` on an existing app.
- `build.sh` — `step_template()` existing-file branch also syncs ports (so a direct `build.sh --auto-deploy` stays consistent).
- `cicd-tests/port_sync.bats` — regression tests for both entry points.

## Technical Context

**Language/Version**: Bash (`set -euo pipefail`; runs on macOS BSD and Linux GNU coreutils)
**Primary Dependencies**: `sed` (BSD/GNU `-i.bak`), `awk` (BSD/GNU), `grep`, `envsubst`, `bats` (test only)
**Storage**: Filesystem only (`.env`, `k8s/{svc,deploy,ingress}.yaml`)
**Testing**: Bats (`bats cicd-tests/`) + ShellCheck
**Target Platform**: macOS / Linux developer machines, k3d/Kubernetes cluster
**Project Type**: Shell CLI tooling (scaffold + CI/CD pipeline)
**Performance Goals**: N/A (idempotent, interactive)
**Constraints**: BSD sed BRE has no `\?`/`\+` quantifiers — must use separate expressions; preserve manifest customizations; idempotent
**Scale/Scope**: 2 scripts modified, 1 test file added

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

**Constitution status**: Template placeholder only — no principles or rules defined.
**Gate result (pre-research)**: PASS (no rules to violate)
**Gate result (post-design)**: PASS (unchanged; no new gates introduced)

## Project Structure

### Documentation (this feature)

```text
specs/012-init-sync-container-port/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/           # Phase 1 output
└── tasks.md             # Phase 2 output (/spec.tasks - NOT created by /spec.plan)
```

### Source Code (repository root)

```text
init/
└── init.sh              # Modified: sync_container_port() + call site

build.sh                 # Modified: step_template() existing-file branch (deploy/svc/ingress)

cicd-tests/
└── port_sync.bats       # New: 5 tests
```

**Structure Decision**: Follows the existing layout exactly. No new source files, no structural changes.

## Triage Framework: [SYNC] vs [ASYNC] Classification

**Execution Strategy**: Small, well-scoped shell edits — low overall risk; classification prioritizes correctness review of the sed/awk patterns and test reliability.

### Preliminary Task Classification

| Task Category | Estimated [SYNC] Tasks | Estimated [ASYNC] Tasks | Rationale |
|---------------|----------------------|----------------------|-----------|
| Business Logic | 2 | 0 | sed/awk port-sync patterns — correctness-critical, portability-sensitive (BSD vs GNU) |
| Integration | 1 | 0 | build.sh step_template existing-file branch — must not regress image/IMAGE_TAG update |
| Testing | 0 | 4 | Bats tests — scriptable and delegable |

### Triage Decision Criteria Applied

**High-Risk [SYNC] Classifications:**
- `sync_container_port()` sed patterns — must match template-generated formats and stay BSD-sed compatible
- `build.sh` deploy awk extension — must preserve existing image/IMAGE_TAG rewrite behavior

**Agent-Delegated [ASYNC] Classifications:**
- Bats regression tests (fixtures mirror real template output formats)

### Triage Audit Trail

| Task | Classification | Primary Criteria | Risk Level | Rationale |
|------|----------------|------------------|------------|-----------|
| init.sh port sync | SYNC | Correctness + portability | Med | sed BRE differs BSD vs GNU; wrong pattern silently no-ops |
| build.sh port sync | SYNC | Backward compat | Med | Must not break image/IMAGE_TAG in-place update |
| port_sync.bats tests | ASYNC | Automation | Low | Deterministic fixtures, no cluster/docker dependency |

## Complexity Tracking

> **Not filled**: no constitution violations exist to justify.

## Verification

- `bats cicd-tests/port_sync.bats` — all 5 tests pass.
- Full `bats cicd-tests/` — no new failures vs base (21 pre-existing environmental failures unchanged; 2 feature tests fail on base, pass with fix).
- `shellcheck build.sh init/init.sh` — only pre-existing SC2034 (`BUILD_STATUS`) warning.
