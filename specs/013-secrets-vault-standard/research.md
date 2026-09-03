# Research: Secrets & Vault Standard Conformance

Phase 0 output — all decisions resolved. No NEEDS CLARIFICATION markers remain.

---

## D1: Detection Method — Offline Manifest Scan

**Decision**: Static scan of git-tracked files in each repo using grep/awk heuristics to identify Vault/ESO indicators, committed secrets, and path convention adherence.

**Rationale**: The audit is offline (no live Vault access) and read-only. The gate (feature 001) already operates on git-tracked files only. All 5 Vault-using repos declare their Vault integration in `k8s/` manifests (SecretStore, ExternalSecret, Deployment envFrom/secretKeyRef), making static detection reliable.

**Alternatives considered**:
- *Live Vault query (read actual secret paths)*: Rejected — requires Vault network access, service account tokens, violates offline constraint. Runtime audit is a separate concern.
- *YAML AST parsing (e.g., kubeval + jq)*: Rejected — adds dependencies; grep/awk is sufficient for indicator detection (presence/absence of `kind: ExternalSecret`, `provider.vault`, etc.).
- *Full-text semantic analysis*: Overkill — the fleet is small (6 repos) and patterns are declarative YAML, not code.

**Detection heuristics** (from fleet survey):

| Signal | Detection pattern | Weight |
|--------|-------------------|--------|
| `kind: SecretStore` or `kind: ClusterSecretStore` with `provider.vault` | `grep -r 'provider.vault' k8s/` | Primary — proves Vault+ESO |
| `kind: ExternalSecret` referencing a Vault-backed store | `grep -r 'kind: ExternalSecret' k8s/` + store reference check | Primary — proves ESO consumption |
| `secretKeyRef` or `envFrom.secretRef` in Deployments | `grep -r 'secretKeyRef\|secretRef' k8s/` | Secondary — proves secret consumption |
| Vault path convention (`/<env>/<service>/<key>`) | Extract paths from ExternalSecret `secretRef.name` and `data[].secretKey` | Scoring — DRY adherence |
| Committed secrets in tracked files | Regex scan (bcrypt hashes, API keys, PII, hardcoded credentials) | Security — anti-pattern |
| No secrets at all (N/A) | No `kind: ExternalSecret`, no `kind: Secret`, no `secretKeyRef` anywhere | N/A classification |

---

## D2: Canonical Standard — Vault-Backed ESO Pattern

**Decision**: The canonical standard = External Secrets Operator with HashiCorp Vault as the provider, following CDR-2026-017 patterns.

**Rationale**: Fleet survey (Phase 0 pre-research) confirmed 5 of 6 repos use this exact pattern. The org rule (CDR-2026-017) was designed for ESO. The user selected "B — HashiCorp Vault" as the standard, but the fleet reality is ESO+Vault (Vault is the backend, ESO is the abstraction). The standard definition must match what the fleet actually uses to produce meaningful verdicts.

**Standard rules** (from CDR-2026-017 + fleet topology):

| Rule ID | Rule | Detection |
|---------|------|-----------|
| VS-001 | SecretStore/ClusterSecretStore declared with `provider.vault` | YAML `provider.vault` field present |
| VS-002 | Vault auth via Kubernetes auth method (not static token) | `kubernetes` auth field in SecretStore `provider.vault.auth` |
| VS-003 | ExternalSecret(s) reference a Vault-backed store | `kind: ExternalSecret` + `spec.secretStoreRef` pointing to a Vault store |
| VS-004 | Path convention: `/<env>/<service>/<key>` (DRY) | Extract and validate ExternalSecret data paths |
| VS-005 | Secret consumption via `secretKeyRef` or `envFrom.secretRef` | Deployment `env`/`envFrom` referencing the ExternalSecret-created K8s Secret |
| VS-006 | No committed secret material in tracked files | Regex scan: bcrypt hashes, API key patterns, hardcoded credentials |
| VS-007 | No static/long-lived Vault tokens in manifests or code | No `VAULT_TOKEN`, `vault login`, hardcoded token strings |

**Rejected alternatives** (for the standard-selection record):
- *ESO + cloud store (GCP Secret Manager, AWS Secrets Manager)*: The org's CDR-2026-017 prefers this, but the fleet uses Vault. Standard = what's deployed, not what's preferred.
- *Raw Vault (vault-agent-injector, consul-template)*: No repo in the fleet uses this pattern. The only Vault integration path is via ESO.
- *Hybrid (ESO supporting both cloud and Vault)*: Adds complexity; the fleet is homogeneous (all Vault). Can be reconsidered if new backends are introduced.

---

## D3: Fleet Discovery — Argo Inventory Parsing

**Decision**: Parse `infra/argocd-infra/apps/applicative/*.yaml` to enumerate the fleet. Each YAML file defines one app with `name`, `repoURL`, `appPath`, `namespace`, `syncWave`.

**Rationale**: The user specified this exact path as the fleet scope (Q1). The inventory is the single source of truth for which repos to audit.

**Mapping**: `repoURL` → local clone path. All 6 repos verified present under `/Users/natan/projects/repos/`. `appPath` (typically `k8s/`) determines the directory to scan within each repo.

