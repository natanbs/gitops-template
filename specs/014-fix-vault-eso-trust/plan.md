# Implementation Plan: Vault↔ESO Secret Trust Restoration & Fleet Secret Reorganization

**Branch**: `014-fix-vault-eso-trust` | **Date**: 2026-09-02 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `specs/014-fix-vault-eso-trust/spec.md`
(+ clarification session 2026-09-02), Fleet Alignment Constitution
(`.specify/memory/constitution.md` v1.0.0), team-ai-directives
(`context_modules/rules/devops/secrets_management.md` CDR-2026-017).

## Summary

Two deployed problems on `cluster-argo` k3d share a Vault-side root cause.
**Problem A (outage):** the shared `vault-store` ClusterSecretStore was
`InvalidProviderConfig` — ESO attempted Kubernetes-auth login as role
`external-secrets`, which the live Vault bootstrap never provisioned. Six of
eight ExternalSecrets failed to sync. **Problem B (drift-on-recreation):** the
authoritative role/policy provisioning was operator-run and never wired into the
cluster-recreation path, so a recreated cluster regresses to A.

**This is now substantially COMPLETE on the trust side** (role `external-secrets`
+ narrowed `eso-reader` provisioned live; `vault-store` → `Valid`), and the
spec has been repurposed to carry a **5-part fleet/secret-engine reorganization**
plus **full cleanup**:

1. **Shared `llm` engine** for analyst + pdf-scan: new KV v2 mount `llm` holding
   `opencode` → `OPENCODE_ZEN_API_KEY`; dedicated `vault-llm` ClusterSecretStore
   (mount-bound `path: llm`) since existing stores are `path: secret`-bound.
   ✅ done (mount, store, analyst/pdf-scan ES rewrites applied).
2. **Familytree on shared `email-env`**: familytree uses the shared SMTP store
   instead of its own `familytree-email`. ⏳ rework pending.
3. **Familytree `admins`/`editors` split**: role-based secret groups from
   `familytree/admins` + `familytree/editors`, wired as OPTIONAL volume mounts;
   seeded with at least one operator-supplied admin who also holds the edit role
   OUT OF THE BOX (8/8 `SecretSynced=True` gate requires the groups populated).
   ⏳ rework + seed pending.
4. **WAHA placeholders**: `familytree/env` seeded with operator-approved
   placeholders (SESSION_SECRET, WAHA_URL, WAHA_API_KEY). ✅ done.
5. **`aws` → `aws/s3` rename**: path `secret/aws/s3` (VALUES COPIED from
   `secret/aws/env`, OLD PATH **DELETED**); `s3-credentials` ES rewritten
   (`aws/s3/...` + property). ✅ done (irreversible-live).

**Cleanup (in scope, clarification Q1):** retire the now-unused analyst
`SecretStore vault-kubernetes-analyst` + role `es-vault-analyst` + policy
`analyst-read-env`; lock down the `eso-reader` over-grant (analyst/aws paths);
delete dormant `secret/analyst/env` + `secret/pdf-scan/env`. ⏳ pending.

## Technical Context

**Language/Version**: N/A — no application code changed. ESO CRDs
(`external-secrets.io/v1beta1`), HashiCorp Vault (HA Raft, k8s auth, KV v2
mounts `secret/` and `llm/`), Bash tooling (operator-run `vault`/`kubectl`).

**Primary Dependencies**: External Secrets Operator (installed),
`secrets-vault-standard/` (013 tooling), `vault-ops.sh` + `eso-reader.hcl`/
`aws-read-env.hcl`/`analyst-read-env.hcl` (sibling platform repo, operator-run),
Vault CLI + live token (cluster reachability via port-forward/in-cluster exec).

**Storage**: Vault KV v2. Canonical (live) paths — `secret/analyst/env`,
`secret/aws/s3`, `secret/email/env`, `secret/email/bulk`, `secret/familytree/env`,
`secret/familytree/admins`, `secret/familytree/editors`, `secret/pdf-scan/env`,
and `llm/opencode`. Mount-bound stores: `vault-store` (path `secret`),
`vault-llm` (path `llm`). DELETE-after-verify: `secret/analyst/env`,
`secret/pdf-scan/env` (dormant duplicates; `llm/opencode` is their replacement).

**Testing**: No unit-test suite changed; acceptance via reproducible quickstart
operational validation (`kubectl get` conditions/events + `vault` read checks;
dry-run first; live steps gated by operator go/no-go). Reuses the 013 bats
suites as the alignment tool's regression net.

**Target Platform**: k3d cluster `k3d-cluster-argo`, ArgoCD apps, manifests
under each repo's `k8s/`; platform automation in sibling repos (this repo holds
shared procedure/contracts).

**Project Type**: Infrastructure/coordination (GitOps YAML contracts, operator
runbook, tooling reuse). Not a library/CLI/web-service.

**Performance Goals**: N/A. Reliability goal (SC-001): zero
`UpdateFailed`/403 recurrence across ≥ 2 ESO refresh cycles (>15 min).

