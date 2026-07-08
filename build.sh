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

# ── Load .env (script dir first, then CWD) ─────────────────────────
_ENV_SOURCE=""
if [ -f "${PROJECT_ROOT}/.env" ]; then
  _ENV_SOURCE="${PROJECT_ROOT}/.env"
elif [ -f ".env" ]; then
  _ENV_SOURCE=".env"
fi
if [ -n "$_ENV_SOURCE" ]; then
  set -a
  # shellcheck source=/dev/null
  . "$_ENV_SOURCE"
  set +a
fi

# If APP_NAME is still empty, infer it from the current directory name (useful when .env is missing)
if [ -z "$APP_NAME" ]; then
  APP_NAME=$(basename "$(pwd)")
fi

# ── Defaults ───────────────────────────────────────────────────────
DEFAULT_REGISTRY_URL="${REGISTRY_URL:-k3d-registry.localhost}"
DEFAULT_REGISTRY_PORT="${REGISTRY_PORT:-5000}"
DEFAULT_REGISTRY_CLUSTER_URL="${REGISTRY_CLUSTER_URL:-k3d-reg}"
DEFAULT_REGISTRY_CLUSTER_PORT="${REGISTRY_CLUSTER_PORT:-5000}"
DEFAULT_K8S_NAMESPACE="${K8S_NAMESPACE:-default}"
DEFAULT_CONTAINER_PORT="${CONTAINER_PORT:-8080}"
DEFAULT_INGRESS_CLASS="${INGRESS_CLASS:-traefik}"
DEFAULT_TEMPLATE_REPO_RAW="https://raw.githubusercontent.com/natanbs/gitops-template/main"
DEFAULT_GIT_REPO_BASE="${GIT_REPO_BASE:-https://github.com/natanbs}"

# ── State (preserves .env values, overridable by CLI) ──────────────
APP_NAME="${APP_NAME:-}"
IMAGE_TAG="${IMAGE_TAG:-}"
REGISTRY_URL="${REGISTRY_URL:-$DEFAULT_REGISTRY_URL}"
REGISTRY_PORT="${REGISTRY_PORT:-$DEFAULT_REGISTRY_PORT}"
REGISTRY_CLUSTER_URL="${REGISTRY_CLUSTER_URL:-$DEFAULT_REGISTRY_CLUSTER_URL}"
REGISTRY_CLUSTER_PORT="${REGISTRY_CLUSTER_PORT:-$DEFAULT_REGISTRY_CLUSTER_PORT}"
K8S_NAMESPACE="${K8S_NAMESPACE:-$DEFAULT_K8S_NAMESPACE}"
CONTAINER_PORT="${CONTAINER_PORT:-$DEFAULT_CONTAINER_PORT}"
INGRESS_CLASS="${INGRESS_CLASS:-$DEFAULT_INGRESS_CLASS}"
TEMPLATE_REPO_RAW="${TEMPLATE_REPO_RAW:-$DEFAULT_TEMPLATE_REPO_RAW}"
GIT_REPO_BASE="${GIT_REPO_BASE:-$DEFAULT_GIT_REPO_BASE}"
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
   --app-name NAME       Application name (k8s-safe: lowercase, alphanumeric only). Optional if .env sets APP_NAME or when run from the service directory (its name is used).

Optional:
  --image-tag TAG       Docker image tag (e.g. v1.0, latest). Omit to auto-increment
                        patch from CURRENT_TAG in .env (e.g. v1.0.0 -> v1.0.1)
  --registry-url URL    Container registry hostname
                        (default: $REGISTRY_URL or k3d-registry.localhost)
  --registry-port PORT  Container registry port
                        (default: $REGISTRY_PORT or 5000)
  --k8s-ns NS    Kubernetes namespace (default: default)
  --container-port PORT Container port for K8s manifests (default: 8080)
  --template-repo-raw URL
                        Base URL for fetching K8s templates at build time
                        (default: $DEFAULT_TEMPLATE_REPO_RAW, path: init/k8s/)
  --app-repo-url URL    Git repository URL for ArgoCD Application template
                        (default: \$GIT_REPO_BASE/\$APP_NAME.git)
  --auto-deploy         Apply generated manifests to the cluster via kubectl
  --continue-on-error   Continue pipeline even if a step fails
  --help                Show this help message and exit

