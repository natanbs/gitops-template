# Contract: Audit CLI

**Interface**: `secrets-vault-standard/audit-fleet.sh`

## Command

```bash
./secrets-vault-standard/audit-fleet.sh [OPTIONS]
```

## Options

| Flag | Description | Default |
|------|-------------|---------|
| `--inventory <path>` | Path to ArgoCD applicative inventory YAML or directory of YAMLs | `<repo-root>/infra/argocd-infra/apps/applicative` |
| `--repo-root <path>` | Root directory where repos are cloned | **_required_** (no default) |
| `--output <path>` | Write report to file instead of stdout | stdout |
| `--format <fmt>` | Output format: `markdown` or `json` | `markdown` |
| `--standard-version <ver>` | Standard version to score against | `1.0.0` |
| `--scan-root` | Also scan repo-root non-appPath files (VS-006 opt-in) and record in report header | off |
| `--verbose` | Print per-file detection details | off |

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | All repos CONFORMING or N/A |
| 1 | One or more repos NON-CONFORMING |
| 2 | Inventory not found or unparseable |
| 3 | One or more repos not found locally |

## Input Contract

**Inventory format** (one YAML file per app in the inventory directory):

```yaml
name: analyst
repoURL: https://github.com/org/analyst.git
appPath: k8s
namespace: apps-ns
syncWave: "10"
```

**Repo resolution**: `{repo-root}/{name}` (the `name` field from the Argo YAML
matches the local directory name). If `{repo-root}/{name}` does not exist, the
repo is reported in the fleet summary as UNKNOWN with the reason "Repo not found
locally" and the audit exits with code 3 — it is never silently dropped from the
fleet count (SC-001).

> **NOT_FOUND vs UNKNOWN**: `NOT_FOUND` is a resolution failure (the repo is not
> present locally). It is surfaced in the report as an `UNKNOWN` row with a
> reason (and `notFound: true` in JSON) while exit code 3 is still returned.
> A repo that IS present but whose secret management cannot be determined from
> git-tracked manifests (unresolved store reference, manual review) is also
> `UNKNOWN`. The two are distinct and never conflated.

## Output Contract

See [report.md](report.md) for the full output schema.

**stdout behavior**: By default, the full markdown report is written to stdout.
With `--output <path>`, the report is written to the file instead.

**stderr behavior**: Progress/status messages (e.g., "Scanning analyst...") are
written to stderr. Error messages are also stderr.

## Invocation Examples

```bash
# Fleet-wide audit (default inventory path under --repo-root)
./secrets-vault-standard/audit-fleet.sh \
  --repo-root /Users/natan/projects/repos

# Custom inventory + repo root
./secrets-vault-standard/audit-fleet.sh \
  --inventory /path/to/inventory \
  --repo-root /path/to/repos

# Write report to file
./secrets-vault-standard/audit-fleet.sh \
  --repo-root /Users/natan/projects/repos --output fleet-report.md

# JSON output (for future gate integration)
./secrets-vault-standard/audit-fleet.sh \
  --repo-root /Users/natan/projects/repos --format json --output fleet-report.json
```

## Behavior

1. Parse inventory YAML(s) → enumerate `FleetApp` entities.
2. For each app:
   a. Resolve local path (`repo-root/name`).
   b. If not found → verdict = NOT_FOUND, continue.
   c. Run detectors (`vault-eso.sh`, `committed-secrets.sh`, `path-convention.sh`,
      `consumption-pattern.sh`, `static-tokens.sh`)
      against `appPath` (+ optional repo root for committed secrets).
   d. Aggregate per-rule results → `RepoVerdict`.
3. Assemble `FleetReport` (per-repo verdicts + summary).
4. Write output (stdout or file).
5. Exit with code 0, 1, 2, or 3.
