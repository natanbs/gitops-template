# Research: List Available Services

**Phase**: Phase 0 — Resolve unknowns and document design decisions.

## Unknowns Resolved

The spec contained no NEEDS CLARIFICATION markers. All design decisions were derived from the existing decommission CLI patterns and standard Go/kubectl practices.

## Design Decisions

### Decision 1: Implement as `--list` flag, not a subcommand
- **Rationale**: The existing CLI uses flags (`--namespace`, `--force`, `--dry-run`). Adding `--list` as a flag is consistent with the current UX and avoids introducing a subcommand parser (which would require structural changes). The `--list` flag is mutually exclusive with the service-name positional argument.
- **Alternatives considered**: Adding a `list` subcommand (requires cobra or manual subcommand routing), a separate `decommission-list` binary (unnecessary complexity).

### Decision 2: Discover services via kubectl exec
- **Rationale**: `kubectl get deployments --all-namespaces` lists all Deployments (Direct Deploy services). `kubectl get applications -n argocd` lists ArgoCD Applications (GitOps services). Both are non-destructive, well-known commands. No client-go dependency needed.
- **Alternatives considered**: Using client-go for K8s API discovery (adds dependency, unnecessary for simple listing), reading from ArgoCD API directly (requires auth).

### Decision 3: Classify a service as GitOps if it has a matching ArgoCD Application
- **Rationale**: Reuses the existing `detectModel()` logic from `detect.go`. A Deployment with a matching ArgoCD Application (same name) is classified as GitOps; otherwise Direct Deploy.
- **Alternatives considered**: Only listing Deployments and separately listing Applications (two separate output sets — less useful), requiring the user to specify model (defeats auto-detection).

### Decision 4: Output format — aligned table + JSON
- **Rationale**: Existing CLI supports `--json` for audit output. Table format with aligned columns is the standard human-readable format. No new formatting library needed — `text/tabwriter` from stdlib.
- **Alternatives considered**: YAML output (unnecessary), raw kubectl passthrough (poor UX).

## Best Practices

### kubectl output parsing
- Use `-o jsonpath` or `-o json` with `jq`-like Go parsing. `jsonpath` is simpler for single-field extraction; `json` + `encoding/json` unmarshal is better for structured data.
- For listing, use `kubectl get deployments -o json` and unmarshal into a typed struct for reliability.

### Go flag conventions
- Boolean flags (`--list`) should not require a value argument. The presence of the flag enables the mode.
- Mutually exclusive flags should be validated at parse time with a clear error message.
