# Tasks: Remove Duplicate Service YAML

**Input**: Design documents from `/specs/007-remove-duplicate-service-yaml/`

**Prerequisites**: plan.md (required), spec.md (required for user stories), research.md

**Tests**: No tests requested in spec. Verification is done via kubectl commands.

## Format: `[ID] [P?] [SYNC/ASYNC] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[SYNC]/[ASYNC]**: Execution mode
- **[Story]**: Which user story this task belongs to (e.g., US1)

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Verify environment and prerequisites

- [x] T001 [ASYNC] Verify kubectl is available and cluster is accessible
- [x] T002 [ASYNC] Verify current analyst Service state with `kubectl get service analyst -n apps-ns -o yaml`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Confirm both files are identical and no external references exist

- [x] T003 [ASYNC] Confirm `service.yaml` and `svc.yaml` define identical Service resources by comparing content
- [x] T004 [ASYNC] Search for explicit `service.yaml` filename references across the analyst repo with `grep -r`

---

## Phase 3: User Story 1 - Clean up duplicate k8s Service manifests (Priority: P1) 🎯 MVP

**Goal**: Delete duplicate `service.yaml`, keeping `svc.yaml` as the single source of truth.

**Independent Test**: Apply `svc.yaml` with `kubectl apply --dry-run=client` and verify live Service unchanged.

### Implementation for User Story 1

- [x] T005 [ASYNC] [US1] Delete `k8s/service.yaml` from the analyst repo
- [x] T006 [ASYNC] [US1] Verify `k8s/svc.yaml` applies cleanly with `kubectl apply --dry-run=client -f k8s/svc.yaml`
- [x] T007 [ASYNC] [US1] Verify live analyst Service is unchanged with `kubectl get service analyst -n apps-ns -o yaml`
- [x] T008 [ASYNC] [US1] Confirm no other files in analyst k8s/ reference the deleted `service.yaml`

**Checkpoint**: Duplicate manifest removed, Service operational, single source of truth established.

---

## Phase 4: Polish & Cross-Cutting Concerns

**Purpose**: Final verification and documentation

- [x] T009 [ASYNC] Run `quickstart.md` verification steps end-to-end

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - verify env first
- **Foundational (Phase 2)**: Depends on Setup completion - validates preconditions
- **User Story 1 (Phase 3)**: Depends on Foundational phase completion
- **Polish (Final Phase)**: Depends on User Story 1 completion

### User Story Dependencies

- **User Story 1 (P1)**: The only user story - standalone, no dependencies on other stories

### Parallel Opportunities

- T003 and T004 in Foundational phase can run in parallel
- T006, T007, T008 in User Story 1 can run in parallel after T005

---

## Parallel Example: User Story 1

```bash
# Verification tasks (after deletion):
Task: "Verify svc.yaml with kubectl apply --dry-run"
Task: "Verify live service unchanged"
Task: "Confirm no references to deleted file"
```

---

## Implementation Strategy

### MVP

1. Complete Phase 1: Verify env
2. Complete Phase 2: Validate preconditions
3. Complete Phase 3: Delete file and verify
4. Complete Phase 4: Final verification

The task is already complete — this serves as the audit trail.