**Constraints**: Least privilege (reads only, confined to consumed paths; no
writes — FR-003/SC-004); secrets never committed/printed (FR-009); declarative +
idempotent provisioning (FR-004/SC-005); durable recreation-path wiring
(FR-013/SC-006); migration/reorganization only against the live backend with
operator approval (FR-007); local manifest rewrites stay uncommitted until an
accepted reorganization lands (FR-011); agent/operator split — agents never run
destructive `kubectl`/`vault`; clean up over-broad `eso-reader` and retired
analyst trust objects (clarification Q1).

**Scale/Scope**: 5 repos in the ArgoCD applicative inventory + this template
repo; stores `vault-store` + `vault-llm`; 8 ExternalSecrets; 2 Vault mounts
(`secret`, `llm`); contracts + quickstart + data model + research; no new repo
source code.

## Constitution Check

*GATE: Passed pre-research; re-checked post-design below.*

**Fleet Alignment Constitution v1.0.0** (`.specify/memory/constitution.md`)

| Principle | Implication for this change | Status |
|-----------|-----------------------------|--------|
| I-1 Gate Compliance First | Restores ESO/Vault trust plane + reorganizes secret layout; ships no new merge-time gates, changes no consumer app CI. | PASS |
| I-2 Shared Versioned Artifacts @vX.Y.Z | No new unpinned refs; reuses committed `secrets-vault-standard` tooling (013) unchanged. | PASS |
| I-3 Tracked Re-Sync | Manifest rewrites stay in each consumer repo (inventory commit scope, FR-011); no template re-sync in scope. | PASS |
| II-1 Blast-Radius Isolation | Reorganization is canary-gated: `analyst` first (→ `llm`), verified, then fleet; live Vault provisioning/seeding is a documented operator step behind go/no-go. | PASS |
| II-2 Gate Ergonomics | Each blocking quickstart check emits an actionable remediation line (`fix:` semantics inherited from 013); unknown → manual review, never silent. | PASS |
| II-3 Bypass Auditing | Migration/reorg approval recorded in the runbook as explicit operator decisions (include bootstrap-admin seed + cleanup deletes) with traceable dry-run; no unowned bypass. | PASS |
| Pending Decision Log | PDL "Migration" refers to template-fleet brownfield onboarding, not this KV path reorg; the `aws→aws/s3` rename and `llm` engine are data-plane decisions owned by the operator. No new gated phase rolled out. | PASS |

**Gate result (pre-research)**: PASS — no violations.
**Gate result (post-design)**: PASS — re-verified after Phase 1; the reorg design
is additive to already-applied live state, cleanup is explicit and approved, no
new scoped phase is rolled out, and no live mutation is scope-mandated beyond
operator-approved paths.

## Project Structure

### Documentation (this feature)

```text
specs/014-fix-vault-eso-trust/
├── plan.md              # This file (/spec.plan command output)
├── research.md          # Phase 0 output (/spec.plan command)
├── data-model.md        # Phase 1 output (/spec.plan command)
├── quickstart.md        # Phase 1 output (/spec.plan command)
├── contracts/           # Phase 1 output (/spec.plan command)
│   ├── vault-trust.md   # Required Vault-side trust state + policy scope + durability contract
│   └── migration.md     # KV path-migration/reorg contract: mapping, canary, ordering, commit scope + cleanup
└── tasks.md             # Phase 2 output (/spec.tasks command - NOT created by /spec.plan)
```

### Source Code (repository root)

No new source files. The migration tooling already exists and is reused
unchanged: `secrets-vault-standard/align-fleet.sh` (+`align-plan.py`,
`tests/align-fleet.bats`) from 013 — the authoritative planner/executor for
dry-run planning and KV apply.

```text
secrets-vault-standard/
├── align-fleet.sh       # REUSE (unchanged): plans + applies manifest/KV alignment
├── align-plan.py        # REUSE (unchanged): planner TSV (FILE/LINE/KIND/OLD/PROP/TARGET/NEW)
└── tests/align-fleet.bats  # REUSE (unchanged): 11 tests (dry-run, apply, git-HEAD recovery)
```

Consumer-manifest state (real fleet):
- **Already rewritten + applied live (uncommitted)**: `analyst/k8s/external-secret.yaml`
  (`vault-llm`/`opencode`, key `OPENCODE_ZEN_API_KEY` → target `analyst-secrets`),
  `pdf-scan/k8s/external-secret.yaml` (`vault-llm`/`opencode`, secretKey
  `LLM_API_KEY` → `pdf-scan-env`), `aws/k8s/external-secret.yaml`
  (`aws/s3/...` + property → `s3-credentials`).
- **Pending rework**: `familytree/k8s/external-secret.yaml` (env flat-path +
  properties, drop `familytree-email`, split auth into admins/editors),
  `familytree/k8s/deploy.yaml` (use `email-env`; optional mounts + env refs for
  `familytree-admins`/`familytree-editors`).
- **Cleanup targets**: analyst `SecretStore vault-kubernetes-analyst` + role
  `es-vault-analyst` + policy `analyst-read-env`; `eso-reader` over-grant;
  `secret/analyst/env` + `secret/pdf-scan/env`.

