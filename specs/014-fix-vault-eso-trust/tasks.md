---

description: "Task list for restoring Vault-to-Secret sync trust and executing the 5-part fleet/secret reorganization + cleanup (014)"

---

# Tasks: Vault↔ESO Secret Trust Restoration, Fleet Secret Reorganization & Cleanup

**Input**: Design documents from `specs/014-fix-vault-eso-trust/`

**Prerequisites**: plan.md (required), spec.md (required for user stories), research.md, data-model.md, contracts/, quickstart.md

**Tests**: No new test suites are written. Acceptance is operational (quickstart Steps 0–8) and reuses the existing 013 bats suites (`secrets-vault-standard/tests/align-fleet.bats`, `detectors.bats`, `audit-fleet.bats`, inventory bats) as a regression net (run in Polish, T025).

**Organization**: Tasks are grouped by user story; every live/state-changing task is operator-executed with go/no-go (SYNC) while documentation/verification-deliverable and manifest-file-edit tasks are agent-delegable (ASYNC) per the Constitution Human-Oversight directive.

## Format: `[ID] [P?] [SYNC/ASYNC] [Story] Description with file path`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[SYNC]**: Operator-governed — destructive/live cluster+Vault operations; human review required
- **[ASYNC]**: Agent-delegated — reviewable, non-executing deliverables (research/verify-doc/regression/manifest-file edits)
- **[Story]**: Maps to user story (US1/US2/US3); Setup/Foundational/Polish have no story label

## Path Conventions

- Tooling (reuse, unchanged): `secrets-vault-standard/` at this repo root (`align-fleet.sh`, `align-plan.py`, `tests/align-fleet.bats`)
- Feature docs: `specs/014-fix-vault-eso-trust/` (`contracts/vault-trust.md`, `contracts/migration.md`, `quickstart.md`)
- Consumer manifests (owned by inventory repos, not this repo): `analyst/k8s/external-secret.yaml`, `aws/k8s/external-secret.yaml`, `familytree/k8s/external-secret{,-auth}.yaml`, `familytree/k8s/deploy.yaml`, `pdf-scan/k8s/external-secret.yaml`, `tech-companies/k8s/external-secret-email-{bulk,env}.yaml`
- Operator scratch (never committed): `/tmp/014/`

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Verify reusable tooling and prepare the non-committed baseline convention

- [x] T001 [ASYNC] Verify reused 013 tooling is present and unchanged in `secrets-vault-standard/align-fleet.sh`, `secrets-vault-standard/align-plan.py`, `secrets-vault-standard/tests/align-fleet.bats`
- [x] T002 [P] [ASYNC] Document baseline-snapshot scratch convention (`/tmp/014/`) in `specs/014-fix-vault-eso-trust/quickstart.md` — operator-scratch only, never committed

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Anchor the before-state and preconditions every user story depends on

- [x] T003 [SYNC] Operator captures baseline (quickstart Step 0): store status, all 8 ExternalSecret statuses, `UpdateFailed` events → `/tmp/014/before-state.yaml`
- [x] T004 [ASYNC] Confirm root-cause preconditions pinned in `specs/014-fix-vault-eso-trust/contracts/vault-trust.md` and `specs/014-fix-vault-eso-trust/research.md` (role `external-secrets`, policy `eso-reader`; provisioning command `infra/vault/scripts/vault-ops.sh setup-k8s-auth`)

**Checkpoint**: Baseline + precondition pin ready.

---

## Phase 3: User Story 1 - Restore Vault↔ESO Authentication for the Shared Store (Priority: P1)

**Goal**: Provision the missing `external-secrets` kubernetes-auth role + scoped `eso-reader` policy on the live Vault so `vault-store` authenticates and all six affected ExternalSecrets recover.

**Status**: COMPLETE — role/policy provisioned; `vault-store` reports `Valid | store validated`; six failing ES recovered from old-path data.

**Independent Test**: Store `Ready=True`; ExternalSecrets referencing the shared store reach `SecretSynced=True`.

