# Feature Specification: Fix Init Template Scaffolding

**Feature Branch**: `001-fix-init-templates`

**Created**: 2026-07-06

**Status**: Draft

**Input**: User description: "The repo was built almost right, but when running init.sh it would create in the created app orphans of templates. Goal is for this repo to be the source of all needed files to create the new app and in the created app only have relevant files that are needed for the service to run in the cluster. Currently the repo got broken trying to handle the issue for overlapping fields."

## User Scenarios & Testing

### User Story 1 - Scaffold a new app without orphan template files (Priority: P1)

A developer runs `init.sh --app-name my-service` to create a new application from the gitops template. The resulting app directory should contain only the files needed to build, deploy, and run the service — no template scaffolding artifacts, no example files, no configuration files that belong to the template repository itself.

**Why this priority**: This is the core value proposition of the template. If scaffolding produces orphan files, developers waste time cleaning up or accidentally commit template garbage to their new repo.

**Independent Test**: Can be fully tested by running `init.sh --app-name test-app --local`, inspecting the output directory, and verifying only intended files exist.

**Acceptance Scenarios**:

1. **Given** the template repository is clean, **When** `init.sh --app-name test-app --local` is run, **Then** the output directory contains only: `.env`, `build.sh`, `templates/` (with `.tmpl.yaml` files), and optionally a `Dockerfile` and source files based on `--dockerfile` flag.
2. **Given** a scaffolded app, **When** inspecting the output, **Then** no files from the `.specify/`, `.opencode/`, `specs/`, `tests/`, `cicd-tests/`, `argocd/` directories appear in the output.
3. **Given** a scaffolded app, **When** inspecting the output, **Then** the `k8s/` directory exists but contains only rendered manifests (no static example YAML files from the template repo).

---

### User Story 2 - Build and deploy the scaffolded app without errors (Priority: P1)

After scaffolding, the developer runs `build.sh --app-name test-app --image-tag v1.0` and the pipeline completes successfully — Docker build, tag/push, and template processing all work. The generated k8s manifests contain the correct app name and settings from `.env`.

**Why this priority**: The scaffolded app must be immediately usable. If template files or rendered output are missing or incorrect, the pipeline fails and the template is broken.

**Independent Test**: Run `init.sh --app-name test-app --local`, then `build.sh --app-name test-app --image-tag v1.0 --continue-on-error` inside the output directory and verify all pipeline steps complete.

**Acceptance Scenarios**:

1. **Given** a scaffolded app, **When** `build.sh --app-name test-app --image-tag v1.0` is run, **Then** the Docker build succeeds (assuming a Dockerfile is present or `--dockerfile` was provided during init).
2. **Given** a scaffolded app with templates, **When** `build.sh` processes templates, **Then** `k8s/deploy.yaml`, `k8s/svc.yaml` are generated with correct substitutions from `.env`.
3. **Given** the init and build pipeline, **When** both complete without errors, **Then** a new app can be created end-to-end from the template.

---

### User Story 3 - Fix the overlapping fields issue without regressing existing behavior (Priority: P2)

The previous attempt to fix orphan template files introduced a "broken" state where `init.sh` produces incorrect output, missing required files, or fails entirely. The fix must resolve the overlapping fields problem (where static example files and template-rendered files for the same resource co-exist in k8s/) while preserving all working init.sh functionality.

**Why this priority**: Regressions break existing users. The fix must be verified against known working configurations.

**Independent Test**: Can be tested by running the full `init.sh` + `build.sh` pipeline and comparing output directory contents against a known-good snapshot.

**Acceptance Scenarios**:

1. **Given** the template repo is in a working state, **When** `init.sh` runs, **Then** no existing functionality regresses (all previously working flags: `--dockerfile`, `--local`, `--repo-url`, `--registry-url`, etc. continue to work).
2. **Given** the overlapping fields fix, **When** inspecting `k8s/` after init and build, **Then** there is no situation where a static YAML file and a template-rendered file describe the same Kubernetes resource with different content.

---

### Edge Cases

