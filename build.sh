#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${SCRIPT_DIR}"

# ── Colour output ──────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; CYAN='\033[0;36m'; NC='\033[0m'
info()  { printf "${GREEN}[INFO]${NC}  %s\n" "$*"; }
warn()  { printf "${YELLOW}[WARN]${NC}  %s\n" "$*"; }
error() { printf "${RED}[ERROR]${NC} %s\n" "$*"; }
step()  { printf "\n${CYAN}=== %s ===${NC}\n" "$*"; }

# ── Defaults ───────────────────────────────────────────────────────
DEFAULT_REGISTRY_URL="${REGISTRY_URL:-k3d-registry.localhost}"
DEFAULT_REGISTRY_PORT="${REGISTRY_PORT:-5000}"
DEFAULT_K8S_NAMESPACE="${K8S_NAMESPACE:-default}"
DEFAULT_CONTAINER_PORT="${CONTAINER_PORT:-8080}"

# ── State ──────────────────────────────────────────────────────────
APP_NAME=""
IMAGE_TAG=""
REGISTRY_URL="$DEFAULT_REGISTRY_URL"
REGISTRY_PORT="$DEFAULT_REGISTRY_PORT"
K8S_NAMESPACE="$DEFAULT_K8S_NAMESPACE"
CONTAINER_PORT="$DEFAULT_CONTAINER_PORT"
APP_REPO_URL=""
AUTO_DEPLOY=false
CONTINUE_ON_ERROR=false
_FAILED_STEPS=()

# ── Cleanup handler ────────────────────────────────────────────────
cleanup() {
  local exit_code=$?
  if [ ${#_FAILED_STEPS[@]} -gt 0 ]; then
    warn "Pipeline completed with failures in: ${_FAILED_STEPS[*]}"
  fi
  exit "$exit_code"
}
trap cleanup EXIT

# ── Help ───────────────────────────────────────────────────────────
show_help() {
  cat <<'EOF'
Usage: build.sh [OPTIONS]

Build, tag, and push a Docker image for any application. Optionally process
Kubernetes manifest templates and deploy to a cluster.

Required:
  --app-name NAME       Application name (k8s-safe: lowercase, hyphens only)
  --image-tag TAG       Docker image tag (e.g. v1.0, latest)

Optional:
  --registry-url URL    Container registry hostname
                        (default: $REGISTRY_URL or k3d-registry.localhost)
  --registry-port PORT  Container registry port
                        (default: $REGISTRY_PORT or 5000)
  --k8s-namespace NS    Kubernetes namespace (default: default)
  --container-port PORT Container port for K8s manifests (default: 8080)
  --app-repo-url URL    Git repository URL for ArgoCD Application template
  --auto-deploy         Apply generated manifests to the cluster via kubectl
  --continue-on-error   Continue pipeline even if a step fails
  --help                Show this help message and exit

Environment variables:
  REGISTRY_URL, REGISTRY_PORT, K8S_NAMESPACE, CONTAINER_PORT
  can be set instead of passing the corresponding flags.

Examples:
  build.sh --app-name my-app --image-tag v1.0
  build.sh --app-name my-app --image-tag v1.0 --auto-deploy
  build.sh --app-name my-app --image-tag v1.0 --app-repo-url https://github.com/org/my-app.git
EOF
  exit 0
}

# ── Argument parsing (cross-platform: macOS & Linux) ──────────────
parse_args() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --help)              show_help ;;
      --app-name)          APP_NAME="$2"; shift 2 ;;
      --app-name=*)        APP_NAME="${1#*=}"; shift ;;
      --image-tag)         IMAGE_TAG="$2"; shift 2 ;;
      --image-tag=*)       IMAGE_TAG="${1#*=}"; shift ;;
      --registry-url)      REGISTRY_URL="$2"; shift 2 ;;
      --registry-url=*)    REGISTRY_URL="${1#*=}"; shift ;;
      --registry-port)     REGISTRY_PORT="$2"; shift 2 ;;
      --registry-port=*)   REGISTRY_PORT="${1#*=}"; shift ;;
      --k8s-namespace)     K8S_NAMESPACE="$2"; shift 2 ;;
      --k8s-namespace=*)   K8S_NAMESPACE="${1#*=}"; shift ;;
      --container-port)    CONTAINER_PORT="$2"; shift 2 ;;
      --container-port=*)  CONTAINER_PORT="${1#*=}"; shift ;;
      --app-repo-url)      APP_REPO_URL="$2"; shift 2 ;;
      --app-repo-url=*)    APP_REPO_URL="${1#*=}"; shift ;;
      --auto-deploy)       AUTO_DEPLOY=true; shift ;;
      --continue-on-error) CONTINUE_ON_ERROR=true; shift ;;
      -h)                  show_help ;;
      --)                  shift; break ;;
      -*)
        error "Unknown argument: $1"
        exit 1
        ;;
      *)
        error "Unexpected positional argument: $1"
        exit 1
        ;;
    esac
  done
}

