# Tasks: Repo Standards Alignment

**Input**: Design documents from `changes/001-repo-standards-alignment/` (plan.md, spec.md, research.md, data-model.md, contracts/)

**Prerequisites**: plan.md (required), spec.md (required for user stories and priorities)

**Tests**: Tests are explicitly requested by the feature spec (FR5: every check bats-covered; FR4: stamping test) and plan.md Verification.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [SYNC/ASYNC] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[SYNC]**: Requires human review (complex/security-critical logic, correctness-critical portability)
- **[ASYNC]**: Delegable to async agents (deterministic fixtures, tests, docs)
- **[Story]**: User story this task belongs to (US1–US5); split per plan.md triage audit trail

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Project initialization and basic structure

- [x] T001 [SYNC] Create `standards-audit/` directory skeleton (`checks/`, `fixtures/`, `tests/`) and placeholder `standards-audit/allowlist.example`
- [x] T002 [SYNC] Add canonical template-version constant file in `init/template-version` (content `1.0.0` per contracts/template-version.md)

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Runner core that every check and every user story depends on

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [x] T003 [SYNC] Implement runner CLI + IO/exit-code contract in `standards-audit/runner.sh` (`--repo-root`, `--repo-profile`, `--check`, `--allowlist`, `--help`; exit 0/1/2 per contracts/cli.md)
- [x] T004 [SYNC] Implement aggregate output rendering in `standards-audit/runner.sh` (one-line `[PASS|FAIL|N/A] <id>\t<detail>\tfix: <remediation>` + final `AUDIT RESULT: PASS/FAIL (n pass, n fail, n n/a)` line; depends on T003)

**Checkpoint**: Runner core ready — `runner.sh --help` exits 0; checks can now be added in parallel

---

## Phase 3: User Story 1 - Local Deterministic Audit (Priority: P1) 🎯 MVP

**Goal**: US1 — a platform engineer runs the same deterministic audit locally that CI runs, with PASS/FAIL/N/A lines and remediation, before pushing.

**Independent Test**: `bash standards-audit/runner.sh --repo-root standards-audit/fixtures/app-only --repo-profile app` emits only `N/A` / `PASS` lines and `AUDIT RESULT: PASS`; the conformant fixture PASSes, the non-conformant fixture FAILs with `fix:` on each failing line.

- [x] T005 [P] [SYNC] [US1] Create conformant fixture app in `standards-audit/fixtures/conformant-app-k8s-noenv/` (Dockerfile + internally consistent `k8s/{deploy,svc,ingress}.yaml`, `.env` absent → cross-manifest consistency-fallback PASS)
- [x] T006 [P] [SYNC] [US1] Create non-conformant fixture app in `standards-audit/fixtures/non-conformant-app-k8s/` (missing required file + deliberately planted git-tracked credential + planted `.env` whose port conflicts with `k8s/deploy.yaml` → authoritative FAIL with `fix:`)
- [x] T007 [P] [SYNC] [US1] Create `app`-profile fixture in `standards-audit/fixtures/app-only/` (no `k8s/`, no Dockerfile per N/A semantics)
- [x] T008 [SYNC] [US1] Implement profile-adaptive structure check in `standards-audit/checks/structure.sh` (required-file + YAML-parse per `app-k8s`|`app`|`library`; missing inputs for the profile emit `N/A`, never FAIL)
- [x] T009 [SYNC] [US1] Implement offline git-tracked secret scan in `standards-audit/checks/secrets.sh` (pinned ruleset, BSD/GNU portable grep; `git ls-files` surface only)
- [x] T010 [SYNC] [US1] Implement manifest-policy check in `standards-audit/checks/manifest-policy.sh` (.env best-effort authoritative port/PVC/tag/cronjob; cross-manifest internal-consistency fallback when `.env` absent)
- [x] T011 [SYNC] [US1] Add bats coverage in `standards-audit/tests/checks.bats` (conformant PASS, non-conformant FAIL, `app`-profile N/A; asserts `fix:` presence)
- [x] T027 [P] [SYNC] [US1] Create `.env`-present conformant fixture in `standards-audit/fixtures/conformant-app-k8s-env/` (committed `.env` declaring port/PVC/image-tag/cronjob; `k8s/*.yaml` agree → `.env`-authoritative PASS, clarify Q4)
- [x] T029 [P] [SYNC] [US1] Create minimal `library`-profile fixture in `standards-audit/fixtures/library/` (no Dockerfile/k8s/`.env`; structure run emits N/A/PASS, never FAIL)
- [x] T030 [SYNC] [US1] Extend `standards-audit/tests/checks.bats` for `.env`-present agreement (PASS), `.env` mismatch vs manifests (FAIL + `fix:`), no-`.env` fallback (PASS), and `library`-profile run (N/A/PASS, never FAIL; depends on T027/T029)