**Alternatives considered**:
- *Hardcoded repo list*: Rejected — fragile; inventory is the authoritative source.
- *GitHub API enumeration*: Rejected — offline constraint; adds auth complexity.
- *ArgoCD CLI (argocd app list)*: Rejected — requires running ArgoCD; offline audit can't depend on it.

---

## D4: Scoring Model + Report Format

**Decision**: Per-repo verdict (CONFORMING / NON-CONFORMING / N/A / UNKNOWN) + per-rule score (PASS/FAIL/N/A per VS-001..VS-007) + `fix:` remediation lines + fleet summary table. Output: markdown (human-readable).

**Rationale**: Mirrors feature 001's demo sentence pattern (`[PASS]`/`[FAIL]` + `fix:`). Markdown is the existing report format (README, verify.md). JSON can be added later if the gate RFC (Q3: C) needs machine-parseable output.

**Verdict logic**:
- **N/A**: Repo has zero secrets infrastructure (no `kind: ExternalSecret`, no `kind: Secret`, no `secretKeyRef` anywhere in tracked files). Example: `argo-app-go-server`.
- **UNKNOWN**: Repo has secrets but detection can't determine Vault/ESO conformance (e.g., secrets are managed outside git-tracked manifests, or the repo uses a pattern not covered by the detectors). Requires manual review.
- **CONFORMING**: All applicable rules (VS-001..VS-007) PASS.
- **NON-CONFORMING**: One or more rules FAIL. Each FAIL emits a `fix:` line.

**Fleet summary**: Count of CONFORMING / NON-CONFORMING / N/A / UNKNOWN across all repos. Exit code: 0 if all repos are CONFORMING or N/A; 1 if any NON-CONFORMING.

---

## D5: Standard-Selection Document

**Decision**: `contracts/standard.md` records the canonical Vault-backed ESO standard, its criteria, the selected option (B — Vault, but via ESO abstraction), rejected alternatives, and rationale.

**Rationale**: The constitution requires explicit, versioned standard selections. The standard is the "measuring stick" for the audit — it must be documented separately from the audit tool so it can evolve independently (e.g., if a 7th repo uses a different Vault pattern).

**Versioning**: The standard document carries a `version` field (e.g., `1.0.0`). The fleet report references the standard version used for scoring. This supports future standard updates without breaking the audit tool.

---

## D6: Dual SecretStore Topology

**Decision**: The audit must handle two deployment patterns found in the fleet:

1. **Per-app SecretStore** (analyst, aws): Each repo declares its own `SecretStore` with `provider.vault`, its own K8s auth role, and its own CA bundle (inline base64).
2. **Shared ClusterSecretStore** (familytree defines `vault-store`; tech-companies, pdf-scan consume it): A single `ClusterSecretStore` declared in one repo, consumed by others via `secretStoreRef`.

**Rationale**: Both patterns are valid Vault-backed ESO. The audit must not penalize repos for consuming a shared ClusterSecretStore they didn't declare. VS-001 applies differently:
- For repos that define a store: check `provider.vault` is present and correctly configured.
- For repos that consume a store: check that `ExternalSecret.spec.secretStoreRef.name` points to a store that exists (fleet-wide check) or is at least syntactically valid.

**CA bundle handling** also differs: inline base64 (analyst, aws) vs `caProvider` referencing a K8s Secret (familytree). Both are valid.

---

## D7: Committed Secrets Detection Scope

**Decision**: The audit flags committed sensitive material as a FAIL against VS-006. Detection covers: bcrypt/argon2 hashes, hardcoded API keys (regex patterns), PII-like strings, `VAULT_TOKEN`/hardcoded tokens, `kubectl create secret` in tracked scripts.

**Rationale**: The fleet survey found 2 repos with committed sensitive data:
- `analyst/config.toml`: hardcoded auth ID + phone number (PII)
- `familytree/familyTree.yaml`: bcrypt password hash

These are application-level data files, not K8s secrets. They're orthogonal to the Vault/ESO pipeline but still represent a secrets-management hygiene failure. The audit flags them as a finding.

**Scope boundary**: The audit reads files in `appPath` (e.g., `k8s/`) by default. Committed secrets outside `appPath` (like `config.toml` at repo root) are detected only if the audit scans the full repo. **Decision**: scan `appPath` + a configurable set of additional paths (default: repo root `.yaml`, `.toml`, `.json`, `.env` files). This keeps the scope bounded while catching the known cases.

---

## D8: Exemption / N/A Semantics

**Decision**: A repo is classified N/A when it has zero secrets infrastructure — no `kind: ExternalSecret`, no `kind: Secret`, no `secretKeyRef`, no `envFrom.secretRef` anywhere in tracked files. N/A repos are excluded from CONFORMING/NON-CONFORMING counts in the fleet summary.

**Rationale**: From the fleet survey, `argo-app-go-server` has zero secrets — it deploys a bare Deployment with `PORT=8090`. Marking it NON-CONFORMING for lacking Vault/ESO would be a false positive. N/A means "this repo has no secrets to manage; the Vault standard is not applicable."

**UNKNOWN**: If a repo has secrets but the detector can't determine their management pattern (e.g., secrets are injected at runtime by a sidecar not declared in git), the verdict is UNKNOWN — flagged for manual review. This is distinct from N/A (which means "no secrets at all").
