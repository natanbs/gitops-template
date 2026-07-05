# test_helper.bash — Shared utilities for bats tests
#
# Usage: In each .bats file, add:
#   load test_helper

# Detect project root (two levels up from tests/)
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PROJECT_ROOT

# Cleanup function: remove temp directory and restore originals
cleanup() {
  rm -rf "$TEST_TEMP_DIR"
  if [ -n "$_ORIG_APP_NAME" ]; then
    export APP_NAME="$_ORIG_APP_NAME"
  fi
}

# Create a temporary test workspace with a sample Dockerfile
setup_test_env() {
  TEST_TEMP_DIR=$(mktemp -d)
  export TEST_TEMP_DIR

  # Minimal sample Dockerfile
  cat > "$TEST_TEMP_DIR/Dockerfile" <<'EOF'
FROM busybox:latest
CMD ["echo", "test-app"]
EOF

  # Track original environment
  _ORIG_APP_NAME="${APP_NAME:-}"
}

# Assert image exists in local Docker daemon
assert_image_exists() {
  local image="$1"
  docker image inspect "$image" >/dev/null 2>&1 || {
    echo "Image $image does not exist" >&2
    return 1
  }
}

# Assert image does NOT exist in local Docker daemon
assert_image_not_exists() {
  local image="$1"
  docker image inspect "$image" >/dev/null 2>&1 && {
    echo "Image $image exists but should not" >&2
    return 1
  }
}

# Assert file content matches expected string
assert_file_contains() {
  local file="$1"
  local expected="$2"
  grep -qF "$expected" "$file" || {
    echo "File $file does not contain: $expected" >&2
    echo "Contents: $(cat "$file")" >&2
    return 1
  }
}
