# GitOps Template

A reusable CI/CD pipeline template for building, containerizing, and deploying
any application to Kubernetes via ArgoCD. Zero hardcoded names — everything is
parameterized via CLI flags or environment variables.

## How to Build

### End-to-end workflow

This template is designed to work with the
[argo-bootstrap](https://github.com/natanbs/argo-bootstrap) repo which bootstraps
a k3d cluster with ArgoCD and a local registry. The flow is:

```text
argo-bootstrap                  gitops-template (this repo)
┌─────────────────┐            ┌─────────────────────────────┐
│ 1. Create k3d   │            │ 1. Prepare app Dockerfile   │
│    cluster      │            │ 2. Run build.sh to:         │
│ 2. Install      │            │    - build Docker image     │
│    ArgoCD       │            │    - tag & push to registry │
│ 3. Setup local  │            │    - generate K8s manifests │
│    registry     │            │    - apply to cluster       │
│    (port 50000) │            │ 3. ArgoCD syncs changes     │
└─────────────────┘            └─────────────────────────────┘
```

### Step 1: Bootstrap the infrastructure (one-time)

Clone and run the [argo-bootstrap](https://github.com/natanbs/argo-bootstrap)
repo to create a k3d cluster with ArgoCD and a local registry:

```bash
git clone https://github.com/natanbs/argo-bootstrap.git
cd argo-bootstrap
./argocd.sh
```

This sets up:
- A k3d cluster named `cluster-argo`
- A local container registry at `localhost:50000`
- ArgoCD installed in the `argocd` namespace
- Port mapping: `8081:80` (ArgoCD UI), `8090:8090` (app traffic)

### Step 2: Scaffold your app project

```bash
# One command: copies template, inits git, writes .env, scaffolds Dockerfile
./init.sh --app-name my-api --dockerfile go

cd my-api
```

This creates `my-api/` with:
- `build.sh` — the pipeline script
- `.env` — project config (no need to repeat `--registry-url` etc.)
- `Dockerfile` — sample Go Dockerfile
- `k8s/` — K8s manifest templates
- `argocd/` — ArgoCD Application template
- Fresh git history

### Step 3: Build, push, and deploy

```bash
# First build (--app-name and registry come from .env)
./build.sh --image-tag v1.0

# Build + deploy to Kubernetes
./build.sh --image-tag v1.0 --auto-deploy
```

### Step 4: Full GitOps pipeline

```bash
# Push your repo, then generate ArgoCD manifest
git remote add origin https://github.com/your-org/my-api.git
git push -u origin main

./build.sh --image-tag v1.0 \
  --app-repo-url https://github.com/your-org/my-api.git \
  --auto-deploy

git add argocd/application.yaml
git commit -m "Add ArgoCD Application manifest"
git push
```

ArgoCD now watches the repo and auto-syncs changes.

---

### Common scenarios

**Using a custom registry (Docker Hub, ECR, GCR):**
```bash
# Edit .env
sed -i '' 's/REGISTRY_URL=.*/REGISTRY_URL=docker.io/' .env
sed -i '' 's/REGISTRY_PORT=.*/REGISTRY_PORT=443/' .env

# Or override on the CLI (takes precedence)
./build.sh --image-tag v1.0 --registry-url docker.io --registry-port 443
```

**Building for a specific namespace:**
```bash
# Edit .env or use --k8s-namespace
./build.sh --image-tag v1.0 --k8s-namespace production --auto-deploy
```

**Scaffolding without init.sh (copy template manually):**
```bash
git clone https://github.com/natanbs/gitops-template.git my-app
cd my-app
rm -rf .git
git init
git add .
git commit -m "Initial scaffold from gitops-template"
# Write your own .env:
cat > .env <<'EOF'
APP_NAME=my-app
REGISTRY_URL=localhost
REGISTRY_PORT=50000
K8S_NAMESPACE=my-app
CONTAINER_PORT=8080
EOF
```

**Recovering from a partial failure:**
```bash
./build.sh --image-tag v1.0 --continue-on-error
```

---

## Setup (without argo-bootstrap)

### Prerequisites

- **Docker** — Install [Docker Desktop](https://docs.docker.com/engine/install/)
- **kubectl** — `brew install kubectl` (macOS) or [binary download](https://kubernetes.io/docs/tasks/tools/)
- **envsubst** — Ships with GNU gettext (`brew install gettext` on macOS)
- **Container registry** — a local or remote registry to push images to

### Quick k3d cluster

```bash
brew install k3d
k3d cluster create my-cluster --registry-create k3d-registry
# Registry available at k3d-registry.localhost:5000
kubectl cluster-info
```

---

## Quickstart (minimal)

```bash
# 1. Scaffold a new Go app
./init.sh --app-name my-app --dockerfile go

cd my-app

# 2. Build + deploy in two commands
./build.sh --image-tag v1.0
./build.sh --image-tag v1.0 --auto-deploy
```

---

## CLI Reference

### `init.sh` — Scaffold a new project

| Argument              | Default       | Description                                  |
|-----------------------|---------------|----------------------------------------------|
| `--app-name NAME`     | _(required)_  | Application name (k8s-safe: lowercase, hyphens only) |
| `--dockerfile TYPE`   | `none`        | Sample Dockerfile: `go`, `python`, `node`, `none` |
| `--repo-url URL`      | _(remote repo)_ | Clone from custom remote instead of default |
| `--local`             | `false`         | Copy local template directory instead of cloning |
| `--registry-url URL`  | `localhost`   | Container registry hostname                  |
| `--registry-port PORT`| `50000`       | Container registry port                      |
| `--k8s-namespace NS`  | _(app-name)_  | Kubernetes namespace                         |
| `--container-port PORT`| `8080`       | Container port for K8s manifests             |
| `--help`              | —             | Show help                                    |

### `build.sh` — CI/CD Pipeline

| Argument              | Default        | Description                                  |
|-----------------------|----------------|----------------------------------------------|
| `--app-name NAME`     | `.env` or _(required)_ | Application name                     |
| `--image-tag TAG`     | _(required)_   | Docker image tag (e.g. `v1.0`, `latest`)     |
| `--registry-url URL`  | `.env` or `k3d-registry.localhost` | Container registry hostname |
| `--registry-port PORT`| `.env` or `5000` | Container registry port                     |
| `--k8s-namespace NS`  | `.env` or `default` | Kubernetes namespace                     |
| `--container-port PORT`| `.env` or `8080` | Container port for K8s manifests            |
| `--app-repo-url URL`  | _(none)_       | Git repo URL (for ArgoCD Application manifest) |
| `--auto-deploy`       | `false`        | Apply generated manifests to cluster          |
| `--continue-on-error` | `false`        | Continue pipeline on step failure             |
| `--help`              | —              | Show help message                             |

### `.env` file

Place in the project root alongside `build.sh`. Loaded automatically
(script directory first, then current working directory).

```
APP_NAME=my-api
REGISTRY_URL=localhost
REGISTRY_PORT=50000
K8S_NAMESPACE=my-api
CONTAINER_PORT=8080
```

CLI flags always override `.env` values, which override built-in defaults.

---

## Pipeline Steps

1. **Build** — `docker build -t <app>:<tag> .`
2. **Tag** — `docker tag <app>:<tag> <registry>/<app>:<tag>`
3. **Push** — `docker push <registry>/<app>:<tag>`
4. **Template** — Process all `*.tmpl.yaml` files with `envsubst`
5. **Deploy** — `kubectl apply` (only with `--auto-deploy`)

---

## Template Variables

All variables use the `${VARIABLE_NAME}` syntax supported by `envsubst`.

### K8s Manifests (`k8s/*.tmpl.yaml`)

| Variable          | Source                   |
|-------------------|--------------------------|
| `${APP_NAME}`     | `--app-name`             |
| `${IMAGE_TAG}`    | `--image-tag`            |
| `${REGISTRY_URL}` | `--registry-url`         |
| `${REGISTRY_PORT}`| `--registry-port`        |
| `${K8S_NAMESPACE}`| `--k8s-namespace`        |
| `${CONTAINER_PORT}`| `--container-port`      |

### ArgoCD Application (`argocd/*.tmpl.yaml`)

| Variable           | Source                    |
|--------------------|---------------------------|
| `${APP_NAME}`      | `--app-name`              |
| `${APP_REPO_URL}`  | `--app-repo-url`          |
| `${K8S_NAMESPACE}` | `--k8s-namespace`         |

---

## Testing

```bash
# Run all bats tests
bats tests/
```

### Test Suites

| File                   | Tests                                  |
|------------------------|----------------------------------------|
| `tests/arguments.bats` | CLI argument parsing and validation   |
| `tests/errors.bats`    | Error handling and step failure       |
| `tests/manifests.bats` | K8s manifest generation and validation|
| `tests/argocd.bats`    | ArgoCD Application manifest validation|
| `tests/init_env.bats`  | `init.sh` scaffold + `.env` loading   |
| `tests/integration.bats` | End-to-end pipeline integration     |

---

## Project Structure

```
.
├── build.sh                 # Main CI/CD pipeline script
├── init.sh                  # Project scaffold script (one-time per app)
├── k8s/                     # Kubernetes manifest templates
│   ├── deploy.tmpl.yaml     # Deployment template
│   ├── svc.tmpl.yaml        # Service template
│   └── ingress.tmpl.yaml    # Ingress template (optional)
├── argocd/                  # ArgoCD manifest templates
│   └── application.tmpl.yaml # ArgoCD Application template
├── tests/                   # Bats test suites
│   ├── test_helper.bash     # Shared test utilities
│   ├── arguments.bats
│   ├── errors.bats
│   ├── manifests.bats
│   ├── argocd.bats
│   ├── init_env.bats
│   └── integration.bats
├── .shellcheckrc            # ShellCheck configuration
├── .gitignore               # Ignores .env, generated manifests, etc.
└── README.md                # This file
```

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---------|-------------|-----|
| `--app-name is required` | Missing from CLI and `.env` | Add `--app-name my-app` or set `APP_NAME=my-app` in `.env` |
| `k8s-safe` validation error | App name has uppercase/underscore | Use lowercase, hyphens only |
| `docker: command not found` | Docker not installed | Install Docker Desktop |
| `Cannot connect to the Docker daemon` | Docker not running | Start Docker Desktop |
| `no such host` on push | Registry not reachable | Run `./argocd.sh` from argo-bootstrap, or check `--registry-url` |
| `connection refused` on push | Registry not running or wrong port | Run `docker push localhost:50000/test:latest` to verify connection |
| `kubectl apply` fails | No cluster or wrong context | Run `kubectl cluster-info` |
| `envsubst: command not found` | GNU gettext not installed | `brew install gettext` (macOS) or `apt install gettext` (Linux) |
| `step 'Docker Tag/Push' failed` | Registry auth or connection | Run `docker login`, verify `--registry-url` and `--registry-port` |
| `init.sh: command not found` | Not in PATH | Run `./init.sh` from the gitops-template directory |
| `init.sh` clones stale content | Need local changes in template | Use `--local` to copy from your local working tree instead of the remote |
