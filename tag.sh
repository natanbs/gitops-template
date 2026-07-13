#!/usr/bin/env bash

# Exit immediately if a command exits with a non-zero status
set -e

# Handle --help flag
if [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
    echo "Usage: $(basename "$0") <target_version>"
    echo ""
    echo "Release a new version from an app folder."
    echo "Image name is derived from the current folder name."
    echo ""
    echo "Example:"
    echo "  cd myapp/"
    echo "  ../gitops-template/tag.sh v1.0.0"
    echo ""
    echo "This will:"
    echo "  1. Update .env CURRENT_TAG to the target version"
    echo "  2. Update image tags in k8s/deploy.yaml and k8s/cronjob.yaml"
    echo "  3. Push the Docker image to the registry"
    echo "  4. Create and push a git tag"
    exit 0
fi

# Check for required parameters
if [ -z "$1" ]; then
    echo "Error: Missing required parameter."
    echo "Usage: $(basename "$0") <target_version>"
    echo "Example: $(basename "$0") v1.3.0"
    exit 1
fi

# Function to update image tags in YAML files
update_yaml_image_tags() {
    local yaml_file="$1"
    
    if [ ! -f "$yaml_file" ]; then
        return 0
    fi
    
    # Check if file contains image: lines
    if ! grep -q "image:" "$yaml_file"; then
        echo "Error: No image: lines found in $yaml_file"
        exit 1
    fi
    
    # Update image tags (replace tag after last : with new version)
    if sed "s/\(image:.*:\)[^:]*$/\1${NEW_VERSION}/" "$yaml_file" > "${yaml_file}.tmp" 2>/dev/null; then
        mv "${yaml_file}.tmp" "$yaml_file"
        echo "Updated image tags in $yaml_file"
    else
        rm -f "${yaml_file}.tmp"
        echo "Error: Failed to update image tags in $yaml_file"
        exit 1
    fi
}

# --- Configuration ---
REPO_ROOT="$(git rev-parse --show-toplevel)"
IMAGE_NAME="$(basename "$PWD")"
NEW_VERSION="$1"
REGISTRY_CLUSTER_URL="localhost"
REGISTRY_CLUSTER_PORT="50000"
REGISTRY_FULL_URL="${REGISTRY_CLUSTER_URL}:${REGISTRY_CLUSTER_PORT}"

# Target names
LOCAL_SOURCE="${IMAGE_NAME}:latest"
REGISTRY_TARGET="${REGISTRY_FULL_URL}/${IMAGE_NAME}:${NEW_VERSION}"

echo "Processing release for image: ${IMAGE_NAME}"
echo "Target release version: ${NEW_VERSION}"

# 1. Verify local image exists
echo "[1/5] Verifying local image ${LOCAL_SOURCE} exists..."
if ! docker image inspect "${LOCAL_SOURCE}" >/dev/null 2>&1; then
    if docker image inspect "${IMAGE_NAME}" >/dev/null 2>&1; then
        LOCAL_SOURCE="${IMAGE_NAME}"
    else
        echo "❌ Error: Local image '${LOCAL_SOURCE}' not found."
        echo "Please build your image first: docker build -t ${IMAGE_NAME}:latest ."
        exit 1
    fi
fi

# 2. Update CURRENT_TAG in .env
ENV_FILE="${REPO_ROOT}/.env"
if [ -f "$ENV_FILE" ]; then
    echo "[2/5] Updating CURRENT_TAG in .env..."
    if sed "s/^CURRENT_TAG=.*/CURRENT_TAG=${NEW_VERSION}/" "$ENV_FILE" > "${ENV_FILE}.tmp" 2>/dev/null; then
        mv "${ENV_FILE}.tmp" "$ENV_FILE"
        echo "Updated CURRENT_TAG=${NEW_VERSION} in .env"
    else
        rm -f "${ENV_FILE}.tmp"
    fi
else
    echo "[2/5] Skipping .env update - file not found"
fi

# 3. Update YAML image tags
K8S_DIR="${PWD}/k8s"
if [ -d "$K8S_DIR" ]; then
    echo "[3/5] Updating image tags in k8s/deploy.yaml..."
    update_yaml_image_tags "${K8S_DIR}/deploy.yaml"
    echo "[3/5] Updating image tags in k8s/cronjob.yaml..."
    update_yaml_image_tags "${K8S_DIR}/cronjob.yaml"
else
    echo "[3/5] Skipping YAML updates - no k8s/ directory found"
fi

# 4. Tag and Push Docker
echo "[4/5] Tagging Docker image from [${LOCAL_SOURCE}] to [${REGISTRY_TARGET}]..."
docker tag "${LOCAL_SOURCE}" "${REGISTRY_TARGET}"

echo "[4/5] Pushing Docker image to registry..."
docker push "${REGISTRY_TARGET}"

# 5. Tag and Push Git (Forced overwrite if tag exists)
echo "[5/5] Creating Git tag ${NEW_VERSION} on main branch..."
git checkout main
# -f forces the creation of the tag even if it already exists
git tag -f -a "${NEW_VERSION}" -m "Release version ${NEW_VERSION}"
# -f forces the remote repository to accept the tag overwrite
git push origin -f "${NEW_VERSION}"

echo "Successfully bumped both Git and Docker to ${NEW_VERSION}!"
