# Tasks: init.sh Syncs K8s Port from CONTAINER_PORT

**Input**: Design documents from `/specs/012-init-sync-container-port/`

**Prerequisites**: plan.md (required), spec.md (required for user stories), research.md, data-model.md, contracts/

**Tests**: Tests are included — regression tests for the port-sync feature were explicitly requested and are part of the spec's success criteria (SC-004).

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

**Status note**: Implementation was completed and verified in this session; tasks below are marked done to record the delivered state.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Path Conventions

Single-project shell tooling at repository root:

- `init/init.sh`, `build.sh` (source)
- `cicd-tests/port_sync.bats` (tests)

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Project initialization and basic structure

No setup tasks — the feature reuses the existing Bash tooling layout, bats test harness, and linting configuration. No new infrastructure is required.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core infrastructure that MUST be complete before ANY user story can be implemented

No foundational tasks — no schema, models, or shared libraries are involved. The port-sync feature is a set of self-contained shell edits on existing scripts.

**Checkpoint**: Foundation ready - user story implementation can now begin in parallel

---

## Phase 3: User Story 1 - Re-deploy an Existing App with a New Port (Priority: P1) 🎯 MVP

**Goal**: `../gitops-template/init.sh --deploy` (run from any app repo) updates `k8s/svc.yaml`, `k8s/deploy.yaml`, and `k8s/ingress.yaml` port references to match `CONTAINER_PORT` in `.env`.

**Independent Test**: In an existing app dir with `CONTAINER_PORT=9000`, run `../gitops-template/init.sh --deploy` and verify all three manifests reference port 9000.

### Tests for User Story 1 ⚠️

> **NOTE**: These tests were written and confirmed to FAIL on the base code before implementation.

- [x] T001 [P] [US1] Bats test: `init.sh --build` syncs svc/deploy/ingress ports to `CONTAINER_PORT` in cicd-tests/port_sync.bats
- [x] T002 [P] [US1] Bats test: sync is idempotent and `init.sh` without `--build`/`--deploy` does not modify manifests in cicd-tests/port_sync.bats

### Implementation for User Story 1

- [x] T003 [US1] Add `sync_container_port()` to init/init.sh rewriting svc `port`/`targetPort`, deploy `containerPort` + liveness/readiness probe ports, ingress backend `number` (BSD/GNU sed compatible, in-place, removes `.bak`)
- [x] T004 [US1] Call `sync_container_port()` in init/init.sh gated on `RUN_BUILD=true` and existing app (`_APP_EXISTS=true`) (FR-001, FR-002, FR-003, FR-006, FR-008)

**Checkpoint**: At this point, User Story 1 should be fully functional and testable independently

---

## Phase 4: User Story 2 - Direct build.sh Deploy Also Stays in Sync (Priority: P1)

**Goal**: A direct `build.sh --auto-deploy` run against an existing app applies the same port sync, consistent with `init.sh --deploy`.

**Independent Test**: In an existing app with `CONTAINER_PORT=9000`, run `build.sh --image-tag v1.0 --auto-deploy` and verify the three manifests use port 9000.

### Tests for User Story 2 ⚠️

- [x] T005 [P] [US2] Bats test: `build.sh --auto-deploy` syncs existing manifest ports in cicd-tests/port_sync.bats

### Implementation for User Story 2

- [x] T006 [US2] Extend `step_template()` existing-file branch in build.sh to sync deploy.yaml (containerPort, port, probe ports via awk), svc.yaml (port, targetPort), ingress.yaml (backend number via sed) while preserving the existing image/IMAGE_TAG rewrite (FR-005)

**Checkpoint**: At this point, User Stories 1 AND 2 should both work independently

---

## Phase 5: User Story 3 - Customizations Are Preserved (Priority: P2)

**Goal**: Port sync is a targeted field update; custom edits (replicas, annotations, extra containers) in existing manifests are never clobbered.

**Independent Test**: Add a custom annotation to an existing manifest, run the deploy flow, and verify the annotation survives while the port changes.

