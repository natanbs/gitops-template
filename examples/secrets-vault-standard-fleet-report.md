# Secrets & Vault Standard Fleet Report

**Standard**: secrets-vault-standard v1.0.0
**Inventory**: specs/013-secrets-vault-standard/checklists/fixture-inventory
**Date**: 2026-09-01T09:27:42Z
**Scan scope**: appPath only (add --scan-root to include repo-root config files)

## Fleet Summary

| Verdict | Count |
|---------|-------|
| CONFORMING | 2 |
| NON-CONFORMING | 4 |
| N/A | 1 |
| UNKNOWN | 1 |
| **Total** | **8** |

**Exit code**: 1

## Per-Repo Results

### conformant-cluster-store — CONFORMING

| Rule | Verdict | Evidence | Fix |
|------|---------|----------|-----|
| VS-001 | N/A | consumes external ClusterSecretStore (no own store); reference confirmed in fleet | - |
| VS-002 | N/A | consumes external store; auth method governed at the store declaration repo | - |
| VS-003 | PASS | ExternalSecret(s) reference known store(s):vault-cluster-store | - |
| VS-004 | PASS | 1 path(s) follow /<env>/<service>/<key> | - |
| VS-005 | PASS | 1 secret(s) consumed via secretKeyRef/envFrom from ExternalSecret-created Secrets | - |
| VS-006 | PASS | no committed secret patterns in tracked files | - |
| VS-007 | PASS | no static Vault tokens (s.<token>, VAULT_TOKEN, vault login, vault.token) | - |

### conformant-vault-eso — CONFORMING

| Rule | Verdict | Evidence | Fix |
|------|---------|----------|-----|
| VS-001 | PASS | secrets-vault-standard/fixtures/conformant-vault-eso/k8s/secret-store.yaml: provider.vault | - |
| VS-002 | PASS | provider.vault.auth.kubernetes present (role + mountPath) | - |
| VS-003 | PASS | ExternalSecret(s) reference known store(s):vault-store | - |
| VS-004 | PASS | 1 path(s) follow /<env>/<service>/<key> | - |
| VS-005 | PASS | 1 secret(s) consumed via secretKeyRef/envFrom from ExternalSecret-created Secrets | - |
| VS-006 | PASS | no committed secret patterns in tracked files | - |
| VS-007 | PASS | no static Vault tokens (s.<token>, VAULT_TOKEN, vault login, vault.token) | - |

### na-no-secrets — N/A

| Rule | Verdict | Evidence | Fix |
|------|---------|----------|-----|
| VS-001 | N/A | no secrets infrastructure (Vault store rule not applicable) | - |
| VS-002 | N/A | no store declared (auth rule not applicable) | - |
| VS-003 | N/A | no secrets infrastructure (ExternalSecret rule not applicable) | - |
| VS-004 | N/A | no ExternalSecret remoteRef paths to validate | - |
| VS-005 | N/A | no secrets consumed by Deployment/CronJob to validate | - |
| VS-006 | PASS | no committed secret patterns in tracked files | - |
| VS-007 | PASS | no static Vault tokens (s.<token>, VAULT_TOKEN, vault login, vault.token) | - |

### non-conformant-hardcoded — NON-CONFORMING

| Rule | Verdict | Evidence | Fix |
|------|---------|----------|-----|
| VS-001 | PASS | secrets-vault-standard/fixtures/non-conformant-hardcoded/k8s/secret-store.yaml: provider.vault | - |
| VS-002 | PASS | provider.vault.auth.kubernetes present (role + mountPath) | - |
| VS-003 | PASS | ExternalSecret(s) reference known store(s):vault-store | - |
| VS-004 | PASS | 1 path(s) follow /<env>/<service>/<key> | - |
| VS-005 | N/A | no Deployment/CronJob consuming secrets to validate | - |
| VS-006 | FAIL | 1 committed secret pattern(s) in tracked files (e.g. secrets-vault-standard/fixtures/non-conformant-hardcoded/k8s/config.toml:2: bcrypt hash) | fix: Remove committed bcrypt hash from the tracked file; add it to .gitignore; manage via Vault/ESO at runtime |
| VS-007 | PASS | no static Vault tokens (s.<token>, VAULT_TOKEN, vault login, vault.token) | - |

### non-conformant-no-vault — NON-CONFORMING

