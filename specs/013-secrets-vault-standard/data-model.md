# Data Model: Secrets & Vault Standard Conformance

Phase 1 output — entities, fields, relationships, and state transitions for the audit system.

---

## Entities

### FleetApp

Represents one application from the ArgoCD applicative inventory.

| Field | Type | Description |
|-------|------|-------------|
| `name` | string | App name from Argo YAML (e.g., `analyst`) |
| `repoURL` | string | Git repository URL |
| `appPath` | string | Subdirectory containing K8s manifests (e.g., `k8s`) |
| `namespace` | string | Target K8s namespace (e.g., `apps-ns`) |
| `syncWave` | integer | Argo sync wave ordering |
| `localPath` | string | Resolved local clone path (e.g., `/Users/natan/projects/repos/analyst`) |

**Source of truth**: `infra/argocd-infra/apps/applicative/*.yaml`

---

### StandardRule

One scoring rule from the canonical Vault-backed ESO standard.

| Field | Type | Description |
|-------|------|-------------|
| `ruleId` | string | Rule identifier (e.g., `VS-001`) |
| `description` | string | Human-readable rule statement |
| `weight` | enum | `primary` (blocking), `secondary` (advisory), `scoring` (quality) |
| `detectionPattern` | string | grep/awk pattern used to detect compliance |
| `applicableWhen` | string | Condition under which this rule applies (e.g., `repo has ExternalSecrets`) |

### StandardRule instances

| Rule ID | Description | Weight |
|---------|-------------|--------|
| VS-001 | SecretStore/ClusterSecretStore declared with `provider.vault` | primary |
| VS-002 | Vault auth via Kubernetes method (not static token) | primary |
| VS-003 | ExternalSecret(s) reference a Vault-backed store | primary |
| VS-004 | Path convention: `/<env>/<service>/<key>` (DRY) | scoring |
| VS-005 | Secret consumption via `secretKeyRef` or `envFrom.secretRef` | secondary |
| VS-006 | No committed secret material in tracked files | primary |
| VS-007 | No static/long-lived Vault tokens in manifests | primary |

---

### EvidenceMatch

A single detection result for one rule against one repo.

| Field | Type | Description |
|-------|------|-------------|
| `ruleId` | string | FK → StandardRule |
| `repoName` | string | FK → FleetApp |
| `verdict` | enum | `PASS` / `FAIL` / `N/A` / `UNKNOWN` |
| `evidence` | string | Matching line(s) or file(s) that produced the verdict |
| `fix` | string? | `fix:` remediation line (populated on FAIL only) |

---

### RuleVerdict

Aggregated verdict for one rule across the fleet.

| Field | Type | Description |
|-------|------|-------------|
| `ruleId` | string | FK → StandardRule |
| `passCount` | integer | Repos where this rule PASSed |
| `failCount` | integer | Repos where this rule FAILed |
| `naCount` | integer | Repos where this rule is N/A |
| `unknownCount` | integer | Repos where verdict is UNKNOWN |

---

### RepoVerdict

The overall verdict for one repository.

| Field | Type | Description |
|-------|------|-------------|
| `repoName` | string | FK → FleetApp |
| `verdict` | enum | `CONFORMING` / `NON-CONFORMING` / `N/A` / `UNKNOWN` |
| `ruleResults` | EvidenceMatch[] | Per-rule results for this repo |
| `fixCount` | integer | Number of FAIL rules (0 = CONFORMING) |

**Verdict determination logic**:

```
if repo has no secrets infrastructure:
    verdict = N/A
else if any rule is UNKNOWN:
    verdict = UNKNOWN
else if any primary rule is FAIL:
    verdict = NON-CONFORMING
else:
    verdict = CONFORMING
```

---

### FleetReport

The complete audit output.

| Field | Type | Description |
|-------|------|-------------|
| `standardVersion` | string | Version of the standard used (e.g., `1.0.0`) |
| `inventoryPath` | string | Path to Argo inventory YAML |
| `repoCount` | integer | Total repos audited |
| `repoVerdicts` | RepoVerdict[] | Per-repo verdicts (sorted by name) |
| `summary` | FleetSummary | Aggregate counts |
| `timestamp` | string | ISO 8601 audit timestamp |

---

### FleetSummary

Aggregate counts for the fleet.

| Field | Type | Description |
|-------|------|-------------|
| `conforming` | integer | Repos with CONFORMING verdict |
| `nonConforming` | integer | Repos with NON-CONFORMING verdict |
| `na` | integer | Repos with N/A verdict |
| `unknown` | integer | Repos with UNKNOWN verdict |
| `total` | integer | Sum of all (must equal `repoCount`) |
| `exitCode` | integer | 0 if nonConforming = 0; 1 otherwise |

---

## State Transitions

### RepoVerdict lifecycle

```
[NOT_SCANNED]
    ↓ (inventory parsed, repo located)
[SCANNING] — detectors running
    ↓ (all rules evaluated)
[CONFORMING]     — all applicable rules PASS
[NON-CONFORMING] — one or more rules FAIL
[N/A]            — no secrets infrastructure detected
[UNKNOWN]        — secrets exist but pattern undetermined
```

### EvidenceMatch lifecycle

```
[NOT_EVALUATED]
    ↓ (detector runs)
[PASS] / [FAIL] / [N/A] / [UNKNOWN]
    ↓ (on FAIL only)
fix line populated
```

---

## Relationships

```
FleetReport 1──* RepoVerdict
RepoVerdict *──* EvidenceMatch
EvidenceMatch *──1 StandardRule
FleetReport 1──1 FleetSummary
FleetApp 1──1 RepoVerdict (by repoName)
StandardRule 1──* RuleVerdict
```
