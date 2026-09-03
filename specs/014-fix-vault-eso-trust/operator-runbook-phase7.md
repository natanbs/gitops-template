# Operator Runbook — Phase 7: Convergence (T029–T034)

Live-cluster / Vault / git steps are operator-governed per Constitution Human-Oversight.
The agent has staged and validated everything it can. The operator executes these in order:
**T030 (seed) → T029 (apply) → T031+T033 (verify) → T032 (cleanup) → T034 (commit)**.

> T030 is the critical path: until the bootstrap admin is seeded, `familytree-admins` /
> `familytree-editors` cannot report `SecretSynced=True` and the SC-001 8/8 gate stays red.

## Prereqs (every step)

```bash
# Vault access
kubectl -n vault port-forward service/vault-active 8200:8200 &
export VAULT_ADDR=https://127.0.0.1:8200 VAULT_SKIP_VERIFY=true
export VAULT_TOKEN="$(cat /Users/natan/projects/repos/infra/vault/init.json | jq -r '.root_token')"
```

---

## T030 — Seed bootstrap admin (unblocks the 8/8 gate)

> **NFR-004**: values come from the operator / Infisical — **never** backfilled from
> in-cluster Secrets. The operator supplies bootstrap credentials OOB (same person holds
> both roles: admin + edit).

A per-person claim is one key under the path, value = JSON `{"password_hash": "...", "admin": true/false}`.

```bash
# Create both dirs (idempotent) then seed one shared bootstrap member into BOTH groups.
vault kv put -mount=secret familytree/admins/bootstrapper \
  password_hash="<OPERATOR_SUPPLIED_BCRYPT_HASH>" admin="true"

vault kv put -mount=secret familytree/editors/bootstrapper \
  password_hash="<SAME_OPERATOR_SUPPLIED_BCRYPT_HASH>" admin="true"

# Confirm
vault kv get -mount=secret familytree/admins/bootstrapper
vault kv get -mount=secret familytree/editors/bootstrapper
```

> One shared member in both groups satisfies the clarify Q3 requirement (bootstrap admin
> also holds the edit role, seeded OOB). Until real users land, only this seed exists.

---

## T029 — Apply + ArgoCD-sync the FLEET rework (not just familytree)

> **CRITICAL — accurate live baseline (read-only probe, 2026-09-02)**: the cluster is
> currently running the **OLD pre-reorg fleet, 4/8 synced**. Live stores confirmed:
> `analyst-secrets`→`vault-kubernetes-analyst` (False), `s3-credentials`→`vault-kubernetes`
> (False), `familytree-auth` (False), `familytree-email` (True), `pdf-scan-env`→`vault-store`
> (False), `familytree-env` (True), `email-env` (True), `email-bulk` (True).
> **None of the rewritten manifests are applied yet.** So T029 must apply the whole fleet,
> not just the familytree rework.

**Go/no-go is on the `AUTH_SECRET_DIR` mapping decision**: the app's single-dir
`AUTH_SECRET_DIR` now points at the `familytree-admins` volume
(`/etc/secrets/familytree-admins`), plus a new optional
`FAMILYTREE_EDITORS_DIR=/etc/secrets/familytree-editors`.

```bash
cd /Users/natan/projects/repos/familytree

# 0) Remove operator scratch .bak files before apply (never committed)
rm -f k8s/external-secret-auth.yaml.bak k8s/external-secret.yaml.bak

# 1) Review staged deltas across the fleet
for r in familytree analyst aws pdf-scan tech-companies; do
  (cd /Users/natan/projects/repos/$r && git diff --cached --stat)
done

# 2) Apply ALL FOUR rewritten ES manifests + the familytree deploy rework
kubectl apply -n apps-ns -f k8s/external-secret.yaml -f k8s/deploy.yaml       # familytree
kubectl apply -n apps-ns -f /Users/natan/projects/repos/analyst/k8s/external-secret.yaml   # -> vault-llm/opencode
kubectl apply -n apps-ns -f /Users/natan/projects/repos/aws/k8s/external-secret.yaml       # -> vault-kubernetes, reads aws/s3
kubectl apply -n apps-ns -f /Users/natan/projects/repos/pdf-scan/k8s/external-secret.yaml  # -> vault-llm/opencode

# 3) The old single-name ES resources must be removed (superseded):
kubectl -n apps-ns delete externalsecret familytree-auth familytree-email --ignore-not-found
```

If ArgoCD owns the namespace, sync each applicative app instead of raw `kubectl apply`:

```bash
cd /Users/natan/projects/repos/infra
for app in familytree analyst aws pdf-scan tech-companies; do
  argo app sync $app --repo server
  argo app wait $app --operation
done
# Do NOT commit here — commits are T034.
```

Verify the fleet sync status:

```bash
kubectl -n apps-ns get externalsecret \
  -o custom-columns=NAME:.metadata.name,TARGET:.spec.target.name,STORE:.spec.secretStoreRef.name,SYNCED:.status.conditions[0].status
```

