# Contract: Vault-Side Trust (014)

Required state the shared `vault-store` ClusterSecretStore depends on **inside
Vault** on `cluster-argo`. Provisioned by the operator in the sibling platform
repos, NOT by this repository. Feature acceptance hard-depends on this state
existing when the store is validated.

## Required Vault State

| Object | Required form | Command reference |
|--------|---------------|-------------------|
| Kubernetes auth mount | `kubernetes` at `auth/kubernetes`, enabled and idempotent (skip if present) | `vault auth enable -path=kubernetes kubernetes` |
| Role `external-secrets` | bound SA `external-secrets`/`external-secrets`; token policy `eso-reader`; bound audience `https://kubernetes.default.svc.cluster.local`; iss validation disabled | `infra/vault/scripts/vault-ops.sh setup-k8s-auth` |
| Policy `eso-reader` | **read-only**, scoped to familytree/email/llm paths (see below) | `infra/vault/scripts/vault-ops.sh setup-policies` |
| `llm` secret engine | KV v2 mounted at `llm`, record `llm/opencode` → `OPENCODE_ZEN_API_KEY` | `vault secrets enable -path=llm kv-v2`; `vault kv put -mount=llm opencode OPENCODE_ZEN_API_KEY=...` |
| `vault-llm` ClusterSecretStore | mirror of `vault-store` but `spec.provider.vault.path: llm`; role `external-secrets`; CA from `vault-tls`/`ca.crt` | manifest `infra/external-secrets/vault-llm-store.yaml` (applied) |

## Policy Scope (FR-003 / SC-004, fleet-wide refinement of 060)

The shared store serves the six `secret`-family ExternalSecrets plus the `llm`
engine. **Post-reorganization** (narrowed, D11):

```hcl
path "secret/data/familytree/*" { capabilities = ["read"] }
path "secret/data/email/*"      { capabilities = ["read"] }
path "llm/data/*"               { capabilities = ["read"] }
```

Writes and other paths MUST be denied. Reads of `secret/data/analyst/*` and
`secret/data/aws/*` through `eso-reader` MUST be **denied** — analyst moved to
the `llm` engine (shared store reads `llm/data/*`), and `aws` is served by the
per-app policy `aws-read-env` scoped to `secret/data/aws/s3/*`.

**Cleanup of retired analyst trust (clarification Q1 / D11):** the per-app
analyst `SecretStore vault-kubernetes-analyst`, kubernetes-auth role
`es-vault-analyst`, and policy `analyst-read-env` MUST be removed — they are no
longer consumed once `analyst-secrets` reads via `vault-llm`. Remove the
`secret/data/analyst/*` + `secret/data/aws/*` over-grant from `eso-reader.hcl`.

## Reconciliation of Infra DRAFT (known drift — do NOT copy)

`infra/external-secrets/vault-store.yaml` (DRAFT) is not the reference: use the
live cluster store's working contract (`vault.vault.svc.cluster.local:8200`,
Secret `vault-tls`/`ca.crt`, no `audiences` override). Reconcile any draft to
match before it can ever be applied.

## Durability (FR-010 / SC-006)

`setup-k8s-auth` MUST be wired into the cluster-recreation path (bootstrap
`argo-bootstrap/lib/vault.sh` or equivalent) so the role + policy are
provisioned on every recreated cluster — never only via an operator-run script
that is easy to forget. 014 verifies this contract exists; the sibling-repo PR
is the implementing change.

### Verified sibling-repo state (2026-09-02, read-only)

| Contract item | Sibling-repo evidence | Verdict |
|---|---|---|
| Role `external-secrets` via `vault-ops.sh setup-k8s-auth` | `infra/vault/scripts/vault-ops.sh` writes role bound to SA `external-secrets`/`external-secrets`, audience `https://kubernetes.default.svc.cluster.local`, `policies=eso-reader`; auth mount enable is guarded (idempotent) | ✅ matches required form |
| Policies via `vault-ops.sh setup-policies` | iterates `$POLICY_DIR/*.hcl`, `vault policy write` (overwrite-in-place) | ✅ idempotent mechanism |
| **`eso-reader` scope** | `infra/vault/policies/eso-reader.hcl` = `path "secret/data/*"` read | ❌ **OVER-BROAD** — violates FR-003/SC-004; MUST be narrowed to familytree/email/`llm/data` scope (and `analyst`/`aws` over-grant removed) BEFORE re-running `setup-policies` |
| Recreation-path wiring | `argo-bootstrap/lib/eso.sh` installs ESO (helm + ArgoCD app) only; NO role/policy provisioning anywhere in `argo-bootstrap` | ❌ NOT WIRED — drift-on-recreation confirmed; sibling PR required (SC-006) |

**Action (operator/sibling)**: (1) narrow `eso-reader.hcl` to
`secret/data/{familytree,email}/*` + `llm/data/*` and remove the
`analyst`/`aws` over-grant; (2) retire `analyst-read-env.hcl` + role
`es-vault-analyst` + `SecretStore vault-kubernetes-analyst` (D11); (3) wire
`setup-k8s-auth` + `setup-policies` into the recreation path; (4) re-run this
repo's quickstart to close out SC-006.

## Idempotency (FR-004 / SC-005)

Re-applying must be safe: `vault auth enable` guarded (already enabled = skip),
role/policy writes overwrite-in-place, no duplicate mounts/roles after a re-run,
and `es-vault` untouched. Cleanup (D11) is a separate, operator-governed removal
of the retired analyst objects — it does not touch `es-vault`.

## Validation (non-destructive first; live steps need operator go/no-go)

See `quickstart.md`. Key checks: `vault auth list` (kubernetes present),
`vault read auth/kubernetes/role/external-secrets` (exists), `vault policy read
eso-reader` (scoped to familytree/email/`llm/data`, read-only), then store(s)
`Ready=True` + 8/8 `SecretSynced=True` with no `UpdateFailed`; confirm
`es-vault-analyst`/`analyst-read-env`/`secret/analyst/env`/`secret/pdf-scan/env`
are gone (D11).

## Cleanup (clarification Q1 / D11)

Confirmed-removed-after-verify: `secret/analyst/env` + `secret/pdf-scan/env`
(dormant duplicates of `llm/opencode`); analyst `SecretStore
vault-kubernetes-analyst`; role `es-vault-analyst`; policy `analyst-read-env`;
`eso-reader` over-grant to `secret/data/analyst/*` + `secret/data/aws/*`.