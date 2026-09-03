# Quickstart: Secrets & Vault Standard Conformance

Validation scenarios for the fleet audit tool. Each scenario maps to fixture
repos that simulate real fleet conditions.

## Prerequisites

- Bash 3.2+ (macOS default or Linux)
- `git`, `grep`, `awk` available
- Repos cloned under a common root (default: `/Users/natan/projects/repos`)

## Scenario 1: Fleet Audit — All Conforming

**Given**: A fixture fleet with a single repo (`conformant-vault-eso`) that
uses the Vault-backed ESO pattern correctly (SecretStore + ExternalSecret +
secretKeyRef + DRY paths).

Inventory file (`all-conforming.yaml`):
```yaml
name: conformant-vault-eso
repoURL: https://example.com/conformant-vault-eso
appPath: k8s
namespace: default
syncWave: "0"
```

**When**: `./secrets-vault-standard/audit-fleet.sh --inventory <fixture-inventory> --repo-root secrets-vault-standard/fixtures`

**Then**:
- Exit code: 0
- Fleet summary: 1 CONFORMING, 0 NON-CONFORMING, 0 N/A, 0 UNKNOWN
- No `fix:` lines in output
- Per-repo results show VS-001 PASS, VS-002 PASS, VS-003 PASS, VS-004 PASS, VS-006 PASS

## Scenario 2: Fleet Audit — Non-Conforming Repo Detected

**Given**: A fixture fleet with a conforming repo (`conformant-vault-eso`) and
a non-conforming repo (`non-conformant-hardcoded`) that has committed secrets
(a bcrypt hash and API key in `config.toml`).

Inventory files:
```yaml
# conformant-vault-eso.yaml
name: conformant-vault-eso
repoURL: https://example.com/conformant-vault-eso
appPath: k8s
namespace: default
syncWave: "0"
```
```yaml
# non-conformant-hardcoded.yaml
name: non-conformant-hardcoded
repoURL: https://example.com/non-conformant-hardcoded
appPath: k8s
namespace: default
syncWave: "0"
```

**When**: `./secrets-vault-standard/audit-fleet.sh --inventory <fixture-inventory> --repo-root secrets-vault-standard/fixtures`

**Then**:
- Exit code: 1
- `conformant-vault-eso` shows CONFORMING
- `non-conformant-hardcoded` shows NON-CONFORMING with VS-006 FAIL
- VS-006 fix line: `fix: Remove committed secret material from the tracked file; add it to .gitignore; manage via Vault/ESO at runtime`
- Fleet summary: 1 CONFORMING, 1 NON-CONFORMING, 0 N/A, 0 UNKNOWN

## Scenario 3: N/A Repo (No Secrets)

**Given**: A fixture repo (`na-no-secrets`) with zero secrets infrastructure
(Deployment + Ingress only, no ExternalSecret, no Secret, no secretKeyRef).

Inventory file:
```yaml
name: na-no-secrets
repoURL: https://example.com/na-no-secrets
appPath: k8s
namespace: default
syncWave: "0"
```

**When**: `./secrets-vault-standard/audit-fleet.sh --inventory <fixture-inventory> --repo-root secrets-vault-standard/fixtures`

**Then**:
- Exit code: 0
- Repo verdict: N/A
- Per-repo message: VS-001 N/A ("no secrets infrastructure (Vault store rule not applicable)"), VS-002 N/A, VS-003 N/A, VS-004 N/A, VS-006 PASS
- Fleet summary: 0 CONFORMING, 0 NON-CONFORMING, 1 N/A, 0 UNKNOWN
- N/A repos excluded from CONFORMING/NON-CONFORMING counts

## Scenario 4: Missing Repo (NOT_FOUND)

**Given**: Inventory references a repo (`nonexistent-repo`) that does not exist
locally.

Inventory file:
```yaml
name: nonexistent-repo
repoURL: https://example.com/nonexistent-repo
appPath: k8s
namespace: default
syncWave: "0"
```

**When**: `./secrets-vault-standard/audit-fleet.sh --inventory <fixture-inventory> --repo-root secrets-vault-standard/fixtures`

**Then**:
- Exit code: 3
- stderr: `secrets-vault-standard/audit-fleet: repo 'nonexistent-repo' not found locally (<repo-root>/nonexistent-repo) — skipped`
- stderr: `secrets-vault-standard/audit-fleet: no repos resolved locally`
- No stdout report (all repos unresolved)

## Scenario 5: Non-Existent Inventory

**Given**: `--inventory` points to a path that does not exist.

**When**: `./secrets-vault-standard/audit-fleet.sh --inventory /nonexistent/path --repo-root secrets-vault-standard/fixtures`

**Then**:
- Exit code: 2
- stderr includes: `secrets-vault-standard/inventory: inventory not found: /nonexistent/path`
- stderr includes usage text from `inventory.sh`

## Scenario 6: ClusterSecretStore Consumption

**Given**: A fixture repo that consumes a `ClusterSecretStore` declared elsewhere
(no store declaration in its own manifests).

**When**: `./secrets-vault-standard/audit-fleet.sh --inventory <fixture-inventory> --repo-root <fixture-root>`

**Then**:
- VS-001: N/A (repo doesn't declare its own store — consumed elsewhere)
- VS-003: PASS (ExternalSecret references the ClusterSecretStore by name)
- Overall verdict: CONFORMING (if all other rules pass)

## Scenario 7: Duplicate (Determinism)

**Given**: Same fixture fleet as Scenario 2.

**When**: Run `audit-fleet.sh` twice with the same inputs.

**Then**:
- Both runs produce identical output (deterministic sort order)
- Same exit code, same verdicts, same fix lines

## Scenario 6 (Optional): Live Fleet Audit

**Given**: Real repos cloned under `/Users/natan/projects/repos` and the
Argo inventory at `infra/argocd-infra/apps/applicative`.

**When**: `./secrets-vault-standard/audit-fleet.sh`

**Then**:
- 6 repos audited
- Expected verdicts: analyst=NON-CONFORMING, aws=CONFORMING, familytree=NON-CONFORMING,
  tech-companies=CONFORMING, pdf-scan=CONFORMING, argo-app-go-server=N/A
- Exit code: 1 (due to analyst and familytree committed secrets)
