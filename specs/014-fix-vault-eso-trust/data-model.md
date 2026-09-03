# Data Model: Vault↔ESO Secret Trust Restoration & Fleet Secret Reorganization

Phase 1 output — entities, fields, relationships, and state transitions for the
Vault↔ESO trust restoration, the 5-part secret-engine reorganization (shared
`llm` engine, familytree `email-env` + `admins`/`editors` split, WAHA
placeholders, `aws`→`aws/s3` rename), and full cleanup.

---

## Entities

### SecretEngine (Vault mount)

A KV v2 secret engine mounted in Vault, referenced by store `path`.

| Field | Type | Description |
|-------|------|-------------|
| `mount` | string | `secret` (original) and `llm` (new shared engine) |
| `version` | string | `v2` |
| `purpose` | string | `secret` = general fleet secrets; `llm` = shared LLM API keys |
| `records` | string[] | `secret`: `/env`, `/aws/s3`, `/email/*`, `/familytree/*`, `/pdf-scan/env`; `llm`: `/opencode` |

**Validation**: stores are mount-bound via `path:` — a store configured with
`path: secret` CANNOT read the `llm/` mount; a dedicated `path: llm` store is
required.

---

### VaultClusterStore

The cluster-scoped ESO stores that ExternalSecrets reference.

| Field | Type | Description |
|-------|------|-------------|
| `name` | string | `vault-store` (path `secret`) / `vault-llm` (path `llm`) |
| `provider` | enum | `vault` |
| `server` | string | `https://vault.vault.svc.cluster.local:8200` (SAN-valid) |
| `path` | string | `secret` (vault-store) / `llm` (vault-llm) |
| `version` | string | `v2` |
| `mountPath` | string | `kubernetes` |
| `role` | string | `external-secrets` |
| `serviceAccountRef` | string | `external-secrets`/`external-secrets` |
| `refreshInterval` | string | `60` (current) → `3600` (remediation; match ExternalSecret refresh) |
| `statusCondition` | string | `Ready=True` (both stores verified) |

**Validation rule**: server hostname in Vault cert SANs; CA via Secret
`vault-tls`/`ca.crt`; audiences unset (working pattern). `vault-llm` mirrors
`vault-store` except `path: llm`.

---

### VaultAuthRole

A Kubernetes-auth role on the Vault `kubernetes` mount.

| Field | Type | Description |
|-------|------|-------------|
| `name` | string | `external-secrets` (shared) / `es-vault` (healthy, stays) / `es-vault-analyst` (RETIRED D11) |
| `boundServiceAccountNames` | string[] | `external-secrets` for the shared role |
| `boundServiceAccountNamespaces` | string[] | `external-secrets` |
| `tokenPolicies` | string[] | `eso-reader` for the shared role |
| `tokenBoundAudiences` | string[] | `https://kubernetes.default.svc.cluster.local` |
| `boundIssuer` / `disable_iss_validation` | bool | `disable_iss_validation=true` |
| `provisionedOn` | string | `setup-k8s-auth` (operator) |

**Idempotency**: re-running `setup-k8s-auth` overwrites in place, never
duplicates mounts/roles. **Cleanup**: `es-vault-analyst` is deleted (D11).

---

### VaultPolicy

ACL policy scoping secret reads.

| Field | Type | Description |
|-------|------|-------------|
| `name` | string | `eso-reader` (shared) / `aws-read-env` (per-app) / `analyst-read-env` (RETIRED D11) |
| `scopedPaths` | string[] | `eso-reader`: `secret/data/familytree/*`, `secret/data/email/*`, `llm/data/*` (narrowed, D11); `aws-read-env`: `secret/data/aws/s3/*` |
| `capabilities` | enum[] | `read` only (writes denied) |
| `leafPathCoverage` | bool | covers property suffixes under consumed paths |

**Constraints**: reads confined to consumed paths (FR-003); writes denied;
out-of-scope reads (analyst/aws via `eso-reader`) denied. **Cleanup**: remove the
`secret/data/analyst/*` + `secret/data/aws/*` over-grant from `eso-reader` (D11).

---

### SecretEngineRecord (KV key)

A single KV record under a mount.

| Field | Type | Description |
|-------|------|-------------|
| `engine` | FK → SecretEngine | `secret` or `llm` |
| `path` | string | stable path (mount-relative), e.g. `familytree/env`, `aws/s3`, `llm/opencode` |
| `properties` | string[] | KV fields, e.g. `llm/opencode` → `OPENCODE_ZEN_API_KEY` |
| `source` | enum | `infisical` / `operator-approved-placeholder` / `operator-supplied-seed` / `copied` |
| `retired` | bool | true for paths deleted in cleanup (`secret/analyst/env`, `secret/pdf-scan/env`) |

---

### ExternalSecret

One of eight ESO resources mapping backend paths to synced Secrets.

