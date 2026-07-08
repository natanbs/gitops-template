# Tasks: Decommission CLI

**Input**: Design documents from `/specs/003-decommission-cli/`

**Prerequisites**: plan.md (required), spec.md (required for user stories), research.md, data-model.md, contracts/command-schema.md

**Tests**: Unit tests are included as optional tasks (Phase 7). No TDD — tests written after implementation.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [SYNC/ASYNC] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[SYNC]**: Requires human review (safety-critical, structural decisions)
- **[ASYNC]**: Can be delegated (well-defined, reference material, straightforward)
- **[Story]**: Which user story this task belongs to (US1, US2, US3, US4)
- Include exact file paths in descriptions

## Phase 1: Setup (Go Module & Entry Point)

**Purpose**: Initialize the Go module and create the CLI entry point with flag parsing

- [X] T001 [ASYNC] Initialize Go module at repository root and create cmd/decommission/main.go with flag parsing (service-name positional arg, --namespace, --force, --dry-run, --json, --audit-dir, --operator, --version, --help)

---

## Phase 2: Foundational (Shared Across All Stories)

**Purpose**: Core types, pre-flight checks, deployment model detection, audit, and registry cleanup used by all decommission paths

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [X] T002 [ASYNC] Create shared types, error definitions, and constants in cmd/decommission/types.go (DeploymentModel enum, AuditRecord struct, Config struct, error vars, exit code constants per contracts/command-schema.md)
- [X] T003 [P] [SYNC] Implement pre-flight checks in cmd/decommission/precheck.go: validate kubectl context is set, verify required CLIs exist on PATH (git, argocd for GitOps path), confirm service exists in cluster, check for active connections/traffic, abort on failure unless --force
- [X] T004 [P] [ASYNC] Implement deployment model detection in cmd/decommission/detect.go: check for ArgoCD Application resource via kubectl exec, return GitOps or Direct Deploy model
- [X] T005 [P] [ASYNC] Implement audit record creation in cmd/decommission/audit.go: struct fields (service, namespace, model, operator, timestamp, prechecks, resources, image, status), write to file in --audit-dir, print to stdout, support --json output
- [X] T006 [P] [ASYNC] Implement container image cleanup in cmd/decommission/registry.go: detect registry type from image reference, exec appropriate CLI (docker, gh, aws, gcloud) or log warning if unavailable

**Checkpoint**: Foundation ready — user story implementation can now begin

---

## Phase 3: User Story 1 - GitOps Service Decommission via CLI (Priority: P1)

**Goal**: CLI identifies the ArgoCD Application, removes manifests from the app repo, pushes the change, waits for ArgoCD to prune resources, and verifies cleanup

**Independent Test**: Deploy a test service via GitOps, run `decommission <svc>`, verify all K8s resources are pruned by ArgoCD within one sync cycle

- [X] T007 [SYNC] [US1] Implement GitOps decommission workflow in cmd/decommission/gitops.go: clone or pull app repo, remove k8s/ and argocd/ manifests, commit with standardised message, push, wait for ArgoCD prune (poll argocd app get), verify cleanup with kubectl get all

**Checkpoint**: At this point, the GitOps decommission path should be fully functional and independently testable

---

## Phase 4: User Story 2 - Direct Deploy Service Decommission via CLI (Priority: P2)

**Goal**: CLI executes the kubectl delete sequence in the correct order, verifies each step, cleans up the image, and records an audit entry

**Independent Test**: Deploy a test service via Direct Deploy, run `decommission <svc>`, verify all resources are deleted in the correct order

- [X] T008 [ASYNC] [US2] Implement Direct Deploy decommission workflow in cmd/decommission/direct.go: kubectl delete in order (Deployment → Service → Ingress → ConfigMap/Secret → PVC), verify after each step with kubectl get, report which resources were removed

**Checkpoint**: At this point, both GitOps and Direct Deploy paths should be fully functional

---

## Phase 5: User Story 3 - Interactive PVC Data Retention (Priority: P3)

**Goal**: CLI detects PVCs associated with the service and prompts the operator to retain or delete before proceeding with deletion

**Independent Test**: Deploy a service with a PVC, run the CLI choosing "retain" and verify PVC survives; repeat choosing "delete" and verify PVC is removed

- [X] T009 [ASYNC] [US3] Implement PVC detection and retention prompt in cmd/decommission/pvc.go: scan namespace for PVCs matching service name, prompt operator (Y/n to retain, require explicit "yes" to delete), default to retain, log choice in audit record

**Checkpoint**: At this point, US1, US2, and US3 should all be independently functional

---

## Phase 6: User Story 4 - Dry-Run Mode (Priority: P3)