- [x] T005 [SYNC] [US1] Operator read-only root-cause confirmation (quickstart Step 1): `vault read auth/kubernetes/role/external-secrets` + `vault policy read eso-reader` absent → `/tmp/014/root-cause.txt`
- [x] T006 [SYNC] [US1] Operator go/no-go → provision role `external-secrets` (bound SA `external-secrets`/`external-secrets`, token policy `eso-reader`) + scoped `eso-reader` policy per `specs/014-fix-vault-eso-trust/contracts/vault-trust.md` via `infra/vault/scripts/vault-ops.sh setup-policies setup-k8s-auth` (idempotent)
- [x] T007 [SYNC] [US1] Operator (optional) normalizes store refresh interval: `kubectl -n external-secrets patch clustersecretstore vault-store --type merge -p '{"spec":{"refreshInterval":"3600"}}'`
- [x] T008 [SYNC] [US1] Operator verifies `clustersecretstore/vault-store` `Ready=True` + all 8 ExternalSecrets in `apps-ns` `SecretSynced=True` within one refresh cycle (quickstart Step 4)
- [x] T009 [P] [ASYNC] [US1] Verify durable recreation-path contract (FR-013/SC-006): confirm `setup-k8s-auth` wired into `argo-bootstrap/lib/vault.sh` (or record verified follow-on) in `specs/014-fix-vault-eso-trust/contracts/vault-trust.md` Durability section

**Checkpoint**: User Story 1 complete — all eight syncs restored, durability contract verified.

---

## Phase 4: User Story 2 - Verify Full Recovery With No Data Loss (Priority: P2)

**Goal**: Prove all eight synced secrets are byte-for-byte identical to old-path values, least-privilege holds, and provisioning is idempotent/stable across two refresh cycles.

**Status**: COMPLETE for available source data (pre-reorg); re-verified for the reorganized set in US3 (T022).

**Independent Test**: Diff before/after snapshots (byte-identical), writes + out-of-scope reads denied, zero `UpdateFailed` ≥ 15 min.

- [x] T010 [SYNC] [US2] Operator content-equality diff `/tmp/014/before.yaml` vs `/tmp/014/after.yaml` for all 8 synced secrets → byte-identical (SC-003)
- [x] T011 [P] [SYNC] [US2] Operator least-privilege asserts (quickstart Step 5): `vault kv put -mount=secret aws/env junk=x` denied (writes); out-of-scope reads denied under `eso-reader`
- [x] T012 [SYNC] [US2] Operator idempotency/stability checks (quickstart Step 6): re-run `setup-k8s-auth` → no duplicates; zero `UpdateFailed`/403 across 2 refresh cycles (>15 min) (SC-005)

**Checkpoint**: User Stories 1 AND 2 verified — recovery byte-identical, least-privilege, idempotent, stable.

---

## Phase 5: User Story 3 - Execute the 5-Part Fleet Secret Reorganization + Cleanup (Priority: P3)

**Goal**: Adopt the `/engine/service/key` standard via a 5-part reorganization and complete the operator-approved cleanup. Partially complete; familytree rework, bootstrap-admin seed, final apply/verify, and cleanup remain.

**Independent Test**: All 8 ExternalSecrets sync from their canonical paths (`llm/opencode`, `familytree/env`, `familytree/admins`, `familytree/editors`, `aws/s3`, shared `email/env`) with byte-identical values; cleanup objects absent; then commit per the ArgoCD applicative inventory.

### Completed groundwork (operator-approved, live)

