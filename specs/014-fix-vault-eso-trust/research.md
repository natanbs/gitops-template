# Research: 014 — Restore Vault-to-Secret Sync Trust

Phase 0 research for feature 014. Branch of investigation: live `cluster-argo`
k3d Vault/ESO integration. Reused the sibling `060-fix-vault-store` research
(as sanctioned by the spec's Assumptions) and confirmed against the live
cluster. Scope: restore the shared store's authentication, verify 8/8
ExternalSecrets recover, then execute the 5-part secret-engine reorganization
(shared `llm` engine, familytree `email-env` + `admins`/`editors` split, WAHA
placeholders, `aws`→`aws/s3` rename) plus full cleanup of retired trust objects
and dormant secret paths.

## Problem Statement

Two problems, one Vault-side root cause:

1. **Outage (P1):** `vault-store` ClusterSecretStore is `InvalidProviderConfig`
   — "unable to create client". ESO logs a login failure for Kubernetes auth,
   role `external-secrets`: `invalid role name "external-secrets"`. Six of
   eight ExternalSecrets (`email-bulk`, `email-env`, `familytree-auth`,
   `familytree-email`, `familytree-env`, `pdf-scan-env`) report
   `could not get secret data from provider`, while `analyst-secrets` and
   `s3-credentials` sync fine (they use `secretstore` objects
   `vault-kubernetes-analyst`/`vault-kubernetes` with roles
   `es-vault-analyst`/`es-vault`).
2. **Drift-on-recreation:** the authoritative provisioning for role
   `external-secrets` + policy `eso-reader` is operator-run
   (`infra/vault/scripts/vault-ops.sh setup-k8s-auth`) and was never wired
   into the cluster-recreation path — a recreated cluster silently regresses
   to problem 1.

## Findings

### F1 — Cluster store is complete and consumer-aligned; only the role/policy is missing (primary)

Live `vault-store` (external-secrets ns):

| Field | Live value | Verdict |
|---|---|---|
| server | `https://vault.vault.svc.cluster.local:8200` | ✅ matches cert SAN DNS.3 + reachable Service |
| path / version | `secret` / `v2` | ✅ KV v2 |
| auth.kubernetes.mountPath | `kubernetes` | ✅ |
| auth.kubernetes.role | `external-secrets` | ✅ desired role name (not provisioned — see F2) |
| auth.kubernetes.serviceAccountRef | `external-secrets` | ✅ |
| refreshInterval | `60` | ⚠️ aggressive — re-login every 60 s; normalize to `3600` to match ExternalSecret refresh |

No functional consumer change is needed for authentication once Vault trusts
the SA. The store is the reference contract.

### F2 — Root cause in Vault auth provisioning, confirmed live (primary)

- Bootstrap (`argo-bootstrap/lib/vault.sh`) provisions only roles
  `es-vault` / `es-vault-analyst` (AWS-style). It never provisions the K8s-auth
  role `external-secrets`, the `eso-reader` policy, or calls `setup-k8s-auth`.
- Login against a mount whose role does not exist returns 403‑class denial —
  exactly the observed `invalid role name "external-secrets"`.
- Confirmed read-only: the only secret-store-adjacent roles that return policy
  data are `es-vault`/`es-vault-analyst`; `vault policy read eso-reader` and
  `auth/kubernetes/role/external-secrets` are absent → role/policy missing.

### F3 — Reconciliation of infra DRAFT (known drift, sibling repos)

The 060 research documented infra DRAFT `infra/external-secrets/vault-store.yaml`
diverging from cert/chart truth (server `vault-active.vault.svc` short form
not in SANs; CA ConfigMap `vault-tls-ca` not templated; `audiences: [vault]`
contradicting the bound audience). 014 does **not** consume that draft: the
live cluster store is the reference contract and matches the cert.

### F4 — Least-privilege scope for `eso-reader` (fleet-wide refinement of 060)

060 scoped its contract to `familytree/*` + `email/*`. 014 is fleet-wide: the
shared store serves `familytree/*`, `email/*`, AND `pdf-scan/*`. Target:

```hcl
path "secret/data/familytree/*" { capabilities = ["read"] }
path "secret/data/email/*"      { capabilities = ["read"] }
path "secret/data/pdf-scan/*"   { capabilities = ["read"] }
```

> **SUPERSEDED (2026-09-02, F10/D7/D11)**: after the `llm` engine decision,
> pdf-scan reads via the `llm` mount (not `secret/data/pdf-scan/*`). The FINAL
> `eso-reader` scope is `familytree/*`, `email/*`, `llm/data/*` (see
> `contracts/vault-trust.md`). Keep this finding for the reasoning trail only.

Per-app roles keep their existing scoped policies (`analyst-read-env` →
`secret/data/analyst/env`, `aws-read-env` → `secret/data/aws/env`) and MUST be
extended to the split-leaf paths (`secret/data/analyst/env/*`,
`secret/data/aws/env/*`) only as part of an approved migration.

### F5 — Data integrity and 403 on leaf paths (migration context)

- Live Vault data is intact at old flat paths: `secret/analyst/env`
  (`OPENCODE_ZEN_API_KEY`), `secret/aws/env` (`S3_*`). Read of the OLD flat path
  succeeds with the app roles (`read` capability on `secret/data/.../env`).
- Reading a **leaf path** (`secret/data/aws/env/S3_ACCESS_KEY_ID`) returns 403
  `permission denied` — current policies only cover the single `.../env` path,
  not leaf suffixes. Confirms: after any migration, policies MUST be extended
  to `.../env/*` or sync breaks again (this is the migration's policy step).

### F6 — Local Vault CLI is a stub; live access is in-cluster/port-forward only

`VAULT_ADDR`/`VAULT_TOKEN` unset → local `vault status` targets
`127.0.0.1:8200` (connection refused). All live reads/writes MUST go through
the cluster Vault: in-cluster exec (`kubectl -n vault exec vault-0 -- vault
...`) or an authorized `kubectl port-forward -n vault service/vault` + token.
This is the D5 perimeter from 060, restated for 014 and enforced in quickstart.

### F7 — Migration tooling exists and matches the sequencing required

`secrets-vault-standard/align-fleet.sh` (013) plans `/<env>/<service>/<key>`
transforms and, via `--apply-vault --yes`, executes KV migration while
recovering pre-rewrite keys from git HEAD (local rewrites uncommitted). Dry-run
against the real fleet: ALIGN 0 / CONFORM 21, exit 1 with 21 pending `vault kv`
ops. Migration MUST run **before** committing the rewrites (ordering contract).

### F8 — CRITICAL: email/familytree/pdf-scan secret data is ABSENT from live Vault (2026-09-02)

Trust was restored (`vault-store` → `Valid`) using the trusted operator root
token (infra/vault/init.json). Post-provisioning verification revealed the
spec/plan's core assumption ("secret data is intact at the old flat paths") is
**incorrect for this live cluster**:

- `vault kv list secret/` (and recursive API scan) returns **only** `analyst/`
  and `aws/`.
- `secret/email`, `secret/familytree`, `secret/pdf-scan` → **do not exist**.
- The 6 ExternalSecrets (`email-env`, `email-bulk`, `familytree-env`,
  `familytree-auth`, `familytree-email`, `pdf-scan-env`) therefore fail with
  `could not get secret data from provider` / `Secret does not exist` — **after**
  auth was fixed.
- Only `analyst-secrets` (`secret/analyst/env`) and `s3-credentials`
  (`secret/aws/env`) sync — matching the only two paths that exist.

**Implication**: The outage root blocker has shifted from **authentication**
(FIXED — role `external-secrets` + `eso-reader` now provisioned) to **missing
secret data** for six consumers. SC-001/FR-005 (8/8 synced) cannot be met while
those secrets contain no source data in Vault. Story 3 (KV path migration) is
moot for the absent paths — there is nothing to migrate. The consuming
applications must seed the `secret/{email,familytree,pdf-scan}/env` paths
(operator action, values sourced from the running K8s Secrets /
`infra/vault/scripts/vault-ops.sh backfill-from-k8s`) before 8/8 sync is
reachable.

## Decisions

| # | Decision | Rationale | Alternatives considered |
|---|----------|-----------|-------------------------|
| D1 | Keep the live cluster store as the reference contract; provision only the missing Vault-side role+policy (no consumer manifest change except `refreshInterval` 60→3600 at operator discretion) | F1/F2 — consumer already aligned; overlay only what's missing | rewrite the consumer store (rejected — no functional need) |
| D2 | Durable automation contract: `setup-k8s-auth` (role `external-secrets` + scoped `eso-reader`, mount `kubernetes`) MUST be wired into the cluster-recreation path in the sibling platform repo | prevents silent regression (F2 drift-on-recreation) | document-only (rejected — recurs after recreate) |
| D3 | Policy scope for `eso-reader`: `familytree/*`, `email/*`, `pdf-scan/*`; per-app policies extended to `env/*` only with the approved migration | F4/F5 least privilege + leaf-path coverage | keep broad `secret/data/*` (rejected — exceeds FR-003/SC-004) |
| D4 | Vault access only via cluster (exec or port-forward) with a live token; never the local stub (127.0.0.1) | F6 | local `vault` CLI (rejected — stub, connection refused) |
| D5 | Migration gated: dry-run + operator go/no-go → canary on `analyst` first → fleet → policy update → commit across inventory repos (FR-011); never auto-commit | II-1 blast radius, FR-007/008 | agent-executed live migration (rejected — human-oversight violation) |
| D6 | Reuse `align-fleet.sh` unchanged for planning and `--apply-vault` execution | F7 — tool already implements recovery + ordering | new migration script (rejected — duplicates committed tooling) |
| D7 | Dedicated `vault-llm` ClusterSecretStore (mount-bound `path: llm`) for the shared `llm` engine | F10 — Vault stores are mount-bound via `path:`; `secret`-bound stores cannot read the `llm/` mount | (rejected) rebind existing stores to `llm` (would break their `secret` readers; under-specified) |
| D8 | `llm/opencode` holds ONE record with `OPENCODE_ZEN_API_KEY`; analyst key `OPENCODE_ZEN_API_KEY`, pdf-scan secretKey `LLM_API_KEY` | F10/F13 — DRY single source; pdf-scan `envFrom` needs the `LLM_API_KEY` key name | separate `llm/analyst` + `llm/pdf` records (rejected — duplicates the same value) |
| D9 | `aws`→`aws/s3` rename (copy + delete old, values verified), `s3-credentials` ES → `aws/s3` + property | F11 — aligns to new layout; operator-approved; old path deleted | (rejected) leave `aws/env` + new `aws/s3` (dormant duplicate not desired) |
| D10 | Familytree `admins`/`editors` split = ESO-layer + OPTIONAL volume mounts; seed bootstrap admin with edit role OOB | F12 — app reads single-dir `AUTH_SECRET_DIR`; clarification Q2/Q3; enables 8/8 `SecretSynced=True` | (rejected) app-side dual-dir read (out of scope, violates surgical-change) |
| D11 | Cleanup: retire `vault-kubernetes-analyst`/`es-vault-analyst`/`analyst-read-env`; narrow `eso-reader`; delete `secret/analyst/env` + `secret/pdf-scan/env` | F14 / clarification Q1 — least privilege (constitution §4/§9); dormant duplicates removed | (rejected) leave-dormant (over-broad grants + stale sources persist) |

## Scope Boundaries

- This repo (gitops-template): contracts, quickstart, data model, research;
  reuse of 013 tooling; no new source code.
- Sibling repos (operator per contracts): Vault trust provisioning, durable
  recreation wiring, migration execution + policy updates, manifest commits.
- No secret values are read, printed, or committed anywhere in this feature;
  all artifacts reference paths and keys only.
- No changes to application code or existing application manifests beyond the
  ESO/deploy rework in scope. The healthy `vault-kubernetes` store (aws) is
  left intact; the analyst store/role/policy (`vault-kubernetes-analyst`,
  `es-vault-analyst`, `analyst-read-env`) is RETIRED as part of cleanup (D11).
### F9 — Infisical re-seed REMEDIATION of email paths (2026-09-02, operator-authorized)

Using the operator-provided `INFISICAL_API_TOKEN` (never printed), the Infisical
org resolves to project **Emails** (`us.infisical.com`, env `dev`), containing 11
secrets: `SMTP_HOST`, `SMTP_PORT`, `SMTP_USER`, `SMTP_PASS`, `SMTP_FROM`,
`TINYVALIDATOR_API_KEY`, `MAILBOXLAYER_API_KEY`, `HUNTER_API_KEY`,
`OPENCODE_ZEN_API_KEY`, plus `SMTP_USER_API`/`SMTP_PASS_API` (unreferenced).
Seeded directly to Vault (without echoing values):

- `secret/email/env` → SMTP_HOST/PORT/USER/PASS/FROM
- `secret/email/bulk` → TINYVALIDATOR/MAILBOXLAYER/HUNTER
- `secret/analyst/env` → OPENCODE_ZEN_API_KEY (already present, idempotent)

**Result**: 5/8 ExternalSecrets now `True` — `analyst-secrets`, `s3-credentials`,
`email-env`, `email-bulk`, `familytree-email` (verified `SMTP_HOST=smtp.gmail.com`
in the synced K8s Secret).

**Closed loop (unfixable via this Infisical)**: `familytree-auth`
(`familytree/auth` claims), `familytree-env` (`SESSION_SECRET`, `WAHA_URL`,
`WAHA_API_KEY`) and `pdf-scan-env` (`LLM_API_KEY`) still fail because those
values do **not** exist anywhere in the Infisical org this token reaches — only
the email+analyst project is populated. 8/8 (SC-001/FR-005) requires these values
be added to Infisical first.

### F10 — Operator-approved 5-part secret-engine reorganization (2026-09-02)

User directive: reorganize into a shared `llm` engine + familytree split +
WAHA placeholders + `aws`→`aws/s3` rename. Design decisions (see data-model +
contracts): (1) `llm` = new KV v2 mount holding one record `opencode` →
`OPENCODE_ZEN_API_KEY`, served by a NEW dedicated ClusterSecretStore
`vault-llm` (mount-bound `path: llm`, role `external-secrets`, CA from
`vault-tls`/`ca.crt`) because the existing stores are `path: secret`-bound;
analyst + pdf-scan both read this one record via property mapping
(analyst key `OPENCODE_ZEN_API_KEY`; pdf-scan key `LLM_API_KEY` to satisfy its
`envFrom secretRef pdf-scan-env` contract). (2) Familytree consumes the shared
`email-env` for SMTP (drop `familytree-email`). (3) Familytree `admins`/`editors`
= role-based split of `familytree/admins` + `familytree/editors`, wired as
OPTIONAL volume mounts (app reads only single-dir `AUTH_SECRET_DIR`).
(4) `familytree/env` = operator-approved placeholders (SESSION_SECRET, WAHA_URL,
WAHA_API_KEY). (5) `aws`→`aws/s3` rename: values copied from `secret/aws/env`,
OLD PATH **DELETED**; `s3-credentials` ES rewritten (`aws/s3` key + property).

### F11 — `aws`→`aws/s3` rename executed, old path deleted (live, 2026-09-02)

Copied `secret/aws/env` → `secret/aws/s3`; deleted `secret/aws/env`; recovered
S3 values from the intact k8s Secret `s3-credentials` (`access-key-id` len 5,
`secret-access-key` len 9, values verified against the new `aws/s3` record).
**CAUTION**: `secret/aws/env` NO LONGER EXISTS — only `aws/s3`. Any policy or
ES still pointing at `aws/env` will 403 / `Secret does not exist`. `s3-credentials`
ES now targets `aws/s3/...` + property; policy `aws-read-env` narrowed to
`secret/data/aws/s3/*`.

### F12 — Familytree `admins`/`editors` split + bootstrap-admin seed constraint

The familytree `admins`/`editors` split is an ESO-layer + optional-mount
structure. The app reads ONE directory (`AUTH_SECRET_DIR`, default
`/etc/secrets/familytree-auth`), one file per person `_id` =
`{"password_hash","admin"}`; setting `admin` flag makes a person an admin. The
app does NOT read separate admins/editors dirs. **Clarification (Q2/Q3):** wire
OPTIONAL volume mounts + env refs for `familytree-admins`/`familytree-editors`
(non-blocking if empty), no new app-side reading; AND seed at least one admin
who also holds the EDIT role OOB (same person in BOTH `familytree/admins` and
`familytree/editors`) so both groups reach `SecretSynced=True`. Because familytree
auth values are ABSENT from Infisical and NFR-004 bars backfill from in-cluster
K8s Secrets, the bootstrap admin's credentials are OPERATOR-SUPPLIED and seeded
directly into Vault. `familytree/admins`/`editors` paths currently exist (empty).

### F13 — `llm` engine provisioned + `vault-llm` store applied (live, 2026-09-02)

`vault secrets enable -path=llm kv-v2` done. Seeded `llm/opencode` ←
`OPENCODE_ZEN_API_KEY` (68-char `sk-` token recovered from `secret/analyst/env`;
value verified via API, never printed). New `vault-llm` ClusterSecretStore
(`infra/external-secrets/vault-llm-store.yaml`) applied; store `Valid | store
validated`. Analyst ES + pdf-scan ES rewritten to `vault-llm`/`opencode`. Only
`kubernetes-store`, `vault-llm`, `vault-store` stores exist.

### F14 — Cleanup scope (clarification Q1): retire analyst trust + narrow `eso-reader` + delete dormant paths

After analyst/pdf-scan move to the `llm` engine: retire the now-unused analyst
`SecretStore vault-kubernetes-analyst` + kubernetes-auth role `es-vault-analyst`
+ policy `analyst-read-env`. `eso-reader` currently ALSO grants
`secret/data/analyst/*` and `secret/data/aws/*` (over-grant to `eso-reader`) —
must be narrowed to only consumed paths (`familytree/*`, `email/*`,
`llm/data/*`). `secret/analyst/env` + `secret/pdf-scan/env` are dormant duplicates
of `llm/opencode` → DELETE (per clarification). Final delete is operator-governed
and only after verifying `llm/opencode` serves both consumers.

### F15 — Live cluster is AHEAD of Vault-reorg but BEHIND on consumer-manifest application (verified 2026-09-02)

**Correction to F11/F13**: F13 says "Analyst ES + pdf-scan ES rewritten to
`vault-llm`/`opencode`" — true in the **repo manifests**, but a read-only
`kubectl` probe shows the **live cluster still runs the OLD pre-reorg
ExternalSecrets** and is **4/8 synced**. The reorganization is complete on the
Vault side and staged in the repos, but **the manifests are NOT applied to the
cluster** (ArgoCD sync + `kubectl apply` are operator-governed, T029).

Verified live external-secrets (namespace `apps-ns`, store → synced):

| ES | live store | synced | intended |
|----|-----------|--------|----------|
| `analyst-secrets` | `vault-kubernetes-analyst` | ❌ | `vault-llm`/`opencode` |
| `s3-credentials` | `vault-kubernetes` | ❌ | reads `aws/s3` (path renamed) |
| `familytree-auth` | `vault-store` | ❌ | removed (3-resource split) |
| `familytree-email` | `vault-store` | ✅ | removed (merged to shared `email-env`) |
| `pdf-scan-env` | `vault-store` | ❌ | `vault-llm`/`opencode` |
| `familytree-env` | `vault-store` | ✅ | unchanged |
| `email-env` | `vault-store` | ✅ | unchanged (tech-companies/familytree shared) |
| `email-bulk` | `vault-store` | ✅ | unchanged |

Also verified Vault-side completeness:
- `secret/aws/s3` EXISTS; old `secret/aws/env` gone (F11 confirmed).
- `llm/opencode` EXISTS (F13 confirmed), `secret/analyst/env` + `secret/pdf-scan`
  still present (dormant → T032).
- `secret/familytree/{env,admins,editors}` exist; `admins` + `editors` are EMPTY
  (seed = T030, operator-supplied, NFR-004).

**Consequence for T029**: the apply step must push ALL FOUR rewritten consumer
manifests (analyst, aws, pdf-scan, familytree) AND delete superseded
`familytree-auth` + `familytree-email` ES, not just the familytree rework.
The `AUTH_SECRET_DIR`→`familytree-admins` volume mapping is the operator
go/no-go (both mounts are `optional: true`, so empty editors is non-blocking).

**Consequence for T031 (8/8 gate)**: `familytree-admins`/`familytree-editors`
can only reach `SecretSynced=True` AFTER T030 seeds the bootstrap admin; the old
`familytree-auth`/`familytree-email` must be gone. `analyst-secrets`/`pdf-scan-env`
must cite store `vault-llm`; `s3-credentials` stays on `vault-kubernetes` reading
`aws/s3`.
