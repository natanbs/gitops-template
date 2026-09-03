# Secrets & Vault Standard Conformance Audit

An offline fleet auditor that scores every repo in the ArgoCD applicative
inventory against a single, explicitly selected secrets/vault standard
(HashiCorp Vault behind External Secrets Operator — see
`specs/013-secrets-vault-standard/contracts/standard.md`).

For each repo it emits **one verdict** and, when non-conforming, an actionable
`fix:` line.

## Prerequisites

- Bash 3.2+ (macOS default or Linux)
- `git`, `grep`, `awk` available
- The fleet repos cloned under a common root (default:
  `/Users/natan/projects/repos/<name>`)

## Quick Start (real fleet)

Run the audit against the applicative fleet:

```sh
./secrets-vault-standard/audit-fleet.sh \
  --repo-root /Users/natan/projects/repos
```

The default inventory resolves automatically to
`/Users/natan/projects/repos/infra/argocd-infra/apps/applicative`. The report
renders to stdout as markdown.

## CLI Options

```
--inventory <path>       ArgoCD applicative inventory YAML file or directory
                         (default: <repo-root>/infra/argocd-infra/apps/applicative)
--repo-root <path>       base dir where repos are cloned (required)
--output <path>          write report to file instead of stdout
--format <fmt>           markdown (default) | json
--standard-version <ver> standard version to score against (default: 1.0.0)
--scan-root              also scan repo-root non-appPath config files (VS-006)
--verbose                print per-file detection details to stderr
--help                   show this help and exit 0
```

### Common invocations

```sh
# Full fleet audit (markdown to stdout)
./secrets-vault-standard/audit-fleet.sh --repo-root /Users/natan/projects/repos

# Machine-readable output for CI / scripts
./secrets-vault-standard/audit-fleet.sh --repo-root /Users/natan/projects/repos --format json

# Save the report to a file
./secrets-vault-standard/audit-fleet.sh --repo-root /Users/natan/projects/repos \
  --output /tmp/secrets-vault-report.md

# Include repo-root files (e.g. *.env, non-appPath config) in the committed-secrets scan
./secrets-vault-standard/audit-fleet.sh --repo-root /Users/natan/projects/repos --scan-root

# Audit a specific inventory (e.g. demo fixtures)
./secrets-vault-standard/audit-fleet.sh \
  --repo-root secrets-vault-standard/fixtures \
  --inventory specs/013-secrets-vault-standard/checklists/fixture-inventory
```

## Exit Codes

| Code | Meaning |
|------|---------|
| `0` | All repos CONFORMING or N/A (no non-conformances) |
| `1` | One or more repos NON-CONFORMING |
| `2` | Inventory not found or unparseable |
| `3` | One or more repos not found locally (resolution failure) |

## Verdicts

| Verdict | Meaning |
|---------|---------|
| `CONFORMING` | All primary rules pass |
| `NON-CONFORMING` | At least one primary rule FAILs; the report names the gap and a `fix:` |
| `N/A` | Repo uses no secrets/vault infrastructure — never a failure |
| `UNKNOWN` | Secrets handling is not expressible from git-tracked manifests (e.g. unresolved store, no local checkout). Reason is reported; requires manual review. Never silently conforming. |

## The Rules (VS-001 … VS-007)

Rules live in `specs/013-secrets-vault-standard/contracts/standard.md`. Primary
rules gate the verdict; advisory rules are reported but never block.

| Rule | Check | Weight |
|------|-------|--------|
| VS-001 | Vault-backed store declared (`provider.vault`) | Primary (blocking) |
| VS-002 | Kubernetes auth method used | Primary (blocking) |
| VS-003 | ExternalSecret references the Vault store | Primary (blocking) |
| VS-004 | DRY path convention `/<env>/<service>/<key>` | Advisory (non-blocking) |
| VS-005 | Secrets consumed via ESO-created Secrets (not manual `kind: Secret`) | Advisory (non-blocking) |
| VS-006 | No committed secret material (bcrypt hashes, API keys, PII, credentials) | Primary (blocking) |
| VS-007 | No static/long-lived Vault tokens | Primary (blocking) |

> A repo that mixes Vault/ESO with a manual Secret (`kind: Secret`) is
> NON-CONFORMING with both patterns named (FR-004). Repos with no local
> checkout are reported UNKNOWN with a reason and still count toward the fleet
> total (SC-001).

## Reading the Report

Markdown output is two parts:

1. **Fleet Summary** — per-verdict counts plus the total.
2. **Per-repo sections** — a rule table (`Rule | Verdict | Evidence | Fix`)
   for each repo. `Fix` is populated only on FAIL rows; a NON-CONFORMING repo
   always carries at least one `fix:`.