Environment variables:
  REGISTRY_URL, REGISTRY_PORT, REGISTRY_CLUSTER_URL, REGISTRY_CLUSTER_PORT,
  K8S_NAMESPACE, CONTAINER_PORT, GIT_REPO_BASE
  can be set instead of passing the corresponding flags.

Dotenv file:
  If a .env file exists in the project root, it is sourced before
  argument parsing. CLI flags override .env values.

Examples:
  build.sh --app-name my-app                          # auto-version from .env
  build.sh --app-name my-app --auto-deploy            # auto-version + deploy
  build.sh --app-name my-app --image-tag v2.0         # explicit tag
  build.sh --app-name my-app --image-tag v2.0 --auto-deploy
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
      --k8s-ns)     K8S_NAMESPACE="$2"; shift 2 ;;
      --k8s-ns=*)   K8S_NAMESPACE="${1#*=}"; shift ;;
      --container-port)    CONTAINER_PORT="$2"; shift 2 ;;
      --container-port=*)  CONTAINER_PORT="${1#*=}"; shift ;;
      --template-repo-raw) TEMPLATE_REPO_RAW="$2"; shift 2 ;;
      --template-repo-raw=*) TEMPLATE_REPO_RAW="${1#*=}"; shift ;;
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

  # --image-tag: validate format if provided (optional — auto-versioned when omitted)
  if [ -n "$IMAGE_TAG" ] && ! echo "$IMAGE_TAG" | grep -qE '^[a-zA-Z0-9][a-zA-Z0-9._-]*$'; then
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