- What happens when `--local` is used and the working tree is dirty (contains build artifacts)?
- How does the system handle a template repo with no `.tmpl.yaml` files in `templates/`?
- What happens when init.sh is run from a directory that already has a `.specify/` directory?
- How does the system behave when the `--dockerfile` argument is omitted or set to "none"?
- What happens if `.env` already exists in the output directory?

## Requirements

### Functional Requirements

- **FR-001**: `init.sh` MUST only include files in the output app that are necessary for building, deploying, and running the service in a Kubernetes cluster.
- **FR-002**: `init.sh` MUST exclude all template-repo infrastructure files (`.specify/`, `.opencode/`, `specs/`, `tests/`, `cicd-tests/`, `argocd/`, `init.sh`, `README.md`, `CI-CD-FLOW.md`, `.shellcheckrc`) from the scaffolded output.
- **FR-003**: `init.sh` MUST preserve the `templates/` directory and all `.tmpl.yaml` files so that `build.sh` can render them at build time.
- **FR-004**: `init.sh` MUST remove all static example YAML files from `k8s/` before the initial commit, leaving only the directory structure for rendered manifests.
- **FR-005**: `init.sh` MUST preserve `build.sh` and generate a valid `.env` in the output.
- **FR-006**: The scaffolded output MUST pass `build.sh` template processing without errors (assuming Docker is available).
- **FR-007**: `init.sh` MUST handle all existing flags (`--local`, `--repo-url`, `--dockerfile`, `--registry-url`, `--registry-port`, `--k8s-ns`, `--container-port`) without regressions.
- **FR-008**: The template repo MUST remain clean and functional as a source — all template files must exist in this repo, and none should be required to exist in the scaffolded app that aren't needed at runtime.
- **FR-009**: The overlapping fields issue in `k8s/` MUST be resolved: there must be no scenario where a static YAML and a template-rendered YAML describe the same resource in the output.

### Key Entities

- **Template Repository**: The gitops-template repo that serves as the single source of truth for all scaffolding files, templates, and scripts.
- **Scaffolded Application**: The output directory created by `init.sh` that becomes a new standalone application repository.
- **Templates Directory** (`templates/`): Contains `.tmpl.yaml` files with variable substitution placeholders processed by `build.sh` at build time.
- **Kubernetes Manifests Directory** (`k8s/`): Contains rendered YAML manifests after `build.sh` processes templates; initially empty after `init.sh`.
- **Init Script** (`init.sh`): The entry point for scaffolding new applications from the template.
- **Build Script** (`build.sh`): The CI/CD pipeline script included in every scaffolded app to build, push, and deploy.

## Success Criteria

### Measurable Outcomes

- **SC-001**: Running `init.sh --app-name test-app --local` produces an output directory with fewer than 15 files (excluding `.git/`), down from the current count that includes orphan template files.
- **SC-002**: A developer can run `init.sh --app-name test-app --local && cd ../test-app && build.sh --app-name test-app --image-tag v1.0 --continue-on-error` without any errors related to missing or orphan files.
- **SC-003**: Zero files from `.specify/`, `.opencode/`, `specs/`, or the template repo's test directories appear in the scaffolded output.
- **SC-004**: The scaffolded app's `build.sh` template processing step correctly generates all expected Kubernetes manifests (`deploy.yaml`, `svc.yaml`) with correct variable substitution from `.env`.
- **SC-005**: All existing `init.sh` flags (`--local`, `--dockerfile`, `--repo-url`, etc.) continue to work identically to their documented behavior.

## Assumptions

- The `templates/` directory and `.tmpl.yaml` files are required in the scaffolded app because `build.sh` renders them at build time, not at init time.
- The scaffolded app is expected to be used with a CI/CD system that has `envsubst` available (required by `build.sh` template processing).
- Docker is expected to be available on machines running `build.sh`, but not on machines running `init.sh`.
- The `.specify/` directory belongs to the template repo's development workflow and should never be propagated to scaffolded apps.
- Kubernetes manifests in `k8s/` are generated from templates, so static YAML files in the template repo's `k8s/` are example/demo files that should not appear in scaffolded output.