JSON output (`--format json`) mirrors this: `summary` at the top, then one
entry per repo with `verdict`, `rules[]`, and `fix` on failures. Unresolved
repos appear with `notFound: true` and a `reason`.

## Typical Remediation Loop

1. Run the audit, capture a report (markdown or JSON).
2. For each `NON-CONFORMING` repo, apply the `fix:` on its failing rows
   (remove committed secrets, declare/point at a Vault-backed store, switch
   auth to Kubernetes, remove static tokens).
3. Re-audit the same args — verdicts are deterministic for unchanged repos
   (FR-007/SC-005), so the repo flips to `CONFORMING` only when the fix
   actually lands.

## Path-Convention Alignment (VS-004)

`align-fleet.sh` rewrites ExternalSecret `key:`/`extract:` references to the
`/<env>/<service>/<key>` convention (leading slash, >=3 segments) and migrates
the corresponding Vault KV data. It mirrors the audit's inventory/`--repo-root`
interface and reuses the VS-003/VS-006 detectors to report blockers it will
never auto-fix.

Wires:
- `align-plan.py`: line-number-precise planner (comments survive untouched).
- Transform: `remoteRef.key` + `property` -> `/<key-path>/<property>`
  (`property` kept); `dataFrom[].extract.key` -> `/<key-path>/<target-name>`.
- `--apply-manifests` rewrites manifests in place with `.bak` backups;
  `--apply-vault` executes the KV migration (requires `vault` CLI + token) and
  is gated behind a confirmation prompt unless `--yes`.

### Recovering a skipped migration

If `--apply-manifests` ran without a follow-up `--apply-vault` (the migration
plan is generated from the pre-rewrite keys, so it is empty once manifests are
already conformant), `--apply-vault` falls back to reading each old path from
git `HEAD` at the same line — the in-place rewrite preserves line numbers, so
the pre-rewrite value at `file:line` is the old key. Example: after a fleet-wide
manifest rewrite was applied but Vault data still lives at the old paths,
running `--apply-vault --yes` rebuilds and executes the dropped migration.

```sh
./secrets-vault-standard/align-fleet.sh --repo-root /Users/natan/projects/repos \
  --apply-vault --yes
# Vault KV migration recovered from git HEAD (manifests already rewritten)
```

Requirements: the rewrite must be **uncommitted** (git `HEAD` still holds the
old keys) and each repo must be a git checkout. Once the rewrite is committed,
dry-run exits `0` (no recovery rows, nothing pending).

```sh
# Preview the plan + vault ops (no changes)
./secrets-vault-standard/align-fleet.sh --repo-root /Users/natan/projects/repos

# Apply manifests, then migrate Vault data
./secrets-vault-standard/align-fleet.sh --repo-root /Users/natan/projects/repos \
  --apply-manifests --yes
./secrets-vault-standard/align-fleet.sh --repo-root /Users/natan/projects/repos \
  --apply-vault --yes
```

Exit codes: `0` = nothing to change (dry-run) or applied cleanly; `1` =
pending plan (dry-run) or apply left SKIP/blockers; `2` = usage/inventory
error. Blockers (VS-003 unresolved stores, VS-006 committed secrets) are
always reported and never auto-fixed.

> **Ordering matters**: run `--apply-vault` *before* committing the rewritten
> manifests. The migration plan is generated from `remoteRef.key`/`extract.key`
> values; once a rewrite is committed, the old key is gone from git and cannot
> be inferred. `--apply-vault` recovers the old paths from git `HEAD` when the
> manifests were rewritten but not yet committed (see "Recovering a skipped
> migration" below).

## Tests & Validation

```sh
bats secrets-vault-standard/tests/detectors.bats                       # 16
bats secrets-vault-standard/tests/audit-fleet.bats   # 18 (run per-suite subset in a TTY)
bats secrets-vault-standard/tests/align-fleet.bats                      # 11
bats cicd-tests/secrets_vault_inventory.bats                           # 8
shellcheck secrets-vault-standard/*.sh secrets-vault-standard/detectors/*.sh
```

> Note: the full `audit-fleet.bats` suite can hang in interactive TTY
> harnesses; filter by name (e.g. `bats -f markdown:`) or set
> `BATS_TEST_TIMEOUT=40`. This is a harness artifact, not a code defect.

## Design Notes

- **Offline only**: detection reads git-tracked manifests; no network, cloud,
  or Vault access is required (FR-002).
- **Deterministic**: unchanged repos yield identical verdicts across runs and
  environments (FR-007).
- **Gate enforcement** (failing the PR/CI gate) is a gated follow-on bump
  (RFC behind the Pending Decision Log "Ownership"); this deliverable is the
  point-in-time fleet audit (FR-009).