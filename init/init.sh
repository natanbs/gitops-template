#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GREEN='\033[0;32m'; YELLOW='\033[0;33m'; CYAN='\033[0;36m'; RED='\033[0;31m'; NC='\033[0m'
info()  { printf "${GREEN}[INFO]${NC}  %s\n" "$*"; }
warn()  { printf "${YELLOW}[WARN]${NC}  %s\n" "$*"; }
error() { printf "${RED}[ERROR]${NC} %s\n" "$*"; }

show_help() {
  cat <<'EOF'
Usage: init.sh --app-name APP_NAME [OPTIONS]

Scaffold a new application. Creates the app directory with .env config
and optionally a Dockerfile and source files. Optionally runs the build.

Required:
  --app-name NAME       Application name (k8s-safe: lowercase, hyphens only)

Options:
  --dockerfile TYPE    Scaffold a sample Dockerfile (go|python|node|none)
                       (default: none)
  --registry-url URL   Container registry hostname (default: localhost)
  --registry-port PORT Container registry port (default: 50000)
  --k8s-ns NS   Kubernetes namespace (default: apps-ns)
  --container-port PORT External service port (default: 8080)
  --build             Run build.sh after scaffolding (build + push)
  --deploy            Run build.sh --auto-deploy after scaffolding
  --image-tag TAG     Docker image tag for --build/--deploy (omit to auto-version)
  --help               Show this help message

Examples:
  ./init.sh --app-name my-api
  ./init.sh --app-name my-api --dockerfile go
  ./init.sh --app-name my-api --build
  ./init.sh --app-name my-api --build --deploy --image-tag v2.0
EOF
  exit 0
}

# ── Defaults ─────────────────────────────────────────────────
DOCKERFILE_TYPE="none"
DEF_REGISTRY_URL="localhost"
DEF_REGISTRY_PORT="50000"
DEF_K8S_NAMESPACE="apps-ns"
DEF_CONTAINER_PORT="8080"
DEF_CURRENT_TAG="v1.0.0"
RUN_BUILD=false
RUN_DEPLOY=false

# CLI overrides (empty = not provided)
CLI_APP_NAME=""
CLI_REGISTRY_URL=""
CLI_REGISTRY_PORT=""
CLI_K8S_NAMESPACE=""
CLI_CONTAINER_PORT=""
CLI_DOCKERFILE_TYPE=""
CLI_IMAGE_TAG=""
CLI_FORCE=false

while [ $# -gt 0 ]; do
  case "$1" in
    --help)              show_help ;;
    --app-name)          CLI_APP_NAME="$2"; shift 2 ;;
    --app-name=*)        CLI_APP_NAME="${1#*=}"; shift ;;
    --dockerfile)        CLI_DOCKERFILE_TYPE="$2"; shift 2 ;;
    --dockerfile=*)      CLI_DOCKERFILE_TYPE="${1#*=}"; shift ;;
    --registry-url)      CLI_REGISTRY_URL="$2"; shift 2 ;;
    --registry-url=*)    CLI_REGISTRY_URL="${1#*=}"; shift ;;
    --registry-port)     CLI_REGISTRY_PORT="$2"; shift 2 ;;
    --registry-port=*)   CLI_REGISTRY_PORT="${1#*=}"; shift ;;
    --k8s-ns)            CLI_K8S_NAMESPACE="$2"; shift 2 ;;
    --k8s-ns=*)          CLI_K8S_NAMESPACE="${1#*=}"; shift ;;
    --container-port)    CLI_CONTAINER_PORT="$2"; shift 2 ;;
    --container-port=*)  CLI_CONTAINER_PORT="${1#*=}"; shift ;;
    --build)             RUN_BUILD=true; shift ;;
    --deploy)            RUN_DEPLOY=true; RUN_BUILD=true; shift ;;
    --image-tag)         CLI_IMAGE_TAG="$2"; shift 2 ;;
    --image-tag=*)       CLI_IMAGE_TAG="${1#*=}"; shift ;;
    --force)             CLI_FORCE=true; shift ;;
    -h)                  show_help ;;
    *)
      error "Unknown argument: $1"
      exit 1
      ;;
  esac
done

# APP_NAME is required
APP_NAME="$CLI_APP_NAME"
if [ -n "$CLI_DOCKERFILE_TYPE" ]; then
  DOCKERFILE_TYPE="$CLI_DOCKERFILE_TYPE"
fi

TARGET_DIR="$(dirname "$PWD")/$APP_NAME"
_APP_EXISTS=false

