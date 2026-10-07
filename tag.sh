#!/usr/bin/env bash

# Exit immediately if a command exits with a non-zero status
set -e

# Handle --help flag
if [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
echo "Usage: $(basename "$0") <target_version>"
echo ""
echo "Release a new version from an app folder."
echo "If the app has multiple images (multiple image: refs in k8s/*.yaml),"
echo "all images are tagged with the same version."
echo "Falls back to the folder name as image name if no k8s/ directory exists."
echo ""
echo "Example:"
echo "  cd myapp/"
echo "  ../gitops-template/tag.sh v1.0.0"
echo ""
echo "This will:"
echo "  1. Verify the local Docker images exist"
echo "  2. Update .env CURRENT_TAG to the target version"
echo "  3. Update image tags and the IMAGE_TAG env var in all k8s/*.yaml files"
echo "  4. Tag and push all Docker images to the registry"
echo "  5. Commit and push the k8s/ manifest changes"
echo "  6. Create and push a git tag"
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
# Rewrites the tag of every `image:` reference and the IMAGE_TAG env var so
# the committed manifest matches the released version. Untagged and
# digest-pinned references are left untouched.
update_yaml_image_tags() {
    local yaml_file="$1"

    if [ ! -f "$yaml_file" ]; then
        return 0
    fi

    # Check if file contains image: lines — skip if not
    if ! grep -q "image:" "$yaml_file"; then
        return 0
    fi

    if awk -v tag="${NEW_VERSION}" '
        # Replace only the tag segment of an image reference, preserving the
        # registry host, path, quoting and any trailing comment.
        function retag_image(line,   prefix, value, tail, q, first, last, i, ch, idx) {
            if (!match(line, /image:[[:space:]]*/)) return line
            prefix = substr(line, 1, RSTART + RLENGTH - 1)
            value  = substr(line, RSTART + RLENGTH)

            # Split off a trailing YAML comment so it survives the retag
            tail = ""
            for (i = 1; i <= length(value); i++) {
                ch = substr(value, i, 1)
                if (ch ~ /[[:space:]]/ || ch == "#") {
                    tail = substr(value, i)
                    value = substr(value, 1, i - 1)
                    break
                }
            }

            first = substr(value, 1, 1)
            last  = substr(value, length(value), 1)
            q = ""
            if (first == last && (first == "\"" || first == sprintf("%c", 39))) {
                q = first
                value = substr(value, 2, length(value) - 2)
            }

            # Digest-pinned references carry no mutable tag
            if (index(value, "@") > 0) return line

            idx = 0
            for (i = length(value); i > 0; i--) {
                if (substr(value, i, 1) == ":") { idx = i; break }
            }
            if (idx == 0) return line
            return prefix q substr(value, 1, idx) tag q tail
        }
        /^[[:space:]]*(-[[:space:]]+)?image:[[:space:]]*[^[:space:]]/ { print retag_image($0); next }
        /^[[:space:]]*-?[[:space:]]*name:[[:space:]]*"?IMAGE_TAG"?[[:space:]]*$/ {
            print
            if (getline value_line) sub(/value:.*/, "value: \"" tag "\"", value_line)
            print value_line
            next
        }
        { print }
    ' "${yaml_file}" > "${yaml_file}.tmp" 2>/dev/null; then
        mv "${yaml_file}.tmp" "${yaml_file}"
        echo "Updated image tags in $yaml_file"
    else
        rm -f "${yaml_file}.tmp"
        echo "Error: Failed to update image tags in $yaml_file"
        exit 1
    fi
}

# Function to extract unique image names from k8s YAML files
# Extracts the image name (without registry prefix and tag) from image: lines
# e.g., "image: k3d-reg:50000/myapp:v1.0.0" -> "myapp"
discover_images_from_yaml() {
    local k8s_dir="$1"
    local images=()

    for yaml_file in "${k8s_dir}"/*.yaml "${k8s_dir}"/*.yml; do
        [ -f "$yaml_file" ] || continue

        # Extract image names from image: lines
        # Strip "image: " prefix, then strip registry:port/ prefix and :tag suffix
        while IFS= read -r line; do
            # Get the image reference (after "image: ")
            local img_ref="${line#*image: }"
            img_ref="$(echo "$img_ref" | xargs)"  # trim whitespace

            # Extract image name: strip registry prefix (everything up to last /) and tag suffix (after last :)
            local img_name
            img_name="$(echo "$img_ref" | sed 's|.*/||; s|:.*||')"

            if [ -n "$img_name" ]; then
                images+=("$img_name")
            fi
        done < <(grep "image:" "$yaml_file" 2>/dev/null)
    done

    # Return unique image names
    printf '%s\n' "${images[@]}" | sort -u
}

# --- Configuration ---
REPO_ROOT="$(git rev-parse --show-toplevel)"
APP_NAME="$(basename "$PWD")"
NEW_VERSION="$1"
REGISTRY_CLUSTER_URL="localhost"
REGISTRY_CLUSTER_PORT="50000"
REGISTRY_FULL_URL="${REGISTRY_CLUSTER_URL}:${REGISTRY_CLUSTER_PORT}"

# Function to find the best local image tag for a given image name
# Priority: :latest > untagged > highest semver tag
find_local_image() {
    local img="$1"

    # 1. Check for :latest
    if docker image inspect "${img}:latest" >/dev/null 2>&1; then
        echo "${img}:latest"
        return 0
    fi

    # 2. Check for untagged
    if docker image inspect "${img}" >/dev/null 2>&1; then
        echo "${img}"
        return 0
    fi

    # 3. Find highest semver tag
    local best_tag
    best_tag="$(docker images --format '{{.Repository}}:{{.Tag}}' 2>/dev/null \
        | grep -E "^${img}:v[0-9]" \
        | sort -t. -k1,1n -k2,2n -k3,3n \
        | tail -1)"

    if [ -n "$best_tag" ]; then
        echo "$best_tag"
        return 0
    fi

    return 1
}

# Discover images: scan k8s YAML files for image names, fallback to app name
K8S_DIR="${PWD}/k8s"
IMAGES=()
if [ -d "$K8S_DIR" ]; then
    while IFS= read -r img; do
        [ -n "$img" ] && IMAGES+=("$img")
    done < <(discover_images_from_yaml "$K8S_DIR")
fi

# Fallback to single image derived from folder name
if [ ${#IMAGES[@]} -eq 0 ]; then
    IMAGES=("$APP_NAME")
fi

echo "Processing release for image(s): ${IMAGES[*]}"
echo "Target release version: ${NEW_VERSION}"

# 1. Verify all local images exist
echo "[1/6] Verifying local images exist..."
for img in "${IMAGES[@]}"; do
    if ! local_source="$(find_local_image "$img")"; then
        echo "Error: No local image found for '${img}'."
        echo "Please build your image first: docker build -t ${img}:<version> ."
        exit 1
    fi
    echo "[1/6] Found local image: ${local_source}"
done

# 2. Update CURRENT_TAG in .env
ENV_FILE="${REPO_ROOT}/.env"
if [ -f "$ENV_FILE" ]; then
    echo "[2/6] Updating CURRENT_TAG in .env..."
    if sed "s/^CURRENT_TAG=.*/CURRENT_TAG=${NEW_VERSION}/" "$ENV_FILE" > "${ENV_FILE}.tmp" 2>/dev/null; then
        mv "${ENV_FILE}.tmp" "$ENV_FILE"
        echo "Updated CURRENT_TAG=${NEW_VERSION} in .env"
    else
        rm -f "${ENV_FILE}.tmp"
    fi
else
    echo "[2/6] Skipping .env update - file not found"
fi

# 3. Update YAML image tags
if [ -d "$K8S_DIR" ]; then
    echo "[3/6] Updating image tags in k8s YAML files..."
    for yaml_file in "${K8S_DIR}"/*.yaml "${K8S_DIR}"/*.yml; do
        [ -f "$yaml_file" ] || continue
        update_yaml_image_tags "$yaml_file"
    done
else
    echo "[3/6] Skipping YAML updates - no k8s/ directory found"
fi

# 4. Tag and Push all Docker images
echo "[4/6] Tagging and pushing Docker images..."
for img in "${IMAGES[@]}"; do
    local_source="$(find_local_image "$img")"
    registry_target="${REGISTRY_FULL_URL}/${img}:${NEW_VERSION}"
    echo "[4/6] Tagging [${local_source}] -> [${registry_target}]"
    docker tag "${local_source}" "${registry_target}"
    echo "[4/6] Pushing [${registry_target}]..."
    docker push "${registry_target}"
done

# 5. Commit and push manifest changes
# ArgoCD syncs the k8s/ manifests from git, so the release tag must point at
# a commit that carries the new image tag — not the previous HEAD.
echo "[5/6] Committing manifest changes..."
if [ ! -d "${REPO_ROOT}/.git" ]; then
    echo "[5/6] Skipping commit - ${REPO_ROOT} is not a git repository"
elif [ ! -d "$K8S_DIR" ]; then
    echo "[5/6] Skipping commit - no k8s/ directory found"
else
    if [ "$(git -C "$REPO_ROOT" branch --show-current)" != "main" ]; then
        echo "[5/6] Switching to main before committing..."
        if ! git -C "$REPO_ROOT" checkout main; then
            echo "Error: Could not switch to main — commit the manifest changes by hand." >&2
            exit 1
        fi
    fi

    changed="$(git -C "$REPO_ROOT" status --porcelain -- k8s 2>/dev/null || true)"
    if [ -z "$changed" ]; then
        echo "[5/6] No manifest changes to commit"
    else
        git -C "$REPO_ROOT" add k8s
        if git -C "$REPO_ROOT" commit -m "Release ${NEW_VERSION}: update k8s image tag" -q; then
            echo "[5/6] Committed manifest updates: $(git -C "$REPO_ROOT" rev-parse --short HEAD)"
        else
            echo "Error: Failed to commit manifest updates in ${REPO_ROOT}" >&2
            exit 1
        fi
        if git -C "$REPO_ROOT" push origin HEAD; then
            echo "[5/6] Pushed manifest commit to origin"
        else
            echo "Error: Failed to push manifest commit — ArgoCD will not sync it" >&2
            exit 1
        fi
    fi
fi

# 6. Tag and Push Git (Forced overwrite if tag exists)
echo "[6/6] Creating Git tag ${NEW_VERSION} on main branch..."
# -f forces the creation of the tag even if it already exists
git -C "$REPO_ROOT" tag -f -a "${NEW_VERSION}" -m "Release version ${NEW_VERSION}"
# -f forces the remote repository to accept the tag overwrite
git -C "$REPO_ROOT" push origin -f "${NEW_VERSION}"

echo "Successfully bumped both Git and Docker to ${NEW_VERSION}!"