| Field | Type | Description |
|-------|------|-------------|
| `name` | string | `analyst-secrets`, `s3-credentials`, `familytree-env`, `familytree-admins`, `familytree-editors`, `email-env`, `email-bulk`, `pdf-scan-env` |
| `storeRef` | string | FK → VaultClusterStore (`vault-store` or `vault-llm`) |
| `remoteRefs` | SecretRef[] | `remoteRef.key` / `.property` and `dataFrom[].extract.key` |
| `ownerRepo` | string | FK → FleetApp (analyst, aws, familytree, pdf-scan, tech-companies) |
| `syncStatus` | enum | `SecretSynced` (target 8/8) / `SecretNotFound` (awaiting seed) / `SecretSyncedError` |
| `refreshInterval` | string | `1h` |

---

### SecretRef (remote key)

The path/property reference inside one ExternalSecret entry.

| Field | Type | Description |
|-------|------|-------------|
| `file` | string | `k8s/external-secret-*.yaml` |
| `key` | string | mount-relative remote path, e.g. `opencode` (via `vault-llm`), `aws/s3` |
| `property` | string? | the KV field, for `key` kinds |
| `secretKey` | string | the K8s Secret key produced (analyst `OPENCODE_ZEN_API_KEY`; pdf-scan `LLM_API_KEY`) |
| `target` | string | synced Secret name (`analyst-secrets`, `pdf-scan-env`, `s3-credentials`, …) |

---

### FamilytreeRoleGroup

The role-based split of familytree auth.

| Field | Type | Description |
|-------|------|-------------|
| `group` | enum | `admins` / `editors` |
| `vaultPath` | string | `familytree/admins` / `familytree/editors` |
| `syncedSecret` | string | `familytree-admins` / `familytree-editors` |
| `appConsumption` | string | OPTIONAL volume mount + env ref (non-blocking if empty); app reads single-dir `AUTH_SECRET_DIR` |
| `person` | string | a person `_id`; the bootstrap admin appears in BOTH groups (has edit role OOB) |

---

## State Transitions

### VaultClusterStore lifecycle

```
[Broken: InvalidProviderConfig]            (vault-store, pre-trust)
    ↓ (Vault-side role + policy provisioned, D3)
[Ready=True — path secret]                  ✅ verified
[New: vault-llm — path llm]                 ✅ created + applied, Ready=True
```

### ExternalSecret lifecycle

```
[SecretSyncedError / could not get secret data]
    ↓ (store Ready + source data present)
[SecretSynced]      — analyst-secrets, s3-credentials, email-env, email-bulk, familytree-email
    ↓ (llm engine + aws/s3 reorg, D7/D9)
[SecretSynced]      — analyst-secrets, pdf-scan-env (via vault-llm/opencode); s3-credentials (aws/s3)
    ↓ (familytree rework + bootstrap-admin seed, D10)
[SecretSynced]      — familytree-env (placeholders), familytree-admins, familytree-editors
    ↓ (MUST hold across ≥ 2 refresh cycles)
[Stable]            — zero UpdateFailed / 403 (SC-001/SC-003)
```

### Secret value lifecycle

```
[Intact at old source path]            — source of truth (FR-008)
    ↓ (llm engine: llm/opencode ← secret/analyst/env OPENCODE_ZEN_API_KEY)
[Intact at llm/opencode]               — served to analyst + pdf-scan (DRY, D8)
    ↓ (aws→aws/s3 copy + delete; values verified)
[Intact at aws/s3]                     — s3-credentials source
    ↓ (cleanup, D11 — only after verify)
[secret/analyst/env, secret/pdf-scan/env DELETED]  — dormant duplicates removed
```

### Policy coverage lifecycle

```
[Missing/broad: secret/data/*]         — pre-trust (FR-003 violation)
    ↓ (trust restoration, D3)
[Confined: familytree/*, email/*, pdf-scan/*]     — pre-reorg
    ↓ (llm engine + reorg, D7/D11)
[Narrowed: familytree/*, email/*, llm/data/*]     — eso-reader (analyst/aws over-grant REMOVED)
[Narrowed: aws/s3/*]                   — aws-read-env after the rename
```

---

## Relationships

- `SecretEngine` (1) —→ (N) `SecretEngineRecord` via `engine`.
- `VaultClusterStore` (1) —→ (1) `SecretEngine` via `path` (mount-bound).
- `VaultClusterStore` (1) —→ (N) `ExternalSecret` via `storeRef` (8 of 8; no
  per-app SecretStore remains after analyst retirement).
- `ExternalSecret` (N) —→ (1) `SecretEngineRecord` via `SecretRef.key`.
- `ExternalSecret` (1) —→ (N) `SecretRef` (remote keys/properties).
- `ExternalSecret` (N) —→ (1) `FleetApp` (owner repo).
- `VaultAuthRole` (N) —→ (N) `VaultPolicy` (role binds policy; policy scopes reads).
- `FamilytreeRoleGroup` (N) —→ (1) `SecretEngineRecord` (`familytree/admins`/`editors`).
- `VaultPolicy.scopedPaths` are leaf-relative to `VaultClusterStore.path`
  (KV v2 → `secret/data/...` / `llm/data/...`).
