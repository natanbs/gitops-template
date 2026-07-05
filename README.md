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

### Step 2: Prepare your application

Place a `Dockerfile` at the root of your app directory:

```bash
# Example: simple Go HTTP server
cat > Dockerfile <<'EOF'
FROM golang:1.22-alpine AS builder
WORKDIR /app
COPY main.go .
RUN go build -o server main.go

FROM alpine:3.19
WORKDIR /app
COPY --from=builder /app/server .
EXPOSE 8080
CMD ["./server"]
EOF
```

### Step 3: Build, push, and deploy

```bash
# Clone this template alongside your app
git clone https://github.com/natanbs/gitops-template.git
cd gitops-template

# Build Docker image and push to the local registry (port 50000)
./build.sh --app-name my-app --image-tag v1.0 \
  --registry-url localhost --registry-port 50000

# Build + deploy to Kubernetes in one command
./build.sh --app-name my-app --image-tag v1.0 \
  --registry-url localhost --registry-port 50000 \
  --k8s-namespace default \
  --auto-deploy
```

### Step 4: Full GitOps pipeline

```bash
# Build, push, generate manifests, and create ArgoCD Application
./build.sh --app-name my-app --image-tag v1.0 \
  --registry-url localhost --registry-port 50000 \
  --app-repo-url https://github.com/your-org/my-app.git \
  --auto-deploy
```

From this point, ArgoCD watches the repo and auto-syncs changes.

---

### Common build scenarios

**Using a custom registry (Docker Hub, ECR, GCR):**
```bash
./build.sh --app-name my-app --image-tag v1.0 \
  --registry-url docker.io \
  --registry-port 443
```

**Building for a specific namespace:**
```bash
./build.sh --app-name my-app --image-tag v1.0 \
  --registry-url localhost --registry-port 50000 \
  --k8s-namespace production \
  --auto-deploy
```

**Recovering from a partial failure:**
```bash
./build.sh --app-name my-app --image-tag v1.0 \
  --registry-url localhost --registry-port 50000 \
  --continue-on-error
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
# 1. Copy build.sh into your project
cp -r <gitops-template>/* .

# 2. Add your Dockerfile at the root

# 3. Build, tag, and push your image
./build.sh --app-name my-app --image-tag v1.0

# 4. Build + deploy to Kubernetes
./build.sh --app-name my-app --image-tag v1.0 --auto-deploy
```

---

## CLI Reference

### Required Arguments

| Argument       | Description                                          |
|----------------|------------------------------------------------------|
| `--app-name`   | Application name (k8s-safe: lowercase, hyphens only) |
| `--image-tag`  | Docker image tag (e.g. `v1.0`, `latest`)             |

### Optional Arguments

| Argument              | Default                    | Description                                 |
|-----------------------|----------------------------|---------------------------------------------|
| `--registry-url`      | `$REGISTRY_URL` or `k3d-registry.localhost` | Container registry hostname |
| `--registry-port`     | `$REGISTRY_PORT` or `5000` | Container registry port      |
| `--k8s-namespace`     | `$K8S_NAMESPACE` or `default` | Kubernetes namespace      |
| `--container-port`    | `$CONTAINER_PORT` or `8080` | Container port for K8s manifests |
| `--app-repo-url`      | _(none)_                   | Git repo URL (for ArgoCD Application manifest) |
| `--auto-deploy`       | `false`                    | Apply generated manifests to cluster          |
| `--continue-on-error` | `false`                    | Continue pipeline on step failure             |
| `--help`              | —                          | Show help message                             |

### Environment Variables

All optional arguments can also be set via environment variables:
`REGISTRY_URL`, `REGISTRY_PORT`, `K8S_NAMESPACE`, `CONTAINER_PORT`.

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
| `tests/integration.bats` | End-to-end pipeline integration     |

---

## Project Structure

```
.
├── build.sh                 # Main CI/CD pipeline script
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
│   └── integration.bats
├── .shellcheckrc            # ShellCheck configuration
└── README.md                # This file
```

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---------|-------------|-----|
| `--app-name is required` | Missing required argument | Add `--app-name my-app` |
| `k8s-safe` validation error | App name has uppercase/underscore | Use lowercase, hyphens only |
| `docker: command not found` | Docker not installed | Install Docker Desktop |
| `Cannot connect to the Docker daemon` | Docker not running | Start Docker Desktop |
| `no such host` on push | Registry not reachable | Run `./argocd.sh` from argo-bootstrap, or check `--registry-url` |
| `connection refused` on push | Registry not running or wrong port | Run `docker push localhost:50000/test:latest` to verify connection |
| `kubectl apply` fails | No cluster or wrong context | Run `kubectl cluster-info` |
| `envsubst: command not found` | GNU gettext not installed | `brew install gettext` (macOS) or `apt install gettext` (Linux) |
| `step 'Docker Tag/Push' failed` | Registry auth or connection | Run `docker login`, verify `--registry-url` and `--registry-port` |
