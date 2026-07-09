# Quickstart: PVC Support for Services

## Enable persistent storage on a new service

```bash
../gitops-template/init.sh --app-name my-service
# .env now has PVC=false (default)

# Edit .env: set PVC=true
sed -i '' 's/PVC=false/PVC=true/' .env

# Re-run init.sh to populate PVC vars and generate manifests
../gitops-template/init.sh --app-name my-service
```

## Verify PVC resources

```bash
cat k8s/pvc.yaml        # Should show PVC manifest
cat k8s/deploy.yaml     # Should show volumeMounts and volumes
```

## Disable persistent storage

```bash
# Set PVC=false in .env and re-run
sed -i '' 's/PVC=true/PVC=false/' .env
../gitops-template/init.sh --app-name my-service
# Warning about data loss will appear unless --force is used
```

## Customize PVC parameters

Edit `.env`:
```
PVC=true
PVC_SIZE=10Gi
PVC_ACCESS_MODE=ReadWriteMany
PVC_STORAGE_CLASS=ssd
```

Then re-run `init.sh` to regenerate manifests with new values.
