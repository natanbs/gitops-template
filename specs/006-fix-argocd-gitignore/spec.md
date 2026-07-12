# Feature Specification: Fix ArgoCD Gitignore Conflict

**Feature Branch**: `006-fix-argocd-gitignore`

**Created**: 2026-07-10

**Status**: Draft

**Input**: User description: "With every new service created with the .init.sh, I get this argo error message: Failed to load target state: failed to generate manifest for source 1 of 1: rpc error: code = Unknown desc = k8s: app path does not exist. Fix the init.sh, not the service, I want the service to be fixed by running the init.sh"

## User Scenarios & Testing

### User Story 1 - Scaffold a new app that ArgoCD can sync (Priority: P1)

A developer runs `init.sh --app-name my-service` to create a new application. The scaffolded app directory contains `k8s/` and `argocd/` directories with rendered manifests. After pushing to the remote git repository, ArgoCD successfully discovers and syncs the application without errors.

**Why this priority**: This is the core bug. Every new service fails to sync with ArgoCD because the manifests are gitignored and never committed. Without this fix, the entire ArgoCD-based deployment workflow is broken.

**Independent Test**: Run `init.sh --app-name test-app`, verify `k8s/*.yaml` and `argocd/*.yaml` exist in the output directory, run `git status` from the output directory and confirm these files are tracked (not untracked/ignored), then verify ArgoCD can read the `k8s` path from the git repo.

**Acceptance Scenarios**:

1. **Given** a developer runs `init.sh --app-name my-service`, **When** the scaffold completes, **Then** the app directory contains `k8s/deploy.yaml`, `k8s/svc.yaml`, and `argocd/application.yaml` as git-tracked files.
2. **Given** a scaffolded app with tracked k8s manifests, **When** the app is pushed to a remote git repository, **Then** the `k8s/` directory exists in the remote repo with valid YAML content.
3. **Given** an ArgoCD Application resource pointing to `path: k8s` in the app repo, **When** ArgoCD attempts to sync, **Then** it successfully loads the target state without "app path does not exist" errors.

---

### User Story 2 - Existing apps can be fixed by re-running init.sh (Priority: P2)

A developer with an existing scaffolded app that has the gitignore problem re-runs `init.sh --app-name my-service` to update it. The gitignore is corrected and the k8s/argocd manifests become tracked.

**Why this priority**: Users with already-scaffolded apps need a path to recovery without manually editing their .gitignore.

**Independent Test**: Create an app with the old init.sh (manually add gitignore rules), then re-run init.sh with the same app name. Verify k8s/argocd files are now tracked.

**Acceptance Scenarios**:

1. **Given** an existing app with `k8s/*.yaml` and `argocd/*.yaml` in `.gitignore`, **When** `init.sh --app-name my-service` is re-run, **Then** the `.gitignore` no longer ignores these paths and the manifests become git-tracked.
2. **Given** an existing app with custom k8s manifests, **When** `init.sh` is re-run, **Then** existing manifest customizations are preserved (init.sh skips re-rendering for existing apps).

---

### User Story 3 - Build pipeline continues to work after the fix (Priority: P2)

After the gitignore fix, the `build.sh` pipeline still renders k8s/argocd templates correctly into the app directory. The rendered files are no longer gitignored, so developers can commit them after build.

**Why this priority**: The fix must not break the existing build pipeline. If build.sh renders files that are now tracked, the developer workflow must still be smooth.

**Independent Test**: Run `init.sh --app-name test-app`, then run `build.sh --app-name test-app --image-tag v1.0`, verify k8s/deploy.yaml is updated with the new image tag and is still git-tracked.

**Acceptance Scenarios**:

1. **Given** a scaffolded app with the fixed gitignore, **When** `build.sh` renders templates, **Then** the rendered files in `k8s/` and `argocd/` are not ignored by git.
2. **Given** a scaffolded app after build, **When** the developer runs `git status`, **Then** changes to `k8s/deploy.yaml` (e.g., updated image tag) appear as modified files ready to commit.

---

### Edge Cases

- What happens when `init.sh` is run with `--dockerfile none` (no source files, only k8s manifests)?
- What happens when `init.sh` is run from a directory that is not a sibling of the gitops-template repo?
- What happens if the app directory already has a `.gitignore` with custom rules beyond the template?
- What happens when `build.sh` runs with `--skip-template` flag (no k8s/argocd rendering)?

## Requirements

### Functional Requirements

- **FR-001**: `init/gitignore` MUST NOT contain rules that ignore `k8s/*.yaml` or `argocd/*.yaml` files.
- **FR-002**: `init.sh` MUST ensure that rendered `k8s/` and `argocd/` manifest files are git-tracked in the scaffolded app's initial commit.
- **FR-003**: The fix MUST be applied to `init/gitignore` (the template), not to individual scaffolded apps, so all future apps benefit automatically.
- **FR-004**: Existing `init.sh` functionality MUST NOT regress — all flags (`--dockerfile`, `--registry-url`, `--k8s-ns`, `--container-port`, `--build`, `--deploy`) continue to work.
- **FR-005**: `build.sh` template rendering MUST continue to write to `k8s/` and `argocd/` without errors.
- **FR-006**: The ArgoCD Application template MUST continue to reference `path: k8s` and the path MUST resolve to a valid directory in the app's git repo after scaffolding.

### Key Entities

- **`init/gitignore`**: The gitignore template copied into every scaffolded app. This is the file that needs modification.
- **`init.sh`**: The scaffolding script that creates app directories, renders templates, and does initial git commit.
- **`build.sh`**: The build pipeline that re-renders k8s/argocd templates at build time.
- **ArgoCD Application**: Kubernetes resource that points to `path: k8s` in the app's git repo for sync.

## Success Criteria

### Measurable Outcomes

- **SC-001**: Running `init.sh --app-name test-app` produces an app where `k8s/deploy.yaml`, `k8s/svc.yaml`, and `argocd/application.yaml` are git-tracked (not ignored).
- **SC-002**: After scaffolding and pushing to a remote repo, ArgoCD syncs the application without "app path does not exist" errors.
- **SC-003**: The `build.sh` pipeline completes successfully with the fixed gitignore (no file write errors).
- **SC-004**: All existing `init.sh` flags work identically to before the fix.
- **SC-005**: Zero regressions in the scaffolded app's file set (same files as before, minus the gitignore rules for k8s/argocd).

## Assumptions

- The ArgoCD Application template's `path: k8s` is the correct and intended path for manifest discovery.
- k8s/ and argocd/ manifests are intended to live in the app's git repo (not generated-only at build time).
- The gitignore rules for `k8s/*.yaml` and `argocd/*.yaml` were added in error or without considering the ArgoCD workflow.
- `build.sh` does not need changes — it already renders to the correct locations and the files will now be tracked.
- Existing scaffolded apps with the old gitignore are outside the scope of this fix (users must re-run init.sh or fix manually).
