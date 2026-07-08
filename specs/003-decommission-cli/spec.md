# Feature Specification: Decommission CLI

**Feature Branch**: `003-decommission-cli`

**Created**: 2026-07-07

**Status**: Draft

**Input**: User description: "Create a cli to decommission services"

## Mission Brief

**Goal**: Provide an interactive CLI tool that automates the safe decommissioning of services deployed via the GitOps template, reducing operator error and time compared to following the manual procedure.

**Success Criteria**:
- An operator can decommission a service in under 60 seconds of CLI interaction time
- Zero data loss — pre-checks enforce by default, with a `--force` flag to bypass on explicit operator override
- The CLI handles both GitOps and Direct Deploy models

**Constraints**:
- Must be a self-contained CLI tool (single binary or script)
- Must support both GitOps and Direct Deploy deployment models
- Must not require cluster-internal access (runs from operator workstation)
- Must be a Go single-binary CLI for portability and zero runtime dependencies

## User Scenarios & Testing

### User Story 1 - GitOps Service Decommission via CLI (Priority: P1)

An operator needs to remove a GitOps-deployed service. They run the CLI with the service name; the CLI identifies the ArgoCD Application, removes manifests from the app repo, pushes the change, waits for ArgoCD to prune resources, cleans up the container image, and records an audit entry.

**Why this priority**: GitOps is the primary deployment model; automating its decommission path saves the most time and reduces error risk.

**Independent Test**: Deploy a test service via GitOps, run the CLI to decommission it, verify all K8s resources are pruned by ArgoCD within one sync cycle.

**Acceptance Scenarios**:

1. **Given** a service deployed via GitOps with `prune: true`, **When** the operator runs `decommission <service-name>`, **Then** the CLI removes manifests from the repo, commits, and ArgoCD prunes all resources
2. **Given** a decommissioned service, **When** the CLI finishes, **Then** `kubectl get all -n <namespace>` shows no resources from the service remain
3. **Given** a decommissioned service, **When** the CLI finishes, **Then** the ArgoCD Application resource is deleted or absent
4. **Given** a decommissioned service, **When** the CLI finishes, **Then** the container image tag is removed from the registry

---

### User Story 2 - Direct Deploy Service Decommission via CLI (Priority: P2)

An operator needs to remove a Direct Deploy service. They run the CLI; it executes the kubectl delete sequence in the correct order, verifies each step, cleans up the image, and records an audit entry.

**Why this priority**: Direct Deploy lacks ArgoCD's safety net, so automated correct-ordering deletion provides significant risk reduction.

**Independent Test**: Deploy a test service via Direct Deploy, run the CLI, verify all resources are deleted in the correct order.

**Acceptance Scenarios**:

1. **Given** a service deployed via Direct Deploy, **When** the operator runs `decommission <service-name>`, **Then** the CLI deletes resources in the correct order (Deployment → Service → Ingress → ConfigMap/Secret → PVC)
2. **Given** a decommissioned service, **When** the CLI finishes, **Then** `kubectl get all -n <namespace>` shows no resources from the service remain

---

### User Story 3 - Interactive PVC Data Retention (Priority: P3)

The CLI detects a PersistentVolumeClaim associated with the service and prompts the operator to retain or delete the data before proceeding.

**Why this priority**: Data loss is the highest-impact risk; the CLI must handle this case explicitly with an interactive safeguard.

**Independent Test**: Deploy a service with a PVC, run the CLI with "retain" and verify the PVC survives; repeat with "delete" and verify the PVC is removed.

**Acceptance Scenarios**:

1. **Given** a service with a PVC being decommissioned, **When** the operator chooses to retain data, **Then** the PVC and PV survive the decommission
2. **Given** a service with a PVC being decommissioned, **When** the operator chooses to delete data, **Then** the PVC is removed and the PV is released

---

### User Story 4 - Dry-Run Mode (Priority: P3)

An operator wants to preview what a decommission would do without making changes. They run the CLI with a `--dry-run` flag and see a summary of actions that would be taken.

**Why this priority**: Safety-critical operations benefit from a preview mode; low implementation effort relative to value.

