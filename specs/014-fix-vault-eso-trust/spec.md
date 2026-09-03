# Feature Specification: Vault↔ESO Secret Trust Restoration & Fleet Secret Reorganization

**Feature Branch**: `014-fix-vault-eso-trust`

**Created**: 2026-09-02

**Status**: In Progress (trust restored; 5-part reorganization mid-implementation)

**Input**: User description: "Fix the Vault↔ESO secret sync gap: the `vault-store` ClusterSecretStore cannot authenticate because the kubernetes-auth role `external-secrets` is not provisioned on the live Vault, so six of eight ExternalSecrets fail to sync even though the secret data is intact at the old paths. Establish the missing trust, verify all syncs recover, then decide whether to migrate secret data to the new split-path layout. Additionally, execute a 5-part fleet reorganization: a shared `llm` engine for analyst + pdf-scan, familytree uses the shared `email-env` plus an `admins`/`editors` split, WAHA placeholders, and renaming `aws` to `aws/s3`."

## Mission Brief

**Goal**: Restore authentication for the shared secret store so all eight ExternalSecrets sync without errors, then complete a 5-part fleet/secret-engine reorganization (shared `llm` engine, familytree `email-env` + `admins`/`editors` split, WAHA placeholders, `aws`→`aws/s3` rename) and verify every ExternalSecret syncs from its canonical path.

**Success Criteria**:
- 8/8 ExternalSecrets reach and hold a synced state with zero sync errors; recovered values byte-for-byte identical to their prior values.
- The shared `llm` engine serves BOTH `analyst-secrets` (OPENCODE_ZEN_API_KEY) and `pdf-scan-env` (LLM_API_KEY) from one `llm` mount via the dedicated `vault-llm` ClusterSecretStore.
- Familytree consumes the shared `email-env` for SMTP and exposes `admins`/`editors` as distinct role-based secret groups; WAHA values synced from placeholders.
- The `aws` secret path is migrated to `aws/s3` and the `s3-credentials` ExternalSecret syncs from the new path.
- The repair and reorganization perform no unapproved live data mutation; only operator-approved paths are touched.

**Constraints**:
- Secret operations run only against the live cluster backend — never a local stub or offline environment.
- Old paths remain authoritative single source of truth until a migration is explicitly operator-approved and applied.
- Least-privilege reads only (writes denied); no secret values printed to logs or version control.
- Local manifest rewrites stay uncommitted until the reorganization is accepted.
- Manifest commits for a completed reorganization cover every repo in the ArgoCD applicative inventory (`infra/argocd-infra/apps/applicative/*.yaml`) that owns a migrated ExternalSecret.

## Clarifications

### Session 2026-09-02

- Q: Is provisioning the missing store authentication a one-time operator remediation, or does this feature also include making it durable so a recreated cluster does not regress again? → A: Option B — restore trust via documented operator procedure AND update/verify the durable automation contract so the gap cannot silently reappear on cluster recreation.
- Q: When Story 3's migration decision returns "approved", does this feature actually execute the data migration and promote the committed manifest rewrites, or does it stop at producing a reviewed migration plan for a separate follow-up? → A: Option A — after operator approval inside this feature, this feature migrates live data, updates read policies, and commits the rewritten manifests as its final step.
- Q: Which repositories are in scope for committing the rewritten external-secret manifests once an approved migration completes — only this fleet template repo, or also the consumer repos that already hold the uncommitted local rewrites? → A: Custom — commit scope is all apps under the ArgoCD applicative inventory (`infra/argocd-infra/apps/applicative/*.yaml`), i.e. every repo in that inventory that owns a migrated ExternalSecret. This template repo holds the shared procedure, tooling, and verification.
- Q: How should the current, in-flight 5-part reorganization be reflected given live changes are already applied? → A: Capture the current verified state in this spec — the `llm` mount, `vault-llm` store, seeded Vault paths, and rewritten analyst/pdf-scan/aws manifests are DONE; familytree rework, deploy updates, final apply, and verification remain.
- Q: Should the cleanup decisions (retire analyst `SecretStore vault-kubernetes-analyst` + role `es-vault-analyst`/policy `analyst-read-env`, lock down the `eso-reader` over-grant, delete vs. leave dormant `secret/analyst/env` + `secret/pdf-scan/env`) be executed as part of this feature? → A: Option A — execute full cleanup inside this feature: retire the now-unused analyst store/role/policy, lock down `eso-reader`, AND delete the dormant `secret/analyst/env` + `secret/pdf-scan/env` secret paths.
- Q: For the familytree `admins`/`editors` split, should this feature wire the running deployment to mount/consume the split secrets, or deliver it purely as the ESO-layer sync structure? → A: Option A — wire the optional volume mounts + env refs for `familytree-admins`/`familytree-editors` in deploy.yaml now (non-blocking if empty); no new app-side reading of the two groups beyond the existing single-dir `AUTH_SECRET_DIR` pattern.
- Q: Given `familytree/admins` and `familytree/editors` have empty Vault paths, how should completion be defined for those two ExternalSecrets? → A: Require 8/8 `SecretSynced=True`, and this feature SEEDS at least one admin who also holds the edit role OUT OF THE BOX, so the groups are populated and can sync. Because familytree auth values are absent from Infisical and NFR-004 bars backfill from in-cluster Secrets, the bootstrap admin's credentials are OPERATOR-SUPPLIED and seeded directly into Vault `familytree/admins` (that person) + `familytree/editors` (same person = has edit role).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Restore Vault↔ESO Authentication for the Shared Store (Priority: P1)

