# Tasks: Fix ArgoCD Gitignore Conflict

**Input**: Design documents from `/specs/006-fix-argocd-gitignore/`

**Prerequisites**: plan.md (required), spec.md (required for user stories), research.md, data-model.md

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: No setup needed — single file modification

No setup tasks required. This feature modifies one existing file (`init/gitignore`) with no new dependencies, tools, or project structure changes.

---

## Phase 2: User Story 1 - Scaffold a new app that ArgoCD can sync (Priority: P1) MVP

**Goal**: Remove gitignore rules so k8s/argocd manifests are committed to scaffolded apps

**Independent Test**: Run `init.sh --app-name test-app`, verify k8s/argocd files are git-tracked, push to remote, ArgoCD syncs without errors

### Implementation for User Story 1

- [x] T001 [ASYNC] [US1] Remove `k8s/*.yaml` and `argocd/*.yaml` rules from `init/gitignore`

**Checkpoint**: New apps scaffolded with `init.sh` will have k8s/argocd manifests tracked by git

---

## Phase 3: User Story 2 - Existing apps can be fixed by re-running init.sh (Priority: P2)

**Goal**: Verify existing apps recover when re-scaffolded

**Independent Test**: Create app with old gitignore, re-run init.sh, verify k8s/argocd files become tracked

### Implementation for User Story 2

- [x] T002 [SYNC] [US2] Verify end-to-end: scaffold app, confirm k8s/argocd tracked, check initial commit includes manifests in `init/gitignore`

**Checkpoint**: Existing apps can be fixed by re-running init.sh

---

## Phase 4: User Story 3 - Build pipeline continues to work after the fix (Priority: P2)

**Goal**: Confirm build.sh still renders templates correctly with the fixed gitignore

**Independent Test**: Run `build.sh --app-name test-app --image-tag v1.0`, verify k8s/deploy.yaml updated and git-tracked

### Implementation for User Story 3

- [x] T003 [SYNC] [US3] Run build.sh after scaffolding, verify rendered k8s/argocd files are not ignored by git in `init/gitignore`

**Checkpoint**: Build pipeline unaffected by gitignore fix

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — skipped (not needed)
- **User Story 1 (Phase 2)**: Can start immediately — single file edit
- **User Story 2 (Phase 3)**: Depends on T001 completion (gitignore must be fixed first)
- **User Story 3 (Phase 4)**: Depends on T001 completion (gitignore must be fixed first)

### User Story Dependencies

- **User Story 1 (P1)**: No dependencies — the core fix
- **User Story 2 (P2)**: Depends on US1 (gitignore must be fixed to verify recovery)
- **User Story 3 (P2)**: Depends on US1 (gitignore must be fixed to verify build)

### Within Each User Story

- T001 is the only implementation task — all other tasks verify it

### Parallel Opportunities

- T002 and T003 can run in parallel (both verify different aspects of the same fix, different commands)

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete T001: Remove gitignore rules
2. **STOP and VALIDATE**: Run `init.sh --app-name test-app`, verify k8s/argocd tracked
3. The fix is complete — ArgoCD will now find the manifests

### Incremental Delivery

1. T001: Core fix (removes gitignore rules)
2. T002: Verify new apps work (P1 story validated)
3. T003: Verify build pipeline unaffected (P2 stories validated)

### Parallel Team Strategy

Not applicable — single developer task. T002 and T003 can run in parallel if desired.

---

## Notes

- This is a minimal fix: 1 file, 2 lines removed
- No code logic changes — only template file modification
- All tasks except T001 are verification tasks
- T002 and T003 are [SYNC] because they require manual inspection of git status and build output
