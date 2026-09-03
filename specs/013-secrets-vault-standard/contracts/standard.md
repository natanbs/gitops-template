# Contract: Vault-Backed ESO Standard

**Standard ID**: secrets-vault-standard
**Version**: 1.0.0
**Effective date**: 2026-08-31

## Purpose

This document defines the canonical Vault-backed ESO standard used to score
ArgoCD applicative repos for secrets-management conformance. The audit tool
(`audit-fleet.sh`) uses this standard as its measuring stick.

## Scope

Applies to all repos in the ArgoCD applicative inventory
(`infra/argocd-infra/apps/applicative/*.yaml`). A repo is exempt (N/A) when
it has zero secrets infrastructure.

## Rules

### VS-001: Vault-Backed Store Declared

**Description**: At least one `kind: SecretStore` or `kind: ClusterSecretStore`
with `provider.vault` must be declared in the repo's `appPath`.

**Weight**: Primary (blocking)

**Detection**: `grep -r 'provider.vault' <appPath>/`

**Fix on FAIL**: Add a `SecretStore` or `ClusterSecretStore` with
`provider.vault` pointing to the org's Vault cluster. Reference
`secret-management.md` (CDR-2026-017) for the canonical shape.

**Exception**: Repos that consume a ClusterSecretStore declared elsewhere
(e.g., `vault-store` from the familytree repo) may not declare their own.
These repos are scored N/A on this rule if they have an ExternalSecret with
`secretStoreRef.name` referencing a known ClusterSecretStore.

**Definition of "known"**: A ClusterSecretStore is "known" if it is declared
in any repo within the audited ArgoCD applicative fleet, resolved fleet-wide
during inventory load. Fleet-wide resolution: collect all `kind:
SecretStore`/`kind: ClusterSecretStore` names across every audited repo's
`appPath`, build a set, then score VS-001 N/A for any repo whose
`secretStoreRef.name` is in that set. A repo referencing a store not in the
set is CONSIDERED UNRESOLVED and is flagged for manual review (verdict
UNKNOWN), never silently assumed conforming.

---

### VS-002: Kubernetes Auth Method

**Description**: Vault authentication in the SecretStore must use the
Kubernetes auth method (`auth.kubernetes`), not a static `token` or
`tokenSecretRef`.

**Weight**: Primary (blocking)

**Detection**: Check `provider.vault.auth` contains a `kubernetes` field
(with `role` and `mountPath`).

**Fix on FAIL**: Replace static token auth with Kubernetes auth:
`provider.vault.auth.kubernetes.role: <role>` + `mountPath: /v1/auth/kubernetes`.

---

### VS-003: ExternalSecret References Vault Store

**Description**: At least one `kind: ExternalSecret` must reference a
Vault-backed store via `spec.secretStoreRef.name`.

**Weight**: Primary (blocking)

**Detection**: `grep -r 'kind: ExternalSecret' <appPath>/` + validate
`spec.secretStoreRef.name` matches a known store (from VS-001 or fleet-wide).

**Fix on FAIL**: Add an `ExternalSecret` that references the Vault-backed
store and maps Vault KV paths to K8s Secret keys.

---

### VS-004: DRY Path Convention

**Description**: Vault KV paths in ExternalSecrets must follow the
`/<env>/<service>/<key>` convention.

**Weight**: Scoring (advisory — non-blocking)

**Detection**: Extract `data[].remoteRef.key` or `dataFrom[].extract` paths
from ExternalSecrets and validate the `/<env>/<service>/<key>` shape.

**Why advisory (non-blocking)**: Path convention is a DRY/operability quality
signal, not a security control. FR-008 lists the path convention as a
requirement, and it is enforced here as scored guidance: a repo with
non-standard paths is still scored and reported, but does not by itself flip
the verdict to NON-CONFORMING. Only the blocking (Primary) rules gate the
verdict. This is an intentional weight choice, not an omission.

