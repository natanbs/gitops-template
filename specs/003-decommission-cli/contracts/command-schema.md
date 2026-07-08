# CLI Contract: Decommission

## Command Syntax

```
decommission <service-name> [flags]
```

### Positional Arguments

| Argument | Required | Description |
|----------|----------|-------------|
| `service-name` | yes | Name of the service to decommission |

### Flags

| Flag | Type | Default | Description |
|------|------|---------|-------------|
| `--namespace` / `-n` | string | `default` | K8s namespace |
| `--force` | bool | `false` | Skip pre-decommission safety checks |
| `--dry-run` | bool | `false` | Show planned actions without executing |
| `--json` | bool | `false` | Output audit record as JSON instead of text |
| `--audit-dir` | string | `./decommission-audit/` | Directory for audit log files |
| `--operator` | string | `$USER` | Operator name for audit trail |
| `--version` | bool | `false` | Print version and exit |
| `--help` | bool | `false` | Print help text and exit |

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Decommission completed successfully |
| 1 | Pre-checks failed (service not found, active traffic, etc.) |
| 2 | Deployment not found or inaccessible |
| 3 | Deletion failed (partial state reached) |
| 4 | Registry cleanup failed (non-fatal exit, resources already removed) |
| 5 | Invalid arguments or missing required flags |

## Execution Flow

1. Parse arguments → validate service name and flags
2. Check prerequisites (kubectl context, required CLIs)
3. If `--dry-run`: display planned steps → exit 0
4. Run pre-checks (unless `--force`) → fail with exit 1 if any check fails
5. Detect deployment model (ArgoCD vs direct)
6. Detect PVCs → prompt operator
7. Execute resource deletion (GitOps or Direct Deploy path)
8. Attempt container image cleanup
9. Write audit record
10. Exit 0 (or appropriate error code on failure)

## Audit Output Format

### Text mode (default)
```
Service: my-api
Namespace: apps-ns
Deployment Model: gitops
Decommissioned By: jdoe
Date: 2026-07-07T12:00:00Z
Pre-checks Passed: Yes
Resources Removed: Deployment, Service, Ingress
Container Image Deleted: Yes
Status: completed
Notes:
```

### JSON mode (`--json`)
```json
{
  "service_name": "my-api",
  "namespace": "apps-ns",
  "deployment_model": "gitops",
  "operator": "jdoe",
  "timestamp": "2026-07-07T12:00:00Z",
  "pre_checks_passed": true,
  "resources_removed": ["Deployment", "Service", "Ingress"],
  "image_deleted": true,
  "status": "completed",
  "notes": ""
}
```

## Human-Readable Output

Each step prints a progress line:
```
✓ Pre-checks passed
  → Deployment model: GitOps (ArgoCD)
  → No PVCs found
  → Removing manifests from repo...
  → Waiting for ArgoCD prune... done
  → Verifying cleanup... all resources removed
  → Deleting container image... done
✓ Decommission complete
```

Error output:
```
✗ Pre-checks failed: Service "my-api" has active traffic (5 current connections)
  Use --force to bypass this check
```
