# Brainstorm Context: Service Decommissioning

## Problem Statement

When a service managed via this GitOps template is no longer needed, there is no defined procedure to safely remove it. Decommissioning spans multiple layers: Kubernetes resources (Deployment, Service, Ingress), the ArgoCD Application that manages them, the container image in the registry, and the application source repository. Without a structured approach, operators risk orphaned resources, accidental data loss, or disruption to dependent services.

## Key Concepts

- **Service Lifecycle**: Deploy → Operate → Decommission. The template currently handles only the first two phases.
- **GitOps Reconciliation**: ArgoCD continuously reconciles cluster state with the manifests in the app repo. Decommission must account for this — simply deleting resources will cause ArgoCD to recreate them.
- **Resource Cascade**: A service touches multiple layers: code repo, container registry, Kubernetes resources (Deploy, Svc, Ingress), ArgoCD Application object, and optionally PVCs/ConfigMaps/Secrets.
- **Dependency Awareness**: Other services may depend on this service (via DNS, Service name, or API calls). Blind removal can cause cascading failures.
- **Orphan Prevention**: Leftover PVCs, ConfigMaps, or load balancer resources can accrue cost and clutter if not cleaned up.

## Approaches Considered

### Approach A: Manual Checklist Procedure
- **How it works**: A documented step-by-step checklist that the operator executes manually: disable ArgoCD sync → delete ArgoCD Application → delete K8s manifests → remove image from registry → archive source repo.
- **Tradeoffs**: Simple to implement (documentation only), no code changes. Error-prone if steps are missed. Hard to audit. Scales poorly with many services.
- **Risks**: Human error (skipping steps, wrong namespace). No rollback capability. No verification that cleanup completed.
- **Best for**: Small teams with few services, infrequent decommissions.

### Approach B: GitOps-Native Decommission (Declarative Removal)
- **How it works**: Remove the app's manifests and ArgoCD Application resource from the app repo. Commit and push. ArgoCD detects the resources no longer exist in the repo and auto-prunes them from the cluster. A final manual step removes the image from the registry.
- **Tradeoffs**: Leverages existing GitOps mechanisms. No new tooling needed. Prune must be explicitly enabled (it already is in this template: `prune: true`). Doesn't handle external cleanup (registry images, archived repos). Relies on ArgoCD being healthy.
- **Risks**: If `prune` is not enabled, resources become orphaned. If the ArgoCD Application itself is defined in the repo and gets pruned, it may not self-clean. Operator may not realize cleanup is incomplete.
- **Best for**: Teams already bought into GitOps workflows. Services where full cleanup (registry, repo archive) is handled separately.

### Approach C: Decommission Script / Automation
- **How it works**: A `decommission.sh` script (sibling to `build.sh`) that orchestrates the full teardown: optionally drains traffic → archives the repo → removes ArgoCD Application (via `argocd` CLI or `kubectl`) → deletes K8s namespace → removes container image from registry → logs audit trail.
- **Tradeoffs**: Comprehensive and repeatable. Can include safety checks (e.g., "is traffic zero?", "are there dependent services?"). Higher implementation complexity. Requires credentials for ArgoCD, registry, and GitHub. Must handle partial failures gracefully.
- **Risks**: Script may become out of date as the platform evolves. Could delete resources still in use if dependency detection is flawed. Requires maintenance.
- **Best for**: Platform teams, large numbers of services, compliance/audit requirements.

## Architecture Notes

- The template uses a **three-repository architecture**: bootstrap repo, template repo, app repo. Decommission touches the app repo and the cluster, not the template or bootstrap repos.
- Current `build.sh` is **fetch-and-execute** (fetched via curl). A decommission script could follow the same pattern for consistency.
- Generated manifests are **committed to the app repo** (for GitOps mode). This means removing them from the repo is the trigger for ArgoCD to prune.
- The template supports **two deployment models** (Direct Deploy and GitOps). The decommission procedure differs: Direct Deploy has no ArgoCD to manage, so it's simpler.
- **PVC data** is a special concern — persistent volumes survive namespace deletion unless explicitly deleted. The procedure should ask about data retention.
- The **container registry** (local k3d registry or external) has no lifecycle tied to the app — images must be deleted independently.

## Risk Register

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Accidental deletion of active service | L | H | Require confirmation of service name; check for recent traffic/usage |
| Orphaned resources after ArgoCD prune | M | M | Verify cleanup with `kubectl get all -n <ns>` after decommission |
| Data loss (PVC) | M | H | Default to retaining PVCs; ask explicitly before deletion |
| Dependent service disruption | M | H | Require operator to identify and confirm no dependents, or implement dependency mapping |
| Incomplete decommission (registry images, branches, CI config) | H | L | Checklist/automation that exhaustively enumerates all artifacts |
| ArgoCD Application can't self-prune | M | M | Delete Application resource before namespace resources, or use `argocd app delete` |

## Open Questions

- Should the decommission procedure be part of this template repo (as a script), documented as a process, or both?
- How do we handle the container image cleanup? Registry APIs vary (Docker Hub, GHCR, ECR, GCR, local k3d registry).
- Should decommission include archiving the app repository (e.g., moving to an `archived` org, adding a README notice)?
- Do we need a "soft delete" phase (drain traffic, scale to zero) before actual resource removal?
- How do we detect or document service dependencies so decommissioning doesn't break consumers?
- For the Direct Deploy model (no ArgoCD), should we still remove resources via `kubectl delete` or just leave them?

## Recommended Direction

**Start with Approach B (GitOps-Native)** as the primary path, since it aligns with the template's existing GitOps philosophy and requires zero new tooling. Document it as the standard procedure for Model B (GitOps) deployments.

Complement it with a **lightweight Approach A checklist** for Model A (Direct Deploy) and for cleanup steps that fall outside GitOps' scope (registry images, repo archiving, PVC decisions).

Reserve Approach C (automated script) for a future iteration if decommission frequency or compliance requirements justify the investment. The open questions around registry API heterogeneity and dependency detection make a robust script significantly more complex than it first appears.
