# Contract: PVC Template Variables

## Interface: init.sh → k8s tmpl.yaml files

init.sh reads PVC variables from `.env` and substitutes them into the k8s template files (either via `envsubst` or direct shell variable expansion).

### Input (from .env)

| Variable | Required | Default | Example |
|----------|----------|---------|---------|
| PVC | Yes | false | `PVC=true` |
| PVC_NAME | Only if PVC=true | `<app>-data` | `PVC_NAME=my-api-data` |
| PVC_MOUNT_PATH | Only if PVC=true | `/data` | `PVC_MOUNT_PATH=/var/lib/data` |
| PVC_SIZE | Only if PVC=true | `1Gi` | `PVC_SIZE=10Gi` |
| PVC_ACCESS_MODE | Only if PVC=true | `ReadWriteOnce` | `PVC_ACCESS_MODE=ReadWriteMany` |
| PVC_STORAGE_CLASS | Only if PVC=true | `standard` | `PVC_STORAGE_CLASS=ssd` |

### Output (generated files)

When PVC=true, init.sh generates:

1. **pvc.tmpl.yaml** → rendered to `k8s/pvc.yaml`:
   - Uses PVC_NAME, PVC_SIZE, PVC_ACCESS_MODE, PVC_STORAGE_CLASS
   - Output: valid PVC manifest

2. **Volume mounts string** → substituted into `${VOLUME_MOUNTS}` in deploy.tmpl.yaml:
   - Uses PVC_NAME, PVC_MOUNT_PATH
   - Format: standard K8s volumeMounts YAML block

3. **Volumes string** → substituted into `${VOLUMES}` in deploy.tmpl.yaml:
   - Uses PVC_NAME
   - Format: standard K8s volumes YAML block

### Contract invariants

- When PVC=false, `${VOLUME_MOUNTS}` and `${VOLUMES}` must be empty string (no whitespace)
- PVC_NAME must be a valid K8s resource name (lowercase, hyphens, 253 chars max)
- PVC_SIZE must be a valid K8s resource quantity
- PVC_ACCESS_MODE must be ReadWriteOnce, ReadOnlyMany, or ReadWriteMany