**Fix on FAIL**: Reorganize Vault KV paths to follow `/<env>/<service>/<key>`
instead of flat or ad-hoc path structures.

---

### VS-005: Secret Consumption Pattern

**Description**: Deployments and CronJobs must consume secrets via
`env.valueFrom.secretKeyRef` or `envFrom[].secretRef`, referencing the
ExternalSecret-created K8s Secret.

**Weight**: Secondary (advisory)

**Detection**: `grep -r 'secretKeyRef\|secretRef' <appPath>/*Deploy* <appPath>/*Cron*`

**Sources vs. manual Secrets**: A Deployment consuming a secret only counts as
VS-005 PASS when the referenced K8s Secret is created by an ExternalSecret
(its name maps to an `ExternalSecret.spec.target.name`). A Deployment that
references a manually-declared `kind: Secret` (created outside ESO) does NOT
satisfy VS-005 — the detector must confirm the consumed Secret name appears as
a target of a Vault-backed ExternalSecret before scoring PASS; otherwise it is
scored FAIL (secret material not sourced from the Vault standard).

**Fix on FAIL**: Wire Deployment/CronJob env to the ExternalSecret-created
Secret via `secretKeyRef` or `envFrom.secretRef`.

---

### VS-006: No Committed Secret Material

**Description**: No git-tracked files in `appPath` (and optionally repo root)
may contain committed secrets, bcrypt/argon2 hashes, API key patterns,
hardcoded credentials, or PII.

**Weight**: Primary (blocking)

**Detection**: Regex scan for patterns: `\$2[aby]\$` (bcrypt), `\$argon2`
(argon2), `\$6\$`/`\$5\$` (sha-crypt), `AKIA[0-9A-Z]{16}` (AWS access key),
`ASIA[0-9A-Z]{16}` (AWS session token), `sk-[a-zA-Z0-9]{20,}` (OpenAI),
`ghp_[a-zA-Z0-9]{36}` (GitHub PAT), `github_pat_` (GitHub fine-grained),
`eyJ[a-zA-Z0-9_-]{20,}\.[a-zA-Z0-9_-]{10,}` (JWT), `AIza[0-9A-Za-z_-]{35}`
(GCP service account key), `-----BEGIN.*PRIVATE KEY-----` (private key),
`VAULT_TOKEN`, hardcoded phone numbers / email addresses in config files.

**Scan scope**: Default scans the repo `appPath` (e.g., `k8s/`) plus tracked
repo-root `.yaml`/`.toml`/`.json`/`.env` files. Root-NON-appPath scanning is
OPT-IN via the audit `--scan-root` flag; when off, only `appPath` is scanned
and the choice is recorded in the report header.

**False-positive mitigation**: Detection is limited to YAML/TOML/JSON *value*
contexts and ignores comment lines and documentation prose. A match inside an
`example`/`docs`/`README` file or a commented-out line does NOT FAIL. The
detector runs only the concrete patterns above — patterns are deliberately
scoped to high-signal formats (heuristic `sk-`, `AKIA`, `ghp_`, bcrypt,
JWT header) to minimize false positives on ordinary values (ports, hashes,
timestamps).

**Fix on FAIL**: Remove committed secrets from git-tracked files. Add
the file to `.gitignore`. If the secret is needed at runtime, manage it
through Vault/ESO instead.

---

### VS-007: No Static Vault Tokens

**Description**: No static or long-lived Vault tokens may appear in
manifests, scripts, or code.

**Weight**: Primary (blocking)

**Detection**: `grep -r 'VAULT_TOKEN\|vault login\|vault\.token' <appPath>/`
+ scan for `token:` fields in SecretStore `provider.vault` (should be
absent when using Kubernetes auth).

**Fix on FAIL**: Remove static tokens. Use Kubernetes auth (VS-002) instead.

