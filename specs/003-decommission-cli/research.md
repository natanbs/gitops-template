# Research: Decommission CLI

## Decision Record

This feature implements the previously-documented [service decommission procedure](../002-service-decommission-procedure/spec.md) as an interactive Go CLI tool. All technical unknowns were resolved during `/spec.specify` clarifications.

### Key Design Decisions

| Decision | Chosen Approach | Rationale |
|----------|----------------|-----------|
| Language | Go 1.22+ | User preference; single static binary, zero runtime dependencies, excellent CLI support via standard library |
| CLI framework | Go standard library (`flag` package) | Minimal dependencies; CLI surface is simple (positional arg + flags); no need for cobra/viper complexity |
| K8s interaction | Exec `kubectl` commands (not client-go) | Avoids compilation-time cluster binding, auth complexity, and large dependency tree; leverages existing kubectl config |
| Git interaction | Exec `git` commands | Matches documented procedure; no git library dependency needed |
| ArgoCD interaction | Exec `argocd` CLI | Same reasoning as kubectl; ArgoCD API client would add unnecessary complexity |
| Registry cleanup | Exec registry-specific CLIs (docker, aws, gcloud, gh) | Each registry has its own client; exec'ing matches operator workflows |
| Pre-check enforcement | Blocking by default, `--force` override | User clarification; strongest safety guarantee with escape hatch |
| Audit output | Local file + stdout | Simple, no external service dependency |

### Alternatives Considered

| Alternative | Why Rejected |
|-------------|-------------|
| Python CLI | Adds Python runtime dependency; Go chosen by user |
| Shell script CLI | Limited error handling, type safety, and testability compared to Go |
| client-go for all K8s operations | Large dependency tree, auth complexity adds little value over kubectl |
| Cobra/Viper CLI framework | Flag surface is small (<5 flags); standard library flag is sufficient |
| ArgoCD API client | Token management and API versioning complexity not worth the overhead |
| Structured audit DB | Overkill for ops tool; file + stdout audit trail sufficient |

### Assumptions Validated

- Go 1.22+ is available on the build system — confirmed from project golang version usage
- `kubectl`, `git`, and `argocd` CLIs are available on the operator's PATH — confirmed from documented procedure
- The existing decommission procedure at `docs/decommission.md` is the authoritative reference — confirmed as prior feature
- Container registries require separate CLI tools — confirmed from procedure research
- K8s deletion order (Deployment → Service → Ingress → ConfigMap/Secret → PVC) is safe — validated in T014 sandbox testing

### Technology Choices

- **Build system**: Go toolchain (no Makefile needed initially; `go build ./cmd/decommission/`)
- **Testing**: Standard `go test` with table-driven tests
- **Error handling**: Custom error types for each failure mode, wrapped with step context
- **Output format**: Human-readable progress lines by default, JSON output with `--json` flag for machine parsing
