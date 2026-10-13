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
# One command: creates app directory, writes .env, scaffolds Dockerfile
./init.sh --app-name my-api --dockerfile go

cd my-api
```

This creates `my-api/` with:
- `.env` — project config (no need to repeat `--registry-url` etc.)
- `.gitignore` — ignores generated K8s manifests
- `Dockerfile` — sample Go Dockerfile (if requested)
- Fresh git history

### Step 3: Build, push, and deploy

```bash
# Build and push (fetch build.sh from the template repo)
curl -sL https://github.com/natanbs/gitops-template/raw/main/build.sh \
  | bash -s -- --app-name my-api --image-tag v1.0

# Build + deploy to Kubernetes
curl -sL https://github.com/natanbs/gitops-template/raw/main/build.sh \
  | bash -s -- --app-name my-api --image-tag v1.0 --auto-deploy
```

**Note:** `--app-name` can be omitted when running from the app directory (the script infers the name from the current directory) or when `.env` sets `APP_NAME`.

### Step 4: Full GitOps pipeline

```bash
# Push your repo, then generate ArgoCD manifest
git remote add origin https://github.com/your-org/my-api.git
git push -u origin main

curl -sL https://github.com/natanbs/gitops-template/raw/main/build.sh \
  | bash -s -- --app-name my-api --image-tag v1.0 \
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
curl -sL https://github.com/natanbs/gitops-template/raw/main/build.sh \
  | bash -s -- --app-name my-api --image-tag v1.0 \
    --registry-url docker.io --registry-port 443
```

**Building for a specific namespace:**
```bash
# Edit .env or use --k8s-ns
curl -sL https://github.com/natanbs/gitops-template/raw/main/build.sh \
  | bash -s -- --app-name my-api --image-tag v1.0 \
    --k8s-ns production --auto-deploy
```

**Recovering from a partial failure:**
```bash
curl -sL https://github.com/natanbs/gitops-template/raw/main/build.sh \
  | bash -s -- --app-name my-api --image-tag v1.0 --continue-on-error
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

cd ../my-app

# 2. Build + deploy in two commands
curl -sL https://github.com/natanbs/gitops-template/raw/main/build.sh \
  | bash -s -- --app-name my-app --image-tag v1.0
curl -sL https://github.com/natanbs/gitops-template/raw/main/build.sh \
  | bash -s -- --app-name my-app --image-tag v1.0 --auto-deploy
