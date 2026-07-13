# Tasks: Tag Script Update

**Input**: Design documents from `/specs/009-tag-script-update/`

**Prerequisites**: plan.md (required), spec.md (required for user stories), research.md, data-model.md

**Tests**: Not explicitly requested in feature specification. Manual testing via quickstart.md.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Prepare the development environment and understand existing code

- [x] T001 [ASYNC] Read and understand current tag.sh implementation at /Users/natan/projects/gitops-template/tag.sh
- [x] T002 [ASYNC] Verify shellcheck is available for linting

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core script modifications that MUST be complete before user story can be implemented

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [x] T003 [SYNC] Add script path resolution using BASH_SOURCE in /Users/natan/projects/gitops-template/tag.sh
- [x] T004 [ASYNC] Change script arguments from `<image> <tag>` to just `<tag>` in /Users/natan/projects/gitops-template/tag.sh
- [x] T005 [ASYNC] Add IMAGE_NAME derivation using `basename "$PWD"` in /Users/natan/projects/gitops-template/tag.sh

**Checkpoint**: Foundation ready - script now supports relative path invocation and folder-based image name

---

## Phase 3: User Story 1 - Run tag.sh from app folder to release a new version (Priority: P1) 🎯 MVP

**Goal**: A developer can run `../gitops-template/tag.sh <version>` from any app folder and have all three side-effects complete in the correct order

**Independent Test**: Can be fully tested by invoking the script from an app folder and verifying the three side-effects happen in the specified order

### Implementation for User Story 1

- [x] T006 [US1] Reorder operations in /Users/natan/projects/gitops-template/tag.sh: .env update → Docker push → git tag
- [x] T007 [US1] Add progress messages for each major step in /Users/natan/projects/gitops-template/tag.sh
- [x] T008 [US1] Update .env update logic to skip gracefully when file doesn't exist in /Users/natan/projects/gitops-template/tag.sh
- [x] T009 [US1] Update Docker image existence check to use derived IMAGE_NAME in /Users/natan/projects/gitops-template/tag.sh
- [x] T010 [US1] Update git tag creation to use force-overwrite and hardcoded `origin` remote in /Users/natan/projects/gitops-template/tag.sh

**Checkpoint**: User Story 1 complete - script works from any app folder

---

## Phase 4: Polish & Cross-Cutting Concerns

**Purpose**: Improvements that affect the overall script quality

- [x] T011 [ASYNC] Run shellcheck on /Users/natan/projects/gitops-template/tag.sh and fix any warnings
- [x] T012 [ASYNC] Update usage message in /Users/natan/projects/gitops-template/tag.sh to reflect new `<tag>` argument
- [x] T013 [SYNC] Test script execution from nested app folder per quickstart.md validation

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: Depends on Setup completion - BLOCKS user story
- **User Story 1 (Phase 3)**: Depends on Foundational phase completion
- **Polish (Phase 4)**: Depends on User Story 1 being complete

### User Story Dependencies

- **User Story 1 (P1)**: Can start after Foundational (Phase 2) - No dependencies on other stories

### Within Each User Story

- Core implementation before integration
- Story complete before moving to polish

### Parallel Opportunities

- T001 and T002 can run in parallel (different concerns)
- T004 and T005 can run in parallel (different parts of same file, but sequential execution needed)
- T011 and T012 can run in parallel (different concerns)

---

## Parallel Example: User Story 1

```bash
# Sequential execution required (same file):
Task: "T006 Reorder operations"
Task: "T007 Add progress messages"
Task: "T008 Update .env logic"
Task: "T009 Update Docker check"
Task: "T010 Update git tag"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup
2. Complete Phase 2: Foundational (CRITICAL - blocks story)
3. Complete Phase 3: User Story 1
4. **STOP and VALIDATE**: Test User Story 1 independently
5. Deploy/demo if ready

### Incremental Delivery

1. Complete Setup + Foundational → Foundation ready
2. Add User Story 1 → Test independently → Deploy/Demo (MVP!)

---

## Notes

- [P] tasks = different files, no dependencies
- [Story] label maps task to specific user story for traceability
- Each user story should be independently completable and testable
- Commit after each task or logical group
- Stop at any checkpoint to validate story independently
