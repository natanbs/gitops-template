# CI/CD Flow: From Code Change to Deployment

## Architecture Overview

```
┌──────────────────────────────────────────────────────────────┐
│                     Three Repositories                        │
├──────────────┬──────────────────┬────────────────────────────┤
│ argo-bootstrap│  gitops-template │     App Repo (your app)    │
│              │  (this repo)     │                            │
│ Cluster      │  Generic pipeline │   Contains:                │
│  setup +     │  build.sh + K8s  │   - Dockerfile             │
│  ArgoCD      │  templates       │   - Source code            │
│  install     │                  │   - K8s manifests (gen'd)  │
└──────┬───────┴────────┬─────────┴──────────────┬─────────────┘
       │                │                        │
       ▼                ▼                        ▼
┌──────────────────────────────────────────────────────────────┐
│                    k3d Cluster (cluster-argo)                  │
│  ┌──────────┐  ┌──────────┐  ┌────────────────────────────┐  │
│  │ ArgoCD   │  │ Registry │  │ App Pods (Deployment,      │  │
│  │ (argocd  │  │ (port    │  │  Service, Ingress)         │  │
│  │  ns)     │  │  50000)  │  │                            │  │
│  └──────────┘  └──────────┘  └────────────────────────────┘  │
└──────────────────────────────────────────────────────────────┘
```

## Two Deployment Models

### Model A: Manual CI/CD (Direct Deploy)

Developer runs `build.sh` locally — immediate feedback, no GitOps.

```
Code Change
    │
    ▼
┌─────────────────────────────────────────┐
│  1. git commit & push (optional)        │
│  2. ./build.sh --app-name X --image-tag Y│
│     │                                   │
│     ├─ 1. Build   docker build          │
│     ├─ 2. Tag     docker tag            │
│     ├─ 3. Push    docker push           │
│     ├─ 4. Template envsubst → .yaml     │
│     └─ 5. Deploy  kubectl apply         │
└─────────────────────────────────────────┘
    │
    ▼
App running on cluster at the new version
```

**When to use**: Development, testing, hotfixes, when you want full control.

### Model B: GitOps (ArgoCD Auto-Sync)

Developer pushes code — ArgoCD detects change and deploys automatically.

```
Code Change
    │
    ▼
┌─────────────────────────────────────────┐
│  1. Developer commits code              │
│  2. CI runs build.sh to:                │
│     - Build & push Docker image         │
│     - Generate K8s manifests            │
│     - Generate ArgoCD Application       │
│  3. Push manifests to app repo          │
└─────────────────────────────────────────┘
    │
    ▼  (ArgoCD detects drift)
┌─────────────────────────────────────────┐
│  ArgoCD syncPolicy:                     │
│  - selfHeal: true   (fixes drift)       │
│  - prune: true      (removes old res)   │
│  - CreateNamespace  (auto-create ns)    │
└─────────────────────────────────────────┘
    │
    ▼
Cluster state matches git → app updated
```

**When to use**: Production, teams, audit trail, multi-environment.

---

## Step-by-Step: The Full Flow

### Phase 0: One-Time Infrastructure Setup

```bash
# ── 1. Bootstrap cluster + ArgoCD ──────────────────────────
git clone https://github.com/natanbs/argo-bootstrap.git
cd argo-bootstrap
./argocd.sh
```

What this does:
| Step | Action | Result |
|------|--------|--------|
| 0a | Install k3d, kubectl, argocd CLI | Tooling ready |
| 0b | Create local registry (port 50000) | `localhost:50000` |
| 0c | Create k3d cluster `cluster-argo` | 2 agents, ports mapped |
| 0d | Install ArgoCD in `argocd` namespace | ArgoCD running |
| 0e | Patch ArgoCD to LoadBalancer + Ingress | Accessible at `localhost:8081` |
| 0f | Set admin password to `ChangeMe` | Login ready |

```bash
# Verify
kubectl cluster-info
kubectl get pods -n argocd
curl -k https://localhost:8081  # ArgoCD UI
```

### Phase 1: Onboard a New App (one-time per app)

```bash
# ── 1. Scaffold from template ───────────────────────────────
# Clones gitops-template, renames to my-app, inits git, writes .env
./init.sh --app-name my-app --dockerfile go

cd my-app

# ── 2. First build (flags come from .env) ──────────────────
./build.sh --image-tag v1.0

# ── 3. First deploy ─────────────────────────────────────────
./build.sh --image-tag v1.0 --auto-deploy

# ── 4. Enable GitOps: push + generate ArgoCD Application ───
git remote add origin https://github.com/your-org/my-app.git
git push -u origin main

./build.sh --image-tag v1.0 \
  --app-repo-url https://github.com/your-org/my-app.git \
  --auto-deploy

git add argocd/application.yaml
git commit -m "Add ArgoCD Application manifest"
git push
```