# ── Validation ─────────────────────────────────────────────────────
validate_inputs() {
  local errors=0

  # --app-name: k8s-safe (lowercase, alphanumeric + hyphens, start alpha)
  if [ -z "$APP_NAME" ]; then
    error "--app-name is required"
    errors=1
  elif ! echo "$APP_NAME" | grep -qE '^[a-z][a-z0-9-]*$'; then
    error "--app-name must be k8s-safe: start with a letter, only lowercase alphanumeric and hyphens (got: '$APP_NAME')"
    errors=1
  fi

  # --image-tag: non-empty, basic format
  if [ -z "$IMAGE_TAG" ]; then
    error "--image-tag is required"
    errors=1
  elif ! echo "$IMAGE_TAG" | grep -qE '^[a-zA-Z0-9][a-zA-Z0-9._-]*$'; then
    error "--image-tag must start with alphanumeric and contain only alphanumeric, dot, underscore, hyphen (got: '$IMAGE_TAG')"
    errors=1
  fi

  # --registry-port: numeric
  if ! echo "$REGISTRY_PORT" | grep -qE '^[0-9]+$'; then
    error "--registry-port must be a number (got: '$REGISTRY_PORT')"
    errors=1
  fi

  if [ "$errors" -ne 0 ]; then
    exit 1
  fi
}

# ── Docker utilities ──────────────────────────────────────────────
_full_image_name() {
  if [ -n "$REGISTRY_PORT" ] && [ "$REGISTRY_PORT" != "443" ] && [ "$REGISTRY_PORT" != "80" ]; then
    echo "${REGISTRY_URL}:${REGISTRY_PORT}/${APP_NAME}:${IMAGE_TAG}"
  else
    echo "${REGISTRY_URL}/${APP_NAME}:${IMAGE_TAG}"
  fi
}

# ── Pipeline steps ─────────────────────────────────────────────────
run_step() {
  local step_name="$1"
  shift
  info "Step: $step_name"
  if ! "$@"; then
    if [ "$CONTINUE_ON_ERROR" = true ]; then
      warn "Step '$step_name' failed — continuing (--continue-on-error)"
      _FAILED_STEPS+=("$step_name")
    else
      error "Step '$step_name' failed — aborting"
      exit 1
    fi
  fi
}

step_build() {
  step "1. Building Docker Image"
  docker build -t "${APP_NAME}:${IMAGE_TAG}" . || return 1
}

step_tag_push() {
  local full_name
  full_name=$(_full_image_name)

  step "2. Tagging Image"
  docker tag "${APP_NAME}:${IMAGE_TAG}" "$full_name" || return 1

  step "3. Pushing Image to Registry"
  docker push "$full_name" || return 1

  export IMAGE_FULL_REF="$full_name"
}

step_template() {
  step "4. Processing Kubernetes Templates"

  export APP_NAME IMAGE_TAG REGISTRY_URL REGISTRY_PORT K8S_NAMESPACE CONTAINER_PORT APP_REPO_URL

  # Process all .tmpl.yaml files in k8s/ directory
  if [ -d "${PROJECT_ROOT}/k8s" ]; then
    for tmpl in "${PROJECT_ROOT}"/k8s/*.tmpl.yaml; do
      [ -f "$tmpl" ] || continue
      local output="${tmpl%.tmpl.yaml}.yaml"
      info "  Template: $(basename "$tmpl") -> $(basename "$output")"
      envsubst < "$tmpl" > "$output" || return 1
    done
  fi

  # Process all .tmpl.yaml files in argocd/ directory
  if [ -d "${PROJECT_ROOT}/argocd" ]; then
    for tmpl in "${PROJECT_ROOT}"/argocd/*.tmpl.yaml; do
      [ -f "$tmpl" ] || continue
      local output="${tmpl%.tmpl.yaml}.yaml"
      info "  Template: $(basename "$tmpl") -> $(basename "$output")"
      envsubst < "$tmpl" > "$output" || return 1
    done
  fi
}

step_deploy() {
  step "5. Applying Manifests to Cluster"

  # Apply K8s manifests
  if [ -d "${PROJECT_ROOT}/k8s" ]; then
    for manifest in "${PROJECT_ROOT}"/k8s/*.yaml; do
      [[ "$manifest" == *.tmpl.yaml ]] && continue
      [ -f "$manifest" ] || continue
      info "  Applying: $(basename "$manifest")"
      kubectl apply -f "$manifest" --namespace "$K8S_NAMESPACE" || return 1
    done
  fi

  # Apply ArgoCD manifests (if any)
  if [ -d "${PROJECT_ROOT}/argocd" ]; then
    for manifest in "${PROJECT_ROOT}"/argocd/*.yaml; do
      [[ "$manifest" == *.tmpl.yaml ]] && continue
      [ -f "$manifest" ] || continue
      info "  Applying: $(basename "$manifest")"
      kubectl apply -f "$manifest" --namespace "$K8S_NAMESPACE" || return 1
    done
  fi
}

# ── Main ───────────────────────────────────────────────────────────
main() {
  parse_args "$@"
  validate_inputs

  info "Application: $APP_NAME"
  info "Image tag:   $IMAGE_TAG"
  info "Registry:    ${REGISTRY_URL}:${REGISTRY_PORT}"
  info "Namespace:   $K8S_NAMESPACE"
  info "Auto-deploy: $AUTO_DEPLOY"

  run_step "Docker Build"     step_build
  run_step "Docker Tag/Push"  step_tag_push
  run_step "Template Process" step_template

  if [ "$AUTO_DEPLOY" = true ]; then
    run_step "Deploy" step_deploy
  else
    info "Skipping deploy (use --auto-deploy to enable)"
  fi

  if [ ${#_FAILED_STEPS[@]} -gt 0 ]; then
    warn "Pipeline completed with ${#_FAILED_STEPS[@]} failed step(s): ${_FAILED_STEPS[*]}"
    exit 1
  fi

  step "Pipeline completed successfully"
}

main "$@"
