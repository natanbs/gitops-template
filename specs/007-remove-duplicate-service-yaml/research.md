# Research: Remove Duplicate Service YAML

## Decisions

| Decision | Chosen | Rationale | Alternatives Considered |
|----------|--------|-----------|------------------------|
| File to keep | `svc.yaml` | Already had port naming (`name: http`), matches convention of other k8s files | Keeping both (rejected — causes drift risk) |
| Deletion method | `rm` | Immediate cleanup, reversible via git | Move to backup (unnecessary — git tracks history) |

## Verification

```bash
# Dry-run to confirm surviving manifest is valid
kubectl apply --dry-run=client -f k8s/svc.yaml

# Confirm live service is unchanged
kubectl get service analyst -n apps-ns -o yaml

# Confirm only svc.yaml remains
ls k8s/svc.yaml
```
