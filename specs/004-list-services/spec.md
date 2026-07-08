# Feature Specification: List Available Services

**Feature Branch**: `004-list-services`

**Created**: 2026-07-07

**Status**: Draft

**Input**: User description: "add to the decommission cli option to list all the available services"

## Mission Brief

**Goal**: Add an option to the decommission CLI that lists all available services the operator can decommission, including their namespace, deployment model, and current status.

**Success Criteria**:
- An operator can run a single command to see all services eligible for decommission
- The output clearly distinguishes between GitOps and Direct Deploy services
- An operator can filter the list by namespace

**Constraints**:
- Must be a single flag or subcommand on the existing decommission CLI binary
- Must not require cluster-internal access (runs from operator workstation)
- Must support both table (human-readable) and JSON output formats

## User Scenarios & Testing

### User Story 1 - List All Services (Priority: P1)

An operator wants to see all services deployed in the cluster before deciding which to decommission. They run the CLI with a list option; it shows each service's name, namespace, deployment model (GitOps or Direct Deploy), and health status.

**Why this priority**: Listing is a prerequisite to informed decommissioning — an operator cannot safely choose a service without knowing what exists.

**Independent Test**: Run the CLI's list option against a cluster with known services and verify all are displayed with correct model classification.

**Acceptance Scenarios**:

1. **Given** a cluster with both GitOps and Direct Deploy services, **When** the operator runs `decommission --list`, **Then** all services are listed with name, namespace, deployment model, and status
2. **Given** the operator runs `decommission --list`, **When** they inspect the output, **Then** each entry shows whether it is GitOps-managed (has an ArgoCD Application) or Direct Deploy
3. **Given** the operator runs `decommission --list --json`, **When** they inspect the output, **Then** it is valid JSON with the same data as the table view

---

### User Story 2 - Filter by Namespace (Priority: P2)

An operator wants to see only services in a specific namespace to narrow down their choices.

**Why this priority**: Namespace filtering reduces cognitive load when many services are deployed.

**Independent Test**: Run the CLI's list option with a namespace filter against a multi-namespace cluster and verify only matching services are shown.

**Acceptance Scenarios**:

1. **Given** services in multiple namespaces, **When** the operator runs `decommission --list --namespace prod`, **Then** only services in the `prod` namespace are displayed
2. **Given** the operator runs `decommission --list --namespace nonexistent`, **Then** the output shows an empty list (not an error)

---

### Edge Cases

- What happens when there are no services in the cluster (empty list)?
- What happens when the kubectl context is invalid or unreachable?
- What happens when there are hundreds of services (pagination / scrollability)?
- What happens when a service has no corresponding Deployment but has an ArgoCD Application (or vice versa)?

## Requirements

### Functional Requirements

- **FR-001**: The CLI MUST support a `--list` flag that displays all discoverable services (both GitOps and Direct Deploy)
- **FR-002**: For each service, the CLI MUST display: service name, namespace, deployment model (GitOps/Direct Deploy), and health/status
- **FR-003**: The CLI MUST auto-detect the deployment model by checking for an ArgoCD Application resource, falling back to Direct Deploy
- **FR-004**: The CLI MUST support `--list --namespace <ns>` to filter results to a single namespace
- **FR-005**: The CLI MUST support `--list --json` to output the listing as valid JSON array
- **FR-006**: The CLI MUST exit with code 0 on success and a non-zero code on failure (e.g., cannot reach cluster)

### Key Entities

- **Service**: A deployed application in the cluster, identified by its Deployment name and namespace
- **ArgoCD Application**: A GitOps-managed Custom Resource that tracks a service; a service with a matching Application is classified as GitOps
- **Deployment Model**: Classification of how the service was deployed — either GitOps (managed by ArgoCD) or Direct Deploy (applied via kubectl)

## Success Criteria

### Measurable Outcomes

- **SC-001**: An operator can list all services in under 5 seconds of CLI interaction time
- **SC-002**: The listing correctly classifies every service by deployment model with no false positives
- **SC-003**: An operator can determine which services are eligible for decommission without switching to additional tools (kubectl, ArgoCD UI)

## Assumptions

- The operator has kubectl access to the cluster with permissions to list Deployments and ArgoCD Applications
- The `--list` output can be reasonably displayed in a terminal without pagination (typical cluster has < 200 services)
- No authentication or authorization changes are needed — existing kubectl access is sufficient
- The existing `--namespace` flag semantics are reused (default: all namespaces unless specified)
