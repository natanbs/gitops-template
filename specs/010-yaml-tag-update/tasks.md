# Tasks: YAML Tag Update

**Input**: Design documents from `/specs/010-yaml-tag-update/`

**Prerequisites**: plan.md (required), spec.md (required for user stories), research.md, data-model.md, quickstart.md

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2)

---

## Phase 1: Foundational (Blocking Prerequisites)

**Purpose**: Create shared function that both user stories depend on

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [x] T001 [ASYNC] Create `update_yaml_image_tags` function in tag.sh that scans `k8s/` subdirectory for YAML files, matches `image:` lines, and replaces tag after last `:` with new version
- [x] T002 [ASYNC] Insert function call after `.env` update (step 2) and before Docker push (step 3) in tag.sh
- [x] T003 [ASYNC] Update step counts from [1/4] to [1/5] for all existing steps in tag.sh

**Checkpoint**: Foundation ready - user story implementation can now begin

---

## Phase 2: User Story 1 - Update deploy.yaml (Priority: P1) 🎯 MVP

**Goal**: The script updates `k8s/deploy.yaml` image tag fields with the new version

**Independent Test**: Run tag.sh and verify deploy.yaml contains the new tag value

### Implementation for User Story 1

- [x] T004 [P] [ASYNC] [US1] Add progress message for deploy.yaml update in tag.sh: `[2/5] Updating image tags in k8s/deploy.yaml...`
- [x] T005 [P] [ASYNC] [US1] Add success message after deploy.yaml update in tag.sh: `Updated image tags in k8s/deploy.yaml`
- [x] T006 [P] [ASYNC] [US1] Add skip message when k8s/ directory doesn't exist in tag.sh: `Skipping YAML updates - no k8s/ directory found`

**Checkpoint**: User Story 1 complete - deploy.yaml updates working

---

## Phase 3: User Story 2 - Update cronjob.yaml (Priority: P2)

**Goal**: The script updates `k8s/cronjob.yaml` image tag fields with the new version

**Independent Test**: Run tag.sh and verify cronjob.yaml contains the new tag value

### Implementation for User Story 2

- [x] T007 [P] [ASYNC] [US2] Add progress message for cronjob.yaml update in tag.sh: `[3/5] Updating image tags in k8s/cronjob.yaml...`
- [x] T008 [P] [ASYNC] [US2] Add success message after cronjob.yaml update in tag.sh: `Updated image tags in k8s/cronjob.yaml`

**Checkpoint**: User Story 2 complete - cronjob.yaml updates working

---

## Phase 4: Polish & Cross-Cutting Concerns

**Purpose**: Improvements that affect multiple user stories

- [x] T009 [P] [ASYNC] Update help text in tag.sh to mention YAML updates
- [x] T010 [P] [ASYNC] Run shellcheck on tag.sh to verify no linting errors
- [x] T011 [ASYNC] Run quickstart.md manual test to verify end-to-end functionality

---

## Dependencies & Execution Order

### Phase Dependencies

- **Foundational (Phase 1)**: No dependencies - can start immediately
- **User Stories (Phase 2-3)**: Depend on Foundational phase completion
- **Polish (Phase 4)**: Depends on all user stories being complete

### User Story Dependencies

- **User Story 1 (P1)**: Can start after Foundational (Phase 1) - No dependencies on other stories
- **User Story 2 (P2)**: Can start after Foundational (Phase 1) - May integrate with US1 but should be independently testable

### Within Each User Story

- Progress messages before implementation
- Success messages after implementation
- Core implementation before polish

### Parallel Opportunities

- All tasks within each user story marked [P] can run in parallel
- User stories can be worked on in parallel (if team capacity allows)

---

## Parallel Example: User Story 1

```bash
# Launch all US1 tasks together:
Task: "Add progress message for deploy.yaml update in tag.sh"
Task: "Add success message after deploy.yaml update in tag.sh"
Task: "Add skip message when k8s/ directory doesn't exist in tag.sh"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Foundational (create function)
2. Complete Phase 2: User Story 1
3. **STOP and VALIDATE**: Test deploy.yaml update independently
4. Deploy/demo if ready

### Incremental Delivery

1. Complete Foundational → Function ready
2. Add User Story 1 → Test independently → Deploy/Demo (MVP!)
3. Add User Story 2 → Test independently → Deploy/Demo
4. Each story adds value without breaking previous stories

---

## Notes

- [P] tasks = different files, no dependencies
- [Story] label maps task to specific user story for traceability
- Each user story should be independently completable and testable
- Commit after each task or logical group
- Stop at any checkpoint to validate story independently
