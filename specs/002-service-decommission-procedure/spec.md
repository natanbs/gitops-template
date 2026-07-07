# Feature Specification: Service Decommission Procedure

**Feature Branch**: `002-service-decommission-procedure`

**Created**: 2026-07-07

**Status**: Draft

**Input**: User description: "service decommissioning procedure"

## Mission Brief

**Goal**: Establish a clear, repeatable process for safely removing a service and its associated resources from a GitOps-managed Kubernetes cluster.

**Success Criteria**:
- Operators can decommission a service within one ArgoCD sync cycle with confidence all resources are removed
- Zero data loss incidents when procedure is followed
- Procedure covers both GitOps and Direct Deploy models

**Constraints**:
- Must work for both GitOps and Direct Deploy deployment models
- Must be a documented procedure, not an automated script

## User Scenarios & Testing

### User Story 1 - GitOps Service Decommission (Priority: P1)

An operator needs to remove a service that was deployed via GitOps (ArgoCD). The operator removes the service's manifests from the app repository, commits the change, and ArgoCD prunes the resources from the cluster automatically. The operator then cleans up external artifacts: removes the container image from the registry and archives the source repository.

**Why this priority**: This is the primary deployment model for the template, and represents the safest decommission path that leverages existing GitOps mechanisms.

**Independent Test**: Can be tested in a sandbox cluster by deploying a test service via the template, then following the procedure to remove it and verifying all resources are deleted.

**Acceptance Scenarios**:

1. **Given** a service deployed via GitOps with `prune: true`, **When** the operator removes all K8s manifests from the app repo and commits, **Then** ArgoCD prunes the corresponding resources from the cluster
2. **Given** a decommissioned service, **When** the operator runs `kubectl get all -n <namespace>`, **Then** no resources belonging to the service remain
3. **Given** a decommissioned service, **When** the operator verifies the ArgoCD Application resource, **Then** it is deleted or absent from the cluster
4. **Given** a decommissioned service, **When** the operator checks the container registry, **Then** the service's image tag is removed

---

### User Story 2 - Direct Deploy Service Decommission (Priority: P2)

An operator needs to remove a service that was deployed via the Direct Deploy model (without ArgoCD). The operator runs a sequence of `kubectl delete` commands to remove Deployment, Service, Ingress, and any related resources, then cleans up the container image and archives the repository.

**Why this priority**: The Direct Deploy model is simpler but lacks ArgoCD's auto-prune safety net, so a clear manual procedure is needed to avoid orphaned resources.

**Independent Test**: Can be tested in a sandbox cluster by deploying a test service without GitOps, then following the procedure and verifying cleanup.

**Acceptance Scenarios**:

1. **Given** a service deployed via Direct Deploy, **When** the operator follows the manual deletion procedure, **Then** all K8s resources (Deployment, Service, Ingress) are removed
2. **Given** a clean namespace after decommission, **When** the operator runs `kubectl get all`, **Then** no resources from the decommissioned service appear

---

### User Story 3 - Safe Decommission with Data Retention (Priority: P3)

An operator needs to decommission a service that uses a PersistentVolumeClaim. The procedure prompts the operator to decide whether to retain or delete the PVC and its data, with clear guidance on implications.

**Why this priority**: Data loss is the highest-impact risk in decommissioning, so the procedure must handle this case explicitly.

**Independent Test**: Can be tested by deploying a service with a PVC, decommissioning it with both "retain" and "delete" choices, and verifying the PVC behavior matches the choice.

**Acceptance Scenarios**:

1. **Given** a service with a PVC being decommissioned, **When** the operator chooses to retain data, **Then** the PVC and PV survive namespace deletion
2. **Given** a service with a PVC being decommissioned, **When** the operator chooses to delete data, **Then** the PVC is removed and the PV is released

---

### Clarifications

#### Session 2026-07-07

