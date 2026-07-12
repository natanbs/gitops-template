# Quickstart: Remove Duplicate Service YAML

## Verification Steps

1. **Confirm surviving manifest is valid:**
   ```bash
   kubectl apply --dry-run=client -f /Users/natan/projects/analyst/k8s/svc.yaml
   ```

2. **Confirm no references to deleted file:**
   ```bash
   grep -r "service.yaml" /Users/natan/projects/analyst/ --include="*.yaml" --include="*.sh" --include="*.md"
   ```
   Expected: no results

3. **Confirm live service is healthy:**
   ```bash
   kubectl get service analyst -n apps-ns
   kubectl get endpoints analyst -n apps-ns
   ```
