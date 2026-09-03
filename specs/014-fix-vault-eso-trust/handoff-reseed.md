# Operator handoff — Infisical re-seed (Trust FIXED, Data MISSING)

## State
- Vault↔ESO trust is **fixed**: `vault-store` = `Valid | store validated`.
  Role `external-secrets` + policy `eso-reader` (secret/data/{familytree,email,pdf-scan}/* = read) are
  provisioned. The 6 broken ExternalSecrets now fail on **missing source data**, not auth.
- Vault `secret/` currently contains ONLY `analyst/env` and `aws/env`. No email/familytree/pdf-scan paths.

## What to seed (flat paths the LIVE cluster reads TODAY)
Verified directly from the live ExternalSecrets (not git — git manifests are the nested post-migration layout):

| Vault path | Keys | Consumers |
|-----------|------|-----------|
| `email/env` | `SMTP_HOST`, `SMTP_PORT`, `SMTP_USER`, `SMTP_PASS`, `SMTP_FROM` | `email-env`, `familytree-email` |
| `email/bulk` | `TINYVALIDATOR_API_KEY`, `MAILBOXLAYER_API_KEY`, `HUNTER_API_KEY` | `email-bulk` |
| `familytree/env` | `SESSION_SECRET`, `WAHA_URL`, `WAHA_API_KEY` | `familytree-env` |
| `familytree/auth` | JSON claims (`password_hash`/`admin` per person) | `familytree-auth` |
| `pdf-scan/env` | `LLM_API_KEY` | `pdf-scan-env` |

Source = **Infisical** (contract `re-seed.md`, NFR-004 — never from git or in-cluster K8s Secrets).

## Commands (operator, from outside this agent's shell)
Uses the port-forward (`kubectl -n vault port-forward service/vault-active 8200:8200`) and root token from
`infra/vault/init.json`:

```
export VAULT_ADDR=https://127.0.0.1:8200 VAULT_TOKEN=<root-token> VAULT_SKIP_VERIFY=true
vault kv put secret/email/env     SMTP_HOST=... SMTP_PORT=... SMTP_USER=... SMTP_PASS=... SMTP_FROM=...
vault kv put secret/email/bulk    TINYVALIDATOR_API_KEY=... MAILBOXLAYER_API_KEY=... HUNTER_API_KEY=...
vault kv put secret/familytree/env SESSION_SECRET=... WAHA_URL=... WAHA_API_KEY=...
vault kv put secret/familytree/auth @auth-claims.json       # extract dataFrom
vault kv put secret/pdf-scan/env  LLM_API_KEY=...
```

## After seeding
- Reconcile = 60s (familytree-auth) / 1h (others); notify to force-sync the 6 if not auto-recovered.
- The `eso-reader` policy wildcards already cover all these paths — no policy change needed.
- Then this feature resumes: verify 8/8 (T008 → full), T010/T011/T012, migration (T014–T018).
## UPDATE (2026-09-02) — seeder executed
Email paths were seeded from Infisical (Emails project, dev):
- `secret/email/env` + `secret/email/bulk` + `secret/analyst/env` written.
- 5/8 ExternalSecrets now `True`: analyst-secrets, s3-credentials, email-env,
  email-bulk, familytree-email.

## STILL REQUIRED (values absent from Infisical)
These source groups do NOT exist in the Infisical org reachable by the token.
Add them to Infisical, then re-seed to Vault to reach 8/8:
- `secret/familytree/env` ← SESSION_SECRET, WAHA_URL, WAHA_API_KEY
- `secret/familytree/auth` ← JSON claims (password_hash/admin)
- `secret/pdf-scan/env` ← LLM_API_KEY
