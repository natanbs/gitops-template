# Feature Specification: YAML Tag Update

**Feature Branch**: `010-yaml-tag-update`

**Created**: 2026-07-13

**Status**: Draft

**Input**: User description: "Add to the previous tag.sh request to also update the deploy.yaml and cronjob.yaml with the new tag"

## Mission Brief

**Goal**: Extend the tag.sh script to also update `deploy.yaml` and `cronjob.yaml` files with the new tag value, in addition to the existing `.env` update functionality.

**Success Criteria**:
- The script updates `deploy.yaml` image tag fields with the new version
- The script updates `cronjob.yaml` image tag fields with the new version
- Both updates happen in the correct order alongside existing operations
- A failed YAML update halts the script immediately with a clear error

**Constraints**:
- Must integrate with existing tag.sh workflow
- YAML files may have different field structures for image tags
- Must handle the case where YAML files do not exist

## User Scenarios & Testing

### User Story 1 - Update deploy.yaml with new tag (Priority: P1)

A developer runs tag.sh and the script automatically updates the `deploy.yaml` file in the app folder with the new image tag. The deployment manifest reflects the new version without manual editing.

**Why this priority**: This is the primary use case - keeping deployment manifests in sync with releases.

**Independent Test**: Can be fully tested by running tag.sh and verifying deploy.yaml contains the new tag value.

**Acceptance Scenarios**:

1. **Given** a `deploy.yaml` file exists in the app folder with an image tag `v1.0.0`, **When** the user runs `../gitops-template/tag.sh v2.0.0`, **Then** the image tag in deploy.yaml is updated to `v2.0.0`.
2. **Given** no `deploy.yaml` file exists in the app folder, **When** the user runs `../gitops-template/tag.sh v2.0.0`, **Then** the deploy.yaml update step is skipped without error and execution continues.

---

### User Story 2 - Update cronjob.yaml with new tag (Priority: P2)

A developer runs tag.sh and the script automatically updates the `cronjob.yaml` file in the app folder with the new image tag. The cronjob manifest reflects the new version without manual editing.

**Why this priority**: Cronjobs are less common than deployments but still need version tracking.

**Independent Test**: Can be fully tested by running tag.sh and verifying cronjob.yaml contains the new tag value.

**Acceptance Scenarios**:

1. **Given** a `cronjob.yaml` file exists in the app folder with an image tag `v1.0.0`, **When** the user runs `../gitops-template/tag.sh v2.0.0`, **Then** the image tag in cronjob.yaml is updated to `v2.0.0`.
2. **Given** no `cronjob.yaml` file exists in the app folder, **When** the user runs `../gitops-template/tag.sh v2.0.0`, **Then** the cronjob.yaml update step is skipped without error and execution continues.

---

### Edge Cases

- What happens when the YAML file exists but has no image tag field? The script should report a clear error.
- What happens when the YAML file has multiple image tags? All `image:` lines should be updated with the new tag.
- What happens when the YAML file has unusual formatting? The sed replacement must handle typical YAML structure.

## Requirements

### Functional Requirements

- **FR-001**: The script MUST update image tag fields in `k8s/deploy.yaml` if the file exists in the app folder.
- **FR-002**: The script MUST update image tag fields in `k8s/cronjob.yaml` if the file exists in the app folder.
- **FR-003**: If either YAML file does not exist, the script MUST skip that update without error.
- **FR-004**: The YAML updates MUST occur after the `.env` update but before Docker push and git tag operations.
- **FR-005**: The script MUST display progress messages for each YAML file update.
- **FR-006**: A failed YAML update (including no `image:` lines matched) MUST halt the script immediately with a clear error message.

### Key Entities

- **deploy.yaml**: A Kubernetes Deployment manifest located in `k8s/` subdirectory containing the image tag to be updated.
- **cronjob.yaml**: A Kubernetes CronJob manifest located in `k8s/` subdirectory containing the image tag to be updated.
- **Image tag field**: Lines in YAML files matching `image:` where the tag (after the last `:`) is replaced with the new version.

## Success Criteria

### Measurable Outcomes

- **SC-001**: A developer can run `../gitops-template/tag.sh <version>` and have deploy.yaml updated automatically if it exists.
- **SC-002**: A developer can run `../gitops-template/tag.sh <version>` and have cronjob.yaml updated automatically if it exists.
- **SC-003**: The YAML updates complete in under 5 seconds for typical files.
- **SC-004**: A failed YAML update (e.g., malformed file) halts the script immediately with a clear error message.

## Clarifications

### Session 2026-07-13

- Q: Where are the deploy.yaml and cronjob.yaml files located relative to the app folder? → A: In a `k8s/` subdirectory within the app folder
- Q: What pattern should the script use to identify image tags in the YAML files? → A: Match lines containing `image:` and replace the tag after the last `:`
- Q: If a YAML file contains multiple `image:` lines, should all be updated? → A: Yes, update all `image:` lines in the file
- Q: What should happen if sed fails to match any `image:` line in an existing YAML file? → A: Report an error and halt the script
- Q: In what order should the YAML updates occur relative to other operations? → A: After `.env` update, before Docker push and git tag

## Assumptions

- The `deploy.yaml` and `cronjob.yaml` files use standard Kubernetes manifest format.
- Image tags are specified in the format `image: <registry>/<image>:<tag>` or similar.
- The YAML files are located in a `k8s/` subdirectory within the app folder (e.g., `myapp/k8s/deploy.yaml`).
- The script is run from an app folder within the repository, not from the gitops-template root.
