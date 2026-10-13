#!/usr/bin/env bash
set -euo pipefail

REGISTRY_URL="http://localhost:5100"

usage() {
  cat >&2 <<EOF
Usage: $0 [OPTIONS] [image] [tag]

Delete image tags from the local registry.

Options:
  -h, --help         Show this help
  -k, --keep [N]     Keep the newest N tags per image (default: 3) and delete
                     the rest. If [image] is given, only that image is pruned;
                     otherwise all images are pruned.

Examples:
  $0 argo-app-go-server v1.0      Delete a specific tag
  $0 -k argo-app-go-server        Keep newest 3 tags for one image
  $0 -k 5 argo-app-go-server      Keep newest 5 tags for one image
  $0 -k                           Keep newest 3 tags for all images
EOF
  exit $1
}

get_digest() {
  local image="$1" tag="$2" accept digest header
  for accept in \
    "application/vnd.docker.distribution.manifest.v2+json" \
    "application/vnd.docker.distribution.manifest.list.v2+json" \
    "application/vnd.oci.image.index.v1+json" \
    "application/vnd.oci.image.manifest.v1+json"; do
    header=$(curl -sI -H "Accept: $accept" \
      "$REGISTRY_URL/v2/$image/manifests/$tag" 2>/dev/null) || true
    digest=$(echo "$header" | grep -i docker-content-digest | awk '{print $2}' | tr -d '\r') || true
    [ -n "$digest" ] && break
  done
  echo "$digest"
}

delete_tag() {
  local image="$1" tag="$2" digest code
  digest=$(get_digest "$image" "$tag")
  if [ -z "$digest" ]; then
    echo "Warning: Could not get digest for $image:$tag, skipping" >&2
    return 1
  fi
  code=$(curl -s -o /dev/null -w "%{http_code}" -X DELETE \
    "$REGISTRY_URL/v2/$image/manifests/$digest")
  if [ "$code" = "202" ] || [ "$code" = "200" ]; then
    echo "Deleted $image:$tag"
    return 0
  else
    echo "Warning: Delete failed for $image:$tag (HTTP $code)" >&2
    return 1
  fi
}

prune() {
  local keep="$1" image="$2" repos repo tags tag count deleted
  if [ -n "$image" ]; then
    repos="$image"
  else
    repos=$(curl -s "$REGISTRY_URL/v2/_catalog" | jq -r '.repositories[]' | sort)
  fi
  while read -r repo; do
    [ -n "$repo" ] || continue
    tags=$(curl -s "$REGISTRY_URL/v2/$repo/tags/list" | jq -r '.tags[]?' | sort -V -r)
    count=0
    deleted=0
    while read -r tag; do
      [ -n "$tag" ] || continue
      count=$((count + 1))
      if [ "$count" -gt "$keep" ] && delete_tag "$repo" "$tag"; then
        deleted=$((deleted + 1))
      fi
    done <<< "$tags"
    echo "Image $repo: $deleted/$count deleted (keeping newest $keep)"
  done <<< "$repos"
  echo
  echo "Run garbage collection to reclaim disk space:"
  echo "  docker exec -it \$(docker ps -q -f name=k3d-reg) bin/registry garbage-collect /etc/docker/registry/config.yml"
}

KEEP=""
IMAGE=""
TAG=""

[ $# -gt 0 ] || usage 1

while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help)
      usage 0
      ;;
    -k|--keep)
      if [ $# -ge 2 ] && [[ "$2" =~ ^[0-9]+$ ]]; then
        KEEP="$2"
        shift 2
      else
        KEEP="3"
        shift
      fi
      ;;
    *)
      if [ -z "$IMAGE" ]; then
        IMAGE="$1"
        shift
      elif [ -z "$TAG" ]; then
        TAG="$1"
        shift
      else
        usage 1
      fi
      ;;
  esac
done

if [ -n "$KEEP" ]; then
  if [ -n "$TAG" ]; then
    echo "Error: cannot combine --keep with a specific tag" >&2
    exit 1
  fi
  prune "$KEEP" "$IMAGE"
else
  [ -n "$IMAGE" ] && [ -n "$TAG" ] || usage 1
  delete_tag "$IMAGE" "$TAG"
fi
