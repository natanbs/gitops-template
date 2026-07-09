# Feature Specification: K8s Service Templates with Persistent Storage

**Feature Branch**: `005-k8s-service-templates`

**Created**: 2026-07-09

**Status**: Draft

**Input**: User description: "When creating a new service, add to the tmpl.yaml files under init/k8s. Add support to persistent storage. The persistence volume should be created if in the .env file PVC=true. If PVC=true, add to .env: PVC_NAME=<app>-data, PVC_MOUNT_PATH=/data."

**Goal**: Add persistent storage support to the `init/k8s/` scaffolding templates, enabling developers to opt into PVC resources by setting `PVC=true` in `.env`.

**Success Criteria**:
- A developer can enable PVC for any service by adding `PVC=true` to `.env` and re-running scaffolding
- Setting `PVC=true` auto-populates `PVC_NAME=<app>-data` and `PVC_MOUNT_PATH=/data` without manual entry
- Existing services can opt into PVC without data loss or service downtime
- Services without PVC are completely unaffected (backward compatible)

**Constraints**:
- PVC is opt-in only (`PVC=true` toggle); disabled by default
- Default PVC name is `<app>-data`, default mount path is `/data`
- Existing `PVC_NAME`/`PVC_MOUNT_PATH` values must be preserved on re-scaffold
- Must not break existing services that don't use PVC

## User Scenarios & Testing

### User Story 1 - Enable PVC via .env flag when creating a new service (Priority: P1)

As a developer scaffolding a new service, I want to enable persistent storage by setting `PVC=true` in the `.env` file so that the generated k8s manifests automatically include PVC resources with sensible defaults.

**Why this priority**: This is the primary mechanism for opting into persistent storage — a single flag in `.env` controls whether PVC resources are generated.

**Independent Test**: Can be fully tested by creating a `.env` with `PVC=true`, running the scaffolding, and verifying the generated manifests include a PVC and the `.env` is auto-populated with `PVC_NAME=<app>-data`, `PVC_MOUNT_PATH=/data`, `PVC_SIZE=1Gi`, `PVC_ACCESS_MODE=ReadWriteOnce`, and `PVC_STORAGE_CLASS=standard`.

**Acceptance Scenarios**:

1. **Given** a developer sets `PVC=true` in `.env`, **When** the scaffolding runs, **Then** `.env` is updated with `PVC_NAME=<app>-data`, `PVC_MOUNT_PATH=/data`, `PVC_SIZE=1Gi`, `PVC_ACCESS_MODE=ReadWriteOnce`, and `PVC_STORAGE_CLASS=standard`.
2. **Given** `PVC=true` in `.env`, **When** the k8s templates render, **Then** a PersistentVolumeClaim manifest is generated with `PVC_NAME` as the claim name.
3. **Given** `PVC=true` in `.env`, **When** the Deployment template renders, **Then** volume mounts and volume definitions are included using `PVC_NAME` and `PVC_MOUNT_PATH`.
4. **Given** a developer does NOT set `PVC=true` (or sets `PVC=false`), **When** the scaffolding runs, **Then** no PVC resources are generated and `.env` contains no PVC entries.

---

### User Story 2 - Existing service opts into persistent storage (Priority: P2)

As a developer with an existing scaffolded service, I want to add PVC support by adding `PVC=true` to the `.env` file and re-running scaffolding so that I don't need to recreate the service from scratch.

**Why this priority**: Supporting existing services is important for teams adopting persistence after initial setup.

**Independent Test**: Can be tested by taking an existing service directory without PVC, adding `PVC=true` to `.env`, re-running scaffolding, and verifying PVC resources are added.

**Acceptance Scenarios**:

1. **Given** an existing service with `PVC` unset or `false` in `.env`, **When** the developer sets `PVC=true` and re-runs scaffolding, **Then** `PVC_NAME` and `PVC_MOUNT_PATH` are added to `.env` and PVC resources are generated.
2. **Given** an existing service with `PVC=true` and custom `PVC_NAME`/`PVC_MOUNT_PATH`, **When** the developer changes `PVC_NAME` and re-runs scaffolding, **Then** the PVC manifest uses the new name.

---

### Edge Cases

- What happens if `PVC=true` is set but `PVC_NAME` is manually changed? The custom name should be preserved, not overwritten.
- What happens when `PVC=true` is later set to `PVC=false`? The system warns the user about potential data loss but leaves existing PVC manifests intact. A `--force` flag suppresses the warning and removes PVC resources from generated output.
- What happens if the `.env` file doesn't exist yet when `init.sh` runs? The `.env` should be created with defaults including `PVC=false`.

