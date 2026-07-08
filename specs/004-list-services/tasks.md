# Tasks: List Available Services

**Generated**: 2026-07-07  
**Source Spec**: `specs/004-list-services/spec.md`

---

## T001 — Add ServiceInfo / ServiceList to types.go (ASYNC)

**User Story**: US1 (List All Services), US2 (Filter by Namespace)  
**Depends on**: None  
**Files**: `cmd/decommission/types.go`

### Description

Add two new exported types to the shared types file:

- `ServiceInfo` — one struct per the data model (Name, Namespace, DeploymentModel string, Status string, AvailableReplicas int) with JSON tags matching the contract (`name`, `namespace`, `deployment_model`, `status`, `available_replicas`).
- `ServiceList` — container struct with `Services []ServiceInfo` and `TotalCount int`, JSON-tagged `services` and `total_count`.

### Acceptance Criteria

1. `ServiceInfo` exists and matches the data model field-for-field
2. `ServiceList` exists with correct container semantics
3. Both types have JSON tags matching the command schema contract
4. Existing tests and code still compile (no regressions)

---

## T002 — Implement list.go (ASYNC)

**User Story**: US1 (List All Services), US2 (Filter by Namespace)  
**Depends on**: T001  
**Files**: `cmd/decommission/list.go` (NEW)

### Description

Create a new file `list.go` that implements the service listing logic. This file must contain:

- A public function `ListServices(namespace string) (*ServiceList, error)` that:
  1. Runs `kubectl get deployments --all-namespaces -o json` (or `kubectl get deployments -n <ns> -o json` when namespace is non-empty)
  2. Parses the JSON output to extract deployment name, namespace, replica counts
  3. For each deployment, runs `kubectl get applications -n argocd -o json` and checks if an Application exists with the same name — classifies as `gitops` or `direct`
  4. Determines status from the Deployment's ready replica count vs desired replicas
  5. Returns a sorted `*ServiceList` (sort by namespace, then name)
- A public function `RenderTable(w io.Writer, list *ServiceList)` that writes a formatted table with columns: `NAMESPACE`, `NAME`, `MODEL`, `STATUS`, `REPLICAS`
- A public function `RenderJSON(w io.Writer, list *ServiceList)` that writes the list as a JSON object

### Design Decisions

- Parse pod template labels on ArgoCD Applications to match against Deployments
- Use `kubectl` exec'd via `os/exec` (no client-go) to match the rest of the codebase
- Cache the ArgoCD Applications list (one kubectl call) rather than querying per-deployment
- Use `sort` package for alphabetical ordering

### Acceptance Criteria

1. `ListServices("")` returns all services across all namespaces
2. `ListServices("prod")` returns only services in the `prod` namespace
3. Empty namespace filter returns all (backward compatible with existing `--namespace` semantics)
4. Services are correctly classified as GitOps (has matching ArgoCD Application) or Direct Deploy (no match)
5. Status derivation from Deployment replica counts works correctly (Ready when availableReplicas == replicas, Not Ready otherwise, Unknown when no deployment data)
6. `RenderTable` produces the correct column format and respects io.Writer
7. `RenderJSON` produces valid JSON matching the command schema

---

## T003 — Wire --list flag into main.go (ASYNC)

**User Story**: US1 (List All Services)  
**Depends on**: T002  
**Files**: `cmd/decommission/main.go`

### Description

Extend the existing `main.go` to:

1. Add a `--list` boolean flag to the existing `flag.BoolVar` or `flag.Bool` set
2. In the main dispatch logic (after flag parsing, before executing the decommission workflow):
   - If `--list` is set AND a positional (service name) argument is provided, print error to stderr and exit with code 5
   - If `--list` is set (alone or with `--namespace`/`--json`), call `ListServices(namespace)` then `RenderTable` or `RenderJSON` based on `--json` flag, print result, exit 0
   - If `--list` is set and cluster is unreachable, print error to stderr and exit 6

### Acceptance Criteria

1. `decommission --list` invokes the listing function and prints results
2. `decommission --list --json` prints JSON output
3. `decommission --list --namespace prod` filters results
4. `decommission --list myservice` exits with code 5 and prints error message matching the contract
5. All existing flags (--namespace, --json, --force, --dry-run) continue to work for decommission operation when `--list` is not set

---

## T004 — Write tests for list.go (ASYNC)

**User Story**: US1, US2  
**Depends on**: T002  
**Files**: `cmd/decommission/list_test.go` (NEW)

### Description

Write Go unit tests covering:

- `RenderTable` with a populated list, an empty list, single-entry list
- `RenderJSON` with a populated list, empty list
- `RenderJSON` output is valid JSON that can be unmarshalled back to `ServiceList`
- Sorting: services in `ListServices` result are sorted by namespace then name
- Deployments are classified correctly: `default` namespace, `name: "my-deploy"`, deserialize properly etc

Since `ListServices` calls kubectl, mock or stub the exec calls. Use a helper that replaces `exec.Command` with a test version (or make `ListServices` accept an `exec.Command` factory / interface).

### Acceptance Criteria

1. All test functions pass with `go test ./cmd/decommission/`
2. Table rendering tests verify exact string output (no trailing spaces, correct column alignment)
3. JSON rendering tests verify valid JSON round-trips correctly
4. Empty list handles gracefully (table shows headers only; JSON shows `{"services":[],"total_count":0}`)
5. No external dependencies required to run tests (kubectl not needed)

---

## T005 — Build and smoke test (SYNC)

**User Story**: US1, US2  
**Depends on**: T001, T002, T003, T004  
**Files**: N/A

### Description

Perform a final build verification and smoke test:

1. Run `go build ./cmd/decommission/` to confirm compilation
2. Run `go vet ./cmd/decommission/` for static analysis
3. Verify `decommission --help` includes the new `--list` flag
4. Verify that `decommission --list` (without a real cluster) produces a graceful error rather than a panic

### Acceptance Criteria

1. Binary compiles without errors
2. `go vet` passes cleanly
3. Help output mentions `--list`
4. Running against an unreachable cluster exits with code 6 and a clear error message
