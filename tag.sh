#!/usr/bin/env bash

# Exit immediately if a command exits with a non-zero status
set -e

# Check for required parameters
if [ -z "$1" ] || [ -z "$2" ]; then
    echo "Error: Missing required parameters."
    echo "Usage: $0 <image_name> <target_version>"
    echo "Example: $0 familytree v1.3.0"
    exit 1
fi

# --- Configuration ---
IMAGE_NAME="$1"
NEW_VERSION="$2"
REGISTRY_CLUSTER_URL="localhost"
REGISTRY_CLUSTER_PORT="50000"
REGISTRY_FULL_URL="${REGISTRY_CLUSTER_URL}:${REGISTRY_CLUSTER_PORT}"

# Target names
LOCAL_SOURCE="${IMAGE_NAME}:latest"
REGISTRY_TARGET="${REGISTRY_FULL_URL}/${IMAGE_NAME}:${NEW_VERSION}"

echo "Processing release for image: ${IMAGE_NAME}"
echo "Target release version: ${NEW_VERSION}"

# 1. Verify local image exists
echo "Verifying local image ${LOCAL_SOURCE} exists..."
if ! docker image inspect "${LOCAL_SOURCE}" >/dev/null 2>&1; then
    if docker image inspect "${IMAGE_NAME}" >/dev/null 2>&1; then
        LOCAL_SOURCE="${IMAGE_NAME}"
    else
        echo "❌ Error: Local image '${LOCAL_SOURCE}' not found."
        echo "Please build your image first: docker build -t ${IMAGE_NAME}:latest ."
        exit 1
    fi
fi

# 2. Tag and Push Git (Forced overwrite if tag exists)
echo "Creating Git tag ${NEW_VERSION} on main branch..."
git checkout main
# -f forces the creation of the tag even if it already exists
git tag -f -a "${NEW_VERSION}" -m "Release version ${NEW_VERSION}"
# -f forces the remote repository to accept the tag overwrite
git push origin -f "${NEW_VERSION}"

# 3. Tag and Push Docker
echo "Tagging Docker image from [${LOCAL_SOURCE}] to [${REGISTRY_TARGET}]..."
docker tag "${LOCAL_SOURCE}" "${REGISTRY_TARGET}"

echo "Pushing Docker image to registry..."
docker push "${REGISTRY_TARGET}"

# 4. Update CURRENT_TAG in .env
if [ -f ".env" ]; then
    if sed "s/^CURRENT_TAG=.*/CURRENT_TAG=${NEW_VERSION}/" ".env" > ".env.tmp" 2>/dev/null; then
        mv ".env.tmp" ".env"
        echo "Updated CURRENT_TAG=${NEW_VERSION} in .env"
    else
        rm -f ".env.tmp"
    fi
fi

echo "Successfully bumped both Git and Docker to ${NEW_VERSION}!"
