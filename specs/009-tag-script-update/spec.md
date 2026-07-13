# Feature Specification: Tag Script Update

**Feature Branch**: `009-tag-script-update`

**Created**: 2026-07-13

**Status**: Draft

**Input**: User description: "when running ../gitops-template/tag.sh from the app folder, should do: 1. update .env CURRENT_TAG to the target tag 2. push the current image to the registry with that tag 3. git tag with the provided tag"

## Mission Brief

**Goal**: When running `../gitops-template/tag.sh` from an app folder (not the gitops-template root), the script should execute three operations in order: update the `.env` `CURRENT_TAG` to the target tag, push the current image to the registry with that tag, and create a git tag with the provided tag.

**Success Criteria**:
- A developer can run `../gitops-template/tag.sh` from any app folder and have all three side-effects complete in the correct order
- After script execution, `.env` contains the new version as CURRENT_TAG, the registry hosts the image under the new tag, and the git repository has the new annotated tag
- A failed step halts the script immediately with a clear error

**Constraints**:
- Script is invoked from an app folder (subdirectory), not from the gitops-template root
- Must handle the case where `.env` does not exist
- Compatible with both macOS and GNU sed

## User Scenarios & Testing

### User Story 1 - Run tag.sh from app folder to release a new version (Priority: P1)

A developer navigates to an app folder (e.g., `services/myapp/`) and runs `../gitops-template/tag.sh <tag>` to release a new version. The image name is automatically derived from the current folder name. The script updates the project's tag tracking in the gitops-template root, pushes the Docker image to the registry, and records the version as a git tag — in that order.

**Why this priority**: This is the primary workflow — there is only one user journey for this script.

**Independent Test**: Can be fully tested by invoking the script from an app folder and verifying the three side-effects happen in the specified order. Delivers a correct, atomic release workflow.

**Acceptance Scenarios**:

1. **Given** a valid `.env` file with `CURRENT_TAG=v1.0.0` in the gitops-template root and current folder is `services/myapp`, **When** the user runs `../gitops-template/tag.sh v2.0.0` from the app folder, **Then** `.env` is updated to `CURRENT_TAG=v2.0.0` and the old value is replaced.
2. **Given** no `.env` file exists in the gitops-template root and current folder is `services/myapp`, **When** the user runs `../gitops-template/tag.sh v2.0.0` from the app folder, **Then** the `.env` update step is skipped without error and execution continues.
3. **Given** a local Docker image tagged `myapp:latest` and current folder is `services/myapp`, **When** the script reaches the push step, **Then** the image is tagged with the registry URL and target version, and pushed to the registry.
4. **Given** version `v2.0.0` already exists as a git tag, **When** the script creates that tag, **Then** the existing tag is force-overwritten locally and on the remote.
5. **Given** the script runs to completion from an app folder, **When** all steps finish, **Then** each step occurs before the next one in the order: (1) `.env` update, (2) Docker push, (3) git tag.

### Edge Cases

- What happens when the local Docker image `myapp:latest` does not exist? The script should fall back to `myapp` (no tag), or report a clear error.
- What happens when the git remote is unreachable? The push should fail immediately (due to `set -e`) and stop the script.
- What happens when `.env` contains `CURRENT_TAG` with unusual formatting (e.g., spaces, quotes)? The sed replacement must handle a typical `.env` line format.
- What happens when the script is invoked with an incorrect relative path? The script should fail with a clear error message.

## Requirements

### Functional Requirements

- **FR-001**: The script MUST update the `CURRENT_TAG` entry in `.env` to the target version before any other mutation.
- **FR-002**: The script MUST derive the image name from the current folder name using `basename "$PWD"`, then tag the local Docker image with the registry URL and target version, and push it to the registry.
- **FR-003**: The script MUST create a git annotated tag using just the version string (e.g., `v2.0.0`) and push it to the `origin` remote.
- **FR-004**: The git tag step MUST be the final step in the script execution.
- **FR-005**: The script MUST exit with a non-zero code and an informative message if any step fails (`set -e` behavior).
- **FR-006**: If `.env` does not exist, the script MUST skip the `.env` update without error.
- **FR-007**: If the git tag already exists, the script MUST force-overwrite it (locally and on remote).
- **FR-008**: The script MUST correctly resolve paths when invoked from a subdirectory using relative paths.
- **FR-009**: The script MUST display progress messages for each major step (updating .env, pushing image, creating git tag).

### Key Entities

- **CURRENT_TAG**: An environment variable stored in `.env` that tracks the most recently released version of an image.
- **Docker image**: The container image being released; identified by the current folder name (derived via `basename "$PWD"`) and tagged with the target version and registry URL.
- **Git tag**: An annotated git reference using just the version string (e.g., `v2.0.0`), pushed to the remote repository.

## Success Criteria

### Measurable Outcomes

- **SC-001**: A developer can run `../gitops-template/tag.sh <version>` from any app folder and have all three side-effects complete in the correct order.
- **SC-002**: After script execution, `.env` contains the new version as `CURRENT_TAG`, the registry hosts the image under the new tag, and the git repository has the new annotated tag.
- **SC-003**: The script completes in under 60 seconds for a typical image (under 200 MB) on a standard development machine with the registry available locally.
- **SC-004**: A failed step (e.g., missing Docker image, network failure) halts the script immediately with a clear error message and no partial side-effects remain from subsequent steps.

## Clarifications

### Session 2026-07-13

- Q: How should the script determine the Docker image name to push? → A: Derived from the current folder name using `basename "$PWD"`
- Q: What format should the git tag use? → A: Just the version string (e.g., `v2.0.0`)
- Q: Does the registry require authentication to push images? → A: No authentication needed (local/insecure registry)
- Q: What level of output should the script provide during execution? → A: Progress messages for each step
- Q: Should the git remote name be hardcoded to `origin` or configurable? → A: Hardcoded to `origin`

## Assumptions

- The target Docker registry is a local cluster registry running at `localhost:50000` with no authentication required.
- The local Docker image is already built and tagged as `<image_name>:latest` (or `<image_name>` without tag), where `<image_name>` is derived from the current folder name using `basename "$PWD"`.
- The git repository is already cloned, configured with a remote named `origin`, and has a `main` branch.
- `.env` uses standard `KEY=VALUE` syntax with no spaces around the `=` sign.
- The script is run from an app folder within the repository, not from the gitops-template root.
- The relative path to the script correctly resolves to the gitops-template directory.
