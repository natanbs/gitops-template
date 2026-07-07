# Quickstart: Decommission a Service

This guide covers the two decommission paths for this GitOps template.

## GitOps (ArgoCD) Decommission — Primary Path

```text
1. PRE-CHECK: Verify service is safe to decommission
   - No other services depend on it
   - Traffic is zero or acceptable
   - Confirm the service name matches the ArgoCD Application

2. Remove all K8s manifests from the app repo
   - Delete k8s/deploy.yaml, k8s/svc.yaml, k8s/ingress.yaml
   - Also delete argocd/application.yaml
   - Commit and push

3. Wait for ArgoCD to sync and prune
   - Verify via ArgoCD UI or `argocd app get <name>`
   - Resources should disappear within one sync cycle

4. Verify cleanup
   - kubectl get all -n <namespace>
   - Ensure no resources from the decommissioned service remain

5. Delete container image from registry
   - Via registry CLI, API, or UI

6. (Optional) Archive source repository
   - Move to archive org or mark as read-only

7. Record audit entry:
   Service: <name> | Date: <timestamp> | By: <operator> | Status: completed
```

## Direct Deploy Decommission — Secondary Path

```text
1. PRE-CHECK: Same as above (verify safety)

2. Delete K8s resources in order:
   kubectl delete deployment <name> -n <namespace>
   kubectl delete service <name> -n <namespace>
   kubectl delete ingress <name> -n <namespace>
   kubectl delete configmap <name> -n <namespace>  # if present
   kubectl delete secret <name> -n <namespace>      # if present

3. Verify cleanup
4. Delete container image from registry
5. (Optional) Archive source repository
6. Record audit entry
```

## PVC Data Retention

- **Default**: Retain PVC — the PVC and PV survive namespace deletion
- **To delete**: After all other resources are removed, run:
  `kubectl delete pvc <name> -n <namespace>`
- **Warning**: Data deletion is irreversible. Confirm with the team before proceeding.

## Recovery on Failure

If any step fails, stop and address the issue before proceeding:
- **Pre-check fails**: Resolve the dependency or traffic issue, or escalate
- **ArgoCD doesn't prune**: Check Application status; manually delete if needed
- **Registry deletion fails**: Try CLI, UI, or contact registry admin
- For any other failure: Note the state, resolve, and resume or roll back manually
