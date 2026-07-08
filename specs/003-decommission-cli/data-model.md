# Data Model: Decommission CLI

## Entities

### Service
- **Identifier**: App name (string) + K8s namespace (string, default from kubectl context)
- **Source of truth**: Cluster state (ArgoCD Application or Deployment manifest)
- **State**: Active → decommissioning → decommissioned / failed
- **Validation**: Must exist in the cluster before any action is taken

### K8s Resource Set
- **Types**: Deployment, Service, Ingress, ConfigMap, Secret, PVC
- **Scope**: All resources in the service's namespace matching the service name
- **Discovery**: Via kubectl API calls (get deployment, service, ingress, etc.)
- **Deletion order**: Deployment → Service → Ingress → ConfigMap/Secret → PVC

### Deployment Model
- **GitOps** (ArgoCD): ArgoCD Application exists and manages the service; decommission via manifest removal + prune
- **Direct Deploy**: No ArgoCD Application; decommission via sequential kubectl delete
- **Detection**: Check for ArgoCD Application resource `kubectl get application -n argocd <name>`

### ArgoCD Application
- **Source**: Points to an app repository (repoURL + path)
- **Key setting**: `spec.syncPolicy.automated.prune` — must be `true` for automatic cleanup
- **Decommission action**: Remove manifests from repo → commit → push → ArgoCD prunes
- **Edge case**: If Application is in the same repo, it may self-prune

### Container Image
- **Location**: `${registry}/${app}:${tag}`
- **Cleanup**: Via registry-specific CLI (docker, aws, gcloud, gh) or API
- **Failure mode**: Registry API unavailable — log and continue

### Source Repository
- **Contents**: Application source code + generated k8s/ and argocd/ manifests
- **Actions**: Clone (if needed), remove k8s/ and argocd/ dirs, commit, push
- **Edge case**: Uncommitted changes → prompt operator

### Audit Record

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| ServiceName | string | yes | Name of the decommissioned service |
| Namespace | string | yes | K8s namespace |
| DeploymentModel | string | yes | "gitops" or "direct" |
| Operator | string | yes | User who ran the CLI (from `$USER` or `--operator` flag) |
| Timestamp | string | yes | ISO 8601 timestamp |
| PreChecksPassed | bool | yes | Whether pre-checks passed (or --force used) |
| ResourcesRemoved | []string | yes | List of resource types deleted |
| ImageDeleted | bool | yes | Whether container image was cleaned up |
| Status | string | yes | "completed" or "partial" with notes |
| Notes | string | no | Free-text failure details |

## State Transitions

```
Service Identified (name + namespace)
  │
  ├── [--dry-run] → Display planned actions → Exit 0
  │
  ├── Pre-checks
  │   ├── Pass → continue
  │   └── Fail (no --force) → Exit 1 with error
  │
  ├── Deployment Model Detection
  │   ├── ArgoCD Application found → GitOps path
  │   └── No ArgoCD Application → Direct Deploy path
  │
  ├── PVC Check
  │   ├── PVC found → Prompt operator (retain/delete)
  │   └── No PVC → skip
  │
  ├── Resource Deletion
  │   ├── GitOps: Git operations → push → wait for prune → verify
  │   └── Direct: kubectl delete sequence → verify each step
  │
  ├── Container Image Cleanup
  │   ├── Registry CLI available → delete image
  │   └── Registry CLI unavailable → log warning
  │
  ├── Audit Record → Write to file + stdout
  │
  └── Complete → Exit 0
```

## Validation Rules

- **Pre-check**: Service name must resolve to at least one K8s resource
- **Pre-check**: Operator must confirm service identity (Y/n prompt)
- **Pre-check**: If GitOps mode, ArgoCD Application must exist with `prune: true`
- **Post-check**: After deletion, `kubectl get all -n <ns>` must return no service resources
- **Post-check**: Audit record must be written before exit
- **Error recovery**: On any failure, CLI must output current state and exit 1