**Structure Decision**: This is a coordination/GitOps feature — the plan's
deliverables are the Vault-trust contract, the reorg/migration contract, and the
operator quickstart that resolve to existing tooling (013). No application code
or new tooling is needed; adding any would violate "no writes in repair" and
duplicate the committed 013 executor.

## Triage Framework: [SYNC] vs [ASYNC] Classification

**Execution strategy**: Hybrid — agent-delegated documentation/contract
production + operator-gated live remediation/seeding.

### Preliminary Task Classification

| Task Category | Estimated [SYNC] Tasks | Estimated [ASYNC] Tasks | Rationale |
|---------------|----------------------|----------------------|-----------|
| Business Logic | 0 | 0 | No application logic in scope |
| Data Operations | 5 | 0 | Vault trust provisioning, `llm`/AWS data already applied, familytree env+admin/editor SEED, cleanup deletes, policy narrowing — operator-applied live, go/no-go |
| Tooling | 0 | 0 | 013 tooling reused unchanged |
| Contract/Design Docs | 0 | 3 | vault-trust.md, migration.md, quickstart.md — delegable, reviewable |
| Verification | 3 | 0 | Baseline snapshot, Ready/Synced asserts, least-privilege/idempotency/cleanup asserts — operator-run per quickstart |

### Triage Decision Criteria Applied

**High-Risk [SYNC] Classifications:** all live Vault/kubectl operations
(`setup-k8s-auth` provisioning; familytree env + admin/editor seed; cleanup
deletes of `secret/analyst/env`/`secret/pdf-scan/env` and retired analyst trust
objects; `vault policy` narrowing; ArgoCD sync + manifest commits across
inventory repos). These are destructive or state-changing, touch real secret
material, and fail loudly if mis-sequenced. They require human review per the
constitution's Human Oversight gate.

**Agent-Delegated [ASYNC] Classifications:** authoring the two contracts, the
operator quickstart, and the data model — all reviewable, non-executing
deliverables.

### Triage Audit Trail

| Task | Classification | Primary Criteria | Risk Level | Rationale |
|------|----------------|------------------|------------|-----------|
| Vault trust provisioning (role `external-secrets` + scoped `eso-reader`) | SYNC | Destructive/live | Med | ✅ already applied; operator runs `vault-ops.sh` w/ go/no-go; idempotent |
| `llm` engine + `vault-llm` store + seed `llm/opencode` | SYNC | Data ops | Med | ✅ already applied (mount, store, seed from analyst value) |
| `aws`→`aws/s3` rename (copy + delete old) | SYNC | Destructive/live | High | ✅ already applied + operator-approved; old path deleted |
| Familytree `env` ES rework + deploy.yaml optional mounts | SYNC | Manifest | Med | operator applies + ArgoCD sync |
| Familytree `admins`/`editors` rework + SEED bootstrap admin (edit role OOB) | SYNC | Data ops + manifest | High | operator supplies creds + seeds both groups; enables 8/8 gate |
| Cleanup: retire analyst store/role/policy + narrow `eso-reader` + delete `analyst/env`/`pdf-scan/env` | SYNC | Destructive/live | High | approval recorded; delete only after verify (clarification Q1) |
| Recreation-path wiring contract (durability) | ASYNC | Documentation | Low | contract only; sibling-repo PR is a follow-on |
| contracts/vault-trust.md, migration.md, quickstart.md, data-model.md | ASYNC | Documentation | Low | deterministic, reviewable, no execution |
| Baseline + acceptance + cleanup verification runs | SYNC | Operational | Med | operator executes quickstart asserts |

## Complexity Tracking

> **Not filled**: no constitution violations exist to justify.

## Verification

- Baseline: confirm current live store/policy/8-ES state (Step 0/1 of quickstart).
- Reorg artifacts applied: `vault-llm` store `Ready=True`; `analyst-secrets` +
  `pdf-scan-env` sync from `llm/opencode`; `s3-credentials` syncs from `aws/s3`
  (values byte-identical to `aws/env`).
- Familytree: `familytree-env` syncs from `familytree/env` properties; `admins`/
  `editors` sync `SecretSynced=True` after the bootstrap-admin seed; deploy.yaml
  mounts them as optional volumes.
- Cleanup: no `vault-kubernetes-analyst` SecretStore, `es-vault-analyst` role, or
  `analyst-read-env` policy remains; `eso-reader` scoped to consumed paths;
  `secret/analyst/env` + `secret/pdf-scan/env` absent.
- Tooling regression: `bats secrets-vault-standard/tests/align-fleet.bats` (11),
  `detectors.bats` (16), `audit-fleet.bats` (18), inventory bats (8);
  `shellcheck secrets-vault-standard/*.sh secrets-vault-standard/detectors/*.sh`.
- Operator acceptance: quickstart Steps 0–8 (baseline, root-cause confirm,
  trust provisioning, `Ready`, 8/8 `SecretSynced`, byte-equality, least-privilege,
  idempotency/stability ≥ 2 cycles, cleanup) plus dry-run review before any live
  mutation.
