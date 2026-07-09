# Tasks: K8s Service Templates with Persistent Storage

**Input**: Design documents from `specs/005-k8s-service-templates/`

**Prerequisites**: plan.md (required), spec.md (required for user stories), research.md, data-model.md, contracts/

**Tests**: No explicit test tasks — testing is manual via end-to-end verification (T006).

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [SYNC/ASYNC] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[SYNC]**: Requires human review (complex logic, security-critical)
- **[ASYNC]**: Can be delegated to async agents (well-defined, clear spec)
- **[Story]**: Which user story this task belongs to (US1, US2)
- Include exact file paths in descriptions

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Project initialization — no build tools to install, this is a bash script project. Setup is understanding the existing codebase.

- [x] T001 [ASYNC] Add PVC=false to default .env output and implement PVC=true .env population logic in `init/init.sh`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core PVC template and contract changes that MUST be complete before user stories can be validated.

- [x] T002 [P] [ASYNC] Create PVC manifest template at `init/k8s/pvc.tmpl.yaml` using PVC_NAME, PVC_SIZE, PVC_ACCESS_MODE, PVC_STORAGE_CLASS
- [x] T003 [P] [ASYNC] Update deploy.tmpl.yaml PVC rendering — ensure ${VOLUME_MOUNTS} and ${VOLUMES} are properly substituted (empty string when PVC=false, volume blocks when PVC=true) in `init/k8s/deploy.tmpl.yaml`
- [x] T004 [ASYNC] Extend init.sh PVC preservation to cover all PVC vars (PVC_SIZE, PVC_ACCESS_MODE, PVC_STORAGE_CLASS) alongside existing PVC_NAME/PVC_MOUNT_PATH in `init/init.sh`

**Checkpoint**: Foundation ready — PVC template exists, deploy template has live placeholders, and .env preservation covers all PVC vars.

---

## Phase 3: User Story 1 - Enable PVC via .env flag (Priority: P1) 🎯 MVP

**Goal**: Developer sets PVC=true in .env and scaffolding auto-generates PVC resources with sensible defaults.

**Independent Test**: Create a `.env` with `PVC=true`, run `init.sh --app-name test-pvc`, verify `.env` is populated with all PVC vars and `k8s/pvc.yaml` is generated with correct values.

### Implementation for User Story 1

- [x] T005 [SYNC] [US1] Implement PVC toggle true→false warning and --force flag in `init/init.sh`

**Checkpoint**: US1 complete — new service with PVC=true generates full PVC resources; toggling off warns user.

---

## Phase 4: User Story 2 - Add PVC to existing service (Priority: P2)

**Goal**: Developer adds PVC=true to an existing scaffolded service's .env and re-runs scaffolding to add PVC resources.

**Independent Test**: Take an existing service directory without PVC, add `PVC=true` to `.env`, re-run `init.sh`, verify PVC resources appear in output.

### Implementation for User Story 2

*(All implementation for US2 is covered by T001-T004 from Phase 2 — the foundational changes enable both US1 and US2. No separate coding tasks needed.)*

**Checkpoint**: US2 functional — existing services can opt into PVC without recreating the service.

---

## Phase 5: Polish & Cross-Cutting Concerns

- [x] T006 [SYNC] Manual end-to-end test: run `init.sh --app-name pvc-test`, verify PVC=false default; set PVC=true, re-run, verify all PVC vars and manifests; toggle PVC=false, verify warning; use --force, verify removal

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies
- **Foundational (Phase 2)**: Depends on Setup — T002, T003, T004 are parallel
- **User Stories (Phase 3-4)**: Depend on Phase 2 completion
- **Polish (Phase 5)**: T006 depends on all prior tasks

### User Story Dependencies

- **US1 (P1)**: Depends on Phase 2 completion
- **US2 (P2)**: No additional code beyond Phase 2 — inherits all foundational work

### Within Each User Story

- T001 → T004 (Foundational) before T005 (US1 implementation)
- T006 (E2E test) must run after all implementation tasks

### Parallel Opportunities

- T002 and T003 can run in parallel (pvc.tmpl.yaml and deploy.tmpl.yaml are independent files)

---

## Parallel Example: Foundational Phase

```bash
# Launch parallel:
Task: "Create pvc.tmpl.yaml in init/k8s/pvc.tmpl.yaml"
Task: "Update deploy.tmpl.yaml PVC placeholders in init/k8s/deploy.tmpl.yaml"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Add PVC=false and PVC=true .env logic (T001)
2. Complete Phase 2: PVC template + deploy template updates (T002, T003, T004)
3. Complete Phase 3: Toggle warning + --force flag (T005)
4. **STOP and VALIDATE**: Run T006 end-to-end test with PVC scenarios
5. Deploy/demo if ready

### Incremental Delivery

1. Complete Setup + Foundational → Foundation ready
2. Add US1 (PVC for new services with full toggle behavior) → Test → Deploy
3. US2 is automatically covered by the same foundational code

### Parallel Team Strategy

Single developer — sequential execution in task order.
