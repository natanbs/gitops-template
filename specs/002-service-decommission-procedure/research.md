# Research: Service Decommission Procedure

## Decision Record

This feature is a **documented procedure** (runbook), not a software implementation. No technical unknowns, dependencies, or integration points require research.

### Key Design Decisions (from Brainstorm)

| Decision | Chosen Approach | Rationale |
|----------|----------------|-----------|
| Primary decommission path | GitOps-Native (remove manifests → ArgoCD prunes) | Aligns with template's GitOps philosophy; zero new tooling |
| Direct Deploy path | Manual checklist with kubectl delete sequence | Simpler model with no ArgoCD; documented procedure sufficient |
| Scope bound | Documented procedure only, not an automated script | Per constraint from Mission Brief |
| Pre-checks | Mandatory documented pre-checks before any deletion | Prevents accidental decommission (per clarification) |
| Recovery | Phase-specific recovery guidance for partial failures | Ensures operator always has a path forward (per clarification) |
| Audit trail | Lightweight record-keeping (service, timestamp, operator, outcome) | Basic auditability without procedural overhead (per clarification) |

### Alternatives Considered

| Alternative | Why Rejected |
|-------------|-------------|
| Automated decommission script (Approach C) | Constraint requires documented procedure, not script; registry API heterogeneity makes robust automation complex |
| Structured audit log per step | Overkill for template repo; lightweight record-keeping sufficient |

### Assumptions Validated

- `prune: true` is the template default for ArgoCD Applications — confirmed from `init/argocd/application.tmpl.yaml`
- Two deployment models (GitOps and Direct Deploy) are both in active use — confirmed from template docs
- Container registries vary in API — procedure must cover multiple methods (CLI, UI, API)
