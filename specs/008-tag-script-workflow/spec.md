# Feature Specification: Tag Script Workflow

**Feature Branch**: `008-tag-script-workflow`

**Created**: 2026-07-13

**Status**: Draft

**Input**: User description: "when running tag.sh, should do: 1. update .env CURRENT_TAG to the target tag 2. push the current image to the registry with that tag 3. git tag with the provided tag"

## Mission Brief

**Goal**: Ensure tag.sh executes its three actions in the correct order: update CURRENT_TAG in .env first, then push the Docker image to the local registry, then create and push the git tag.

**Success Criteria**:
- A developer can run a single command (`tag.sh <image> <version>`) and have all three side-effects complete in the correct order
- After script execution, `.env` contains the new version as CURRENT_TAG, the registry hosts the image under the new tag, and the git repository has the new annotated tag
- A failed step halts the script immediately with a clear error

**Constraints**:
- Script may be run from a different folder, with the path to the gitops-template root provided
- Must handle the case where `.env` does not exist
- Compatible with both macOS and GNU sed

## Clarifications

### Session 2026-07-13

- Q: How should tag.sh locate the gitops-template root when run from a different folder? A: Via GITOPS_ROOT environment variable

## User Scenarios & Testing

### User Story 1 - Run tag.sh to release a new version (Priority: P1)

A developer runs `tag.sh <image> <tag>` to release a new version. The script updates the project's tag tracking, pushes the Docker image to the registry, and records the version as a git tag &mdash; in that order.

**Why this priority**: This is the single primary workflow &mdash; there is only one user journey for this script.

**Independent Test**: Can be fully tested by invoking the script and verifying the three side-effects happen in the specified order. Delivers a correct, atomic release workflow.

**Acceptance Scenarios**:

1. **Given** a valid `.env` file with `CURRENT_TAG=v1.0.0`, **When** the user runs `tag.sh myapp v2.0.0`, **Then** `.env` is updated to `CURRENT_TAG=v2.0.0` and the old value is replaced.
2. **Given** no `.env` file exists, **When** the user runs `tag.sh myapp v2.0.0`, **Then** the `.env` update step is skipped without error and execution continues.
3. **Given** a local Docker image tagged `myapp:latest`, **When** the script reaches the push step, **Then** the image is tagged as `localhost:50000/myapp:v2.0.0` and pushed to the registry.
4. **Given** version `v2.0.0` already exists as a git tag, **When** the script creates that tag, **Then** the existing tag is force-overwritten locally and on the remote.
5. **Given** the script runs to completion, **When** all steps finish, **Then** each step occurs before the next one in the order: (1) `.env` update, (2) Docker push, (3) git tag.

### Edge Cases

- What happens when the local Docker image `myapp:latest` does not exist? The script should fall back to `myapp` (no tag), or report a clear error.
- What happens when the git remote is unreachable? The push should fail immediately (due to `set -e`) and stop the script.
- What happens when `.env` contains `CURRENT_TAG` with unusual formatting (e.g., spaces, quotes)? The sed replacement must handle a typical `.env` line format.

## Requirements

### Functional Requirements

- **FR-001**: The script MUST update the `CURRENT_TAG` entry in `.env` to the target version before any other mutation.
- **FR-002**: The script MUST tag the local Docker image with the registry URL and target version, then push it to the registry.
- **FR-003**: The script MUST create a git annotated tag with the target version and push it to the remote.
- **FR-004**: The git tag step MUST be the final step in the script execution.
- **FR-005**: The script MUST exit with a non-zero code and an informative message if any step fails (`set -e` behavior).
- **FR-006**: If `.env` does not exist, the script MUST skip the `.env` update without error.
- **FR-007**: If the git tag already exists, the script MUST force-overwrite it (locally and on remote).

### Key Entities

- **CURRENT_TAG**: An environment variable stored in `.env` that tracks the most recently released version of an image.
- **Docker image**: The container image being released; identified by image name and tagged with the target version and registry URL.
- **Git tag**: An annotated git reference recording the release version, pushed to the remote repository.

## Success Criteria

### Measurable Outcomes

- **SC-001**: A developer can run a single command (`tag.sh <image> <version>`) and have all three side-effects complete in the correct order.
- **SC-002**: After script execution, `.env` contains the new version as `CURRENT_TAG`, the registry hosts the image under the new tag, and the git repository has the new annotated tag.
- **SC-003**: The script completes in under 60 seconds for a typical image (under 200 MB) on a standard development machine with the registry available locally.
- **SC-004**: A failed step (e.g., missing Docker image, network failure) halts the script immediately with a clear error message and no partial side-effects remain from subsequent steps.

## Assumptions

- The target Docker registry is a local cluster registry running at `localhost:50000`.
- The local Docker image is already built and tagged as `<image_name>:latest` (or `<image_name>` without tag).
- The git repository is already cloned, configured with a remote named `origin`, and has a `main` branch.
- `.env` uses standard `KEY=VALUE` syntax with no spaces around the `=` sign.
- The script is run from the repository root where `.env` resides.
