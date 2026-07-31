# Interface Contracts: init.sh Syncs K8s Port from CONTAINER_PORT

## 1. `init.sh` CLI

```
../gitops-template/init.sh --deploy
```

- `--build`: after scaffolding/sync, runs `build.sh` (build + push).
- `--deploy`: implies `--build`; additionally passes `--auto-deploy`.
- Behavior contract for this feature: when invoked with `--build` or `--deploy` against
  an existing app (directory already present), the script rewrites the port fields of
  existing `k8s/svc.yaml`, `k8s/deploy.yaml`, `k8s/ingress.yaml` to match the effective
  `CONTAINER_PORT` before applying manifests / invoking `build.sh`.
- Without `--build`/`--deploy`, existing manifests are not modified.

## 2. `.env` schema (relevant keys)

| Key | Meaning | Example |
|-----|---------|---------|
| `APP_NAME` | Application name (k8s-safe) | `my-api` |
| `CONTAINER_PORT` | Container/service port; single source of truth for k8s ports | `9000` |

CLI flag precedence: `--container-port` > `.env` `CONTAINER_PORT` > default `8080`.

## 3. `build.sh` CLI

```
../gitops-template/build.sh --app-name <name> --image-tag <tag> [--auto-deploy]
```

- `--auto-deploy`: apply generated/updated manifests to the cluster.
- Behavior contract for this feature: during template processing, existing
  `k8s/deploy.yaml`, `k8s/svc.yaml`, and `k8s/ingress.yaml` get their port fields
  updated to the effective `CONTAINER_PORT` in place (alongside the existing
  image/IMAGE_TAG update for `deploy.yaml`). `k8s/pvc.yaml` is untouched.
- Missing manifest files are skipped without error.

## 4. Manifest field contract (port fields, after sync)

| Manifest | Field(s) | Value |
|----------|----------|-------|
| `svc.yaml` | `spec.ports[].port`, `spec.ports[].targetPort` | effective `CONTAINER_PORT` |
| `deploy.yaml` | `containerPort`, liveness/readiness probe `port` | effective `CONTAINER_PORT` |
| `ingress.yaml` | `backend.service.port.number` | effective `CONTAINER_PORT` |

All other content of existing manifests is preserved verbatim.
