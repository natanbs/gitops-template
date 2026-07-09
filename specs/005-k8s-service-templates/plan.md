# Implementation Plan: K8s Service Templates with Persistent Storage

**Branch**: `005-k8s-service-templates` | **Date**: 2026-07-09 | **Spec**: specs/005-k8s-service-templates/spec.md

**Input**: Feature specification from specs/005-k8s-service-templates/spec.md

## Summary

Add persistent storage support to the `init/k8s/` scaffolding templates by reading a `PVC=true` flag from `.env`, auto-populating PVC-related environment variables (`PVC_NAME`, `PVC_MOUNT_PATH`, `PVC_SIZE`, `PVC_ACCESS_MODE`, `PVC_STORAGE_CLASS`), generating a `pvc.tmpl.yaml`, and rendering volume mounts/volumes in the Deployment template. Existing services are unaffected (PVC is opt-in).

## Technical Context

**Language/Version**: Bash (POSIX-compatible, as used in `init.sh`)

**Primary Dependencies**: None beyond standard Unix utilities (grep, sed, envsubst) and kubectl

**Storage**: Kubernetes PersistentVolumeClaim manifests (YAML templates)

**Testing**: Manual verification via `init.sh --app-name test-service` with PVC=true/false; `kubectl apply --dry-run=client` on generated output

**Target Platform**: Kubernetes cluster (k3d default, any standard K8s)

**Project Type**: Build/Scaffolding scripts (bash + YAML templates)

**Performance Goals**: N/A — templates are rendered at init time, not at runtime

**Constraints**:
- Must not change behavior for services without `PVC=true` (backward compatible)
- Must preserve existing PVC env var values on re-scaffold
- Default PVC mount path `/data`, default PVC size `1Gi`, default access mode `ReadWriteOnce`, default storage class `standard`

**Scale/Scope**: Single feature modifying 4 template files + 1 bash script in `init/`

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

**Gate Evaluation**:
- The constitution file at `.specify/memory/constitution.md` contains template placeholders only (`[PROJECT_NAME]`, `[PRINCIPLE_1_NAME]`, etc.) — no actual codified principles, constraints, or governance rules exist.
- **Result: PASS** — No binding constitution rules to violate. No violations to justify.

## Project Structure

### Documentation (this feature)

```
specs/005-k8s-service-templates/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/           # Phase 1 output
└── tasks.md             # Phase 2 output
```

### Source Code (repository root)

```
init/
├── init.sh                    # Modified: add PVC detection, .env population, PVC template rendering
├── k8s/
│   ├── deploy.tmpl.yaml       # Modified: ${VOLUME_MOUNTS}/${VOLUMES} placeholders already exist
│   ├── svc.tmpl.yaml          # Unchanged
│   ├── ingress.tmpl.yaml      # Unchanged
│   └── pvc.tmpl.yaml          # NEW: PVC manifest template
└── argocd/
    └── application.tmpl.yaml  # Unchanged
```

**Structure Decision**: Follow existing project layout — templates under `init/k8s/`, logic in `init/init.sh`. No new directories needed.

## Complexity Tracking

No constitution violations — Complexity Tracking section not required.

## Phase 0: Outline & Research

No NEEDS CLARIFICATION remain from Technical Context — all items are known:
- Language: Bash (existing project standard)
- Dependencies: None new
- Storage: K8s PVC (known Kubernetes concept)
- Testing: Manual + dry-run validation
- Platform: Kubernetes (known from existing templates)
- Project type: Bash scaffolding (existing pattern)

Proceeding to Phase 1.

## Phase 1: Design & Contracts

### Data Model

See `data-model.md` for PVC entity definition, fields, and validation rules.

### Interface Contracts

Contracts are the template variable substitution interfaces between init.sh and the k8s tmpl.yaml files. See `contracts/pvc-variables.md`.

### Agent Context Update

Agent-context extension not detected. Skipping.

## Phase 2: Implementation Tasks

### Task Classification

All tasks classified as [SYNC] (requires developer review and testing) or [ASYNC] (can be delegated).

#### [ASYNC] T-001: Add PVC env vars to init.sh .env generation
- **File**: `init/init.sh`
- **Description**: After line 155 (`.env` base write), add `PVC=false` to the default .env. After the PVC preservation block (lines 157-161), add block that reads `PVC` from existing .env. If `PVC=true`, write all PVC vars to .env.
- **Rationale**: Pattern matches existing init.sh .env handling. Low risk, well-defined.
- **Acceptance**: Running `init.sh --app-name test` produces `.env` with `PVC=false`. Running with existing `.env` containing `PVC=true` preserves and populates PVC vars.

#### [ASYNC] T-002: Create pvc.tmpl.yaml
- **File**: `init/k8s/pvc.tmpl.yaml` (NEW)
- **Description**: Create PVC manifest template using env vars: PVC_NAME, PVC_SIZE, PVC_ACCESS_MODE, PVC_STORAGE_CLASS.
- **Rationale**: Follows existing tmpl.yaml pattern identically. Trivial file creation.
- **Acceptance**: `envsubst` with PVC vars filled produces valid PVC YAML.

#### [ASYNC] T-003: Update deploy.tmpl.yaml with PVC placeholder logic
- **File**: `init/k8s/deploy.tmpl.yaml`
- **Description**: `${VOLUME_MOUNTS}` and `${VOLUMES}` placeholders already exist. Ensure the rendering in init.sh substitutes them with actual volume mounts/volumes when PVC=true, or empty string when PVC=false.
- **Rationale**: Placeholders already in place. Only rendering logic in init.sh needs updating.
- **Acceptance**: Template renders correctly with and without PVC=true.

#### [ASYNC] T-004: Update init.sh PVC preservation to cover all PVC vars
- **File**: `init/init.sh`
- **Description**: Extend existing `_PVC_NAME`/`_PVC_MOUNT_PATH` preservation (lines 114-116, 125-126, 157-161) to also preserve `_PVC_SIZE`, `_PVC_ACCESS_MODE`, `_PVC_STORAGE_CLASS` from existing `.env`.
- **Rationale**: Same pattern as existing code. Low risk.
- **Acceptance**: Custom PVC_SIZE/PVC_ACCESS_MODE/PVC_STORAGE_CLASS in .env survive re-scaffold.

### [SYNC] T-005: PVC toggle true→false warning
- **Description**: When `.env` changes from PVC=true to PVC=false, init.sh must warn about potential data loss and require `--force` to remove PVC resources. Leave PVC manifests intact without `--force`.
- **Rationale**: Data safety concern — deleting PVCs can cause permanent data loss. Requires developer judgment.
- **Acceptance**: Running init.sh without `--force` after PVC=true→false shows warning and leaves manifests. With `--force`, warning suppressed and manifests removed.

### [SYNC] T-006: Manual end-to-end test
- **Description**: Run `init.sh --app-name pvc-test`, verify `.env` has PVC=false by default. Set PVC=true, re-run, verify `.env` has all PVC vars and k8s manifests include PVC. Set PVC=false, re-run, verify warning.
- **Rationale**: Full integration verification of the feature. Requires developer to inspect output.
- **Acceptance**: All scenarios from the spec's acceptance criteria pass.
