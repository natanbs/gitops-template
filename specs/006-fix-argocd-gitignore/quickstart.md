# Quickstart: Fix ArgoCD Gitignore Conflict

## What changed

Removed `k8s/*.yaml` and `argocd/*.yaml` from `init/gitignore` so rendered ArgoCD manifests are committed to scaffolded apps' git repos.

## How to verify

1. Scaffold a new app:
   ```bash
   ./init.sh --app-name my-service
   ```

2. Check that k8s/argocd files are tracked:
   ```bash
   cd ../my-service
   git status
   ```
   Expected: `k8s/deploy.yaml`, `k8s/svc.yaml`, `argocd/application.yaml` appear as tracked files (not untracked/ignored).

3. Verify the initial commit includes them:
   ```bash
   git log --oneline -1
   git show --stat HEAD
   ```
   Expected: `k8s/deploy.yaml`, `k8s/svc.yaml`, `argocd/application.yaml` are in the commit.

4. After pushing to a remote, ArgoCD should sync without "app path does not exist" errors.