# ── Create app directory ────────────────────────────────────
if [ -d "$TARGET_DIR" ]; then
  _APP_EXISTS=true
  info "App directory exists — updating .env"
else
  info "Creating $APP_NAME..."
  mkdir -p "$TARGET_DIR"
fi

cd "$TARGET_DIR" || exit 1

# ── Merge .env values (existing file + CLI overrides) ───────
# For new apps: start with defaults.
# For existing apps: preserve current values, only override CLI-provided fields.
_APP_NAME="$APP_NAME"
_REGISTRY_URL="$DEF_REGISTRY_URL"
_REGISTRY_PORT="$DEF_REGISTRY_PORT"
_K8S_NS="$DEF_K8S_NAMESPACE"
_CONTAINER_PORT="$DEF_CONTAINER_PORT"
_CURRENT_TAG="$DEF_CURRENT_TAG"
_PVC=""
_PVC_NAME=""
_PVC_MOUNT_PATH=""
_PVC_SIZE=""
_PVC_ACCESS_MODE=""
_PVC_STORAGE_CLASS=""
_INGRESS_CLASS=""

if [ -f .env ]; then
  _APP_NAME="$(       grep -s '^APP_NAME='       .env | sed 's/^APP_NAME=//'       || echo "$APP_NAME")"
  _REGISTRY_URL="$(   grep -s '^REGISTRY_URL='   .env | sed 's/^REGISTRY_URL=//'   || echo "$DEF_REGISTRY_URL")"
  _REGISTRY_PORT="$(  grep -s '^REGISTRY_PORT='  .env | sed 's/^REGISTRY_PORT=//'  || echo "$DEF_REGISTRY_PORT")"
  _K8S_NS="$(         grep -s '^K8S_NAMESPACE='  .env | sed 's/^K8S_NAMESPACE=//'  || echo "$DEF_K8S_NAMESPACE")"
  _CONTAINER_PORT="$( grep -s '^CONTAINER_PORT=' .env | sed 's/^CONTAINER_PORT=//' || echo "$DEF_CONTAINER_PORT")"
  _CURRENT_TAG="$(     grep -s '^CURRENT_TAG='    .env | sed 's/^CURRENT_TAG=//'    || echo "$DEF_CURRENT_TAG")"
  _PVC="$(             grep -s '^PVC='             .env | sed 's/^PVC=//'             || true)"
  _PVC_NAME="$(       grep -s '^PVC_NAME='       .env | sed 's/^PVC_NAME=//'       || true)"
  _PVC_MOUNT_PATH="$( grep -s '^PVC_MOUNT_PATH=' .env | sed 's/^PVC_MOUNT_PATH=//' || true)"
  _PVC_SIZE="$(       grep -s '^PVC_SIZE='       .env | sed 's/^PVC_SIZE=//'       || true)"
  _PVC_ACCESS_MODE="$( grep -s '^PVC_ACCESS_MODE=' .env | sed 's/^PVC_ACCESS_MODE=//' || true)"
  _PVC_STORAGE_CLASS="$( grep -s '^PVC_STORAGE_CLASS=' .env | sed 's/^PVC_STORAGE_CLASS=//' || true)"
  _INGRESS_CLASS="$(  grep -s '^INGRESS_CLASS='  .env | sed 's/^INGRESS_CLASS=//'  || true)"
fi

# CLI overrides take precedence
[ -n "$CLI_APP_NAME" ]          && _APP_NAME="$CLI_APP_NAME"
[ -n "$CLI_REGISTRY_URL" ]      && _REGISTRY_URL="$CLI_REGISTRY_URL"
[ -n "$CLI_REGISTRY_PORT" ]     && _REGISTRY_PORT="$CLI_REGISTRY_PORT"
[ -n "$CLI_K8S_NAMESPACE" ]     && _K8S_NS="$CLI_K8S_NAMESPACE"
[ -n "$CLI_CONTAINER_PORT" ]    && _CONTAINER_PORT="$CLI_CONTAINER_PORT"

# Export merged values for build.sh / kubectl
APP_NAME="$_APP_NAME"
REGISTRY_URL="$_REGISTRY_URL"
REGISTRY_PORT="$_REGISTRY_PORT"
K8S_NAMESPACE="$_K8S_NS"
CONTAINER_PORT="$_CONTAINER_PORT"

