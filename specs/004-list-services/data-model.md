# Data Model: List Available Services

## Entities

### ServiceInfo

Represents a single deployable service discovered in the cluster.

| Field | Type | Description |
|-------|------|-------------|
| Name | string | The service name (Deployment name) |
| Namespace | string | The Kubernetes namespace |
| DeploymentModel | string | Either `"gitops"` or `"direct"` |
| Status | string | Health/ready status (e.g., `"Ready"`, `"Not Ready"`, `"Unknown"`) |
| AvailableReplicas | int | Number of ready replicas (0 if not applicable) |

### ServiceList

Container for the listing response.

| Field | Type | Description |
|-------|------|-------------|
| Services | []ServiceInfo | The list of discovered services |
| TotalCount | int | Total number of services returned |

## Validation Rules

- A service is classified as GitOps if an ArgoCD Application with the same name exists in the `argocd` namespace
- A service with no matching ArgoCD Application is classified as Direct Deploy
- Services with no Deployment and no ArgoCD Application are excluded (must have at least one)

## State Transitions

N/A — listing is a read-only operation with no state changes.
