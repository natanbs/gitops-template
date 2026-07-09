# Research: K8s Service Templates with Persistent Storage

No unknowns required research. All technical context was determined directly from the existing codebase:

## Decisions

| Decision | Value | Rationale |
|----------|-------|-----------|
| PVC Manifest Template | `init/k8s/pvc.tmpl.yaml` | Follows existing `*.tmpl.yaml` convention in `init/k8s/` |
| Env var defaults | PVC=false, PVC_NAME=<app>-data, PVC_MOUNT_PATH=/data, PVC_SIZE=1Gi, PVC_ACCESS_MODE=ReadWriteOnce, PVC_STORAGE_CLASS=standard | Confirmed via /spec.clarify session |
| Template variable substitution | Shell variable expansion (${VAR}) | Existing pattern in all tmpl.yaml files; rendered by envsubst or shell |
| PVC detection mechanism | Read `PVC` key from `.env` file | Existing pattern: init.sh already reads PVC_NAME/PVC_MOUNT_PATH from .env |
| Backward compatibility | PVC=false by default; no PVC resources generated when unset/false | Existing services unchanged |

## K8s PVC Best Practices

- Use `PersistentVolumeClaim` with `ReadWriteOnce` for single-pod workloads
- Specify `storageClassName` explicitly rather than relying on cluster default — pre-existing cluster may not have a default
- PVC mount path `/data` is conventional for application data directories
- PVC naming convention `<app-name>-data` avoids conflicts within namespace
- PVC reclaim policy is set at the StorageClass level, not on the PVC itself