---

## T031 — Verify 8/8 synced across ≥2 cycles

Wait at least two reconcile cycles (default interval), then assert all 8:

```bash
kubectl -n apps-ns get externalsecret \
  -o custom-columns=NAME:.metadata.name,TARGET:.spec.target.name,STORE:.spec.secretStoreRef.name,SYNCED:.status.conditions[0].status

# Expect 8/8 SYNCED:
#   analyst-secrets, email-env (tech-companies), email-bulk (tech-companies),
#   familytree-env, familytree-admins, familytree-editors,
#   pdf-scan-env, s3-credentials
```

> `familytree-admins`/`familytree-editors` can only report `True` **after** T030 seeds
> the bootstrap member; the old `familytree-auth`/`familytree-email` must be gone (T029 step 3).
> `analyst-secrets`/`pdf-scan-env` must now cite store `vault-llm`; `s3-credentials` stays
> on `vault-kubernetes` reading `aws/s3`.

---

## T033 — Byte-equality + least-privilege re-verify

Byte-equality: the synced `familytree-env` target must match the expected Vault values and
the app's env contract (SESSION_SECRET, WAHA_URL, WAHA_API_KEY):

```bash
vault kv get -mount=secret familytree/env
kubectl -n apps-ns get secret familytree-env -o json | \
  python3 -c 'import json,sys,base64
d=json.load(sys.stdin)
for k,v in sorted(d["data"].items()):
    print(k,"=",base64.b64decode(v).decode())'
```

Least-privilege (pre-cleanup sanity): read the effective `eso-reader` scope from
`vault/policies/eso-reader.hcl` and confirm it covers only `familytree/*, email/*, llm/data/*`.

---

## T032 — Cleanup (destructive → operator go/no-go)

### 4a. Delete dormant Vault paths
```bash
vault kv delete -mount=secret analyst/env   # dormant (retired analyst store)
vault kv delete -mount=secret pdf-scan/env  # dormant (superseded by llm/data)
```

### 4b. Narrow `eso-reader` to `familytree/*, email/*, llm/data/*`
Replace `vault/policies/eso-reader.hcl` and re-push (matches the `contracts/vault-trust.md` scope):

```bash
cat > /Users/natan/projects/repos/infra/vault/policies/eso-reader.hcl << 'INNER'
path "secret/data/familytree/*" { capabilities = ["read"] }
path "secret/data/email/*"      { capabilities = ["read"] }
path "llm/data/*"               { capabilities = ["read"] }
INNER
vault policy write eso-reader /Users/natan/projects/repos/infra/vault/policies/eso-reader.hcl
```

### 4c. Retire the analyst trust (live-only artifacts)
```bash
vault delete auth/kubernetes/role/es-vault-analyst   # analyst k8s-auth role
vault policy delete analyst-read-env                  # per-app analyst policy
# Namespace: delete the analyst SecretStore vault-kubernetes-analyst + its ExternalSecret is
# already rewritten to vault-llm/opencode (no live delete needed for the ES itself).
kubectl -n apps-ns delete secretstore vault-kubernetes-analyst --ignore-not-found
```

> If `vault-kubernetes-analyst` / `es-vault-analyst` / `analyst-read-env.hcl` don't exist
> live (they were not found under infra source), skip the corresponding `vault delete` —
> they may already be gone. Confirm with `vault list auth/kubernetes/role` /
> `vault policy list` first.

---

## T034 — Commit rewritten manifests per inventory

Committed per the ArgoCD applicative inventory (each app in its own repo, appPath `k8s`):

```bash
# familytree
cd /Users/natan/projects/repos/familytree
git add k8s/external-secret.yaml k8s/deploy.yaml
git rm -f k8s/external-secret-auth.yaml
git commit -m "014: rework familytree ESO (env+admins+editors), email-env shared, drop auth ES"
git push

# analyst / aws / pdf-scan (already rewritten to vault-llm | aws/s3 — commit them)
cd /Users/natan/projects/repos/analyst    && git add k8s/external-secret.yaml && git commit -m "014: ESO -> vault-llm/opencode" && git push
cd /Users/natan/projects/repos/aws         && git add k8s/external-secret.yaml && git commit -m "014: ESO -> aws/s3 + property" && git push
cd /Users/natan/projects/repos/pdf-scan    && git add k8s/external-secret.yaml && git commit -m "014: ESO -> vault-llm/opencode (LLM_API_KEY)" && git push
```

> ArgoCD auto-sync (or a manual sync) will reconcile the rewritten ES across the fleet once pushed.
> Do not commit the policy/hcl files unless infra repo governance requires it — commit only
> application manifests per the applicative inventory.

---

## Post-completion handoff

After T030→T033 pass and T034 is pushed, inform the agent to run `/spec.implement`
(mark T029–T034 done) then `/spec.converge`, which will report **converged** and run the
Test Gate → Diff → 4-Pillar → `verify.md` phases.