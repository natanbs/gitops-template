# Tasks: Service Decommission Procedure

**Input**: Design documents from `/specs/002-service-decommission-procedure/`

**Prerequisites**: plan.md (required), spec.md (required for user stories), research.md, data-model.md, quickstart.md

**Tests**: This is a documentation-only feature — no automated tests. Validation is performed by manually walking through the procedure against a sandbox deployment.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [SYNC/ASYNC] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[SYNC]**: Requires human review (safety-critical, structural decisions)
- **[ASYNC]**: Can be delegated (reference material, straightforward writing)
- **[Story]**: Which user story this task belongs to (US1, US2, US3)
- Include exact file paths in descriptions

## Phase 1: Setup (File & Structure)

**Purpose**: Determine where the procedure lives and establish the outline

- [X] T001 [SYNC] Determine file location and create procedure document at docs/decommission.md
- [X] T002 [ASYNC] Create outline structure with sections for pre-checks, GitOps path, Direct Deploy path, PVC handling, registry cleanup, recovery, and audit

---

## Phase 2: Foundational (Shared Across All Stories)

**Purpose**: Pre-checks checklist and audit template used by all decommission paths

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [X] T003 [P] [ASYNC] Write pre-decommission safety checklist section with verification steps for dependencies, traffic, and service name confirmation
- [X] T004 [P] [ASYNC] Write audit trail template section with record-keeping format (service name, timestamp, operator, outcome)

**Checkpoint**: Foundation ready — user story implementation can now begin

---

## Phase 3: User Story 1 - GitOps Service Decommission (Priority: P1)

**Goal**: Document the complete procedure for decommissioning a service deployed via GitOps (ArgoCD)

**Independent Test**: Deploy a test service via the template in GitOps mode, then follow the procedure to remove it. Verify all resources are pruned by ArgoCD within one sync cycle and no orphaned resources remain.

- [X] T005 [SYNC] [US1] Write GitOps decommission procedure: remove manifests from repo → commit → wait for ArgoCD prune → verify cleanup, including phase-specific recovery guidance for each step
- [X] T006 [P] [ASYNC] [US1] Write container image cleanup guidance covering common registry types (Docker Hub, GHCR, ECR, GCR, local k3d registry)
- [X] T007 [P] [ASYNC] [US1] Write source repository archival guidance (archive org, mark read-only, delete)
- [X] T008 [P] [ASYNC] [US1] Write ArgoCD Application edge case: handling the self-prune scenario when Application manifest is in the same repo

**Checkpoint**: At this point, the GitOps decommission path should be fully documented and independently testable

---

## Phase 4: User Story 2 - Direct Deploy Service Decommission (Priority: P2)

**Goal**: Document the complete procedure for decommissioning a service deployed via Direct Deploy (no ArgoCD)

**Independent Test**: Deploy a test service via the template in Direct Deploy mode, then follow the procedure to remove it. Verify all resources are deleted and no orphans remain.

- [X] T009 [SYNC] [US2] Write Direct Deploy decommission procedure: kubectl delete sequence in correct order (Deployment → Service → Ingress → ConfigMap/Secret/PVC) with verification after each step, including phase-specific recovery guidance

**Checkpoint**: At this point, both GitOps and Direct Deploy paths should be fully documented

---

## Phase 5: User Story 3 - Safe Decommission with Data Retention (Priority: P3)

**Goal**: Document PVC handling so operators can safely retain or delete persistent data during decommission

**Independent Test**: Deploy a service with a PVC, decommission it choosing "retain" and verify PVC survives; repeat with "delete" and verify PVC is removed.

- [X] T010 [SYNC] [US3] Write PVC data retention guidance: default to retain, require explicit confirmation to delete, clear warning about irreversibility
- [X] T011 [ASYNC] [US3] Write verification commands to check PVC/PV status after decommission

**Checkpoint**: All user stories should now be independently functional

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Integration, cross-referencing, and validation

- [X] T012 [P] [ASYNC] Add cross-references between GitOps and Direct Deploy sections for shared procedures (pre-checks, registry cleanup, audit)
- [X] T013 [SYNC] Integrate procedure file into repository (update README.md with link to docs/decommission.md)
- [X] T014 [ASYNC] Run through both decommission paths in a sandbox environment end-to-end and log results — VALIDATED: logs at sandbox-validation-results.log
- [ ] T015 [SYNC] Review all safety-critical sections for accuracy and completeness

---

## Phase 7: Convergence

**Purpose**: Remediate gaps found during spec.couverge

- [X] T016 Add repo archive recovery guidance to the Recovery Guide table per FR-009 (`partial`)

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — can start immediately
- **Foundational (Phase 2)**: Depends on Setup — shared content used by all stories
- **User Stories (Phase 3-5)**: All depend on Foundational phase completion
- **Polish (Phase 6)**: Depends on all user story phases being complete

### User Story Dependencies

- **User Story 1 (P1)**: Can start after Foundational — no dependencies on other stories
- **User Story 2 (P2)**: Can start after Foundational — independent from US1
- **User Story 3 (P3)**: Can start after Foundational — independent from US1 and US2

### Within Each User Story

- Core procedure before supporting reference material
- Safety-critical sections written before verification tasks
- Story complete before moving to next priority

### Parallel Opportunities

- T003 and T004 can run in parallel (different sections)
- T006, T007, and T008 can run in parallel with T005 (different topics within US1)
- T012 can run partially in parallel with T013 (different files)
- All user stories can be written in any order (no code dependencies)

---

## Parallel Example: User Story 1

```bash
# Launch GitOps procedure, registry cleanup, repo archive, and ArgoCD edge case in parallel:
Task: "Write GitOps decommission procedure" (T005 — review-blocking, start first)
Task: "Write registry cleanup guidance" (T006 — reference, can proceed in parallel)
Task: "Write repo archive guidance" (T007 — reference, can proceed in parallel)
Task: "Write ArgoCD edge case" (T008 — reference, can proceed in parallel)
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup — determine file location
2. Complete Phase 2: Foundational — pre-checks + audit template
3. Complete Phase 3: User Story 1 — GitOps decommission path
4. **STOP and VALIDATE**: Run through GitOps procedure in sandbox
5. Deploy/demo if ready

### Incremental Delivery

1. Complete Setup + Foundational → Foundation ready
2. Add User Story 1 (GitOps) → Test independently → Deploy/Demo (MVP!)
3. Add User Story 2 (Direct Deploy) → Test independently → Deploy/Demo
4. Add User Story 3 (PVC) → Test independently → Deploy/Demo
5. Each story adds value without breaking previous stories

### Parallel Team Strategy

With multiple writers:

1. Team completes Setup + Foundational together
2. Once Foundational is done:
   - Writer A: User Story 1 (GitOps)
   - Writer B: User Story 2 (Direct Deploy)
   - Writer C: User Story 3 (PVC)
3. Stories complete and integrate independently