The cluster's shared secret store (`vault-store`) previously could not authenticate to the secret backend: it attempted a Kubernetes-auth login as role `external-secrets`, but that role was never provisioned on the live Vault. As a result the six ExternalSecrets referencing this store (`familytree-env`, `familytree-email`, `familytree-auth`, `email-env`, `email-bulk`, `pdf-scan-env`) reported `SecretSyncedError`, while the two stores using working roles (`analyst-secrets`, `s3-credentials`) synced correctly. The underlying data existed at the old paths. **This is COMPLETE**: the `external-secrets` kubernetes-auth role and the narrowed `eso-reader` policy were provisioned, and the store now reports `Valid | store validated`.

**Why this priority**: Six of eight secret-sync resources were down — the widest ongoing production impact, now resolved.

**Independent Test** (PASSED): With the role/policy provisioned, the shared store reports a valid configuration, and the ExternalSecrets referencing it transition to a synced state from old-path data without touching data or application config.

**Acceptance Scenarios** (all met):
1. **Given** the shared store reported an invalid role, **When** the role and read policy were provisioned, **Then** the store reported a valid, ready configuration.
2. **Given** six ExternalSecrets failed with provider errors, **When** the store became ready, **Then** all six transitioned to a synced state within one refresh cycle.
3. **Given** all eight ExternalSecrets synced, **When** a subsequent refresh cycle elapsed, **Then** all eight remained synced with zero sync errors re-emerging.

---

### User Story 2 - Verify the Full Secret Sync Set Recovers With No Data Loss (Priority: P2)

After trust is restored, the operator and consumers need deterministic verification that all eight sync resources are healthy and that recovered secrets contain the exact prior values — recovery must not silently modify or drop secret material.

**Why this priority**: Restoring sync is only valuable if recovered secrets are complete and correct; silent truncation or value drift is worse than the error state.

**Independent Test** (PASSED with caveats): Snapshot synced secret contents before/after the fix and diff to prove byte-for-byte equality. CAVEAT: three ExternalSecrets (familytree-auth, familytree-env, pdf-scan-env) lacked source data in Infisical/Vault and remained non-synced until seeded; familytree/env was later seeded with operator-approved placeholders.

**Acceptance Scenarios**:
1. **Given** the two working syncs, **When** the fix is applied, **Then** their synced values are byte-for-byte unchanged. ✔
2. **Given** the six recovered syncs, **When** they first report synced, **Then** each synced value matches the value already stored at the old backend paths. ✔ (5/6 synced from Infisical seed; familytree/env now on placeholders)
3. **Given** an all-synced state, **When** a verification run executes, **Then** it reports no `UpdateFailed`, no 403, and no value mismatches. ✔ where source data exists.

---

### User Story 3 - Migrate Secret Data to the New Split-Path Layout and Execute the 5-Part Reorganization (Priority: P3)

