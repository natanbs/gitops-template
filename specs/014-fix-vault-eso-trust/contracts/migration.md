# Contract: Secret-Engine Reorganization & Cleanup (014 Story 3 + Clarifications)

Operator-governed execution of the 5-part secret-engine reorganization plus full
cleanup. This document is the approval surface: nothing here mutates or commits
except with explicit operator go/no-go after a reviewed dry-run/plan. Portions
already applied live are recorded as such; pending items are the remaining gate.

## 1. The 5-part reorganization (what/why)

| # | Change | Vault side | ESO/consumer side | Status |
|---|--------|-----------|-------------------|--------|
| 1 | Shared `llm` engine for analyst + pdf-scan | `llm` KV v2 mount; record `llm/opencode` → `OPENCODE_ZEN_API_KEY` | `vault-llm` ClusterSecretStore (path `llm`); analyst ES + pdf-scan ES → `vault-llm`/`opencode` | ✅ DONE (applied live, uncommitted) |
| 2 | Familytree on shared `email-env` | none (reuse `secret/email/env`) | drop `familytree-email`; familytree SMTP reads shared `email-env` | ⏳ PENDING (deploy.yaml + ES) |
| 3 | Familytree `admins`/`editors` split | seed `familytree/admins` + `familytree/editors` with bootstrap admin (edit role OOB) | `familytree-admins`/`familytree-editors` ES + OPTIONAL volume mounts/env refs | ⏳ PENDING (ES + seed + deploy) |
| 4 | WAHA placeholders | `familytree/env` → SESSION_SECRET/WAHA_URL/WAHA_API_KEY (operator-approved) | `familytree-env` ES reads `familytree/env` properties | ✅ DONE (seeded) |
| 5 | `aws`→`aws/s3` rename | copied `aws/env`→`aws/s3`; **old deleted** | `s3-credentials` ES → `aws/s3` + property | ✅ DONE (applied live, uncommitted, irreversible) |

**Path standard**: canonical layout after reorg = mount-relative flat paths
(`familytree/env` + properties; `aws/s3` + properties; `llm/opencode` +
properties) read via property-mapped `data` refs — matching the LIVE channel
(flat paths), not the git-nested rewrite.

## 2. Consumer mapping to canonical paths

| Repo | ExternalSecret | Store | Remote reader | Synced Secret |
|------|----------------|-------|---------------|---------------|
| analyst | `analyst-secrets` | `vault-llm` | key `opencode`, property `OPENCODE_ZEN_API_KEY` | `analyst-secrets` |
| pdf-scan | `pdf-scan-env` | `vault-llm` | key `opencode`, property `OPENCODE_ZEN_API_KEY` → secretKey `LLM_API_KEY` | `pdf-scan-env` |
| aws | `s3-credentials` | `vault-store` | key `aws/s3` + property | `s3-credentials` |
| familytree | `familytree-env` | `vault-store` | key `familytree/env` + properties SESSION/WAHA | `familytree-env` |
| familytree | `familytree-admins` | `vault-store` | key `familytree/admins` | `familytree-admins` |
| familytree | `familytree-editors` | `vault-store` | key `familytree/editors` | `familytree-editors` |
| tech-companies | `email-env` | `vault-store` | key `email/env` | `email-env` |
| tech-companies | `email-bulk` | `vault-store` | key `email/bulk` | `email-bulk` |

## 3. Bootstrap admin with edit role OOB (clarification Q3 / D10)

The `admins`/`editors` split MUST be seeded so both reach `SecretSynced=True`.
At least ONE person is provisioned in BOTH `familytree/admins` (admin flag) and
`familytree/editors` — same person = has the edit role out of the box.

- **Source**: OPERATOR-SUPPLIED (familytree auth values are absent from
  Infisical; NFR-004 bars backfill from in-cluster K8s Secrets).
- **Format** (per app `auth-reconcile.js` contract, see `data-model.md` +
  familytree `contracts/re-seed.md`): per-person `_id` file =
  `{"password_hash": "<bcrypt>", "admin": true}`.
- **Commands (operator)**: `vault kv put -mount=secret familytree/admins
  <person_id>='{"password_hash":"<bcrypt>","admin":true}'` and
  `vault kv put -mount=secret familytree/editors <person_id>='{"password_hash":"<bcrypt>","admin":true}'`.
- **Verify**: `familytree-admins` + `familytree-editors` → `SecretSynced=True`.

## 4. Cleanup (clarification Q1 / D11) — delete after verify

Only after analyst/pdf-scan are confirmed synced from `llm/opencode`:

1. Delete dormant paths: `secret/analyst/env`, `secret/pdf-scan/env`
   (`vault kv metadata delete -mount=secret analyst/env`, `pdf-scan/env`).
2. Narrow `eso-reader`: remove `secret/data/analyst/*` + `secret/data/aws/*`
   over-grant (keep `familytree/*`, `email/*`, `llm/data/*`).
3. Retire analyst trust: delete role `es-vault-analyst`
   (`vault delete auth/kubernetes/role/es-vault-analyst`), policy
   `analyst-read-env`, and `SecretStore vault-kubernetes-analyst`
   (kubectl delete) + remove from infra manifests.

**Ordering**: verify-`llm` first → delete dormant paths → narrow policy → retire
analyst trust. Never delete before `llm/opencode` is provably serving both
consumers (FR-008 replacement-source rule).

## 5. Ordering / commit scope

- LiVe mutations are operator-applied behind go/no-go; manifest rewrites stay
  uncommitted until each step is verified.
- Commit scope (FR-011): every repo owning a reorganized ExternalSecret in the
  ArgoCD applicative inventory (`infra/argocd-infra/apps/applicative/*.yaml`) —
  analyst, pdf-scan, aws, familytree, tech-companies. This template repo holds
  the procedure/tooling/verification only.

## 6. Canary (II-1 Blast-Radius Isolation)

- **Canary 1**: analyst → `llm` engine (smallest already-syncing consumer).
  ✅ done live; verify `analyst-secrets` synced from `vault-llm`/`opencode`.
- **Canary 2**: aws → `aws/s3` (irreversible rename). ✅ done live; verify
  `s3-credentials` values byte-identical to the old `aws/env`.
- **Fleet**: pdf-scan → `llm`; familytree env/admins/editors + deploy wiring.

## 7. Failed/partial handling & deferral

- If a step fails mid-way, stop, record the failure (never blind-retry), keep
  the intact source until promotion (FR-008).
- If the familytree `admins`/`editors` seed is deferred by the operator, those
  two ExternalSecrets remain `SecretNotFound` (structure correct) and the 8/8
  gate (SC-001) is not met until seeded — documented, not silently passed.
