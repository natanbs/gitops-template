# Command Schema: `decommission --list`

## Synopsis

List all discoverable services in the cluster.

```text
decommission --list [--namespace <ns>] [--json]
```

## Flags

| Flag | Type | Default | Description |
|------|------|---------|-------------|
| `--list` | bool | false | Enable service listing mode |
| `--namespace` | string | `""` (all) | Filter services by namespace |
| `--json` | bool | false | Output as JSON array |

## Behavior

1. When `--list` is provided, the CLI discovers all services by:
   - Listing all Deployments across all namespaces (or filtered by `--namespace`)
   - Checking each Deployment's name against ArgoCD Applications in the `argocd` namespace
   - Classifying each as GitOps or Direct Deploy
2. Output rows are sorted alphabetically by namespace, then by service name
3. When `--list` is provided with a service-name positional argument, the CLI MUST error with exit code 5

## Output Format

### Table (default, `--json=false`)

```text
NAMESPACE     NAME            MODEL     STATUS     REPLICAS
default       my-api          direct    Ready      3/3
production    web-frontend    gitops    Ready      5/5
staging       cache-redis     direct    Not Ready  0/1
```

### JSON (`--json=true`)

```json
{
  "services": [
    {
      "name": "my-api",
      "namespace": "default",
      "deployment_model": "direct",
      "status": "Ready",
      "available_replicas": 3
    }
  ],
  "total_count": 1
}
```

## Exit Codes

| Code | Condition |
|------|-----------|
| 0 | Success — listing completed |
| 5 | Invalid arguments (e.g., `--list` with service name) |
| 6 | Cluster unreachable or kubectl context issue |

## Error Messages

- `"Error: --list cannot be used with a service name"` — when both `--list` and positional arg are provided
- `"Error: cannot reach cluster: ..."` — when kubectl cluster-info or listing fails
