#!/usr/bin/env bash

REGISTRY_URL="http://localhost:5100"
GITOPS_DIR="${GITOPS_DIR:-$(cd "$(dirname "$0")" && pwd)}"
REPOS_DIR="${REPOS_DIR:-$(dirname "$GITOPS_DIR")}"
ARGOCD_APPS_DIR="${ARGOCD_APPS_DIR:-$REPOS_DIR/infra/argocd-infra/apps/applicative}"

show_help() {
    echo "Usage: ecr.sh [OPTIONS] [-a <app>]"
    echo "List container images and tags from the local registry."
    echo ""
    echo "Options:"
    echo "  -h, --help        Show this help message"
    echo "  -f, --full        Show all tags (default: show last 3)"
    echo "  -a, --app <app>   Only act on the specified app/image"
    echo "  -b, --bump        For every app in the ArgoCD applicative dir"
    echo "                    ($ARGOCD_APPS_DIR),"
    echo "                    run init.sh --deploy in its repo, then"
    echo "                    'git add . && git commit -m bump && git push'"
}

# ── Bump every ArgoCD applicative app ─────────────────────────────
# Each <app>.yaml is expected to have a sibling repo at $REPOS_DIR/<app>
# (the same layout init.sh/build.sh assume). Failures are collected so
# one broken repo doesn't stop the rest.
bump_apps() {
    if [ ! -d "$ARGOCD_APPS_DIR" ]; then
        echo "ArgoCD applicative apps dir not found: $ARGOCD_APPS_DIR" >&2
        exit 1
    fi

    local failed=""
    local found=false
    local manifest app app_dir

    for manifest in "$ARGOCD_APPS_DIR"/*.yaml; do
        [ -e "$manifest" ] || continue
        app="$(basename "$manifest" .yaml)"
        if [ -n "$APP" ] && [ "$app" != "$APP" ]; then
            continue
        fi
        found=true

        app_dir="$REPOS_DIR/$app"
        echo "=== Bumping $app ==="
        if [ ! -d "$app_dir/.git" ]; then
            echo "  Skipped: not a git repository: $app_dir" >&2
            failed="$failed $app"
            continue
        fi

        if (cd "$app_dir" && "$GITOPS_DIR/init.sh" --deploy && git add . && git commit -m "bump" && git push); then
            echo "  OK: $app"
        else
            echo "  FAILED: $app" >&2
            failed="$failed $app"
        fi
        echo "-------------------"
    done

    if [ "$found" = false ]; then
        echo "No matching ArgoCD app found in: $ARGOCD_APPS_DIR"
        return 1
    fi
    if [ -n "$failed" ]; then
        echo "Bump failed for:$failed" >&2
        return 1
    fi
    echo "All apps bumped and pushed."
}

SHOW_ALL=false
APP=""
BUMP=false

while [ $# -gt 0 ]; do
    case "$1" in
        -h|--help)
            show_help
            exit 0
            ;;
        -f|--full)
            SHOW_ALL=true
            shift
            ;;
        -b|--bump)
            BUMP=true
            shift
            ;;
        -a|--app)
            if [ $# -lt 2 ] || case "$2" in -*) true;; *) false;; esac; then
                echo "Usage: ecr.sh [-h|--help] [-f|--full] [-b|--bump] [-a|--app <app>]" >&2
                exit 1
            fi
            APP="$2"
            shift 2
            ;;
        *)
            echo "Usage: ecr.sh [-h|--help] [-f|--full] [-b|--bump] [-a|--app <app>]" >&2
            exit 1
            ;;
    esac
done

if [ "$BUMP" = true ]; then
    bump_apps
    exit $?
fi

FOUND=false

while read -r repo; do
    if [ -n "$APP" ] && [ "$repo" != "$APP" ]; then
        continue
    fi
    FOUND=true
    echo "Image: $repo"
    echo "Tags:"
    TAGS=$(curl -s "$REGISTRY_URL/v2/$repo/tags/list" | jq -r '.tags[]?' | sort -V -r)
    if [ "$SHOW_ALL" = true ]; then
        echo "$TAGS" | while read -r tag; do
            [ -n "$tag" ] && echo "  - $tag"
        done
    else
        echo "$TAGS" | head -n 3 | while read -r tag; do
            [ -n "$tag" ] && echo "  - $tag"
        done
    fi
    echo "-------------------"
done < <(curl -s "$REGISTRY_URL/v2/_catalog" | jq -r '.repositories[]' | sort)

if [ -n "$APP" ] && [ "$FOUND" = false ]; then
    echo "No matching image found for: $APP"
fi
