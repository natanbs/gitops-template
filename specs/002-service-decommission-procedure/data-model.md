# Data Model: Service Decommission Procedure

## Entities

### Service
- **Identifier**: App name (e.g., `my-api`) + K8s namespace
- **Source of truth**: `.env` file or ArgoCD Application manifest
- **Relationships**: Owned by a source repository; deployed as K8s resources; managed optionally by ArgoCD Application

### Kubernetes Resources
- **Types**: Deployment, Service, Ingress, ConfigMap, Secret, PVC
- **Scope**: All resources in the service's namespace that match the service's app name labels
- **Lifecycle**: Created by `build.sh` template processing; destroyed by decommission

### ArgoCD Application
- **Scope**: Present only for GitOps deployments (Model B)
- **Relation**: References the app repo's `k8s/` directory as source; targets the service's K8s namespace
- **Critical setting**: `spec.syncPolicy.automated.prune: true` enables automatic cleanup

### Container Image
- **Location**: `${REGISTRY_URL}:${REGISTRY_PORT}/${APP_NAME}:${IMAGE_TAG}`
- **Cleanup**: Independent of K8s lifecycle — must be deleted via registry API, CLI, or UI
- **Types**: Local k3d registry or external (Docker Hub, GHCR, ECR, GCR)

### Source Repository
- **Contents**: Application source code, Dockerfile, generated `k8s/` and `argocd/` manifests
- **Post-decommission states**: Archived (read-only), transferred to archive org, or deleted

## State Transitions

```
Active Service
  │
  ├── [Pre-checks passed]
  │
  ├── GitOps Path:
  │   1. Remove manifests from repo → commit
  │   2. ArgoCD sync → prunes cluster resources
  │   3. Verify all resources removed
  │   4. Delete container image from registry
  │   5. (Optional) Archive source repository
  │
  └── Direct Deploy Path:
      1. kubectl delete deployment, svc, ingress, cm, secret
      2. Verify all resources removed
      3. Delete container image from registry
      4. (Optional) Archive source repository

Recovery States (from any step):
  - If step fails → execute phase-specific recovery guidance
  - If partial deletion → verify remaining resources manually
```

## Validation Rules

- **Pre-check**: Service must not be a dependency of other active services
- **Pre-check**: Traffic must be zero or at acceptable level
- **Pre-check**: Service name must match source of truth
- **Post-check**: `kubectl get all -n <ns>` must return no resources belonging to the service
- **Post-check**: ArgoCD Application resource must be absent
- **Post-check**: Container image tag must be removed from registry
- **Audit**: Each decommission must record service name, timestamp, operator, and outcome
