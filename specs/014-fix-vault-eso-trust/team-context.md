# Team Context — Team AI Directives Discovery

Feature domain: Secrets Management / GitOps / Kubernetes / External Secrets Operator / Vault
Feature tech: Kubernetes, HashiCorp Vault, External Secrets Operator (ESO), Helm, ArgoCD/GitOps, ClusterSecretStore
Feature patterns: DRY secrets, store-bound mount paths, least-privilege policies, secret rotation, GitOps-as-source-of-truth
Feature actions: provision, seed, sync, migrate, reorganize, refactor, verify

## Discovered Modules

| CDR | Module | Type | Descriptor | Relevance |
|-----|--------|------|------------|-----------|
| CDR-2026-017 | context_modules/rules/devops/secrets_management.md | Rule | Comprehensive secrets management patterns for Kubernetes using External Secrets Operator and DRY principles | High |
| CDR-2026-003 | context_modules/personas/cloud_native_platform_architect.md | Persona | Kubernetes, GitOps, platform engineering specialist | High |
| CDR-2026-005 | context_modules/personas/devops_engineer.md | Persona | CI/CD, Infrastructure as Code, GitOps specialist | Medium |
| CDR-2026-020 | context_modules/rules/security/pre_commit_checklist.md | Rule | Pre-commit security checklist to verify before submitting code | Medium |

## Matched Skills

| Skill | Type | Relevance |
|-------|------|-----------|
| external-secrets (default) | Skill | High — ESO patterns for syncing secrets from Vault into Kubernetes |
| gke-workload-identity (default) | Skill | Medium — keyless GCP auth (not primary here) |
| helm-charts (default) | Skill | Medium — chart authoring for manifests |
| github-actions (default) | Skill | Low — OIDC CI/CD, not core to this feature |

### High-Relevance Rule — CDR-2026-017 Secrets Management (loaded)

Key operative guidance for this feature:
- **ExternalSecret CRD**: `apiVersion: external-secrets.io/v1beta1`, use `secretStoreRef` with proper `kind` (ClusterSecretStore vs SecretStore).
- **Data mapping**: use `data` for static key-value pairs; `dataFrom` with `extract:` for whole-path extraction.
- **Refresh interval**: 1m for API keys, 10m for DB passwords, 1h for long-lived certs.
- **Security**: `creationPolicy: Owner` so chart/namespace owns the secret; never commit real secret values; least-privilege access to secret stores.
- **DRY**: single source pattern — cloud environments inject all keys via `dataFrom.extract` (no values.yaml duplication).
- Related: GKE Workload Identity, Helm packaging.

**Constitution-aligned operating constraints** (from constitution.md):
1. Human oversight mandatory before merge.
2. Build for observability/reproducibility — surface every failure, never report success when something skipped/rolled back/bypassed.
3. Security by default — least privilege for credentials, never ship hard-coded tokens.
4. Documentation matters — capture assumptions, API contracts, hand-off notes in repo.
5. Zero trust — verify/auth every request, least privilege, continuous monitoring.
6. Think before coding — don't assume; surface tradeoffs; ask when uncertain.
7. Simplicity first — minimum code that solves the problem.
8. Surgical changes — touch only what you must; match existing style.
9. Goal-driven execution — define success criteria, loop until verified; long-running ops need checkpoints and confirmation.

_Searched CDR index (Accepted rows) + .skills.json; 4 module matches + 4 skills; High relevance loaded in full._