**Checkpoint**: US1 complete — local audit is deterministic and offline; `bats standards-audit/tests/` green

---

## Phase 4: User Story 2 - Opt-in CI Caller (Priority: P1)

**Goal**: US2 — a repo owner imports the audit via a caller workflow declaring their profile and gets a merge-blocking PR check, no re-scaffold.

**Independent Test**: `standards-audit.yml` triggers on `workflow_call` with required `repo-profile` input; `examples/standards-audit-caller.yml` validates as YAML and references the tag/SHA-pinned workflow path.

- [x] T012 [SYNC] [US2] Implement reusable workflow in `.github/workflows/standards-audit.yml` (`workflow_call`, inputs `repo-profile`/`repo-root`, `permissions: contents: read`, SHA-pinned actions only)
- [x] T013 [P] [SYNC] [US2] Add documented opt-in caller example in `examples/standards-audit-caller.yml` (imports audit, passes `repo-profile`)
- [x] T014 [SYNC] [US2] Add workflow-contract bats in `standards-audit/tests/workflow.bats` (YAML parses; no unpinned action refs; `repo-profile` required)

**Checkpoint**: US2 complete — caller example + workflow contract verified

---

## Phase 5: User Story 3 - Actionable Remediation (Priority: P1)

**Goal**: US3 — every failing check names the file and the exact fix, so a failure is actionable with zero extra tooling.

**Independent Test**: non-conformant fixture run shows every FAIL line ending in `fix: <remediation>` identifying the file; seeded secret remediated via `--allowlist` clears the check without editing the ruleset.

- [x] T015 [SYNC] [US3] Embed `fix:` remediation for every branch of `standards-audit/checks/structure.sh`, `secrets.sh`, `manifest-policy.sh` (depends on T008–T010)
- [x] T016 [SYNC] [US3] Add documented exemption/allowlist support in `standards-audit/checks/secrets.sh` + fill `standards-audit/allowlist.example` (depends on T009)
- [x] T017 [SYNC] [US3] Extend `standards-audit/tests/checks.bats` to assert `fix:` remediation and allowlist clearing (depends on T011)

**Checkpoint**: US3 complete — Gate Ergonomics (Constitution II-2) satisfied; no FAIL line lacks a remedy

---

## Phase 6: User Story 4 - Template Provenance Stamping (Priority: P1)

**Goal**: US4 — `init.sh` stamps `.template-version` from the canonical constant so any scaffolded app proves which template version built it.

**Independent Test**: scaffolding a fresh fixture app produces a committed `.template-version` file whose content equals `init/template-version`; re-running `init.sh` is idempotent.

- [ ] T018 [SYNC] [US4] Stamp `.template-version` into scaffolded apps in `init/init.sh` (read canonical constant; idempotent; safe to commit; depends on T002)
- [ ] T019 [SYNC] [US4] Ensure `.template-version` is committed, not ignored, in `init/gitignore`
- [ ] T020 [SYNC] [US4] Add stamping bats test in `cicd-tests/init_env.bats` (file created with expected content; re-run idempotent)

**Checkpoint**: US4 complete — `bats cicd-tests/init_env.bats` green

---

## Phase 7: User Story 5 - Additive, Non-Disturbing Rollout (Priority: P1)

**Goal**: US5 — existing build/CI behavior is intact; the gate is additional and does not disturb running repos.

**Independent Test**: full pre-change `cicd-tests/` suite still passes; runner runs with no network/cluster; no new runtime deps in the tree.

- [ ] T021 [ASYNC] [US5] Run full pre-existing suite `bats cicd-tests/` and confirm the additive regression criterion (no new failures beyond known environmental ones)
- [ ] T022 [P] [SYNC] [US5] Verify offline determinism + no-new-dependency in `standards-audit/tests/runner.bats` (no git-network/Docker/cluster calls in check paths)

**Checkpoint**: US5 complete — additive criterion satisfied

---

## Phase 8: Polish & Cross-Cutting Concerns

**Purpose**: Improvements affecting multiple stories

