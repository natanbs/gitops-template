# Contract: Report Output Schema

**Format**: Markdown (default), JSON (optional, `--format json`)

## Markdown Format

```markdown
# Secrets & Vault Standard Fleet Report

**Standard**: secrets-vault-standard v1.0.0
**Inventory**: infra/argocd-infra/apps/applicative
**Date**: 2026-08-31T10:00:00Z

## Fleet Summary

| Verdict | Count |
|---------|-------|
| CONFORMING | 3 |
| NON-CONFORMING | 2 |
| N/A | 1 |
| UNKNOWN | 0 |
| **Total** | **6** |

**Exit code**: 0

## Per-Repo Results

### analyst — NON-CONFORMING

| Rule | Verdict | Evidence | Fix |
|------|---------|----------|-----|
| VS-001 | PASS | `k8s/secret-store.yaml: provider.vault` | — |
| VS-002 | PASS | `k8s/secret-store.yaml: auth.kubernetes` | — |
| VS-003 | PASS | `k8s/external-secret.yaml: kind: ExternalSecret` | — |
| VS-004 | PASS | `k8s/external-secret.yaml: remoteRef.key: analyst/env/OPENCODE_ZEN_API_KEY` | — |
| VS-005 | PASS | `k8s/deployment.yaml: secretKeyRef` | — |
| VS-006 | FAIL | `config.toml:173: hardcoded auth ID 028873800, phone 0587849705` | `fix: Remove hardcoded PII from config.toml; add to .gitignore; manage via Vault if runtime is needed` |
| VS-007 | PASS | No static tokens found | — |

### argo-app-go-server — N/A

No secrets infrastructure detected. Vault standard is not applicable.

### aws — CONFORMING

| Rule | Verdict | Evidence | Fix |
|------|---------|----------|-----|
| VS-001 | PASS | `k8s/secret-store.yaml: provider.vault` | — |
| VS-002 | PASS | `k8s/secret-store.yaml: auth.kubernetes` | — |
| VS-003 | PASS | `k8s/external-secret.yaml: kind: ExternalSecret` | — |
| VS-004 | PASS | `k8s/external-secret.yaml: remoteRef.key: aws/env/S3_ACCESS_KEY_ID` | — |
| VS-005 | PASS | `k8s/deployment.yaml: secretKeyRef` | — |
| VS-006 | PASS | No committed secrets detected | — |
| VS-007 | PASS | No static tokens found | — |
```

*(remaining repos follow the same per-repo structure, sorted alphabetically)*

---

## JSON Format

```json
{
  "standardVersion": "1.0.0",
  "inventoryPath": "infra/argocd-infra/apps/applicative",
  "timestamp": "2026-08-31T10:00:00Z",
  "repoCount": 6,
  "summary": {
    "conforming": 3,
    "nonConforming": 2,
    "na": 1,
    "unknown": 0,
    "total": 6,
    "exitCode": 0
  },
  "repos": [
    {
      "name": "analyst",
      "localPath": "/Users/natan/projects/repos/analyst",
      "verdict": "NON-CONFORMING",
      "fixCount": 1,
      "rules": [
        {
          "ruleId": "VS-001",
          "verdict": "PASS",
          "evidence": "k8s/secret-store.yaml: provider.vault",
          "fix": null
        },
        {
          "ruleId": "VS-006",
          "verdict": "FAIL",
          "evidence": "config.toml:173: hardcoded auth ID + phone number",
          "fix": "Remove hardcoded PII from config.toml; add to .gitignore; manage via Vault if runtime is needed"
        }
      ]
    }
  ]
}
```

## Verdict Sorting

Repos are sorted alphabetically by name in both formats. Rules are sorted by
rule ID (VS-001 through VS-007).
