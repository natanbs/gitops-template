# Quickstart: 014 — Vault↔ESO Trust Restoration & Secret Reorganization

Non-destructive-first validation guide for the operator/reviewer. Agents do not
execute `kubectl`/`vault`; steps are run by the operator. Any live,
state-changing step requires explicit operator go/no-go (see
`contracts/vault-trust.md` and `contracts/migration.md`).

## Prerequisites

- Kubeconfig for `k3d-cluster-argo`; `kubectl` and `vault` CLIs available to the
  operator.
- Live Vault access: `kubectl -n vault exec vault-0 -- vault ...` OR
  `kubectl -n vault port-forward service/vault-active 8200:8200` plus a token.
  The local `vault` binary alone is a stub (`127.0.0.1:8200` refused) — never
  use it as the backend.
- `vault-ops.sh` available in `infra/vault/scripts` (sibling repo) with a
  working token.
- No secret values are read, printed, or committed at any point; only paths/keys.
- **Operator scratch (never committed)**: `/tmp/014/` for baselines/diffs.

## Step 0 — Baseline: capture current state (non-destructive)

```bash
kubectl -n external-secrets get clustersecretstore -o name
kubectl -n external-secrets get clustersecretstore vault-store vault-llm -o jsonpath='{range .items[*]}{.metadata.name}::{.status.conditions[?(@.type=="Ready")].status}{"\n"}{end}'
kubectl -n apps-ns get externalsecrets -o jsonpath='{range .items[*]}{.metadata.name}::{.status.conditions[?(@.type=="Ready")].status}{"\n"}{end}'
kubectl -n apps-ns get events --field-selector reason=UpdateFailed
```

Expected (trust restored): both stores `Ready=True`; analyst-secrets,
s3-credentials, email-env, email-bulk, familytree-email `True`; familytree-env,
familytree-admins, familytree-editors, pdf-scan-env state depends on seed/rework.

## Step 1 — Confirm Vault trust + reorg data (read-only, operator)

```bash
kubectl -n vault exec vault-0 -- vault auth list
kubectl -n vault exec vault-0 -- vault read auth/kubernetes/role/external-secrets
kubectl -n vault exec vault-0 -- vault policy read eso-reader
kubectl -n vault exec vault-0 -- vault kv list -mount=secret
kubectl -n vault exec vault-0 -- vault kv list -mount=llm
```