### Tests for User Story 3 ⚠️

- [x] T007 [P] [US3] Bats test: custom annotations/replicas survive the port sync in cicd-tests/port_sync.bats

### Implementation for User Story 3

- [x] T008 [US3] Ensure `sync_container_port()` and the build.sh existing-file branch only rewrite the intended port fields, and skip missing manifests without error (FR-004, FR-007)

**Checkpoint**: At this point, User Stories 1, 2 AND 3 should all work independently

---

## Phase 6: User Story 4 - New App Scaffolding Unaffected (Priority: P2)

**Goal**: Scaffolding a brand-new app (no `.env`) still renders the default port (8080) exactly as before.

**Independent Test**: Run `init.sh --app-name fresh-app` and verify the rendered manifests use the default port as today.

### Tests for User Story 4 ⚠️

- [x] T009 [P] [US4] Bats test: new-app scaffolding renders default port 8080 unchanged in cicd-tests/port_sync.bats

### Implementation for User Story 4

- [x] T010 [US4] Confirm the sync path is unreachable for new apps (only existing manifests are touched; template rendering path untouched) in init/init.sh and build.sh

**Checkpoint**: All user stories should now be independently functional

---

## Phase N: Polish & Cross-Cutting Concerns

**Purpose**: Improvements that affect multiple user stories

- [x] T011 Run full `bats cicd-tests/` suite (no new failures vs base; 2 feature tests fail on base, pass with fix) and `shellcheck build.sh init/init.sh` (only pre-existing SC2034 warning); run quickstart.md validation

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: Depends on Setup completion - BLOCKS all user stories
- **User Stories (Phase 3+)**: All depend on Foundational phase completion
  - User stories can then proceed in parallel (if staffed)
  - Or sequentially in priority order (P1 → P2 → P3)
- **Polish (Final Phase)**: Depends on all desired user stories being complete

### User Story Dependencies

- **User Story 1 (P1)**: Can start after Foundational (Phase 2) - No dependencies on other stories
- **User Story 2 (P2)**: Can start after Foundational (Phase 2) - May integrate with US1 but should be independently testable
- **User Story 3 (P2)**: Can start after Foundational (Phase 2) - May integrate with US1/US2 but should be independently testable
- **User Story 4 (P2)**: Can start after Foundational (Phase 2) - No dependencies on other stories

### Within Each User Story

- Tests (if included) MUST be written and FAIL before implementation
- Core implementation before integration
- Story complete before moving to next priority

### Parallel Opportunities

- All tests for a user story marked [P] can run in parallel
- Different user stories can be worked on in parallel by different team members

---

## Parallel Example: User Story 1

```bash
# Launch all tests for User Story 1 together:
Task: "Bats test: init.sh --build syncs ports in cicd-tests/port_sync.bats"
Task: "Bats test: idempotency + no-modify-without-build in cicd-tests/port_sync.bats"

# Implementation depends on both:
Task: "sync_container_port() in init/init.sh"
Task: "Call site in init/init.sh"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup
2. Complete Phase 2: Foundational (CRITICAL - blocks all stories)
3. Complete Phase 3: User Story 1
4. **STOP and VALIDATE**: Test User Story 1 independently
5. Deploy/demo if ready

### Incremental Delivery

1. Complete Setup + Foundational → Foundation ready
2. Add User Story 1 → Test independently → Deploy/Demo (MVP!)
3. Add User Story 2 → Test independently → Deploy/Demo
4. Add User Story 3 → Test independently → Deploy/Demo
5. Add User Story 4 → Test independently → Deploy/Demo
6. Each story adds value without breaking previous stories

---

## Notes

- [P] tasks = different files, no dependencies
- [Story] label maps task to specific user story for traceability
- Each user story should be independently completable and testable
- Verify tests fail before implementing
- Commit after each task or logical group
- Stop at any checkpoint to validate story independently
- Avoid: vague tasks, same file conflicts, cross-story dependencies that break independence