**Overlap with VS-006**: A static `VAULT_TOKEN` committed in a tracked file
satisfies BOTH VS-006 (committed secret) and VS-007 (static vault token).
This overlap is intentional: a static token is a critical anti-pattern on two
axes. Both rules report FAIL and each emits its own `fix:` line; de-duplication
of the report rows is not required, but the repo is classified NON-CONFORMING
once (a single NON-CONFORMING verdict), not counted twice in the fleet summary.

---

## Detection Precision & Propagation Notes

These cross-cutting rules apply to all VS-* detectors and bound offline,
read-only classification.

**Comment / documentation immunity**: All detectors must ignore comment lines
and documentation prose. A match must occur in an active YAML/TOML/JSON field
value, not in a `#` / `//` comment, an `example`/`docs`/`README` file, or a
commented-out block. This prevents the `provider.vault`, `secretKeyRef`, and
credential patterns from false-positiving on documentation (CHK003, CHK017,
CHK019).

**Mixed-pattern detection (FR-004)**: A repo that references a Vault-backed
ExternalSecret AND ALSO declares a separate static mechanism (e.g., a manual
`kind: Secret` with literal values, or a vault-agent-injector annotation) is
NON-CONFORMING, and both patterns are named in the report. Detectors must not
silently assume a single pattern when multiple indicators are present (CHK026).

**Offline classification bound**: Classification is limited to what manifests
declare. If a repo's secret management is not expressible from git-tracked
manifests (e.g., secrets provisioned out-of-band by an unreferenced sidecar or
external sync the manifests do not name), the repo is classified UNKNOWN
(manual review), never silently assumed CONFORMING (CHK014).

**CA bundle handling (valid = NOT a failure)**: A SecretStore or
ClusterSecretStore may present its Vault CA either inline as a base64
`caBundle` (analyst, aws) or as a `caProvider` referencing a K8s Secret in the
`vault` namespace (familytree). Both forms satisfy the standard. If a
`caProvider` references a Secret the audit cannot confirm exists, the store is
flagged in a report note for review but is not itself a hard fail (offline
audit cannot resolve cross-repo Secret existence) (CHK020).

---

## Standard-Selection Record

| Field | Value |
|-------|-------|
| Selected option | B — HashiCorp Vault as single standard |
| Implementation pattern | ESO+Vault (ESO is abstraction, Vault is provider) |
| Selection criterion 1 (security) | Uses short-lived/dynamic credentials (K8s auth, AppRole), never static/long-lived tokens |
| Selection criterion 2 (DRY) | Consistent `/<env>/<service>/<key>` path convention across all repos |
| Selection criterion 3 (consistency) | Uniform declarative pattern (SecretStore/ClusterSecretStore + ExternalSecret) measurable fleet-wide offline |
| Selection criterion 4 (fit) | Matches the dominant deployed pattern (5/6 Vault-using repos already use ESO+Vault) |
| Rejected alternative 1 | ESO + cloud store (GCP Secret Manager) — org rule preferred but fleet uses Vault |
| Rejected alternative 2 | Raw Vault (vault-agent-injector, consul-template) — no repo uses this |
| Rejected alternative 3 | Hybrid ESO (cloud + Vault) — adds complexity; fleet is homogeneous |
| Supersedes | CDR-2026-017's ESO-oriented default (org rule is cloud-store-oriented; this audit uses Vault as the concrete backend) |
| Rationale | Standard must match what the fleet actually deploys to produce meaningful verdicts |
| Constitution alignment | Supersede of the org rule is recorded as an explicit standard-selection decision per US2. Pending formal alignment with the constitution's Governance ("existing directives MUST be aligned before they take effect"), this decision is documented here and the audit references it; the formal alignment/amendment is tracked alongside the Ownership RFC (no gate rollout occurs until alignment is recorded). |
| Constitution governance | Standard-selection documented per US2; gate integration deferred to RFC (Q3: C, PDL Ownership) |

---

## Version History

| Version | Date | Change |
|---------|------|--------|
| 1.0.0 | 2026-08-31 | Initial standard definition — Vault-backed ESO, 7 rules + Detection Precision notes + selection criteria |