Once sync was restored from the old paths, the fleet adopts the `/env/service/key` standard. This story now INCOrpORATES the operator-approved 5-part reorganization. The reorganization is partially complete:
- **DONE**: `llm` KV-v2 mount provisioned and seeded with `OPENCODE_ZEN_API_KEY`; dedicated `vault-llm` ClusterSecretStore created and applied; analyst ES rewritten to `vault-llm`/`opencode`; pdf-scan ES rewritten to `vault-llm`/`opencode` (keeps `LLM_API_KEY` secretKey for envFrom); aws renamed to `aws/s3` (values recovered and rewritten; old `aws/env` deleted); `eso-reader` + `aws-read-env` policies updated; `familytree/env` seeded with placeholders; empty `familytree/admins` + `familytree/editors` paths created.
- **REMAINING**: familytree ES rework (env flat-path + properties, drop familytree-email, split auth into admins/editors) + SEED `familytree/admins` + `familytree/editors` with at least one operator-supplied admin who also holds the edit role (bootstrap admin, out of the box); deploy.yaml updates (familytree uses `email-env`; wire OPTIONAL volume mounts + env refs for `familytree-admins`/`familytree-editors`, non-blocking if empty); apply + verify all 8 ExternalSecrets; full cleanup: retire the now-unused analyst `SecretStore vault-kubernetes-analyst` + role `es-vault-analyst`/policy `analyst-read-env`, lock down the `eso-reader` over-grant, and delete the dormant `secret/analyst/env` + `secret/pdf-scan/env` secret paths.

**Why this priority**: The path-standard rewrite aligns manifests with a fleet convention; adoption is sequenced behind restored sync and gated on operator approval. The rename to `aws/s3` is irreversible-live (old path deleted), so it is tracked here for verification parity.

**Independent Test**: Run the migration/reorganization against the live backend, update read policies, verify all eight ExternalSecrets sync from their canonical paths, then commit the rewritten manifests.

**Acceptance Scenarios**:
1. **Given** all eight ExternalSecrets synced, **When** the reorganization plan is dry-run against the live backend, **Then** it enumerates every old→new mapping without modifying data. ✔ for aws→aws/s3; analyst/pdf-scan now read the shared `llm` engine via `vault-llm`.
2. **Given** a reviewed plan and operator approval, **When** the reorganization is applied, read policies updated, and manifests rewritten, **Then** all eight ExternalSecrets sync from the new paths with values equal to the old-path values. ⏳ familytree + final apply/verify pending.
3. **Given** reorganization is finalized, **Then** the `familytree-admins`/`familytree-editors` split exists as ESO-layer structure with optional volume mounts, AND is seeded with at least one operator-supplied admin who also holds the edit role (same person in both groups), so both reach `SecretSynced=True`.

---

### Edge Cases

