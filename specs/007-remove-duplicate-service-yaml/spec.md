# Feature Specification: Remove Duplicate Service YAML

**Feature Branch**: `007-remove-duplicate-service-yaml`

**Created**: 2026-07-12

**Status**: Draft

**Input**: User description: "analyst repo svc.yaml and service.yaml are duplication. delete service.yaml but make sure the service would not break"

## User Scenarios & Testing

### User Story 1 - Clean up duplicate k8s Service manifests (Priority: P1)

As an operator managing the analyst service's Kubernetes manifests, I want duplicate Service definition files removed so that there is a single source of truth for the service configuration, reducing confusion and preventing drift between files.

**Why this priority**: Duplicate manifests create a maintenance burden and risk of inconsistent updates — the core reason for this task.

**Independent Test**: Can be fully tested by verifying the surviving manifest (`svc.yaml`) produces an identical `kubectl apply` result as the removed file and that `kubectl get service analyst` returns the expected configuration.

**Acceptance Scenarios**:

1. **Given** the analyst k8s directory contains both `svc.yaml` and `service.yaml`, **When** `service.yaml` is deleted, **Then** `kubectl apply -f k8s/svc.yaml` applies successfully without error.
2. **Given** only `svc.yaml` remains, **When** `kubectl get service analyst -o yaml` is run, **Then** the live Service resource matches the definition in `svc.yaml`.

### Edge Cases

- What happens if a deployment or other resource references the filename `service.yaml` explicitly? (Checked: no such references exist — `kubectl apply -f k8s/` applies the directory, not individual files.)

## Requirements

### Functional Requirements

- **FR-001**: The surviving manifest (`svc.yaml`) MUST define the exact same Service resource (same name, namespace, labels, selector, ports, type) as the removed `service.yaml`.
- **FR-002**: Deleting `service.yaml` MUST NOT require any changes to other files or deployment processes.
- **FR-003**: The analyst Service MUST remain operational after the deletion — existing traffic, selectors, and port mappings MUST be unchanged.

### Key Entities

- **analyst Service**: A LoadBalancer-type Kubernetes Service in the `apps-ns` namespace, selector `app: analyst`, exposing port 8888.

## Success Criteria

### Measurable Outcomes

- **SC-001**: `kubectl apply -f k8s/svc.yaml` succeeds without warnings or errors.
- **SC-002**: `kubectl get service analyst -n apps-ns -o jsonpath='{.spec.ports[0].targetPort}'` returns `8888`.
- **SC-003`: `kubectl get service analyst -n apps-ns -o jsonpath='{.spec.ports[0].port}'` returns `8888`.
- **SC-004**: No downtime or connectivity issues observed for the analyst service after the change.

## Assumptions

- No external tooling or pipeline references the filename `service.yaml` explicitly — all references are to the Service resource name (`analyst`) or the directory (`k8s/`).
- The two files are functionally identical (verified by content comparison).
- The Service resource's live state in the cluster is driven by the manifest content, not the filename.
