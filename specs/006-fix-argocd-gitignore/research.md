# Research: Fix ArgoCD Gitignore Conflict

## Decision: Remove gitignore rules for k8s/argocd YAML files

**Rationale**: The ArgoCD Application template hardcodes `path: k8s` as the manifest source. ArgoCD reads manifests from the app's git repo at that path. If `k8s/*.yaml` is gitignored, the directory is empty or absent in the remote repo, causing "app path does not exist" errors. Removing the gitignore rules is the minimal, correct fix.

**Alternatives considered**:

1. **Force-add in init.sh** (`git add -f k8s/*.yaml argocd/*.yaml`): More surgical but creates a confusing contradiction — files are gitignored yet force-added. Developers must remember to force-add after every build.sh run. Rejected because it trades one problem for another.

2. **Auto-commit in build.sh**: Adds `git add + commit` to build.sh after template rendering. Risky because it changes the build pipeline's side effects and may conflict with CI/CD workflows that expect to handle commits. Rejected as over-scoped for this fix.

3. **Remove gitignore AND add build.sh commit**: Combines approach 1 with auto-commit. Most complete but adds complexity. Rejected because build.sh auto-commit is a separate concern.

## Key Finding

The gitignore rules for `k8s/*.yaml` and `argocd/*.yaml` contradict the ArgoCD workflow. These files must be in the git repo for ArgoCD to function. The rules were likely added without considering the ArgoCD integration.

## Impact Assessment

- **Scope**: 1 file, 2 lines removed
- **Risk**: Low — removing ignore rules can only cause files to be tracked, never untracked
- **Backward compatibility**: No impact on existing apps (they already have the old gitignore; users must re-run init.sh or fix manually)