- What happens when the exact secret backend address (hostname, port, CA) referenced by the store does not match the certificate SANs? (Known drift: draft infra store used a short hostname not in cert SANs — reconciliation must keep the working consumer contract.)
- How does the system behave when the Kubernetes-auth mount itself is missing or misconfigured, not just the role?
- What happens when more than one service relies on the same backend path (e.g., `email/env` read by both `familytree` and sibling repos)? Ops must be idempotent — re-provisioning must not duplicate or clobber roles/policies.
- `llm` engine shared by analyst + pdf-scan: analyst needs `OPENCODE_ZEN_API_KEY`, pdf-scan needs `LLM_API_KEY` — they must map distinct secretKeys from the SAME mounted property without write conflicts.
- Familytree SMTP now consuming shared `email-env` — how to avoid duplicating or clobbering when multiple consumers use one backend path.
- What happens if a policy intended for read-only is accidentally given broader scope (e.g., `secret/data/*` instead of path-scoped reads)? (NOTE: `eso-reader` currently also grants `secret/data/analyst/*` and `secret/data/aws/*` — verify/lock down as part of least-privilege.)
- What happens if the operator runs provisioning against a stub/offline backend instead of the live cluster backend?
- Familytree `admins`/`editors` split is an ESO-layer + optional-mount structure; the app reads ONE dir (`AUTH_SECRET_DIR`) — the split mounts are non-blocking/optional so an empty group does not break the single-dir read contract.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The shared store MUST authenticate to the secret backend without static credentials, using Kubernetes service-account identity. ✔ done
- **FR-002**: The authentication identity for the shared store MUST be a dedicated role (distinct from the existing per-service roles) bound to the External Secrets Operator's service account. ✔ done
- **FR-003**: The read policy attached to that role MUST be least-privilege: read access confined to the specific secret paths consumed by the affected ExternalSecrets, with writes denied by default. ✔ done (verify `eso-reader` does not over-grant analyst/aws paths)
- **FR-004**: The provisioned role and policy MUST be idempotent — re-applying the same configuration MUST NOT create duplicates or alter existing unrelated roles/policies. ✔ done
- **FR-005**: All eight ExternalSecrets MUST reach and hold a synced state across consecutive refresh cycles with zero sync errors or permission denials. ⏳ where source data exists
- **FR-006**: Restoring trust MUST NOT require any change to external application manifests, consumed data values, or the two already-working sync roles. ✔ done
- **FR-007**: A new dedicated ClusterSecretStore (`vault-llm`, mount-bound to path `llm`) MUST be created so the shared `llm` engine is readable, since the existing stores are mount-bound via `path: secret`. ✔ done
- **FR-008**: The shared `llm` engine MUST serve both analyst (key `OPENCODE_ZEN_API_KEY`) and pdf-scan (key `LLM_API_KEY`) from the single `llm/opencode` record via property mapping. ✔ done
- **FR-009**: Familytree MUST consume SMTP from the shared `email-env` (not a dedicated familytree-email) and expose `admins`/`editors` as distinct role-based secret groups synced from `familytree/admins` and `familytree/editors`. ⏳ in progress — deploy.yaml MUST additionally wire the optional volume mounts + env refs for `familytree-admins`/`familytree-editors` (non-blocking if empty), with NO new app-side reading beyond the existing single-dir `AUTH_SECRET_DIR` pattern.
- **FR-009a**: The feature MUST seed at least one admin who also holds the EDIT role out of the box — the same person provisioned in BOTH `familytree/admins` (as admin) and `familytree/editors` (as editor). Credentials are operator-supplied and seeded directly into Vault (absent from Infisical; no backfill from in-cluster Secrets per NFR-004), so `familytree-admins` + `familytree-editors` reach `SecretSynced=True`.
- **FR-010**: The `aws` secret path MUST be migrated to `aws/s3` (old `aws/env` deleted) and `s3-credentials` MUST sync from the new path with byte-identical values. ✔ done
- **FR-011**: Manifest commits for the completed reorganization MUST cover every repo in the ArgoCD applicative inventory (`infra/argocd-infra/apps/applicative/*.yaml`) that owns a migrated ExternalSecret; the shared procedure, tooling, and verification live in this template repo.
- **FR-012**: The reorganization MUST be verifiable via reproducible status conditions and events (`Ready=True`, `SecretSynced=True`, no `UpdateFailed`), not via secret value inspection in logs.
- **FR-013**: The feature MUST restore trust AND make that restoration durable — the recreation-path automation MUST provision the store's auth role/policy (or a verified contract for that automation MUST be in place) so a recreated cluster does not silently regress.
- **FR-014**: Full cleanup is IN SCOPE: the now-unused analyst `SecretStore vault-kubernetes-analyst`, kubernetes-auth role `es-vault-analyst`, and policy `analyst-read-env` MUST be retired; the `eso-reader` policy MUST be narrowed to remove the over-grant on `secret/data/analyst/*` and `secret/data/aws/*`; and the dormant `secret/analyst/env` + `secret/pdf-scan/env` secret paths MUST be deleted.

### Key Entities *(include if feature involves data)*