- [ ] T023 [SYNC] Add "Standards Alignment" section in `README.md` (gate, opt-in caller, org-level promotion path, constitution roadmap — including the scheduled conformance-sweep usage)
- [ ] T031 [SYNC] Add scheduled conformance-sweep caller snippet (cron/`schedule` trigger) in `examples/standards-audit-caller.yml` or the README section
- [ ] T024 [SYNC] Run ShellCheck on `standards-audit/runner.sh build.sh init/init.sh` — no new warnings
- [ ] T025 [P] [ASYNC] Run quickstart.md scenarios 1–5 on macOS and Linux
- [ ] T026 [ASYNC] Optional live smoke test of the reusable workflow (quickstart scenario 6) if a GitHub runner is reachable; otherwise document manual invocation as the gate

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — can start immediately
- **Foundational (Phase 2)**: Depends on Setup — BLOCKS all user stories
- **User Stories (Phase 3+)**: All depend on Foundational completion
  - US1 (P1 MVP) → US2 → US3 sequentially (runner/checks land in US1; US3 reuses same files — no parallel within that chain)
  - US4 is independent of US1–US3 after Foundational (parallelizable (if staffed)
  - US5 depends on all prior stories being in place
- **Polish (Phase 8)**: Depends on all desired user stories

### User Story Dependencies

- **US1 (P1)**: Depends on T003–T004 (runner core)
- **US2 (P1)**: Depends on US1 checks being runnable (workflow invokes runner + checks)
- **US3 (P1)**: Depends on US1 checks (T008–T010); edits same files → sequential after US1
- **US4 (P1)**: Depends only on T002 (constant) — can run in parallel with US1–US3
- **US5 (P1)**: Depends on US1–US4 completion

### Within Each User Story

- Fixtures (`[P]` ASYNC) written before check logic
- Check logic before bats assertions (assertions target implemented behavior)
- Core implementation before integration

### Parallel Opportunities

- All Setup tasks marked [P] can run in parallel
- US1 fixture tasks T005–T007, T027, T029 in parallel
- US1 check tasks T008–T010 sequential after fixtures (shared runner/checks, distinct files — parallelizable only if staffed; keep sequential for correctness review)
- US2 T013/T014 `[P]` can run in parallel
- US4 (T018–T020) fully parallel with US1–US3 scope
- T021/T022 `[P]` parallel

---

## Parallel Example: User Story 1

```bash
# Fixtures (parallel, SYNC):
Task: "Create conformant fixture app in standards-audit/fixtures/conformant-app-k8s/" (T005)
Task: "Create non-conformant fixture app in standards-audit/fixtures/non-conformant-app-k8s/" (T006)
Task: "Create app-profile fixture in standards-audit/fixtures/app-only/" (T007)
```

## Parallel Example: User Story 4 + US1 (cross-story)

```bash
Task: "Stamp .template-version into scaffolded apps in init/init.sh" (T018, SYNC US4)
Task: "Implement profile-adaptive structure check in standards-audit/checks/structure.sh" (T008, SYNC US1)
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup (T001–T002)
2. Complete Phase 2: Foundational runner (T003–T004)
3. Complete Phase 3: User Story 1 (T005–T011)
4. **STOP and VALIDATE**: `bash standards-audit/runner.sh --repo-root standards-audit/fixtures/app-only --repo-profile app` → `AUDIT RESULT: PASS`; `bats standards-audit/tests/`
5. Demo ready: local deterministic audit + conformant/non-conformant fixtures

### Incremental Delivery

1. Setup + Foundational → runner CLI contract working (`runner.sh --help`)
2. US1 → deterministic local audit (MVP)
3. US2 → CI gate caller
4. US3 → Gate Ergonomics remediation complete
5. US4 → provenance stamping (parallel track)
6. US5 → additive regression green

### Parallel Team Strategy

- Foundation done (T003–T004) → track A: US1→US2→US3 (runner/checks), track B: US4 (init.sh stamping) in parallel
- US5 verification after both tracks land

---

## Notes

- `[SYNC]`/`[ASYNC]` per `tasks-meta-utils.sh classify` (authoritative modal in `tasks_meta.json`); plan.md triage guided the split (security-critical logic = SYNC)
- Task IDs, modes, and files registered in `tasks_meta.json` for `/spec.implement` quality gates
- Constitution checks: no unpinned refs (T012), Gate Ergonomics (T015), Pending Decision Log gates P2/P3 (excluded from P1 scope by design)
- P2 (shared versioned artifacts / org enforcement) and P3 (copier/tracked re-sync) remain RFC-classified, blocked behind the Pending Decision Log — tracked as non-implementing items
- Commit after each task or logical group; stop at any checkpoint to validate a story independently