cat > .env <<EOF
# Generated by init.sh — customize as needed
APP_NAME=$_APP_NAME
GIT_REPO_BASE=https://github.com/natanbs
REGISTRY_URL=$_REGISTRY_URL
REGISTRY_PORT=$_REGISTRY_PORT
REGISTRY_CLUSTER_URL=k3d-reg
REGISTRY_CLUSTER_PORT=5000
K8S_NAMESPACE=$_K8S_NS
CONTAINER_PORT=$_CONTAINER_PORT
CURRENT_TAG=$_CURRENT_TAG
EOF

if [ "$_PVC" = "true" ]; then
  cat >> .env <<EOF
PVC=true
PVC_NAME=${_PVC_NAME:-$_APP_NAME-data}
PVC_MOUNT_PATH=${_PVC_MOUNT_PATH:-/data}
PVC_SIZE=${_PVC_SIZE:-1Gi}
PVC_ACCESS_MODE=${_PVC_ACCESS_MODE:-ReadWriteOnce}
PVC_STORAGE_CLASS=${_PVC_STORAGE_CLASS:-standard}
EOF
else
  echo "PVC=false" >> .env
  if [ -n "$_PVC_NAME" ]; then
    echo "PVC_NAME=$_PVC_NAME" >> .env
    echo "PVC_MOUNT_PATH=${_PVC_MOUNT_PATH:-/data}" >> .env
  fi
fi

# Ingress class (defaults to traefik for k3d clusters)
echo "INGRESS_CLASS=${_INGRESS_CLASS:-traefik}" >> .env

info "Wrote .env"

# ── PVC toggle warning ─────────────────────────────────────────
# Detect PVC being turned off: existing .env had PVC=true but new .env won't
_PVC_NEW=false
# Get the last PVC= line from .env (first match is default PVC=false)
_grep_pvc=$(grep -s '^PVC=' .env | tail -1 | sed 's/^PVC=//' || true)
[ "$_grep_pvc" = "true" ] && _PVC_NEW=true
if [ "$_PVC" = "true" ] && [ "$_PVC_NEW" != "true" ] && [ "$CLI_FORCE" != "true" ]; then
  warn "PVC was previously enabled but is now disabled."
  warn "Existing PVC manifests in k8s/pvc.yaml have been left in place."
  warn "Use --force to regenerate templates without PVC resources."
fi

# Determine effective PVC state from the rewritten .env for template rendering
_PVC_ACTIVE=false
[ "$_PVC_NEW" = "true" ] && _PVC_ACTIVE=true

# ── Render k8s templates ──────────────────────────────────────
mkdir -p k8s argocd

# Compute PVC name and mount path (used for both live templates and exports)
_PVC_NAME_FINAL="${_PVC_NAME:-$_APP_NAME-data}"
_PVC_MOUNT_FINAL="${_PVC_MOUNT_PATH:-/data}"

if [ "$_PVC_ACTIVE" = "true" ]; then
  VOLUME_MOUNTS="        volumeMounts:
        - name: ${_PVC_NAME_FINAL}
          mountPath: ${_PVC_MOUNT_FINAL}"
  VOLUMES="      volumes:
      - name: ${_PVC_NAME_FINAL}
        persistentVolumeClaim:
          claimName: ${_PVC_NAME_FINAL}"
else
  VOLUME_MOUNTS=""
  VOLUMES=""