**Independent Test**: Run the CLI with `--dry-run` against an active service and verify no resources are modified.

**Acceptance Scenarios**:

1. **Given** an active service, **When** the operator runs `decommission <service-name> --dry-run`, **Then** the CLI displays all planned actions without executing any
2. **Given** a dry-run execution, **When** it completes, **Then** all K8s resources, ArgoCD Applications, and registry images remain unchanged

---

### Edge Cases

- What happens when the service name does not exist or is misspelled?
- What happens when the ArgoCD Application is defined in the same repo as the service manifests (self-prune scenario)?
- What happens when the container registry API is unavailable or does not support deletion?
- What happens when the operator interrupts the CLI mid-execution?
- What happens when the service has active traffic or is a dependency of other services?
- What happens when the kubectl context is not set to the correct cluster?
- What happens when the app repo has uncommitted changes?
- What happens when the operator does not have permissions to delete resources?

## Requirements

### Functional Requirements

- **FR-001**: The CLI MUST accept a service name as a positional argument and an optional namespace flag
- **FR-002**: The CLI MUST auto-detect the deployment model (GitOps vs Direct Deploy) by checking for an ArgoCD Application resource
- **FR-003**: The CLI MUST run pre-decommission safety checks: verify service exists, check for active connections, confirm service name against source of truth; and MUST abort if any check fails (unless `--force` is specified, which bypasses pre-checks)
- **FR-004**: The CLI MUST execute the GitOps decommission workflow: clone or pull the app repo, remove K8s manifests, commit with a standardised message, push, and wait for ArgoCD to prune
- **FR-005**: The CLI MUST execute the Direct Deploy decommission workflow: delete resources in the correct order (Deployment → Service → Ingress → ConfigMap/Secret → PVC) and verify each step
- **FR-006**: The CLI MUST detect PersistentVolumeClaims and prompt the operator to retain or delete, defaulting to retain
- **FR-007**: The CLI MUST attempt to delete the container image from the registry and gracefully handle registries that do not support API deletion
- **FR-008**: The CLI MUST support a `--dry-run` flag that displays all planned actions without executing any destructive operations
- **FR-009**: The CLI MUST display progress output for each step (what it is doing, success/failure)
- **FR-010**: The CLI MUST record an audit entry (service name, timestamp, operator, outcome) to a configurable location
- **FR-011**: The CLI MUST exit with a non-zero exit code and a clear error message if any step fails, without leaving the system in a partially-deleted state
- **FR-012**: The CLI MUST validate that the kubectl context is set and the ArgoCD CLI (for GitOps path) is available before proceeding
- **FR-013**: The CLI MUST support `--help` and `--version` flags

### Key Entities

- **Service**: The application being decommissioned, identified by its app name and namespace
- **Kubernetes Resources**: The set of manifests deployed for the service (Deployment, Service, Ingress, ConfigMap, Secret, PVC)
- **ArgoCD Application**: The ArgoCD custom resource managing the service via GitOps; its `prune` setting controls automatic cleanup
- **Container Image**: The Docker image in the registry; cleanup method depends on registry type
- **Source Repository**: The application code repository containing the manifests; the CLI may need to clone, modify, commit, and push
- **Audit Record**: A log entry recording the decommission (service name, timestamp, operator name, outcome, deployment model)

## Success Criteria

### Measurable Outcomes

- **SC-001**: An operator can complete the CLI interaction for a decommission in under 60 seconds
- **SC-002**: Zero data loss incidents when the operator follows the CLI prompts
- **SC-003**: The CLI handles both GitOps and Direct Deploy models with clear, distinct workflows
- **SC-004**: An operator can verify decommission completeness using the CLI output without manual kubectl commands

## Assumptions

- Operators have kubectl access to the cluster with appropriate permissions to delete resources
- Operators have git credentials configured for the app repository (for GitOps path)
- The ArgoCD Application has `prune: true` enabled (matching the template default)
- The container registry supports some form of image deletion (API, CLI, or UI)
- The service being decommissioned is no longer serving production traffic (pre-checks verify this)
- Service dependencies are known or identifiable via the pre-check phase
- The operator has the registry CLI or credentials configured for image deletion