- [x] T013 [SYNC] [US3] Provision + seed shared `llm` engine: `vault secrets enable -path=llm kv-v2`; `llm/opencode` ← `OPENCODE_ZEN_API_KEY` (SC-007; values verified, never printed)
- [x] T014 [SYNC] [US3] Deploy dedicated `vault-llm` ClusterSecretStore (path `llm`, role `external-secrets`, CA `vault-tls`/`ca.crt`) → `infra/external-secrets/vault-llm-store.yaml`; verify `Valid | store validated`
- [x] T015 [SYNC] [US3] Rewrite analyst + pdf-scan ExternalSecrets to `vault-llm`/`opencode` with property mapping (analyst key `OPENCODE_ZEN_API_KEY`; pdf-scan secretKey `LLM_API_KEY` for envFrom) in `analyst/k8s/external-secret.yaml`, `pdf-scan/k8s/external-secret.yaml` (SC-007, FR-008)
- [x] T016 [SYNC] [US3] Migrate `aws`→`aws/s3`: recover values to new path, rewrite `s3-credentials` ES to `vault-store`/`aws/s3` with property, DELETE old `aws/env`, narrow `aws-read-env` to `secret/data/aws/s3/*` → `aws/k8s/external-secret.yaml` (SC-009, FR-010)
- [x] T017 [SYNC] [US3] Seed `familytree/env` with operator-approved placeholders (SESSION_SECRET, WAHA_URL, WAHA_API_KEY); create empty `familytree/admins` + `familytree/editors` paths
- [x] T018 [SYNC] [US3] Update policies live: extend `eso-reader` with `llm/data/*`; narrow `aws-read-env` (pre-cleanup; final `eso-reader` narrowing is T023)

### Remaining: familytree rework + seed + apply/verify

- [x] T019 [P] [ASYNC] [US3] Rewrite `familytree/k8s/external-secret.yaml` to flat-path schema: `familytree/env` with properties (SESSION_SECRET, WAHA_URL, WAHA_API_KEY) → target Secret `familytree-env`; DROP `familytree-email` (consume shared `email-env`); and split auth into `familytree-admins` + `familytree-editors` ExternalSecrets extracting `familytree/admins` + `familytree/editors` (remove `external-secret-auth.yaml` single group) — per `specs/014-fix-vault-eso-trust/contracts/migration.md` §3 (FR-009, FR-009a) ✔ DONE (staged, uncommitted)
- [x] T020 [P] [ASYNC] [US3] Update `familytree/k8s/deploy.yaml`: familytree `envFrom` → `email-env`; wire OPTIONAL volume mounts + env refs for `familytree-admins`/`familytree-editors` (non-blocking if empty; no app-side reading beyond existing single-dir `AUTH_SECRET_DIR`) (FR-009, SC-008) ✔ DONE (staged; AUTH_SECRET_DIR→familytree-admins mapping needs operator go/no-go)
- [ ] T021 [SYNC] [US3] **[BLOCKED — operator supply]** Operator seeds bootstrap admin into Vault `familytree/admins` + `familytree/editors` (SAME person in both group = holds EDIT role out of the box); credentials OPERATOR-SUPPLIED (absent from Infisical; no backfill from in-cluster Secrets per NFR-004) so `familytree-admins`/`familytree-editors` reach `SecretSynced=True` (FR-009a) ⏸ BLOCKED — awaiting operator-supplied credentials
- [ ] T022 [SYNC] [US3] Operator `kubectl apply` changed familytree manifests (rework + deploy); verify all 8 ExternalSecrets `SecretSynced=True`, `vault-store` + `vault-llm` `Ready=True`, stable across 2 cycles (>15 min) with zero `UpdateFailed` (quickstart Steps 4–5; SC-001/002, FR-005/012)
- [ ] T023 [SYNC] [US3] Content-equality + least-privilege re-verify for the reorganized set: `s3-credentials` byte-identical to old `aws/env` values; `llm/opencode` serves both keys; out-of-scope reads/writes denied (SC-003/009, FR-003)

### Remaining: cleanup (FR-014 / SC-010)

- [ ] T024 [SYNC] [US3] Execute full cleanup: DELETE dormant `secret/analyst/env` + `secret/pdf-scan/env`; narrow `eso-reader` to `familytree/*, email/*, llm/data/*` (remove `secret/data/analyst/*` + `secret/data/aws/*` over-grant); retire analyst `SecretStore vault-kubernetes-analyst` + kubernetes-auth role `es-vault-analyst` + policy `analyst-read-env` (FR-014, SC-010)