```

---

## CLI Reference

### `init.sh` — Scaffold a new project

| Argument              | Default       | Description                                  |
|-----------------------|---------------|----------------------------------------------|
| `--app-name NAME`     | folder name   | Application name (k8s-safe: lowercase, hyphens only). Defaults to the current directory name. |
| `--dockerfile TYPE`   | `none`        | Sample Dockerfile: `go`, `python`, `node`, `none` |
| `--registry-url URL`  | `localhost`   | Container registry hostname                  |
| `--registry-port PORT`| `50000`       | Container registry port                      |
| `--k8s-ns NS`         | `apps-ns`     | Kubernetes namespace                         |
| `--container-port PORT`| `8080`       | Container port for K8s manifests             |
| `--build`             | `false`       | Run build.sh after scaffolding (build + push) |
| `--deploy`            | `false`       | Run build.sh --auto-deploy after scaffolding |
| `--image-tag TAG`     | `v1.0`        | Docker image tag for --build/--deploy        |
| `--help`              | —             | Show help                                    |

### `build.sh` — CI/CD Pipeline

| Argument              | Default        | Description                                  |
|-----------------------|----------------|----------------------------------------------|
| `--app-name NAME`     | `.env` or CWD  | Application name (optional if set in `.env` or running from app dir) |
| `--image-tag TAG`     | _(auto)_      | Docker image tag (e.g. `v1.0`, `latest`). Omit to auto-increment the patch from `CURRENT_TAG`. |
| `--registry-url URL`  | `.env` or `k3d-registry.localhost` | Container registry hostname |
| `--registry-port PORT`| `.env` or `5000` | Container registry port                     |
| `--k8s-ns NS`         | `.env` or `default` | Kubernetes namespace                     |
| `--container-port PORT`| `.env` or `8080` | Container port for K8s manifests            |
| `--app-repo-url URL`  | _(none)_       | Git repo URL (for ArgoCD Application manifest) |
| `--auto-deploy`       | `false`        | Apply generated manifests to cluster          |
| `--continue-on-error` | `false`        | Continue pipeline on step failure             |
| `--template-repo-raw URL` | _(template repo)_ | Base URL for fetching K8s templates at build time |
| `--help`              | —              | Show help message                             |

### `.env` file

Place `.env` in the project root. Loaded automatically by `build.sh` and `init.sh`.

```
APP_NAME=my-api
GIT_REPO_BASE=https://github.com/your-org
REGISTRY_URL=localhost
REGISTRY_PORT=50000
REGISTRY_CLUSTER_URL=k3d-reg
REGISTRY_CLUSTER_PORT=5000
K8S_NAMESPACE=my-api
CONTAINER_PORT=8080
```

`build.sh` loads `.env` from the current working directory (or from the script directory if running via curl). CLI flags always override `.env` values, which override built-in defaults.

`init.sh` reads the same file. Re-running it on an existing app preserves your `.env` edits and re-syncs the image registry `REGISTRY_CLUSTER_URL:REGISTRY_CLUSTER_PORT` into `k8s/deploy.yaml` (your other manifest customizations are left untouched).

---

## Pipeline Steps

1. **Build** — `docker build -t <app>:<tag> .`
2. **Tag** — `docker tag <app>:<tag> <registry>/<app>:<tag>`
3. **Push** — `docker push <registry>/<app>:<tag>`
4. **Template** — Process all `*.tmpl.yaml` files with `envsubst`
5. **Deploy** — prepare the generated manifests for ArgoCD to apply from git (only with `--auto-deploy`)

---

## Template Variables

All variables use the `${VARIABLE_NAME}` syntax supported by `envsubst`.

### K8s Manifests (`k8s/*.tmpl.yaml`)

| Variable          | Source                   |
|-------------------|--------------------------|
| `${APP_NAME}`     | `--app-name`             |
| `${IMAGE_TAG}`    | `--image-tag`            |
| `${REGISTRY_CLUSTER_URL}`  | `.env` / `REGISTRY_CLUSTER_URL`  |
| `${REGISTRY_CLUSTER_PORT}` | `.env` / `REGISTRY_CLUSTER_PORT` |
| `${K8S_NAMESPACE}`| `--k8s-ns`        |
| `${CONTAINER_PORT}`| `--container-port`      |

### ArgoCD Application (`argocd/*.tmpl.yaml`)

| Variable           | Source                    |
|--------------------|---------------------------|
| `${APP_NAME}`      | `--app-name`              |
| `${APP_REPO_URL}`  | `--app-repo-url`          |
| `${K8S_NAMESPACE}` | `--k8s-ns`         |

---

## Standards Alignment

A reusable, opt-in, offline standards gate validates repository shape against the
Fleet Alignment Constitution before merge — no cluster, network, or secrets access
required. Every `[FAIL]` line embeds a concrete `fix:` remediation (Gate
Ergonomics).

### Profiles

| Profile   | Required surface                            | N/A semantics                       |
|-----------|---------------------------------------------|-------------------------------------|
| `app-k8s` | `Dockerfile`, `k8s/` manifests, `.env`      | Inputless dirs & repos not matching never fail   |
| `app`     | `Dockerfile`, (`.env`)                      | Missing app inputs → `N/A`          |
| `library` | (any) — structure check      | Never `FAIL`s on structure          |

Checks: **structure-files** (profile-adaptive required files + `Dockerfile`/`.env`
FORMAT), **secrets-scan** (git-tracked credential patterns for known provider
keys/private keys), **policy-manifests** (`.env` ↔ k8s value agreement, `namespace`,
`service port`, `image tag`, PVC, cron `schedule`). Secrets exemptions are
documented via an allowlist (see `standards-audit/allowlist.example`).

### Run locally

```bash
standards-audit/runner.sh --repo-root . --repo-profile app-k8s
# exit 0 = PASS, 1 = FAIL, 2 = usage error
```

### CI gate (opt-in callers)

Copy `examples/standards-audit-caller.yml` into your app repo as a required PR
check, or `examples/standards-audit-sweep.yml` for a scheduled conformance sweep
(`cron: "0 2 * * 1"` — Constitution FR3). Both import the reusable workflow
`.github/workflows/standards-audit.yml` **SHA-pinned** — never a mutable branch.

### Provenance & promotion path

`init.sh` stamps every scaffolded app with `.template-version` (copied from the
canonical `init/template-version` constant, currently `1.0.0`), so lineage lag is
detectable.

---

## Container Security (Trivy)

Scanning policy lives in one file, [`trivy.yaml`](trivy.yaml). Thresholds, scanners,
DB sources, and cache location are set there and nowhere else, so a local run and
the CI gate cannot drift apart. Suppressions live in [`.trivyignore`](.trivyignore)
and must carry a justification plus an `exp:` date.

### Three scan stages

| Stage | Target | Catches | Runs |
|-------|--------|---------|------|
| `source` | repo filesystem | dependency CVEs, IaC misconfiguration, committed secrets | every PR |
| `image` | published image **by digest** | OS/library CVEs in the shipped artifact; emits CycloneDX SBOM | post-push |
| `rescan` | same digest, current DB | CVEs **disclosed after** the image was built | weekly sweep |

The `rescan` stage exists because a build-time scan is a snapshot. An image that
passed CI can become vulnerable weeks later while nothing about it changes.

### Scanning by digest, not tag

Tags are mutable. The artifact that was scanned may not be the artifact that
shipped, which makes the SARIF record a statement about something else. Pass
`image@sha256:...` whenever the push produced a digest.

### Gating

Blocks on `HIGH,CRITICAL` with `--ignore-unfixed`. A CVE with no vendor patch is
unactionable — blocking on it only teaches engineers to bypass the gate.
Unfixed findings stay in the report; they just do not set the exit code.

Start with `CRITICAL` only and add `HIGH` once the backlog is drained, rather than
breaking every build on day one.

### Run locally

```bash
make trivy-scan   # report only, never fails
make trivy-gate   # same scan with a blocking exit code, matching CI
make trivy-db     # pre-populate the vuln DB (also cached in CI)

# Scan a specific image / emit an SBOM
make trivy-image TRIVY_IMAGE=ghcr.io/your-org/your-app@sha256:<DIGEST>
make trivy-sbom  TRIVY_IMAGE=ghcr.io/your-org/your-app@sha256:<DIGEST>
```

### CI gates (opt-in callers)

Copy [`examples/trivy-scan-caller.yml`](examples/trivy-scan-caller.yml) into your
app repo as a required PR check, or
[`examples/trivy-rescan-sweep.yml`](examples/trivy-rescan-sweep.yml) for the
scheduled rescan (`cron: "0 3 * * 1"`). Both import
`.github/workflows/trivy-scan.yml` **SHA-pinned** — the policy that gates your
merge must not be mutable by anyone who can push.

Findings upload as SARIF to the Security tab via `if: always()`, so the full
picture is recorded even when the gate fails. Without that, a failing build leaves
an empty Security tab.

### Fleet sweep

`hack/trivy-fleet.sh` clones every repository under a GitHub account/org and
scans each with this same `trivy.yaml`, so "what is the security posture of the
account" is one answer instead of N answers that depend on which repos someone
remembered to wire up.

```bash
./hack/trivy-fleet.sh                 # all repos in $GITHUB_OWNER (default: natanbs)
./hack/trivy-fleet.sh --list          # show what would be scanned, scan nothing
./hack/trivy-fleet.sh --repo app-a --repo app-b
./hack/trivy-fleet.sh --no-fail       # report-only: always exit 0
```

Repos are cloned shallowly into temp dirs and scanned in parallel (`--jobs`,
default 4). Output lands in `trivy-fleet-out/` — per-repo SARIF alongside
`summary.md` and `summary.json`. Exit codes: `0` pass, `1` blocking
(CRITICAL/HIGH) findings, `2` scan error or usage problem. Requires `trivy`,
an authenticated `gh`, and `python3`.

### Suppressions

Prefer a VEX document (`--vex`) over an ignore line: a VEX statement travels with
the artifact and is reviewable by anyone consuming it, while an ignore entry is
invisible outside the repo. Use `.trivyignore` for accepted risk that is local to
this codebase, and always set `exp:`. An unbounded ignore is how three-year-old
CVEs reach production.

### Known findings

`trivy.yaml` excludes `standards-audit/fixtures/` and `secrets-vault-standard/fixtures/`.
Those trees are **intentionally** non-conformant — planted credentials and insecure
manifests exist to prove the detectors fire. Scanning them would be a false
positive on every run. Add any new fixture directory to `scan.skip-dirs` in the
same commit that introduces it.

| Phase | Scope | Status |
|-------|-------|--------|
| P1 | Offline audit gate + `.template-version` provenance | Shipped here |
| P2 | Promote to org-level shared versioned artifacts (`@vX.Y.Z` reusable workflow) | Recorded in Pending Decision Log |
| P3 | Tracked re-sync tooling (compares `.template-version`, auto-remediates) | Recorded in Pending Decision Log |

---

## Testing

```bash
# Run all bats tests
bats cicd-tests/
```

### Test Suites

| File                   | Tests                                  |
|------------------------|----------------------------------------|
| `cicd-tests/arguments.bats` | CLI argument parsing and validation   |
| `cicd-tests/errors.bats`    | Error handling and step failure       |
| `cicd-tests/manifests.bats` | K8s manifest generation and validation|
| `cicd-tests/argocd.bats`    | ArgoCD Application manifest validation|
| `cicd-tests/init_env.bats`  | `init.sh` scaffold + `.env` loading   |
| `cicd-tests/integration.bats` | End-to-end pipeline integration     |
| `cicd-tests/tag_release.bats` | `tag.sh` manifest retag + release    |

---

## Project Structure

```
gitops-template/
├── build.sh                 # Main CI/CD pipeline script (fetched via curl at build time)
├── init.sh                  # Project scaffold script (forwarder to init/init.sh)
├── init/                    # All scaffolding templates and init script
│   ├── init.sh              #   init driver script
│   ├── app.env              #   .env template
│   ├── template-version     #   canonical provenance constant
│   ├── gitignore            #   .gitignore template
│   ├── go/                  #   Go Dockerfile + source
│   ├── python/              #   Python Dockerfile + source
│   ├── node/                #   Node.js Dockerfile + source
│   ├── k8s/                 #   K8s manifest templates (*.tmpl.yaml)
│   └── argocd/              #   ArgoCD manifest templates
├── cicd-tests/              # Bats test suites
├── specs/                   # Feature specifications
├── .specify/                # Specification tooling
└── README.md                # This file

Scaffolded app (my-app/):
├── .template-version        # Provenance stamp (copied from init/template-version)
├── .env                     # App configuration (generated by init.sh)
├── .gitignore               # Ignores generated manifests and .env
├── Dockerfile               # App Dockerfile (if --dockerfile was used)
├── main.go / app.py /      # App source (if --dockerfile was used)
│   server.js / package.json
└── k8s/                     # Generated K8s manifests (created by build.sh)
    ├── deploy.yaml
    ├── svc.yaml
    └── ingress.yaml
```

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---------|-------------|-----|
| `--app-name is required` | Missing from CLI and `.env` | Add `--app-name my-app` or set `APP_NAME=my-app` in `.env`, or run from the app directory |
| `k8s-safe` validation error | App name has uppercase/underscore | Use lowercase, hyphens only |
| `docker: command not found` | Docker not installed | Install Docker Desktop |
| `Cannot connect to the Docker daemon` | Docker not running | Start Docker Desktop |
| `no such host` on push | Registry not reachable | Run `./argocd.sh` from argo-bootstrap, or check `--registry-url` |
| `connection refused` on push | Registry not running or wrong port | Run `docker push localhost:50000/test:latest` to verify connection |
| `kubectl apply` fails | No cluster or wrong context | Run `kubectl cluster-info` |
| `envsubst: command not found` | GNU gettext not installed | `brew install gettext` (macOS) or `apt install gettext` (Linux) |
| `step 'Docker Tag/Push' failed` | Registry auth or connection | Run `docker login`, verify `--registry-url` and `--registry-port` |
| `init.sh: command not found` | Not in PATH | Run `./init.sh` from the gitops-template directory |

---

## Service Lifecycle

### Decommissioning a Service

When a service is no longer needed, follow the [decommission procedure](docs/decommission.md)
to safely remove it from the cluster, clean up the container image, and archive the
source repository. The procedure covers both GitOps (ArgoCD) and Direct Deploy models.