fi
export APP_NAME="${_APP_NAME}" K8S_NAMESPACE="${_K8S_NS}" CONTAINER_PORT="${_CONTAINER_PORT}" VOLUME_MOUNTS VOLUMES
export PVC_NAME="${_PVC_NAME_FINAL}" PVC_MOUNT_PATH="${_PVC_MOUNT_FINAL}" PVC_SIZE="${_PVC_SIZE:-1Gi}" PVC_ACCESS_MODE="${_PVC_ACCESS_MODE:-ReadWriteOnce}" PVC_STORAGE_CLASS="${_PVC_STORAGE_CLASS:-standard}"
export REGISTRY_CLUSTER_URL="${REGISTRY_CLUSTER_URL:-k3d-reg}"
export REGISTRY_CLUSTER_PORT="${REGISTRY_CLUSTER_PORT:-5000}"
export INGRESS_CLASS="${_INGRESS_CLASS:-traefik}"
export GIT_REPO_BASE="${GIT_REPO_BASE:-https://github.com/natanbs}"
export APP_REPO_URL="${GIT_REPO_BASE}/${_APP_NAME}.git"
# Only render templates for new apps — skip for existing to preserve customizations
if [ "$_APP_EXISTS" != true ]; then
  IMAGE_TAG="${_CURRENT_TAG:-v1.0.0}"
  export IMAGE_TAG
  for tmpl in "$SCRIPT_DIR/k8s"/*.tmpl.yaml; do
    [ -f "$tmpl" ] || continue
    filename=$(basename "$tmpl" .tmpl.yaml)
    # Only render pvc template when PVC is active
    if [ "$filename" = "pvc" ] && [ "$_PVC_ACTIVE" != "true" ]; then
      continue
    fi
    output="k8s/${filename}.yaml"
    envsubst < "$tmpl" > "$output"
    info "  Rendered: $output"
  done
  for tmpl in "$SCRIPT_DIR/argocd"/*.tmpl.yaml; do
    [ -f "$tmpl" ] || continue
    filename=$(basename "$tmpl" .tmpl.yaml)
    output="argocd/${filename}.yaml"
    envsubst < "$tmpl" > "$output"
    info "  Rendered: $output"
  done
  unset IMAGE_TAG
fi

# ── Write .gitignore ────────────────────────────────────────
cp -n "$SCRIPT_DIR/gitignore" .gitignore 2>/dev/null || true
info "Wrote .gitignore"

# ── Copy language-specific scaffolds ────────────────────────
case "$DOCKERFILE_TYPE" in
  go|python|node)
    if [ -d "$SCRIPT_DIR/$DOCKERFILE_TYPE" ]; then
      for f in "$SCRIPT_DIR/$DOCKERFILE_TYPE"/*; do
        [ -f "$f" ] || continue
        cp -n "$f" ./ 2>/dev/null || true
      done
      info "Scaffolded $DOCKERFILE_TYPE Dockerfile + source files"
    fi
    ;;
  none)
    info "No Dockerfile scaffolded (add your own)"
    ;;
  *)
    warn "Unknown dockerfile type '$DOCKERFILE_TYPE' — skipping"
    ;;
esac

# ── git init (only for new directories) ─────────────────────
if [ ! -d .git ]; then
  git init
  git add .
  git commit -m "Initial scaffold" >/dev/null 2>&1 || true
  info "Initialized git repository"
fi

# ── Ensure namespace exists ─────────────────────────────────
if command -v kubectl &>/dev/null && kubectl cluster-info 2>/dev/null >/dev/null; then
  kubectl create namespace "$K8S_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
  info "Ensured namespace '$K8S_NAMESPACE' exists on cluster"
else
  warn "No cluster reachable — skipping namespace creation"
fi

# ── Run build if requested ──────────────────────────────────
_build_tag_arg() {
  if [ -n "$CLI_IMAGE_TAG" ]; then
    echo "--image-tag" "$CLI_IMAGE_TAG"
  fi
}

_build_extra_args() {
  :  # build.sh handles existing manifests natively — no extra flags needed
}

if [ "$RUN_BUILD" = true ]; then
  BUILD_STATUS=0
  if [ "$RUN_DEPLOY" = true ]; then
    # deploy implies build — single call with --auto-deploy
    if [ -x "$SCRIPT_DIR/../build.sh" ]; then
      # shellcheck disable=SC2046
      "$SCRIPT_DIR/../build.sh" --app-name "$APP_NAME" $(_build_tag_arg) $(_build_extra_args) --auto-deploy
      BUILD_STATUS=$?
    else
      warn "build.sh not found in parent directory — skipping build/deploy"
      BUILD_STATUS=1
    fi
  else
    # build-only
    if [ -x "$SCRIPT_DIR/../build.sh" ]; then
      # shellcheck disable=SC2046
      "$SCRIPT_DIR/../build.sh" --app-name "$APP_NAME" $(_build_tag_arg) $(_build_extra_args)
      BUILD_STATUS=$?
    else
      warn "build.sh not found in parent directory — skipping build"
      BUILD_STATUS=1
    fi
  fi
fi

# ── Summary ──────────────────────────────────────────────────
echo
step() { printf "\n${CYAN}=== %s ===${NC}\n" "$*"; }
step "Scaffold complete"
echo
echo "  Directory: $TARGET_DIR"
echo "  App name:  $APP_NAME"
echo "  Version:   $_CURRENT_TAG"
echo "  Registry:  $REGISTRY_URL:$REGISTRY_PORT"
echo "  Namespace: $K8S_NAMESPACE"
echo
if [ "$RUN_BUILD" = false ]; then
  echo "Next steps:"
  echo "  cd ../$APP_NAME"
  echo "  ../gitops-template/build.sh --app-name $APP_NAME"
  echo "  ../gitops-template/build.sh --app-name $APP_NAME --auto-deploy"
fi
echo
