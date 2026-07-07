# Service Decommission Procedure

This document describes how to safely and completely remove a service that was deployed
using the [GitOps Template](https://github.com/natanbs/gitops-template).

## Table of Contents

- [Before You Start](#before-you-start)
- [Pre-Decommission Safety Checklist](#pre-decommission-safety-checklist)
- [Audit Trail](#audit-trail)
- [GitOps (ArgoCD) Decommission](#gitops-argocd-decommission)
- [Direct Deploy Decommission](#direct-deploy-decommission)
- [Handling Persistent Data (PVCs)](#handling-persistent-data-pvcs)
- [Container Image Cleanup](#container-image-cleanup)
- [Source Repository Archival](#source-repository-archival)
- [Recovery Guide](#recovery-guide)
- [Verification Checklist](#verification-checklist)

---

## Before You Start

Before decommissioning any service, confirm:

1. **You have the correct cluster context** — `kubectl config current-context`
2. **You have the service name and namespace** — these are the primary identifiers
3. **You know the deployment model** — GitOps (ArgoCD) or Direct Deploy
   - Check for an `argocd/` directory in the app repo or an ArgoCD Application resource
4. **You have access to**:
   - The app repository (to remove manifests, or archive)
   - The container registry (to delete images)
   - The Kubernetes cluster (to verify cleanup)

---

## Pre-Decommission Safety Checklist

**Do not begin decommissioning until all items below are confirmed.**

| # | Check | How to Verify |
|---|-------|---------------|
| 1 | Service is not a dependency of other active services | Check with team; review service mesh config or ingress routes |
| 2 | Traffic is zero or at an acceptable level | Check monitoring dashboard or ingress metrics |
| 3 | Service name is correct | Confirm against the ArgoCD Application (if GitOps) or the Deployment manifest |
| 4 | Data retention decision has been made | Decide whether to retain or delete PVC data BEFORE starting |
| 5 | Stakeholders have been notified | Inform teams that depend on or operate the service |
| 6 | No active connections or in-flight requests | Check service metrics or connection pools |

**Record the outcome** of each check in your audit entry (see below).

---

## Audit Trail

For every decommission, record:

```
Service: <service-name>
Namespace: <namespace>
Deployment Model: GitOps / Direct Deploy
Decommissioned By: <name>
Date: <YYYY-MM-DD HH:MM>
Pre-checks Passed: Yes / No — <notes>
Resources Removed: Deployment, Service, Ingress, ConfigMap, Secret, PVC
Container Image Deleted: Yes / No
Source Repository: Archived / Retained / Deleted
Status: Completed / Partial — <notes>
```

Save this record in a team-accessible location (e.g., shared drive, wiki, or ops log).

---

## GitOps (ArgoCD) Decommission

Use this path when the service was deployed via the GitOps model (ArgoCD Application
manages the service's K8s resources from an app repository).

### Step 1: Pre-Decommission Checks

Run the [safety checklist](#pre-decommission-safety-checklist) and confirm all items pass.

### Step 2: Remove Manifests from the App Repository

1. Clone the app repository (if you don't already have it)
2. Delete the generated K8s manifests (typically `k8s/` directory):
   ```bash
   git rm k8s/deploy.yaml k8s/svc.yaml k8s/ingress.yaml
   ```
3. Delete the ArgoCD Application manifest (typically `argocd/` directory):
   ```bash
   git rm argocd/application.yaml
   ```
4. Commit and push:
   ```bash
   git commit -m "decommission: remove manifests for <service-name>"
   git push
   ```

### Step 3: Wait for ArgoCD to Prune

ArgoCD will detect that the manifests no longer exist in the repo and automatically
prune the corresponding resources from the cluster (requires `prune: true` in the
Application's sync policy — this is the template default).

Monitor progress via the ArgoCD UI or CLI:
```bash
argocd app get <service-name>
```

Typical sync completes within 2-3 minutes.

> **If the ArgoCD Application manifest was defined in the same repository** and you
> deleted it in Step 2, ArgoCD may have pruned the Application resource itself along
> with the other resources. This is the expected behavior — verify cleanup in Step 4.

### Step 4: Verify Cleanup

```bash
# Check that no resources from this service remain
kubectl get all -n <namespace>

# Check that the ArgoCD Application is gone (GitOps path)
kubectl get application -n argocd | grep <service-name> || echo "Application removed"

# Check for any leftover ConfigMaps or Secrets
kubectl get configmap,secret -n <namespace>
```

### Step 5: Clean Up External Artifacts

- [Delete the container image](#container-image-cleanup) from the registry
- [Archive the source repository](#source-repository-archival) (optional)

### Step 6: Record Audit Entry

Fill in the [audit trail template](#audit-trail) and save it.

---

## Direct Deploy Decommission

Use this path when the service was deployed directly via `build.sh --auto-deploy`
(no ArgoCD managing it).

### Step 1: Pre-Decommission Checks

Run the [safety checklist](#pre-decommission-safety-checklist) and confirm all items pass.

### Step 2: Delete Kubernetes Resources

Delete resources in the following order:

```bash
# 1. Delete the Deployment (stops pods gracefully)
kubectl delete deployment <service-name> -n <namespace>

# 2. Delete the Service (removes load balancer / DNS entry)
kubectl delete service <service-name> -n <namespace>

# 3. Delete the Ingress (removes external routing)
kubectl delete ingress <service-name> -n <namespace>

# 4. Delete associated ConfigMaps (if any)
kubectl get configmap -n <namespace> -l app=<service-name> \
  -o name | xargs kubectl delete -n <namespace>

# 5. Delete associated Secrets (if any — BE CAREFUL not to delete shared secrets)
kubectl get secret -n <namespace> -l app=<service-name> \
  -o name | xargs kubectl delete -n <namespace>

# 6. Handle PVC separately — see "Handling Persistent Data" below
```

**Verify after each step** that the resource is gone:
```bash
kubectl get deployment <service-name> -n <namespace>  # should return "NotFound"
```

### Step 3: Verify Cleanup

```bash
kubectl get all -n <namespace>
```

Ensure no resources from the decommissioned service remain. Pay attention to
resources that may share the namespace with other services.

### Step 4: Clean Up External Artifacts

- [Delete the container image](#container-image-cleanup) from the registry
- [Archive the source repository](#source-repository-archival) (optional)

### Step 5: Record Audit Entry

Fill in the [audit trail template](#audit-trail) and save it.

---

## Handling Persistent Data (PVCs)

If the service uses a PersistentVolumeClaim, decide how to handle the data **before**
deleting the PVC.

### Default: Retain Data

The PVC and its backing PersistentVolume are **not** deleted as part of the standard
decommission. They remain in the namespace so the data can be accessed or migrated later.

```bash
# After decommission, the PVC will still exist:
kubectl get pvc -n <namespace>
```

To access retained data, mount the PVC to a temporary pod or migrate it to another
storage location.

### Option: Delete Data

**⚠️ WARNING: This is irreversible. Confirm with the team before proceeding.**

Only delete the PVC after all other resources have been removed and you are certain
the data is no longer needed:

```bash
# Delete the PVC (this will also release the PV depending on reclaim policy)
kubectl delete pvc <pvc-name> -n <namespace>

# Verify the PVC is gone
kubectl get pvc -n <namespace>
```

The PV's reclaim policy determines what happens to the underlying storage:
- `Delete` — storage is deleted along with the PVC
- `Retain` — storage persists but must be manually reclaimed
- `Recycle` — storage is wiped and made available for new claims (deprecated)

Check the reclaim policy:
```bash
kubectl get pv <pv-name> -o jsonpath='{.spec.persistentVolumeReclaimPolicy}'
```

---

## Container Image Cleanup

After the service is decommissioned from the cluster, delete its container image
from the registry to free storage and prevent accidental re-deployment of stale images.

### Common Registries

| Registry | CLI / Method |
|----------|-------------|
| **Docker Hub** | `docker rmi <image>:<tag>` (local) then delete via Docker Hub web UI or API |
| **GitHub Container Registry (GHCR)** | `ghcr.io` — delete via GitHub web UI (packages) or `gh api` |
| **Amazon ECR** | `aws ecr batch-delete-image --repository-name <name> --image-ids imageTag=<tag>` |
| **Google GCR / Artifact Registry** | `gcloud container images delete <image>:<tag>` |
| **Local k3d registry** | `k3d registry delete <name>` or `docker exec` to the registry container and use `regctl` or curl |
| **Generic registry** | `docker run --rm instrumentisto/regctl tag rm <registry>/<image>:<tag>` |

If the registry does not support CLI or API-based deletion, use the registry's web UI
to navigate to the repository and delete the tag or image manually.

---

## Source Repository Archival

After decommission, you may want to archive the application source repository to
prevent confusion and keep the active repository list clean.

### Option 1: Mark Repository as Archived (GitHub)

1. Go to the repository settings on GitHub
2. Scroll to "Danger Zone"
3. Click "Archive this repository"
4. The repository becomes read-only

### Option 2: Move to Archive Organization

Transfer the repository to a dedicated archive organization (e.g., `archived-*`).

### Option 3: Delete the Repository

**⚠️ Only if you are certain the code is no longer needed.** Ensure the code exists
in a backup or another location first.

---

## Recovery Guide

If a step fails at any point, stop and follow the guidance below.

| Phase | Failure Scenario | Recovery |
|-------|-----------------|----------|
| **Pre-checks** | Service has active dependencies or traffic | Do not proceed. Notify the team and wait for approval. |
| **GitOps manifest removal** | Push rejected (branch protection) | Create a pull request instead of pushing directly; have it reviewed and merged. |
| **ArgoCD prune** | ArgoCD doesn't prune within 5 minutes | Check Application status: `argocd app get <name>`. If stuck, manually sync or delete: `argocd app delete <name> --cascade`. |
| **ArgoCD self-prune edge case** | Application manifest deleted before resources | Verify resources manually with `kubectl get all -n <ns>`. If resources remain, delete them manually using the Direct Deploy method. |
| **kubectl delete** (Direct Deploy) | Resource deletion times out | Force delete: `kubectl delete <resource> <name> -n <ns> --force --grace-period=0`. For stuck finalizers, patch them: `kubectl patch <resource>/<name> -n <ns> -p '{"metadata":{"finalizers":[]}}' --type=merge`. |
| **Registry deletion** | Registry CLI not available or API fails | Use the registry's web UI to delete the image manually. If that also fails, leave the image and note it in the audit entry. |
| **PVC deletion** | PVC stuck in Terminating state | Remove finalizers: `kubectl patch pvc <name> -n <ns> -p '{"metadata":{"finalizers":[]}}' --type=merge`. |
| **Namespace cleanup** | Namespace stuck in Terminating | Check for remaining resources: `kubectl get all -n <ns>`. Remove finalizers from any stuck resources. |
| **Repo archive** | Archive operation fails (API error, permission denied) | Retry using a different method (e.g., web UI instead of CLI). If all methods fail, note the issue in the audit entry and escalate to the repository admin. |

If you cannot resolve the issue, document the current state in the audit trail
and escalate to the platform team.

---

## Verification Checklist

After completing the decommission, run these checks:

- [ ] `kubectl get all -n <namespace>` — no resources from the service remain
- [ ] `kubectl get application -A | grep <service-name>` — no ArgoCD Application found
- [ ] Container image tag removed from registry
- [ ] Source repository archived or marked as decommissioned
- [ ] Audit entry recorded with timestamp and operator name
- [ ] Stakeholders notified of completion