What gets created:

| Artifact | Location | From Template |
|----------|----------|---------------|
| Docker image | `localhost:50000/my-app:v1.0` | `Dockerfile` |
| Deployment | `k8s/deploy.yaml` | `k8s/deploy.tmpl.yaml` |
| Service | `k8s/svc.yaml` | `k8s/svc.tmpl.yaml` |
| Ingress | `k8s/ingress.yaml` | `k8s/ingress.tmpl.yaml` |
| ArgoCD App | `argocd/application.yaml` | `argocd/application.tmpl.yaml` |

### Phase 2: Daily Development Cycle

#### For a bugfix or feature (Manual CI/CD):

```bash
# 1. Make code changes
vim main.go

# 2. Build + deploy in one shot (--app-name from .env)
./build.sh --image-tag v1.1 --auto-deploy

# 3. Verify
curl localhost:8090/healthz
kubectl get pods -n my-app
```

#### For a GitOps-managed app:

```bash
# 1. Make code changes
vim main.go

# 2. Build + push image (no direct deploy)
./build.sh --image-tag v1.1

# 3. Update manifests and push to git
git add k8s/ argocd/
git commit -m "Update my-app to v1.1"
git push

# 4. ArgoCD auto-syncs (within ~3 min default)
#    Or trigger manually:
argocd app sync my-app
```

---

## Pipeline Step Details

### Step 1: Docker Build

```
Input:  Dockerfile, app source
Action: docker build -t <app>:<tag> .
Output: Local Docker image
```

The Docker image is tagged locally with the app name and tag
(e.g., `my-app:v1.1`).

### Step 2: Tag & Push

```
Input:  Local Docker image
Action: docker tag + docker push to registry
Output: Image in registry at <url>:<port>/<app>:<tag>
        (e.g., localhost:50000/my-app:v1.1)
```

### Step 3: Template Processing

```
Input:  *.tmpl.yaml files (k8s/ + argocd/)
Action: envsubst substitutes ${VARIABLES} with flag values
Output: *.yaml files with concrete values

Variables injected:
  ${APP_NAME}       →  my-app
  ${IMAGE_TAG}      →  v1.1
  ${REGISTRY_URL}   →  localhost
  ${REGISTRY_PORT}  →  50000
  ${K8S_NAMESPACE}  →  my-app
  ${CONTAINER_PORT} →  8080
  ${APP_REPO_URL}   →  https://github.com/.../my-app.git
```

### Step 4: Deploy (--auto-deploy only)

```
Input:  Generated *.yaml files
Action: kubectl apply -f <file> --namespace <ns>
Output: Resources created/updated on cluster

Resources applied:
  - k8s/deploy.yaml    →  Deployment
  - k8s/svc.yaml       →  Service
  - k8s/ingress.yaml   →  Ingress
  - argocd/*.yaml      →  ArgoCD Application
```

---

## Error Handling

```
Failure at any step:
  Default: abort → exit 1 → no partial state applied
  With --continue-on-error: log error → continue pipeline
```

| Step fails | Default behavior | With --continue-on-error |
|------------|-----------------|--------------------------|
| Docker build | Exit (no image) | Skip to tag/push (will fail) |
| Docker push | Exit (image tagged locally only) | Skip to template processing |
| Template | Exit (no manifests) | Skip to deploy (no files) |
| Deploy | Exit (partial apply) | Continue, report failure |

---

## Verification Commands

```bash
# After deploy, verify the app is running
kubectl get all -n my-app

# Check the image that was deployed
kubectl get deployment my-app -n my-app -o jsonpath='{.spec.template.spec.containers[0].image}'

# Check ArgoCD Application status
argocd app get my-app

# Check registry contents
curl -s http://localhost:50000/v2/_catalog | jq
curl -s http://localhost:50000/v2/my-app/tags/list | jq

# Rollback to previous version (Manual)
./build.sh --app-name my-app --image-tag v1.0 --auto-deploy

# Rollback (GitOps — revert and push)
git revert HEAD
git push
# ArgoCD auto-syncs to the previous state
```

## Summary: Key Commands Reference

| Action | Command |
|--------|---------|
| Bootstrap cluster | `cd argo-bootstrap && ./argocd.sh` |
| Scaffold new app | `./init.sh --app-name X --dockerfile go` |
| Build image only | `./build.sh --image-tag Y` (uses `.env` for app/registry) |
| Build + Deploy | `./build.sh --image-tag Y --auto-deploy` |
| Enable GitOps | Add `--app-repo-url https://github.com/...` |
| Skip failures | Add `--continue-on-error` |
| Check ArgoCD UI | Open `https://localhost:8081` (admin / ChangeMe) |
| Force ArgoCD sync | `argocd app sync X` |
| View running apps | `kubectl get pods -A` |
