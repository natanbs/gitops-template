#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
INIT_SH="$SCRIPT_DIR/../../init.sh"
PASS=0
FAIL=0

green() { printf "\033[0;32m%s\033[0m\n" "$*"; }
red()   { printf "\033[0;31m%s\033[0m\n" "$*"; }

cleanup() { rm -rf /tmp/smoke-* /tmp/gitops-template /tmp/other-app 2>/dev/null; }
trap cleanup EXIT
cleanup

assert_exit() {
  local expected=$1 actual=$2 test_name=$3
  if [ "$actual" = "$expected" ]; then
    green "  PASS: $test_name"
    PASS=$((PASS + 1))
  else
    red "  FAIL: $test_name (expected exit $expected, got $actual)"
    FAIL=$((FAIL + 1))
  fi
}

assert_contains() {
  local haystack="$1" needle="$2" test_name=$3
  if echo "$haystack" | grep -qE "$needle"; then
    green "  PASS: $test_name"
    PASS=$((PASS + 1))
  else
    red "  FAIL: $test_name (output missing: $needle)"
    FAIL=$((FAIL + 1))
  fi
}

echo "=== Smoke Tests: init.sh Default App Name ==="
echo

# Test 1: Default from folder name
echo "Test 1: Default from folder name"
mkdir -p /tmp/smoke-my-api && cd /tmp/smoke-my-api
OUTPUT=$("$INIT_SH" 2>&1) && EC=$? || EC=$?
assert_exit 0 "$EC" "exits 0"
assert_contains "$OUTPUT" "App name:.*my-api" "uses folder name as app name"
assert_contains "$OUTPUT" "Directory: /tmp/smoke-my-api" "scaffolds in current dir"
[ -f .env ] && green "  PASS: .env created" && PASS=$((PASS + 1)) || { red "  FAIL: .env not created"; FAIL=$((FAIL + 1)); }

# Test 2: Explicit --app-name override
echo
echo "Test 2: Explicit --app-name override"
mkdir -p /tmp/smoke-parent && cd /tmp/smoke-parent
OUTPUT=$("$INIT_SH" --app-name other-app 2>&1) && EC=$? || EC=$?
assert_exit 0 "$EC" "exits 0"
assert_contains "$OUTPUT" "App name:  other-app" "uses explicit name"
[ -d /tmp/other-app ] && green "  PASS: sibling dir created" && PASS=$((PASS + 1)) || { red "  FAIL: sibling dir not created"; FAIL=$((FAIL + 1)); }

# Test 3: Invalid K8s name aborts
echo
echo "Test 3: Invalid K8s name aborts"
mkdir -p /tmp/smoke-My_App.Name && cd /tmp/smoke-My_App.Name
OUTPUT=$("$INIT_SH" 2>&1) && EC=$? || EC=$?
assert_exit 1 "$EC" "exits 1"
assert_contains "$OUTPUT" "not K8s-safe" "shows K8s validation error"

# Test 4: Blocklisted name aborts
echo
echo "Test 4: Blocklisted name aborts"
mkdir -p /tmp/gitops-template && cd /tmp/gitops-template
OUTPUT=$("$INIT_SH" 2>&1) && EC=$? || EC=$?
assert_exit 1 "$EC" "exits 1"
assert_contains "$OUTPUT" "reserved" "shows blocklist error"

# Test 5: Empty string treated as default
echo
echo "Test 5: Empty --app-name treated as default"
mkdir -p /tmp/smoke-empty-test && cd /tmp/smoke-empty-test
OUTPUT=$("$INIT_SH" --app-name "" 2>&1) && EC=$? || EC=$?
assert_exit 0 "$EC" "exits 0"
if echo "$OUTPUT" | grep -q "smoke-empty-test"; then
  green "  PASS: uses folder name"
  PASS=$((PASS + 1))
else
  red "  FAIL: uses folder name (output: $OUTPUT)"
  FAIL=$((FAIL + 1))
fi

# Test 6: Help text
echo
echo "Test 6: Help text"
OUTPUT=$("$INIT_SH" --help 2>&1) && EC=$? || EC=$?
assert_exit 0 "$EC" "exits 0"
assert_contains "$OUTPUT" "current folder name" "mentions folder name default"
assert_contains "$OUTPUT" "cd my-api && ../gitops-template/init.sh" "has folder-name example"

echo
echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] && green "ALL TESTS PASSED" && exit 0 || red "SOME TESTS FAILED" && exit 1