| Rule | Verdict | Evidence | Fix |
|------|---------|----------|-----|
| VS-001 | FAIL | manual kind: Secret present but no Vault-backed store declared (secrets not sourced from Vault) | fix: Replace the manual Secret with a Vault-backed SecretStore/ClusterSecretStore + ExternalSecret |
| VS-002 | FAIL | manual Secret present but no Vault store with Kubernetes auth | fix: Replace static token auth with Kubernetes auth: provider.vault.auth.kubernetes.role: <role> + mountPath: /v1/auth/kubernetes |
| VS-003 | FAIL | manual kind: Secret present instead of an ExternalSecret (not sourced from Vault standard) | fix: Add an ExternalSecret that references the Vault-backed store and maps Vault KV paths to K8s Secret keys |
| VS-004 | N/A | no ExternalSecret remoteRef paths to validate | - |
| VS-005 | FAIL | deployment.yaml: secret 'web-app-manual-secret' consumed via secretKeyRef but not created by an ExternalSecret | fix: Wire Deployment/CronJob env to the ExternalSecret-created Secret via secretKeyRef or envFrom.secretRef |
| VS-006 | PASS | no committed secret patterns in tracked files | - |
| VS-007 | PASS | no static Vault tokens (s.<token>, VAULT_TOKEN, vault login, vault.token) | - |

### non-conformant-static-token — NON-CONFORMING

| Rule | Verdict | Evidence | Fix |
|------|---------|----------|-----|
| VS-001 | PASS | secrets-vault-standard/fixtures/non-conformant-static-token/k8s/secret-store.yaml: provider.vault | - |
| VS-002 | PASS | provider.vault.auth.kubernetes present (role + mountPath) | - |
| VS-003 | PASS | ExternalSecret(s) reference known store(s):vault-store | - |
| VS-004 | PASS | 1 path(s) follow /<env>/<service>/<key> | - |
| VS-005 | N/A | no Deployment/CronJob consuming secrets to validate | - |
| VS-006 | PASS | no committed secret patterns in tracked files | - |
| VS-007 | FAIL | 1 static Vault token pattern(s) in tracked files (e.g. secrets-vault-standard/fixtures/non-conformant-static-token/k8s/bootstrap.sh:2: raw Vault root/child token) | fix: Remove static/long-lived Vault tokens; use Kubernetes auth (VS-002): provider.vault.auth.kubernetes.role: <role> + mountPath: /v1/auth/kubernetes |

### store-issuer — NON-CONFORMING

| Rule | Verdict | Evidence | Fix |
|------|---------|----------|-----|
| VS-001 | PASS | secrets-vault-standard/fixtures/store-issuer/k8s/cluster-secret-store.yaml: provider.vault | - |
| VS-002 | PASS | provider.vault.auth.kubernetes present (role + mountPath) | - |
| VS-003 | FAIL | Vault store declared but no ExternalSecret referencing it | fix: Add an ExternalSecret that references the Vault-backed store and maps Vault KV paths to K8s Secret keys |
| VS-004 | N/A | no ExternalSecret remoteRef paths to validate | - |
| VS-005 | N/A | no Deployment/CronJob consuming secrets to validate | - |
| VS-006 | PASS | no committed secret patterns in tracked files | - |
| VS-007 | PASS | no static Vault tokens (s.<token>, VAULT_TOKEN, vault login, vault.token) | - |

### unknown-manual-review — UNKNOWN

| Rule | Verdict | Evidence | Fix |
|------|---------|----------|-----|
| VS-001 | UNKNOWN | references unresolved store(s):ops-provisioned-store (cannot confirm Vault-backed; manual review) | fix: declare a provider.vault store, or ensure the referenced ClusterSecretStore exists fleet-wide |
| VS-002 | UNKNOWN | Vault store auth method not determinable (store(s)ops-provisioned-store unresolvable; manual review) | fix: Ensure the referenced ClusterSecretStore is declared fleet-wide with provider.vault.auth.kubernetes |
| VS-003 | UNKNOWN | ExternalSecret references unresolved store(s):ops-provisioned-store (manual review) | fix: Ensure ExternalSecret.secretStoreRef.name matches a declared Vault-backed store |
| VS-004 | PASS | 1 path(s) follow /<env>/<service>/<key> | - |
| VS-005 | N/A | no Deployment/CronJob consuming secrets to validate | - |
| VS-006 | PASS | no committed secret patterns in tracked files | - |
| VS-007 | PASS | no static Vault tokens (s.<token>, VAULT_TOKEN, vault login, vault.token) | - |