# ── Version utilities ────────────────────────────────────────────
_bump_patch() {
  local ver="$1"
  ver="${ver#v}"
  local major="${ver%%.*}"
  local rest="${ver#*.}"
  local minor="${rest%%.*}"
  local patch
  if [[ "$rest" == *"."* ]]; then
    patch="${rest#*.}"
  else
    patch=0
  fi
  patch=$((patch + 1))
  echo "v${major}.${minor}.${patch}"
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

  # Set PVC placeholders (empty by default, filled from .env)
  PVC_NAME="${PVC_NAME:-}"
  PVC_MOUNT_PATH="${PVC_MOUNT_PATH:-/data}"
  VOLUME_MOUNTS=""
  VOLUMES=""
  if [ -n "$PVC_NAME" ]; then
    VOLUME_MOUNTS="        volumeMounts:
        - name: ${PVC_NAME}
          mountPath: ${PVC_MOUNT_PATH}"
    VOLUMES="      volumes:
      - name: ${PVC_NAME}
        persistentVolumeClaim:
          claimName: ${PVC_NAME}"
  fi
  export APP_NAME IMAGE_TAG REGISTRY_URL REGISTRY_PORT REGISTRY_CLUSTER_URL REGISTRY_CLUSTER_PORT K8S_NAMESPACE CONTAINER_PORT INGRESS_CLASS APP_REPO_URL PVC_NAME PVC_MOUNT_PATH VOLUME_MOUNTS VOLUMES

  # Derive app directory: apps are siblings of the template repo
  local app_dir
  app_dir="$(dirname "$PROJECT_ROOT")/$APP_NAME"
  mkdir -p "$app_dir/k8s" "$app_dir/argocd"

  # Resolve K8s templates: local init/k8s/ dir or download from template repo
  local tmpl_src="${PROJECT_ROOT}/init/k8s"
  local tmpl_cleanup=false
  if [ ! -d "$tmpl_src" ]; then
    tmpl_src="$(mktemp -d)"
    tmpl_cleanup=true
    for t in deploy svc ingress; do
      curl -sLf "${TEMPLATE_REPO_RAW}/init/k8s/${t}.tmpl.yaml" \
        -o "${tmpl_src}/${t}.tmpl.yaml" 2>/dev/null || true
    done
  fi

  for tmpl in "${tmpl_src}"/*.tmpl.yaml; do
    [ -f "$tmpl" ] || continue
    local filename; filename=$(basename "$tmpl" .tmpl.yaml)
    local output="${app_dir}/k8s/${filename}.yaml"
    info "  Template: $(basename "$tmpl") -> ${app_dir}/k8s/${filename}.yaml"
    envsubst < "$tmpl" > "$output" || return 1
  done

  if [ "$tmpl_cleanup" = true ]; then
    rm -rf "$tmpl_src"
  fi

  # Process ArgoCD templates (only if repo URL is set)
  if [ -n "$APP_REPO_URL" ]; then
    local argocd_src="${PROJECT_ROOT}/init/argocd"
    local argocd_cleanup=false
    if [ ! -d "$argocd_src" ]; then
      argocd_src="$(mktemp -d)"
      argocd_cleanup=true
      curl -sLf "${TEMPLATE_REPO_RAW}/init/argocd/application.tmpl.yaml" \
        -o "${argocd_src}/application.tmpl.yaml" 2>/dev/null || true
    fi

    for tmpl in "${argocd_src}"/*.tmpl.yaml; do
      [ -f "$tmpl" ] || continue
      local filename; filename=$(basename "$tmpl" .tmpl.yaml)
      local output="${app_dir}/argocd/${filename}.yaml"
      info "  ArgoCD Template: $(basename "$tmpl") -> ${app_dir}/argocd/${filename}.yaml"
      envsubst < "$tmpl" > "$output" || return 1
    done

    if [ "$argocd_cleanup" = true ]; then
      rm -rf "$argocd_src"
    fi
  fi
}

step_deploy() {
  step "5. Applying Manifests to Cluster"

  local app_dir
  app_dir="$(dirname "$PROJECT_ROOT")/$APP_NAME"

  # Apply K8s manifests from the app's k8s/ directory
  if [ -d "$app_dir/k8s" ]; then
    for manifest in "$app_dir"/k8s/*.yaml; do
      [[ "$manifest" == *.tmpl.yaml ]] && continue
      [ -f "$manifest" ] || continue
      info "  Applying: $(basename "$manifest")"
      local kind
      kind=$(grep -E '^kind:' "$manifest" | head -1 | sed 's/^kind: *//')
      if [ "$kind" = "Service" ]; then
        kubectl delete -f "$manifest" --namespace "$K8S_NAMESPACE" --ignore-not-found 2>/dev/null
        kubectl apply -f "$manifest" --namespace "$K8S_NAMESPACE" || return 1
      else
        kubectl apply -f "$manifest" --namespace "$K8S_NAMESPACE" || return 1
      fi
    done
  fi

  # Apply ArgoCD manifests from the app's argocd/ directory
  if [ -n "$APP_REPO_URL" ] && [ -d "$app_dir/argocd" ]; then
    for manifest in "$app_dir"/argocd/*.yaml; do
      [[ "$manifest" == *.tmpl.yaml ]] && continue
      [ -f "$manifest" ] || continue
      info "  Applying: $(basename "$manifest")"
      kubectl apply -f "$manifest" || return 1
    done
  fi
}

# ── Main ───────────────────────────────────────────────────────────
main() {
  parse_args "$@"

  # Derive repo URL from convention if not explicitly set
  if [ -z "$APP_REPO_URL" ] && [ -n "$APP_NAME" ]; then
    APP_REPO_URL="${GIT_REPO_BASE}/${APP_NAME}.git"
  fi

  # Auto-version when no explicit tag given
  _VERSION_AUTO=false
  if [ -z "$IMAGE_TAG" ]; then
    local current_tag="${CURRENT_TAG:-v1.0.0}"
    IMAGE_TAG="$(_bump_patch "$current_tag")"
    _VERSION_AUTO=true
    info "Auto-version: $current_tag -> $IMAGE_TAG"
  fi

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

  # Persist new CURRENT_TAG to .env when auto-versioned (not for explicit --image-tag)
  if [ "$_VERSION_AUTO" = true ] && [ ${#_FAILED_STEPS[@]} -eq 0 ]; then
    local app_dir
    app_dir="$(dirname "$PROJECT_ROOT")/$APP_NAME"
    local env_file="${app_dir}/.env"
    if [ -f "$env_file" ]; then
      if sed "s/^CURRENT_TAG=.*/CURRENT_TAG=$IMAGE_TAG/" "$env_file" > "${env_file}.tmp" 2>/dev/null; then
        mv "${env_file}.tmp" "$env_file"
        info "Updated CURRENT_TAG=$IMAGE_TAG in $env_file"
      else
        rm -f "${env_file}.tmp"
      fi
    fi
  fi

  if [ ${#_FAILED_STEPS[@]} -gt 0 ]; then
    warn "Pipeline completed with ${#_FAILED_STEPS[@]} failed step(s): ${_FAILED_STEPS[*]}"
    exit 1
  fi

  step "Pipeline completed successfully"
}

main "$@"
