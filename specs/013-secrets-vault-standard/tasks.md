# Tasks: Secrets & Vault Standard Conformance

**Input**: Design documents from `specs/013-secrets-vault-standard/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/standard.md, contracts/audit-cli.md, contracts/report.md

**Tests**: Bats tests included per story (deterministic fixtures, no cluster/docker required).

**Organization**: Tasks grouped by user story. US1 + US2 combined (P1 MVP) because US2's standard document is a prerequisite for US1's scoring.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (US1, US2, US3)

---

## Phase 1: Setup

**Purpose**: Directory structure and shared infrastructure

- [X] T001 [P] [ASYNC] Create `secrets-vault-standard/` directory structure (detectors/, fixtures/, tests/) at repo root per plan.md
- [X] T002 [P] [ASYNC] Create `contracts/` directory under feature dir for standard.md, audit-cli.md, report.md

---

## Phase 2: Foundational

**Purpose**: Inventory parsing and repo resolution — MUST complete before ANY user story

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [X] T003 [SYNC] Implement inventory parsing — read `infra/argocd-infra/apps/applicative/*.yaml`, extract FleetApp entities (name, repoURL, appPath, namespace, syncWave) in `secrets-vault-standard/inventory.sh`
- [X] T004 [SYNC] Implement repo resolution — map Argo `repoURL`/`name` to local filesystem path (`{repo-root}/{name}`) with NOT_FOUND handling in `secrets-vault-standard/inventory.sh`
- [X] T005 [P] [ASYNC] Write bats tests for inventory parsing and repo resolution in `cicd-tests/secrets_vault_inventory.bats`

**Checkpoint**: Foundation ready — fleet enumeration and repo resolution working

---

## Phase 3: User Story 1 + 2 — Fleet Audit & Standard Selection (P1) 🎯 MVP

**Goal**: Running the audit against the fleet produces exactly one verdict (CONFORMING / NON-CONFORMING / N/A / UNKNOWN) per repo, scored against a documented, versioned standard.

**Independent Test**: `./secrets-vault-standard/audit-fleet.sh --inventory <fixture-inventory> --repo-root <fixture-root>` produces per-repo verdicts matching fixture expectations.

### Standard Document (US2 prerequisite)

- [X] T006 [SYNC] [US2] Verify `contracts/standard.md` completeness — ≥3 selection criteria, ≥1 rejected alternative, versioned (v1.0.0), 7 rules (VS-001..VS-007) each with detection pattern and fix. If gaps found, update standard document in `specs/013-secrets-vault-standard/contracts/standard.md`

### Detectors (US1 core)

- [X] T007 [SYNC] [US1] Implement `vault-eso.sh` detector — detect SecretStore/ClusterSecretStore with `provider.vault` (VS-001), Kubernetes auth (VS-002), ExternalSecret references (VS-003); handle dual topology (per-app vs ClusterSecretStore consumers); output PASS/FAIL/N/A per rule in `secrets-vault-standard/detectors/vault-eso.sh`
- [X] T008 [SYNC] [US1] Implement `committed-secrets.sh` detector — regex scan for bcrypt hashes (`\$2[aby]\$`), API keys (AKIA, sk-, ghp_), hardcoded credentials, PII in appPath + repo root yaml/toml/json files (VS-006); output PASS/FAIL per rule in `secrets-vault-standard/detectors/committed-secrets.sh`
- [X] T009 [SYNC] [US1] Implement `path-convention.sh` detector — extract ExternalSecret `remoteRef.key` and `dataFrom[].extract` paths, validate `/<env>/<service>/<key>` shape (VS-004); output PASS/FAIL/N/A per rule in `secrets-vault-standard/detectors/path-convention.sh`

### Entrypoint (US1 orchestration)

- [X] T010 [SYNC] [US1] Implement `audit-fleet.sh` entrypoint — parse inventory, resolve repos, run detectors, aggregate per-rule verdicts into RepoVerdict (CONFORMING/NON-CONFORMING/N/A/UNKNOWN), assemble FleetReport with deterministic sort order (alphabetical repos, rules by ID) in `secrets-vault-standard/audit-fleet.sh`
- [X] T011 [SYNC] [US1] Implement report formatter — markdown output per contracts/report.md schema (per-repo tables with Rule/Verdict/Evidence columns, fleet summary table, exit code 0/1) in `secrets-vault-standard/report.sh`

### Fixtures (deterministic test data)

- [X] T012 [P] [ASYNC] [US1] Create `conformant-vault-eso/` fixture — repo with per-app SecretStore + ExternalSecret + secretKeyRef, all rules PASS in `secrets-vault-standard/fixtures/conformant-vault-eso/`
- [X] T013 [P] [ASYNC] [US1] Create `conformant-cluster-store/` fixture — repo consuming ClusterSecretStore (no store declaration), VS-001 N/A, VS-003 PASS in `secrets-vault-standard/fixtures/conformant-cluster-store/`
- [X] T014 [P] [ASYNC] [US1] Create `non-conformant-no-vault/` fixture — repo with Deployment/Ingress but no Vault/ESO indicators, VS-001/VS-002/VS-003 FAIL in `secrets-vault-standard/fixtures/non-conformant-no-vault/`
- [X] T015 [P] [ASYNC] [US1] Create `non-conformant-hardcoded/` fixture — repo with committed bcrypt hash + hardcoded API key, VS-006 FAIL in `secrets-vault-standard/fixtures/non-conformant-hardcoded/`
- [X] T016 [P] [ASYNC] [US1] Create `na-no-secrets/` fixture — repo with zero secrets infrastructure (Deployment + Ingress only), verdict N/A in `secrets-vault-standard/fixtures/na-no-secrets/`
- [X] T017 [P] [ASYNC] [US1] Create `unknown-manual-review/` fixture — repo with secrets managed outside git-tracked manifests, verdict UNKNOWN in `secrets-vault-standard/fixtures/unknown-manual-review/`

### Tests

- [X] T018 [P] [ASYNC] [US1] Write bats unit tests for detectors (vault-eso, committed-secrets, path-convention) against fixtures in `secrets-vault-standard/tests/detectors.bats`
- [X] T019 [P] [ASYNC] [US1] Write bats integration tests for `audit-fleet.sh` end-to-end (inventory → verdicts → report) against fixture inventory in `secrets-vault-standard/tests/audit-fleet.bats`

**Checkpoint**: Fleet audit produces correct verdicts for all 6 fixture repos; standard document complete

---

## Phase 4: User Story 3 — Actionable Remediation (P2)

**Goal**: Every NON-CONFORMING row carries an explicit `fix:` remediation naming the violating artifact and a deterministic fix.

**Independent Test**: Every fixture repo with a FAIL rule has a `fix:` line in the report output; no verdict-only failures exist.

### Fix Lines

- [X] T020 [SYNC] [US3] Add `fix:` remediation lines to `vault-eso.sh` FAIL output — each FAIL emits `fix: <specific action referencing the file/setting to change>` in `secrets-vault-standard/detectors/vault-eso.sh`
- [X] T021 [SYNC] [US3] Add `fix:` remediation lines to `committed-secrets.sh` FAIL output — `fix: Remove committed <type> from <file>; add to .gitignore; manage via Vault` in `secrets-vault-standard/detectors/committed-secrets.sh`
- [X] T022 [SYNC] [US3] Add `fix:` remediation lines to `path-convention.sh` FAIL output — `fix: Reorganize Vault KV paths to /<env>/<service>/<key>` in `secrets-vault-standard/detectors/path-convention.sh`
- [X] T023 [SYNC] [US3] Wire fix lines into report formatter — aggregate per-repo fix lines, append Fix column to markdown report per contracts/report.md in `secrets-vault-standard/report.sh`

### Tests & Documentation

- [X] T024 [P] [ASYNC] [US3] Write bats tests asserting fix: line presence on all NON-CONFORMING fixtures (no verdict-only failures) in `secrets-vault-standard/tests/audit-fleet.bats`
- [X] T025 [P] [ASYNC] [US3] Create sample fleet report demonstrating fix: lines in `examples/secrets-vault-standard-fleet-report.md`

**Checkpoint**: All NON-CONFORMING rows carry actionable fix: lines; report matches contracts/report.md schema

---

## Phase 5: Polish & Cross-Cutting

**Purpose**: Validation, hardening, and documentation

- [X] T026 [P] [ASYNC] Run ShellCheck on all `secrets-vault-standard/*.sh` and `secrets-vault-standard/detectors/*.sh` — fix any warnings
- [X] T027 [P] [ASYNC] Run quickstart.md validation scenarios 1-5 against fixture repos — confirm expected exit codes and output
- [X] T028 [P] [ASYNC] Verify determinism — run `audit-fleet.sh` twice against same fixtures, diff output, confirm identical results (FR-007, SC-005)
- [X] T029 [P] [ASYNC] Run `cicd-tests/` — confirm no pre-existing test failures introduced

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — can start immediately
- **Foundational (Phase 2)**: Depends on Setup — BLOCKS all user stories
- **US1+US2 (Phase 3)**: Depends on Foundational — MVP
- **US3 (Phase 4)**: Depends on US1+US2 (detectors must exist to add fix lines)
- **Polish (Phase 5)**: Depends on US3 completion

### User Story Dependencies

- **US1+US2 (P1)**: Can start after Foundational (Phase 2) — no dependencies on other stories
- **US3 (P2)**: Depends on US1+US2 (fix lines are added to existing detectors)
- **US4 (P3)**: OUT OF SCOPE — gated RFC per Q3: C (PDL Ownership)

### Within Each User Story

- Standard document verification (US2) before detector implementation (US1 scoring depends on it)
- Detectors before entrypoint (orchestration depends on detectors)
- Entrypoint before report formatter (report aggregates detector output)
- Fixtures before tests (tests assert against fixture data)

### Parallel Opportunities

- T001 + T002 (Setup) — parallel
- T012–T017 (all fixtures) — parallel
- T018 + T019 (detector tests + integration tests) — parallel
- T026–T029 (all Polish tasks) — parallel

---

## Parallel Example: US1 Fixtures

```bash
# Launch all fixture creation tasks together:
Task: "Create conformant-vault-eso fixture in secrets-vault-standard/fixtures/conformant-vault-eso/"
Task: "Create conformant-cluster-store fixture in secrets-vault-standard/fixtures/conformant-cluster-store/"
Task: "Create non-conformant-no-vault fixture in secrets-vault-standard/fixtures/non-conformant-no-vault/"
Task: "Create non-conformant-hardcoded fixture in secrets-vault-standard/fixtures/non-conformant-hardcoded/"
Task: "Create na-no-secrets fixture in secrets-vault-standard/fixtures/na-no-secrets/"
Task: "Create unknown-manual-review fixture in secrets-vault-standard/fixtures/unknown-manual-review/"
```

---

## Implementation Strategy

### MVP First (US1 + US2 Only)

1. Complete Phase 1: Setup
2. Complete Phase 2: Foundational (CRITICAL)
3. Complete Phase 3: US1+US2 (fleet audit + standard document)
4. **STOP and VALIDATE**: Run audit against fixtures, confirm verdicts
5. Ship MVP — fleet audit with verdicts (no fix: lines yet)

### Incremental Delivery

1. Setup + Foundational → Foundation ready
2. US1+US2 → Fleet audit produces verdicts (MVP!)
3. US3 → Add fix: lines → Actionable remediation complete
4. Polish → Hardened, validated, documented
5. US4 → Gated RFC follow-on (after PDL Ownership resolves)

---

## Notes

- [P] tasks = different files, no dependencies
- [Story] label maps task to user story for traceability
- US4 (Continuous Enforcement) is explicitly OUT OF SCOPE per Q3: C — gated RFC behind PDL Ownership
- The standard document (contracts/standard.md) was authored during plan phase; US2 task (T006) verifies completeness
- Fixture repos simulate real fleet topology (per-app SecretStore, ClusterSecretStore, no-vault, committed-secrets, N/A, UNKNOWN)
- Determinism (FR-007) is verified in Polish phase (T028) by diffing two consecutive runs

---

## Phase 6: Convergence

**Purpose**: Close gaps found during /spec.converge — implement the missing static-token and consumption-pattern rules and the mixed-pattern edge case. Run after /spec.implement has completed Phase 5.

- [X] T030 [SYNC] [US1] Implement `static-tokens.sh` detector for VS-007 (Primary blocking) — scan git-tracked manifests/scripts under appPath (+ repo root when `--scan-root`) for raw Vault tokens (`s.` 24+ char base62), `vault login`, `vault.token`, and `token:`/`tokenSecretRef` fields in SecretStore `provider.vault`; emit `VS-007 PASS/FAIL` with `fix:` remediation; wire into `audit-fleet.sh` (VS-007 gates the verdict as a Primary rule) and render the VS-007 row in `report.sh` per `contracts/report.md`; add a fixture repo and bats assertions for it per FR-006/FR-008 (missing, HIGH)
- [X] T031 [SYNC] [US1] Fix mixed-pattern classification (FR-004) — in `detectors/vault-eso.sh`, when a repo has Vault-backed ExternalSecret(s) AND ALSO a manual `kind: Secret` (or other static mechanism), emit a FAIL/mixed-pattern finding so `audit-fleet.sh` classifies the repo NON-CONFORMING with both patterns named instead of silently CONFORMING; add a bats test asserting the mixed-pattern repo flips to NON-CONFORMING per the spec edge case (partial, HIGH)
- [X] T032 [P] [ASYNC] [US1] Implement `VS-005` consumption-pattern detector (secondary advisory) — detect Deployment/CronJob `env.valueFrom.secretKeyRef`/`envFrom[].secretRef` referencing ExternalSecret-created Secrets; emit `VS-005 PASS/FAIL/N/A` (advisory — never gates the verdict), render the VS-005 row in `report.sh` per `contracts/report.md`; add fixture + bats assertion per data-model.md VS-005 (missing, MEDIUM)

## Phase 7: Convergence

**Purpose**: Close gaps found during /spec.converge — fix the default-invocation crash, the default inventory path drift, the unreachable-repo reporting hole, and the `--scan-root` performance issue. Run after /spec.implement has completed Phase 6.

- [X] T033 [SYNC] [US1] Fix default-invocation crash in `audit-fleet.sh` — the `"${INVENTORY_ARG[@]}"` expansion on an empty array at `audit-fleet.sh:100` is an unbound variable under `set -u` on bash 3.2 when `--inventory` is omitted, so the documented default invocation (`./audit-fleet.sh`) crashes with exit 2 "inventory yielded no apps". Build the inventory argument list conditionally (or always supply a resolvable default) so the no-`--inventory` path works; add a bats assertion that the default invocation resolves the real inventory without crashing (missing, HIGH)
- [X] T034 [SYNC] [US1] Reconcile unreachable-repo reporting against the spec edge case — spec.md:99 says a repo with no local checkout / unreachable "is reported UNKNOWN with the reason — never silently dropped from the fleet count", and SC-001 requires "none left unassessed"; the current `NOT_FOUND` path (audit-fleet.sh:123-129, report.sh ignores `notFound`) skips the repo entirely (no report row, excluded from summary total). Make `audit-fleet.sh`/`report.sh` surface unresolved repos as an `UNKNOWN` row with the reason (or at minimum render a `notFound` count in the summary) so no inventory URL is left unassessed (contradicts, MEDIUM)
- [X] T035 [ASYNC] [US1] Fix default inventory-path drift and plan manual-verification command — `infra/argocd-infra/apps/applicative` (audit-fleet.sh:22, inventory.sh:38, spec/plan/quickstart) does not exist in this gitops-template repo; the real applicative inventory lives at the sibling `/Users/natan/projects/repos/infra/argocd-infra/apps/applicative`. Point `DEFAULT_INVENTORY` at a resolvable location (or document the sibling path) and correct `plan.md:150`'s manual-verification command which also omits the required `--repo-root` (partial, MEDIUM)
- [X] T036 [SYNC] [US1] Profile and fix `--scan-root` performance on the real fleet — the plan.md:151 survey expectation ("2 with committed secrets flagged") is only reachable via `--scan-root` (repo-root files such as `*.env` are skipped by the appPath-default), and `committed-secrets.sh --scan-root` on the natural real invocation (`--repo-root /Users/natan/projects/repos`) timed out (>120s, terminated) during assessment. Investigate the slow path (likely `find`/symlink traversal in the shared repo-root parent), bound it, and confirm committed-secret patterns on repo-root files are captured without pathological runtime (partial, LOW)

## Phase 8: Convergence

**Purpose**: Close the gap found during the follow-up /spec.converge run — the added operation guide is an unrequested documentation addition that must be reviewed and justified against the feature intent.

- [X] T037 [SYNC] Review and justify or remove the unrequested `secrets-vault-standard/README.md` operation guide — it was added post-convergence by user request and is not called for by spec.md/plan.md/tasks.md. Confirm it is consistent with the audit CLI contract (`--help`, exit codes 0/1/2/3, rule table VS-001..VS-007, report-reading guidance) and does not drift from `contracts/audit-cli.md` / `contracts/report.md`; if consistent, accept and keep (documenting it as an approved operational doc), otherwise amend or remove so the feature scope stays aligned (unrequested, LOW)

## Phase 9: Convergence

**Purpose**: Add the user-requested VS-004 path-convention alignment tool — an unrequested-by-spec addition that must be registered and justified like the README guide (T037), so the feature scope stays explicit and auditable.

- [X] T038 [SYNC] Build `align-fleet.sh` + `align-plan.py` to align all fleet repos' ExternalSecret `remoteRef.key`/`dataFrom[].extract.key` to the VS-004 `/<env>/<service>/<key>` convention — wire `align-plan.py` (line-number-precise TSV planner: FILE/TAB/LINE/TAB/KIND/TAB/OLD/TAB/PROP/TAB/TARGET/TAB/NEW/TAB/STATUS with ALIGN/CONFORM/SKIP), `align-fleet.sh` (inventory + `--repo-root` interface mirroring `audit-fleet.sh`, dry-run plan + `--apply-manifests` in-place rewrite with one-time `.bak` backups via `.backedup` tracking, `--apply-vault` KV data-migration via `vault kv get|put`/`kv mv`, confirmation gate `--yes`, bash 3.2-safe `${ARR[@]+...}` idiom); report VS-003 unresolved stores and VS-006 committed secrets as blockers never auto-fixed; add `tests/align-fleet.bats` (offline tests) and README usage (unrequested, MEDIUM)
- [X] T039 [SYNC] Fix `--apply-vault` dead-end when manifests are already rewritten — the migration plan is computed from pre-rewrite keys, so after `--apply-manifests` the plan is empty and `--apply-vault` silently reports "nothing to align" even though Vault data still lives at the old paths. Add git `HEAD` recovery of old keys (same line — in-place rewrite preserves line numbers; `git ls-files --full-name` for symlink-safe relpath), a `vault.tsv` effective-rows layer shared by preview + apply loops, and dry-run exit `0` only once the rewrite is committed (no recovery rows pending); blockers revealed the incident: fleet dry-run reported ALIGN:0/CONFORM:21 with 21 unmigrated paths (`analyst/env/*`, `aws/env/*`, `familytree/{env,auth}/*`, `email/{env,bulk}/*`, `pdf-scan/env/*`), exit now 1 while recovery pending (missing, HIGH)