### Remaining: commit (FR-011)

- [ ] T025 [SYNC] [US3] Commit rewritten external-secret + deploy manifests for every ArgoCD applicative inventory repo owning a migrated ExternalSecret: `analyst`, `aws`, `pdf-scan`, `familytree` — per `contracts/migration.md` §4 (migrate/reorg-before-commit; FR-011)

**Checkpoint**: User Story 3 complete — 8/8 synced from canonical paths, cleanup done, inventory commits landed.

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Regression net, traceability audit, and final consistency review

- [x] T026 [P] [ASYNC] Run tooling regression net: `bats secrets-vault-standard/tests/align-fleet.bats` (11), `detectors.bats` (16), `audit-fleet.bats` (18), inventory bats (8); `shellcheck secrets-vault-standard/*.sh secrets-vault-standard/detectors/*.sh` ✔ 45/45 + shellcheck clean
- [x] T027 [P] [ASYNC] Traceability audit: every FR-001..014 / SC-001..010 / edge case maps to a quickstart step or contract section; update `specs/014-fix-vault-eso-trust/quickstart.md` / contracts on any gap ✔ fixed quickstart Step 4 + Step 6
- [x] T028 [P] [ASYNC] Final review: contracts (`specs/014-fix-vault-eso-trust/contracts/`) vs live state; run `bash .specify/scripts/bash/tasks-meta-utils.sh summary specs/014-fix-vault-eso-trust/tasks_meta.json` and reconcile ✔ consistent; summary reconciled

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies
- **Foundational (Phase 2)**: Depends on Setup — BLOCKS all user stories
- **US1 (P1)**: Depends on T003/T004 — done
- **US2 (P2)**: Depends on US1 syncs — done (pre-reorg), re-verify in US3
- **US3 (P3)**: REMAINING work depends on US1+US2 stable; familytree rework (T019/T020) before apply (T022); seed (T021) before final verify; cleanup (T024) + commit (T025) after reorg verified
- **Polish (Phase 6)**: Depends on stories that landed

### User Story Dependencies (remaining work)

- **US3 rework**: T019 ∥ T020 → T022 → T023; T021 (operator-supplied seed, BLOCKED) → T022; T024 → after T022/T023 (cleanup only after reorg verified); T025 → after T022–T024 (commit after verified reorg + cleanup)
- Hard ordering: rework before apply; seed before 8/8 verify; cleanup after reorg verify; commit after verified reorganization (contract §4)

### Parallel Opportunities

- T019 ∥ T020 (different files: `external-secret.yaml` vs `deploy.yaml`)
- T026 ∥ T027 ∥ T028 (Polish)
- No [P] in the live-cluster apply/verify/cleanup/commit sequence — hard ordering constraints

---

## Parallel Example: User Story 3 (as far as live ops allow)

```text
Task: (T019) Rewrite familytree external-secret.yaml (flat env + admins/editors)   [ASYNC, manifest edit]
Task: (T020) Update familytree deploy.yaml (email-env + optional mounts)           [ASYNC, manifest edit — parallel]
```

```text
Task: (T026) Regression net (bats + shellcheck)    [ASYNC]
Task: (T027) Traceability audit (FR/SC/edge cases) [ASYNC — parallel]
Task: (T028) Final contracts-vs-live review        [ASYNC — parallel]
```

---

## Implementation Strategy

### MVP First (User Story 1 already delivered)

1. US1 is complete — 8/8 sync restored from old paths (the live outage is already fixed).
2. US2 verified recovery byte-identical + least-privilege + idempotent (pre-reorg).
3. US3 (remaining): rework (MVP of the reorg = analyst/pdf-scan/aws already live) → familytree rework + deploy edits (ASYNC) → operator supplies bootstrap-admin credentials → seed → apply + final 8/8 verify → cleanup → commit per inventory.

