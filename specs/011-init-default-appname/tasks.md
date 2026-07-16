# Tasks: init.sh Default App Name from Folder

**Input**: Design documents from `/specs/011-init-default-appname/`

**Prerequisites**: plan.md (required), spec.md (required for user stories), research.md, data-model.md, contracts/

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Phase 1: Foundational (Blocking Prerequisites)

**Purpose**: Core arg-parsing changes that ALL user stories depend on

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [x] T001 [SYNC] Add `_APP_NAME_EXPLICIT=false` flag and modify arg-parsing loop in `init/init.sh` to set `_APP_NAME_EXPLICIT=true` when `--app-name` is provided with a non-empty value. After the loop, if `_APP_NAME_EXPLICIT` is false or `CLI_APP_NAME` is empty, set `APP_NAME=$(basename "$PWD")`. If `_APP_NAME_EXPLICIT` is true, keep existing `APP_NAME="$CLI_APP_NAME"` path. (Ref: spec FR-001, FR-002, research Decision 4)

**Checkpoint**: Foundation ready — `--app-name` is now optional, `APP_NAME` is always populated

---

## Phase 2: User Story 1 - Run init.sh Without --app-name (Priority: P1) 🎯 MVP

**Goal**: User navigates to a named directory and runs init.sh without `--app-name`; script uses folder name as app name

**Independent Test**: Run `init.sh` from within a named directory without `--app-name` and verify scaffold uses the folder name

### Implementation for User Story 1

- [x] T002 [SYNC] [US1] Add K8s naming validation function in `init/init.sh` — function `validate_k8s_name()` that checks name matches `^[a-z0-9]([-a-z0-9]*[a-z0-9])?$` and length ≤ 253. Call it after `APP_NAME` is set (from folder name). On failure, print error message per contracts/cli-interface.md and `exit 1`. (Ref: spec FR-006, research Decision 1, data-model Validation Rules)
- [x] T003 [SYNC] [US1] Add blocklist check in `init/init.sh` — inline array `BLOCKED_NAMES=("gitops-template")`, check `APP_NAME` against it when origin is default (not explicit). On match, print error message per contracts/cli-interface.md and `exit 1`. (Ref: spec FR-007, research Decision 2)

**Checkpoint**: US1 fully functional — default from folder name works, validation and blocklist active

---

## Phase 3: User Story 4 - Target Directory Computed Correctly (Priority: P1)

**Goal**: When using folder-name default, scaffold creates files in current directory (not a subdirectory)

**Independent Test**: Run `init.sh` without `--app-name` from a named directory and verify files appear in `$PWD`

### Implementation for User Story 4

- [x] T004 [SYNC] [US4] Modify TARGET_DIR computation in `init/init.sh` (line ~95) — branch on `_APP_NAME_EXPLICIT`: if false, set `TARGET_DIR="$PWD"`; if true, keep existing `TARGET_DIR="$(dirname "$PWD")/$APP_NAME"`. Also adjust `_APP_EXISTS` check accordingly. (Ref: spec FR-003, FR-004, research Decision 3, data-model Target Directory entity)

**Checkpoint**: US4 fully functional — scaffold targets correct directory in both modes

---

## Phase 4: User Story 2 - Override Default App Name with --app-name (Priority: P1)

**Goal**: Explicit `--app-name` still works exactly as before (full backward compatibility)

**Independent Test**: Run `init.sh --app-name my-api` and verify identical behavior to pre-change

### Implementation for User Story 2

- [x] T005 [ASYNC] [US2] Verify backward compatibility — run `init.sh --app-name test-app` from a temp directory and confirm: TARGET_DIR is sibling directory, `.env` has correct APP_NAME, k8s templates render correctly. No code changes expected — this is a verification task. (Ref: spec SC-002)

**Checkpoint**: US2 confirmed — existing workflows produce identical results

---

## Phase 5: User Story 3 - Help Text Reflects New Default (Priority: P2)

**Goal**: Help text documents that `--app-name` is optional with folder-name default

**Independent Test**: Run `init.sh --help` and verify the output mentions the default behavior

### Implementation for User Story 3

- [x] T006 [SYNC] [US3] Update `show_help()` function in `init/init.sh` — change "Required:" section to "Options:", move `--app-name` to Options with description "(default: current folder name)". Update Usage line to `init.sh [OPTIONS]`. Add example without `--app-name` to Examples section. (Ref: spec FR-005, contracts/cli-interface.md)

**Checkpoint**: US3 fully functional — help text accurately reflects new behavior

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Final validation and cleanup

- [x] T007 [P] [ASYNC] Run ShellCheck on `init/init.sh` and fix any warnings introduced by changes
- [x] T008 [P] [ASYNC] Create smoke test script in `specs/011-init-default-appname/smoke-test.sh` that validates: (1) default from folder, (2) explicit override, (3) invalid name abort, (4) blocklist abort, (5) empty string treated as default. Run and verify all pass. (Ref: quickstart.md)
- [x] T009 [SYNC] Run quickstart.md validation — execute each example from quickstart.md and verify expected outcomes

---

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 1 (Foundational)**: No dependencies — starts immediately
- **Phase 2 (US1)**: Depends on Phase 1
- **Phase 3 (US4)**: Depends on Phase 1 (can run in parallel with Phase 2 if different parts of file)
- **Phase 4 (US2)**: Depends on Phases 1 + 3
- **Phase 5 (US3)**: Depends on Phase 1 (can run in parallel with Phases 2-4 — different function in same file)
- **Phase 6 (Polish)**: Depends on all prior phases

### Within Each User Story

- All tasks in a story are sequential (same file: `init/init.sh`)
- Exception: Phase 6 tasks marked [P] can run in parallel (different output files)

### Parallel Opportunities

- Phase 2 (US1) and Phase 3 (US4) can be merged into a single implementation pass since they modify adjacent lines in the same file
- Phase 5 (US3) modifies a different function (`show_help`) and could theoretically be done in parallel, but same-file conflicts make this impractical
- Phase 6 tasks T007 and T008 are independent and can run in parallel

---

## Implementation Strategy

### MVP First (User Story 1 + US4)

1. Complete Phase 1: Add flag and modify arg-parsing
2. Complete Phase 2: Add validation + blocklist
3. Complete Phase 3: Fix TARGET_DIR
4. **STOP and VALIDATE**: Test `init.sh` from a named directory without `--app-name`
5. Ship if ready

### Full Delivery

1. Phase 1-3: Core functionality (MVP)
2. Phase 4: Verify backward compatibility
3. Phase 5: Update help text
4. Phase 6: Polish and smoke tests

---

## Notes

- All code changes are in a single file: `init/init.sh` (~20 lines changed)
- No new files created (except smoke test script in Phase 6)
- No test framework needed — bash script testing via manual execution + ShellCheck
- Backward compatibility is the highest-risk concern — every change must preserve existing `--app-name` behavior