Expected: role `external-secrets` exists; `eso-reader` scoped to
familytree/email/`llm/data` (no analyst/aws over-grant after cleanup, D11);
`secret/` contains analyst/env*, email/*, familytree/env + admins/editors,
aws/s3; `llm/` contains `opencode`. Any drift (e.g. `aws/env` still referenced,
`eso-reader` over-broad) is a `fix:` remediation.

## Step 2 — Verify `llm` engine + `vault-llm` store (already applied live)

```bash
kubectl wait --for=condition=Ready --timeout=120s clustersecretstore/vault-llm -n external-secrets
kubectl wait --for=condition=SecretSynced --timeout=120s externalsecret/analyst-secrets externalsecret/pdf-scan-env -n apps-ns
```

Expected: `vault-llm` `Ready=True`; `analyst-secrets` (key `OPENCODE_ZEN_API_KEY`)
and `pdf-scan-env` (secretKey `LLM_API_KEY`) both `SecretSynced=True` from
`llm/opencode` via property mapping.

## Step 3 — Verify `aws`→`aws/s3` rename (already applied live)

```bash
kubectl wait --for=condition=SecretSynced --timeout=120s externalsecret/s3-credentials -n apps-ns
kubectl -n vault exec vault-0 -- vault kv get -mount=secret aws/s3   # read-only; values NOT printed
kubectl -n vault exec vault-0 -- vault kv list -mount=secret          # confirm aws/env ABSENT
```

Expected: `s3-credentials` synced from `aws/s3`; `aws/env` deleted (only
`aws/s3` exists); values byte-identical to the old `aws/env` (SC-009).

## Step 4 — Familytree rework + bootstrap-admin seed (go/no-go, state-changing)

1. Rewrite `familytree/k8s/external-secret.yaml` → three resources: flat
   `familytree/env` + properties (SESSION_SECRET, WAHA_URL, WAHA_API_KEY) →
   target `familytree-env`; plus `familytree-admins` and `familytree-editors`
   ExternalSecrets → targets `familytree-admins`/`familytree-editors` (keys
   `familytree/admins`, `familytree/editors` via `dataFrom.extract`). Drop the
   dedicated `familytree-email` sync and remove the superseded
   `external-secret-auth.yaml` (single `familytree-auth` group).
2. Update `familytree/k8s/deploy.yaml`: replace `familytree-email` refs with the
   shared `email-env`; add OPTIONAL volume mounts + env refs for
   `familytree-admins`/`familytree-editors` (non-blocking if empty).
3. **Seed** `familytree/admins` + `familytree/editors` with at least one
   operator-supplied bootstrap admin (same person in BOTH groups = edit role
   OOB), per `contracts/migration.md` §3.
4. Apply + ArgoCD-sync; verify:
   ```bash
   kubectl wait --for=condition=SecretSynced --timeout=120s \
     externalsecret/familytree-env externalsecret/familytree-admins externalsecret/familytree-editors -n apps-ns
   kubectl -n apps-ns get deploy -l app=familytree -o jsonpath='{.items[0].spec.template.spec.volumes[*].secret.secretName}'
   ```

Expected: three familytree ExternalSecrets `SecretSynced=True`; deploy mounts
`email-env` + optional admins/editors volumes; pods healthy.

## Step 5 — Cleanup (go/no-go, delete-after-verify; D11)

Only after Step 2 confirms `llm/opencode` serves both analyst + pdf-scan:

```bash
kubectl -n vault exec vault-0 -- vault kv metadata delete -mount=secret analyst/env
kubectl -n vault exec vault-0 -- vault kv metadata delete -mount=secret pdf-scan/env
kubectl -n vault exec vault-0 -- vault delete auth/kubernetes/role/es-vault-analyst
kubectl -n vault exec vault-0 -- vault policy delete analyst-read-env
kubectl -n external-secrets delete secretstore vault-kubernetes-analyst   # or via infra manifest if namespaced
```

Narrow `eso-reader.hcl` (sibling repo) to `familytree/*`, `email/*`, `llm/data/*`
and remove `analyst`/`aws` over-grant; re-run `setup-policies`. Verify:
`secret/analyst/env`, `secret/pdf-scan/env`, `es-vault-analyst`,
`analyst-read-env` all absent (SC-010).

## Step 6 — Byte equality + least-privilege (SC-003/004)

```bash
# equality (apply meat of the reorg between snapshots)
kubectl -n apps-ns get secret s3-credentials -o yaml > /tmp/014/before.yaml
# ... run Steps 2–5 ...
kubectl -n apps-ns get secret s3-credentials -o yaml > /tmp/014/after.yaml
diff /tmp/014/before.yaml /tmp/014/after.yaml        # expect: identical

kubectl -n vault exec vault-0 -- vault kv put -mount=secret email/env junk=x        # expect: denied (write)
kubectl -n vault exec vault-0 -- vault kv get -mount=secret analyst/env             # expect: denied / absent (cleanup)
```

Out-of-scope reads and all writes must be denied.

## Step 7 — Idempotency / stability / durability (SC-005/006/013)

- Re-run `setup-k8s-auth`; expect no duplicates; `es-vault` untouched;
  `es-vault-analyst` NOT recreated.
- Observe zero `UpdateFailed` across ≥ 15 min (two refresh cycles).
- Confirmed `eso-reader.hcl` (sibling) is narrowed and `setup-k8s-auth` +
  `setup-policies` are wired into the recreation path (SC-006/FR-013).

## Step 8 — Final 8/8 gate + commit

```bash
kubectl -n apps-ns get externalsecrets -o jsonpath='{range .items[*]}{.metadata.name}::{.status.conditions[?(@.type=="Ready")].status}{"\n"}{end}'
```

Expected: 8/8 `SecretSynced=True` (analyst-secrets, s3-credentials, email-env,
email-bulk, familytree-env, familytree-admins, familytree-editors, pdf-scan-env).
Commit the rewritten manifests per repo (FR-011) after verification.

## Success Criteria (traceability)

| Requirement | Where verified |
|---|---|
| FR-001/002 k8s-auth login succeeds with role `external-secrets` | Step 1 + Step 2 (Ready) |
| FR-003 least-privilege, writes denied, analyst/aws over-grant removed | Step 6 + Step 5 |
| FR-004/SC-005 idempotent provisioning | Step 7 |
| FR-005/SC-001 8/8 synced, zero errors 2 cycles | Step 4 + Step 8 |
| FR-007/FR-009 `vault-llm` serves analyst + pdf-scan (`llm/opencode`) | Step 2 |
| FR-008/FR-009a familytree `email-env` + admins/editors split + OOB admin seed | Step 4 |
| FR-010 `aws`→`aws/s3`, byte-identical | Step 3 + Step 6 |
| SC-002 store(s) Ready | Step 0/2/3 |
| SC-003 byte-identical values | Step 6 (diff) |
| SC-004 no unapproved writes / no data loss | Step 0 + Step 6 |
| SC-006/FR-013 durable recreation contract | Step 7 |
| SC-010 cleanup complete (analyst trust + dormant paths gone) | Step 5 |