### Incremental Delivery

1. Setup + Foundational → baseline anchored (done)
2. US1 → 8/8 sync restored (done — MVP, fixes live outage)
3. US2 → no-data-loss, least-privilege, idempotency proven (done)
4. US3 → reorg groundwork live (llm/vault-llm/analyst/pdf-scan/aws done); familytree rework + seed + apply/verify + cleanup + commits (remaining)
5. Polish → regression net + traceability + final review

### Operator-Governed Execution Note

Agents stage and verify; the operator applies every Vault-side change (seed, path deletion, `eso-reader` narrowing, role/store/policy retirement, `kubectl apply`, ArgoCD syncs, inventory commits) with explicit go/no-go per the Constitution's human-oversight directive. The familytree admins/editors seed is operator-supplied and BLOCKED until credentials are provided. Live secret values are never read, printed, or committed.

---

## Notes

- [P] tasks = different files or independent surfaces, no dependencies
- [SYNC]/[ASYNC] markers enforced in `tasks_meta.json` via `tasks-meta-utils.sh`
- [Story] label maps each task to a user story for traceability
- Commit after each logical group; reorg-before-commit ordering for US3
- Stop at any checkpoint to validate independently
- Avoid: live cluster/Vault execution by agents (SYNC), committing manifest rewrites before reorg verification, backfilling auth from in-cluster Secrets (NFR-004)

---

## Phase 7: Convergence

**Purpose**: Close the remaining gap between the staged/organized state and the spec's
acceptance criteria (SC-001 / SC-008 / SC-010). Familytree manifests are rewritten and
validated but UNCOMMITTED and UNAPPLIED; the #8 bootstrap-admin seed, live apply + 8/8
re-verify, cleanup, and inventory commits are still open. All live-cluster/Vault steps are
operator-governed (Constitution Human-Oversight); the seed is blocked on operator-supplied
credentials (NFR-004).

- [ ] T029 [SYNC] [US3] Apply + ArgoCD-sync the staged familytree rework (`familytree/k8s/external-secret.yaml` 3-resource, `familytree/k8s/deploy.yaml`, remove `external-secret-auth.yaml`); verify deploy mounts `email-env` + optional `familytree-admins`/`familytree-editors` volumes per `contracts/migration.md` §2/§3 (FR-009, SC-008) (**missing**)
- [ ] T030 [SYNC] [US3] Operator seeds bootstrap admin into Vault `familytree/admins` + `familytree/editors` (same person both groups = edit role OOB); operator-supplied creds (absent from Infisical; no backfill per NFR-004) so both reach `SecretSynced=True` (FR-009a, SC-001) (**missing**)
- [ ] T031 [SYNC] [US3] After apply + seed, confirm all 8 ExternalSecrets `SecretSynced=True` and remain synced across ≥2 refresh cycles (>15 min) with zero `UpdateFailed`/permission-denied (FR-005, SC-001) (**missing**)
- [ ] T032 [SYNC] [US3] Execute cleanup per `contracts/migration.md` §4 / `contracts/vault-trust.md` Cleanup: delete `secret/analyst/env` + `secret/pdf-scan/env`; narrow `eso-reader` to `familytree/*, email/*, llm/data/*`; retire analyst `SecretStore vault-kubernetes-analyst` + role `es-vault-analyst` + policy `analyst-read-env` (FR-014, SC-010) (**missing**)
- [ ] T033 [SYNC] [US3] Re-verify byte-equality (`s3-credentials` vs old `aws/env` values) + least-privilege (writes denied, out-of-scope reads denied) for the reorganized set; `llm/opencode` serves both keys (SC-003, SC-009, FR-003) (**missing**)
- [ ] T034 [SYNC] [US3] Commit rewritten external-secret + deploy manifests for every ArgoCD applicative inventory repo owning a migrated ExternalSecret (`analyst`, `aws`, `pdf-scan`, `familytree`) after reorg verification (FR-011) (**partial**)