- Q: Pre-decommission verification — should the procedure require explicit pre-checks or assume operator readiness? → A: Require documented pre-checks as mandatory steps before any deletion begins.
- Q: Partial failure recovery — should the procedure document recovery steps for mid-process failures or assume operator handles exceptions? → A: Document phase-specific recovery guidance for each decommission step.
- Q: Record keeping / audit trail — should the procedure require recording decommission actions? → A: Include lightweight record-keeping instructions (service name, timestamp, operator, outcome).

### Edge Cases

- What happens when the ArgoCD Application is defined in the same repo as the service manifests and removing the manifests also removes the Application definition before it can prune resources?
- What happens when a service has active traffic or connections at the time of decommission?
- What happens when the container registry does not support API-based image deletion and requires manual cleanup?
- How does the operator handle services that are dependencies for other active services?
- What happens when the namespace contains resources from multiple services and a partial cleanup is needed?
- What happens when the service was deployed with custom resource types (CRDs) that are not covered by standard templates?

## Requirements

### Functional Requirements

- **FR-001**: The procedure MUST document the GitOps service decommission workflow: remove manifests from repo → commit → wait for ArgoCD prune → verify cleanup
- **FR-002**: The procedure MUST document the Direct Deploy service decommission workflow: delete each resource type in the correct order → verify cleanup
- **FR-003**: The procedure MUST mandate a pre-decommission safety checklist executed before any deletion begins, including: verify service is not a dependency of other active services, verify zero or acceptable traffic levels, confirm service name against the source of truth (e.g., ArgoCD Application or namespace), and record the verification outcome
- **FR-004**: The procedure MUST include clear guidance on handling PersistentVolumeClaims: default to retain, require explicit confirmation to delete
- **FR-005**: The procedure MUST include steps for verifying complete cleanup: run verification commands, check namespace, check ArgoCD, check registry
- **FR-006**: The procedure MUST include guidance for container image cleanup across common registry types
- **FR-007**: The procedure MUST include guidance for handling the ArgoCD Application resource when it is defined in the same repository as the service manifests
- **FR-008**: The procedure MUST include optional steps for archiving the source repository after decommission
- **FR-009**: The procedure MUST document recovery guidance for each decommission phase (pre-checks, resource deletion, registry cleanup, repo archive) in case a step fails or times out
- **FR-010**: The procedure MUST instruct the operator to record a lightweight audit entry for each decommission, including service name, timestamp, operator identity, and completion status

### Key Entities

- **Service**: The application being decommissioned, identified by its app name and namespace.
- **Kubernetes Resources**: The set of manifests (Deployment, Service, Ingress, ConfigMap, Secret, PVC) deployed for the service.
- **ArgoCD Application**: The ArgoCD custom resource that manages the service's lifecycle via GitOps reconciliation. Its `prune` setting controls automatic cleanup.
- **Container Image**: The Docker image stored in the registry, tagged with the service's image tag. Cleanup requires separate action per registry.
- **Source Repository**: The application code repository containing the generated manifests and Dockerfile. May be archived or deleted.

## Success Criteria

### Measurable Outcomes

- **SC-001**: An operator can fully decommission a GitOps-deployed service by following the documented procedure, with all K8s resources removed within one ArgoCD sync cycle
- **SC-002**: An operator can fully decommission a Direct Deploy service in under 10 minutes using the documented procedure
- **SC-003**: Zero data loss incidents resulting from the decommission procedure when the operator follows the PVC guidance
- **SC-004**: An operator can verify decommission completeness without access to the original deployment configuration
- **SC-005**: The procedure handles both deployment models (GitOps and Direct Deploy) with clear, distinct workflows

## Assumptions

- Operators have kubectl access to the cluster with appropriate permissions to delete resources
- Operators can access the container registry (CLI or web UI) to delete images
- For GitOps decommission, the ArgoCD Application has `prune: true` enabled (matching the template default)
- The service being decommissioned is no longer serving production traffic
- Service dependencies are known to the operator (automated dependency detection is out of scope for this procedure)
- The container registry supports some form of image deletion (API, CLI, or UI)
- The operator can access the source repository to either remove manifests or archive it