**Goal**: CLI previews what a decommission would do without making changes using --dry-run flag

**Independent Test**: Run `decommission <svc> --dry-run` against an active service and verify no resources are modified

- [X] T010 [ASYNC] [US4] Implement dry-run mode in cmd/decommission/dryrun.go: detect deployment model, list planned actions (repo manifest removal, kubectl delete targets, image deletion), skip all destructive operations, print summary and exit 0

**Checkpoint**: All user stories should now be independently functional

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: Build configuration, tests, validation, and integration

- [X] T011 [P] [ASYNC] Write unit tests in cmd/decommission/decommission_test.go covering precheck, detect, audit, registry, direct, pvc, and dryrun logic with table-driven tests
- [X] T012 [P] [SYNC] Create Makefile or Go build configuration at repository root, add build target for cmd/decommission, and update repository README with build and usage instructions for the CLI
- [X] T013 [ASYNC] Validate implementation by running through both decommission paths in the k3d sandbox cluster end-to-end and log results
- [X] T014 [SYNC] Review all safety-critical sections (precheck enforcement, GitOps git/ArgoCD operations, deletion orchestration) for accuracy and completeness

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — can start immediately
- **Foundational (Phase 2)**: Depends on Setup — shared content used by all stories
- **User Stories (Phase 3-6)**: All depend on Foundational phase completion
- **Polish (Phase 7)**: Depends on all user story phases being complete

### User Story Dependencies

- **User Story 1 (P1)**: Can start after Foundational — no dependencies on other stories
- **User Story 2 (P2)**: Can start after Foundational — independent from US1
- **User Story 3 (P3)**: Can start after Foundational — independent from US1 and US2
- **User Story 4 (P3)**: Can start after Foundational — independent from US1, US2, US3

### Within Each User Story

- Foundational components before story-specific logic
- Safety-critical sections written before verification tasks
- Story complete before moving to next priority

### Parallel Opportunities

- T003, T004, T005, and T006 can run in parallel (different files, no dependencies)
- T011 and T012 can run in parallel (different files)
- All user stories can be implemented in any order (no code dependencies)

---

## Parallel Example: User Story 1

```bash
# Launch pre-check logic, deployment detection, audit, and registry cleanup in parallel:
Task: "Implement pre-flight checks" (T003 — shared foundation, start first)
Task: "Implement deployment model detection" (T004 — shared foundation, can proceed in parallel)
Task: "Implement audit record creation" (T005 — shared foundation, can proceed in parallel)
Task: "Implement container image cleanup" (T006 — shared foundation, can proceed in parallel)

# After foundation is complete:
Task: "Implement GitOps decommission workflow" (T007 — US1 specific)
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup — Go module and main.go
2. Complete Phase 2: Foundational — types, precheck, detect, audit, registry
3. Complete Phase 3: User Story 1 — GitOps decommission
4. **STOP and VALIDATE**: Run through GitOps decommission in sandbox
5. Deploy/demo if ready

### Incremental Delivery

1. Complete Setup + Foundational → Foundation ready
2. Add User Story 1 (GitOps) → Test independently → Deploy/Demo (MVP!)
3. Add User Story 2 (Direct Deploy) → Test independently → Deploy/Demo
4. Add User Story 3 (PVC) → Test independently → Deploy/Demo
5. Add User Story 4 (Dry-run) → Test independently → Deploy/Demo
6. Each story adds value without breaking previous stories

---

## Phase 8: Convergence

- [X] T015 Add ArgoCD Application deletion to GitOps workflow (`gitops.go`) after prune completes — delete via `argocd app delete` or `kubectl delete application`, per US1/AC3 (missing)
- [X] T016 Add kubectl context validation to pre-checks (`precheck.go`): run `kubectl config current-context` and verify cluster reachability, per FR-012 (partial)
- [X] T017 Add signal handler for SIGINT/SIGTERM in `main.go` to print cleanup instructions and exit gracefully, per FR-011 (missing)
- [X] T018 Add RBAC permission pre-checks in `precheck.go` using `kubectl auth can-i delete <resource>`, per Edge Cases (missing)
- [X] T019 Remove or implement `ErrServiceDep` usage — currently defined in `types.go` but never raised, per Edge Cases (missing)

---

### Parallel Team Strategy

With multiple developers:

1. Team completes Setup + Foundational together
2. Once Foundational is done:
   - Developer A: User Story 1 (GitOps)
   - Developer B: User Story 2 (Direct Deploy)
   - Developer C: User Story 3 (PVC)
   - Developer D: User Story 4 (Dry-run)
3. Stories complete and integrate independently