## Requirements

### Functional Requirements

- **FR-001**: System MUST detect the `PVC` variable in the `.env` file to determine whether to generate PVC resources.
- **FR-002**: When `PVC=true`, the system MUST auto-populate `.env` with `PVC_NAME=<app>-data` (where `<app>` is the application name), `PVC_MOUNT_PATH=/data`, `PVC_SIZE=1Gi`, `PVC_ACCESS_MODE=ReadWriteOnce`, and `PVC_STORAGE_CLASS=standard`.
- **FR-003**: When `PVC=true`, the system MUST generate a PersistentVolumeClaim manifest template using `PVC_NAME` as the claim name.
- **FR-004**: When `PVC=true`, the system MUST include volume mounts in the Deployment template referencing `PVC_NAME` mounted at `PVC_MOUNT_PATH`.
- **FR-005**: When `PVC=true`, the system MUST include volume definitions in the Deployment template that bind the PVC to the pod spec.
- **FR-006**: When `PVC` is unset, `false`, or any value other than `true`, the system MUST NOT generate PVC resources (opt-in only).
- **FR-007**: System MUST preserve existing `PVC_NAME` and `PVC_MOUNT_PATH` values when re-scaffolding an existing service (user customizations are not overwritten).
- **FR-008**: Users MUST be able to override `PVC_SIZE`, `PVC_ACCESS_MODE`, and `PVC_STORAGE_CLASS` in `.env`; overrides must be preserved on re-scaffold.

### Key Entities

- **PVC flag** (`PVC`): Boolean toggle in `.env` that controls whether persistent storage is enabled.
- **PVC Name** (`PVC_NAME`): The name of the PersistentVolumeClaim resource. Defaults to `<app-name>-data`.
- **PVC Mount Path** (`PVC_MOUNT_PATH`): The filesystem path inside the container where the persistent volume is mounted. Defaults to `/data`.
- **PVC Size** (`PVC_SIZE`): The requested storage capacity. Defaults to `1Gi`.
- **PVC Access Mode** (`PVC_ACCESS_MODE`): The access mode for the volume (e.g., `ReadWriteOnce`, `ReadWriteMany`). Defaults to `ReadWriteOnce`.
- **PVC Storage Class** (`PVC_STORAGE_CLASS`): The storage class for the PVC. Defaults to `standard`.
- **PersistentVolumeClaim (PVC)**: A Kubernetes resource requesting persistent storage with specified size, access mode, and storage class.
- **Volume Mount**: Container-level configuration mapping a PVC to a directory path.
- **Volume**: Pod-level configuration binding a PVC to the pod.

## Success Criteria

### Measurable Outcomes

- **SC-001**: A developer can enable PVC for any new or existing service by adding a single line (`PVC=true`) to `.env` and re-running scaffolding.
- **SC-002**: Setting `PVC=true` automatically populates `PVC_NAME`, `PVC_MOUNT_PATH`, `PVC_SIZE`, `PVC_ACCESS_MODE`, and `PVC_STORAGE_CLASS` in `.env` without manual entry.
- **SC-003**: Generated PVC manifests are immediately applicable to a cluster without manual edits.
- **SC-004**: Existing services can opt into PVC without data loss or service downtime.
- **SC-005**: Services without PVC support are completely unaffected by the change (backward compatible).

## Clarifications

### Session 2026-07-09

- Q: When PVC is toggled true→false, should the system warn or remove? → A: Warn by default, leave manifests intact. Add `--force` flag to remove.
- Q: Should PVC size and access mode be configurable? → A: Yes, via `PVC_SIZE`, `PVC_ACCESS_MODE`, and `PVC_STORAGE_CLASS` in `.env`, with defaults 1Gi, ReadWriteOnce, and standard.

## Assumptions

- The default PVC mount path `/data` is appropriate for most stateless-to-stateful transitions.
- The PVC name convention `<app>-data` avoids naming conflicts within a namespace.
- Existing `.env` files may lack a `PVC` variable entirely — treated equivalent to `PVC=false`.
- Custom `PVC_NAME` and `PVC_MOUNT_PATH` values set by the user should be respected on subsequent scaffolding runs.
- The target cluster has the `standard` StorageClass available (unless overridden via `PVC_STORAGE_CLASS`).
