# Quickstart: Sync k8s Port from CONTAINER_PORT

## Change an existing app's port and redeploy

```bash
# 1. In your app repo, set the desired port
echo "CONTAINER_PORT=9000" >> .env

# 2. Deploy from any repo that is a sibling of gitops-template
../gitops-template/init.sh --deploy
```

The script rewrites the port fields in `k8s/svc.yaml`, `k8s/deploy.yaml`, and
`k8s/ingress.yaml` to `9000` (preserving all other customizations), applies the
manifests, then builds and deploys.

## Direct build.sh usage

```bash
../gitops-template/build.sh --app-name my-app --image-tag v1.0 --auto-deploy
```

Existing manifests also get their ports synced from `.env`.

## Behavior notes

- Port sync runs only with `--build` or `--deploy`; a plain `init.sh` run does not
  modify existing manifests.
- Re-running with an unchanged `CONTAINER_PORT` is a no-op (idempotent).
- Missing manifests are skipped without error.
