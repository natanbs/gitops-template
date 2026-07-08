# Quickstart: Decommission a Service via CLI

## Prerequisites

- Go 1.22+ (to build)
- `kubectl` configured with your cluster context
- `git` CLI configured with your app repo credentials
- `argocd` CLI (only for GitOps-path services)
- Registry CLI for image deletion (docker, gh, aws, gcloud, etc.)

## Build

```bash
cd gitops-template
go build -o decommission ./cmd/decommission/
```

## Usage

### GitOps Service (ArgoCD)
```bash
decommission my-api --namespace apps-ns
```

### Direct Deploy Service
```bash
decommission my-api --namespace apps-ns
```
(The CLI auto-detects the deployment model — same command for both.)

### Skip Pre-Checks (emergency only)
```bash
decommission my-api --namespace apps-ns --force
```

### Preview Mode (no changes)
```bash
decommission my-api --namespace apps-ns --dry-run
```

### JSON Audit Output
```bash
decommission my-api --namespace apps-ns --json
```

## Verify Decommission

The CLI prints verification results at the end. To double-check manually:
```bash
kubectl get all -n apps-ns
```
No resources from the decommissioned service should remain.

## Audit Trail

Audit records are written to `./decommission-audit/` by default:
```bash
cat ./decommission-audit/2026-07-07-my-api.txt
```

## Troubleshooting

| Error | Likely Cause | Solution |
|-------|-------------|----------|
| "kubectl not found" | CLI not on PATH | Install kubectl |
| "ArgoCD Application not found" | Wrong namespace or service not GitOps | Check service name; the CLI falls back to Direct Deploy |
| "Pre-checks failed" | Service has active traffic or dependencies | Verify it's safe, then retry with `--force` |
| "Registry CLI not available" | Registry tool not installed | Delete image manually, or install the appropriate CLI |
