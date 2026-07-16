# CLI Contract: init.sh

## Usage

```
init.sh [--app-name NAME] [OPTIONS]
```

`--app-name` is **optional**. When omitted, the app name defaults to the current directory name (`basename "$PWD"`).

## Arguments

| Argument | Required | Default | Description |
|----------|----------|---------|-------------|
| `--app-name NAME` | No | `basename "$PWD"` | Application name (k8s-safe: lowercase, hyphens only). When omitted, derived from current directory. |
| `--dockerfile TYPE` | No | `none` | Scaffold a sample Dockerfile (`go`, `python`, `node`, `none`) |
| `--registry-url URL` | No | `localhost` | Container registry hostname |
| `--registry-port PORT` | No | `50000` | Container registry port |
| `--k8s-ns NS` | No | `apps-ns` | Kubernetes namespace |
| `--container-port PORT` | No | `8080` | External service port |
| `--build` | No | `false` | Run build.sh after scaffolding |
| `--deploy` | No | `false` | Run build.sh --auto-deploy after scaffolding |
| `--image-tag TAG` | No | auto-version | Docker image tag |
| `--force` | No | `false` | Force regeneration of templates |

## Exit Codes

| Code | Condition |
|------|-----------|
| 0 | Success |
| 1 | Unknown argument, missing required value, or validation failure |

## Error Messages

| Condition | Message |
|-----------|---------|
| Invalid K8s name characters | `ERROR: App name "My_App.Name" is not K8s-safe. Use lowercase letters, numbers, and hyphens only. Or provide --app-name explicitly.` |
| Blocklisted name | `ERROR: App name "gitops-template" is reserved. Use --app-name with a different name.` |
| Unknown argument | `ERROR: Unknown argument: <arg>` |

## Examples

```bash
# Default from folder name (NEW)
cd my-api && ../gitops-template/init.sh

# Explicit override (existing behavior, unchanged)
./init.sh --app-name my-api

# With additional options
cd my-api && ../gitops-template/init.sh --dockerfile go --build

# Explicit with sibling directory (existing behavior)
./init.sh --app-name my-api --dockerfile python
```
