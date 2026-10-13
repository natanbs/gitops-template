load test_helper

# --bump drives init.sh --deploy + git commit + git push across real repos, so
# drive it against a sandbox of throwaway repos with local bare remotes.
setup() {
  setup_test_env

  WORK="$TEST_TEMP_DIR/bump"
  APPS="$WORK/apps"
  REPOS="$WORK/repos"
  FAKE_GITOPS="$WORK/fake-gitops"
  mkdir -p "$APPS" "$REPOS" "$FAKE_GITOPS"

  cat > "$FAKE_GITOPS/init.sh" <<'EOF'
#!/usr/bin/env bash
[ "${1:-}" = "--deploy" ] || { echo "expected --deploy, got ${1:-}" >&2; exit 1; }
[ "$(basename "$PWD")" = "boom-app" ] && exit 1
echo "change" >> marker.txt
EOF
  chmod +x "$FAKE_GITOPS/init.sh"

  for app in ok-app boom-app; do
    : > "$APPS/$app.yaml"
    git init -q "$REPOS/$app"
    (
      cd "$REPOS/$app"
      git config user.email test@example.com
      git config user.name "Test"
      echo seed > seed.txt
      git add . && git commit -qm initial
      git init -q --bare "$WORK/remote-$app.git"
      git remote add origin "$WORK/remote-$app.git"
      git push -q -u origin HEAD
    )
  done
}

teardown() {
  cleanup
}

@test "ecr.sh --bump deploys, commits and pushes every applicative app" {
  run env GITOPS_DIR="$FAKE_GITOPS" REPOS_DIR="$REPOS" ARGOCD_APPS_DIR="$APPS" \
    "$PROJECT_ROOT/ecr.sh" --bump

  # boom-app's deploy fails, but ok-app must still have been processed
  [ "$status" -eq 1 ]
  [[ "$output" == *"OK: ok-app"* ]]
  [[ "$output" == *"FAILED: boom-app"* ]]

  run git -C "$WORK/remote-ok-app.git" log --oneline
  [[ "$output" == *"bump"* ]]

  run git -C "$WORK/remote-boom-app.git" log --oneline
  [[ "$output" != *"bump"* ]]
}

@test "ecr.sh --bump honours --app to bump a single app" {
  run env GITOPS_DIR="$FAKE_GITOPS" REPOS_DIR="$REPOS" ARGOCD_APPS_DIR="$APPS" \
    "$PROJECT_ROOT/ecr.sh" --bump --app ok-app

  [ "$status" -eq 0 ]
  [[ "$output" == *"OK: ok-app"* ]]
  [[ "$output" != *"boom-app"* ]]
}

@test "ecr.sh --bump skips an app whose repo is missing" {
  rm -rf "$REPOS/boom-app"

  run env GITOPS_DIR="$FAKE_GITOPS" REPOS_DIR="$REPOS" ARGOCD_APPS_DIR="$APPS" \
    "$PROJECT_ROOT/ecr.sh" --bump

  [ "$status" -eq 1 ]
  [[ "$output" == *"not a git repository"* ]]
  [[ "$output" == *"OK: ok-app"* ]]
}