- **Secret Store (shared, cluster-scoped)**: Backend connection config used by ExternalSecrets; `vault-store` (path `secret`) now `Valid`, plus new `vault-llm` (path `llm`) for the shared `llm` engine.
- **`llm` Engine (KV v2 mount)**: New mount holding `opencode` → `OPENCODE_ZEN_API_KEY`; shared by analyst + pdf-scan.
- **`vault-llm` ClusterSecretStore**: Mount-bound store (path `llm`, role `external-secrets`, CA from `vault-tls`/`ca.crt`) enabling reads of the new `llm/` mount.
- **Authentication Role / Read Policy**: Kubernetes-auth identity + least-privilege read grants (`eso-reader`, `aws-read-env`); must not shadow or conflict with existing per-service roles.
- **ExternalSecret (×8)**: Resources mapping backend paths to synced Secrets; analysts/pdf-scan/aws now on their canonical paths; familytree rework pending.
- **Familytree role groups**: `familytree/admins` + `familytree/editors` Vault paths, seeded with at least one operator-supplied admin (who also has edit role in `familytree/editors`), synced as `familytree-admins`/`familytree-editors` Secrets and consumed via OPTIONAL volume mounts + env refs (non-blocking if empty); the app itself reads only the existing single-dir `AUTH_SECRET_DIR`.
- **Secret Values (immutable)**: Secret material must remain byte-identical through fix and reorganization; values never printed.
- **New Path Layout**: `llm/opencode`, `familytree/env`, `familytree/admins`, `familytree/editors`, `aws/s3`, shared `email/env`.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: All eight ExternalSecrets (including `familytree-admins` and `familytree-editors`, seeded with at least one operator-supplied admin who also holds the edit role) report a synced state within one refresh cycle of the fix, and remain synced across at least two consecutive refresh cycles (>15 min) with zero `UpdateFailed` or permission-denied events. ✔ largely met; re-verify after familytree rework, bootstrap-admin seed, and final apply.
- **SC-002**: The shared secret store(s) (`vault-store`, `vault-llm`) report a ready/valid configuration with no provider-config errors. ✔ met.
- **SC-003**: Content equality: every recovered or already-synced secret value is byte-for-byte identical to its value at the old backend path; zero mismatches across all eight syncs. ✔ for available source data.
- **SC-004**: No data loss and no unapproved writes: the fix performs no data mutation; the reorganization touches only paths in an operator-approved plan. ✔ aws rename was operator-approved.
- **SC-005**: Idempotency: re-running provisioning yields an identical store/policy state with no duplicates, no changes to unrelated roles, and no live secret values printed into logs or version control.
- **SC-006**: Durability: recreation-path automation (or a verified contract) provisions the store's auth role/policy so a recreated cluster starts with the store valid and all eight ExternalSecrets synced.
- **SC-007**: The `llm` engine serves both analyst and pdf-scan keys from one shared record via `vault-llm`, with no write conflicts.
- **SC-008**: Familytree consumes `email-env` for SMTP and exposes `admins`/`editors` as ESO-synced role groups with OPTIONAL volume mounts + env refs wired in deploy.yaml (non-blocking if empty; values pending real data seed).
- **SC-009**: `s3-credentials` syncs from `aws/s3` with values byte-identical to the old `aws/env` values.
- **SC-010**: Cleanup complete: no `vault-kubernetes-analyst` SecretStore, `es-vault-analyst` role, or `analyst-read-env` policy remains; `eso-reader` grants only the consumed paths (`familytree/*`, `email/*`, `llm/data/*`); `secret/analyst/env` + `secret/pdf-scan/env` no longer exist in Vault.

## Demo Sentence

After the fix and reorganization, all eight ExternalSecrets report `SecretSynced=True` with `vault-store` and `vault-llm` `Ready=True`, and remain synced across two consecutive refresh cycles with zero sync errors and byte-identical values — observed without printing any secret value. Analyst and pdf-scan both read from the shared `llm` engine; familytree consumes `email-env` for SMTP and exposes `admins`/`editors` as ESO-synced role groups; `s3-credentials` syncs from `aws/s3`.

## Assumptions

- The cluster is a k3d lab cluster (`k3d-cluster-argo`); Vault is HA/Raft with KV v2 mounts `secret/` and `llm/` and a Kubernetes auth mount.
- The `external-secrets` kubernetes-auth role is provisioned and consumers are aligned to its contract (server address, CA via `vault-tls`, mount path, SA reference).
- Only the ExternalSecrets referencing the shared store were broken; the two per-service store contracts must remain intact where still used.
- Perimeter: local operator Vault CLI is not connected to cluster Vault; all live reads/writes are done from inside the cluster or via authorized port-forward, using a token/role that actually exists — never a local stub.
- Live secret operations are operator-governed; agents stage and verify; the operator applies Vault-side changes with go/no-go.
- A pre-existing sibling workstream (`fix-vault-store`) documents the same root cause and contract (role `external-secrets`, `eso-reader` policy, mount `kubernetes`); this spec aligns with and may reuse that research.
- The fleet's authoritative commit scope is the ArgoCD applicative inventory (`infra/argocd-infra/apps/applicative/*.yaml`).
- Familytree real secret values (SESSION_SECRET, WAHA_*, auth claims) are NOT present in Infisical; placeholders for `familytree/env` are operator-approved, and `admins`/`editors` are SEEDED with at least one operator-supplied admin who also holds the edit role (no backfill from in-cluster Secrets per NFR-004).
- `secret/analyst/env` and `secret/pdf-scan/env` are duplicate/dormant after analyst/pdf-scan move to the `llm` engine; per clarification they are DELETED as part of this feature's cleanup (the `llm/opencode` record is their replacement source of truth).
