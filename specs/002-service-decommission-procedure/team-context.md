## Discovered Team Context

| ID | Module | Type | Descriptor | Relevance |
|----|--------|------|------------|-----------|
| CDR-2026-003 | context_modules/personas/cloud_native_platform_architect.md | Persona | Cloud-native platform architecture and infrastructure persona | High |
| CDR-2026-005 | context_modules/personas/devops_engineer.md | Persona | DevOps and CI/CD pipeline engineering persona | High |

_Searched 29 CDR entries, 2 high-relevance matches found._

---

### CDR-2026-003: Cloud-Native Platform Architect

**Type**: Persona | **File**: context_modules/personas/cloud_native_platform_architect.md

**Summary**:
- **Motivation**: Enable developer self-service through Kubernetes-native abstractions, GitOps workflows, and automated delivery pipelines.
- **Pain Points**: Repetitive pipeline configurations, manual infrastructure provisioning, inconsistent deployment patterns, lack of reusable abstractions.
- **Success Criteria**: Self-service platform capabilities, reusable templates, fully automated GitOps workflows, zero manual infrastructure operations.

**Core Philosophy**:
- GitOps as the Source of Truth: If it isn't in Git, it doesn't exist.
- DRY: Use templates, includes, compositions, and reusable components.
- Security-Shift-Left: Scanning, validation, least-privilege by default.
- Abstraction over Complexity: Hide cloud provider complexity from developers.
- Multi-Environment Parity: Same abstractions across environments.

**Domain Contexts**: CI, Packaging (Helm), GitOps (ArgoCD), IaC (Crossplane)

### CDR-2026-005: DevOps Engineer

**Type**: Persona | **File**: context_modules/personas/devops_engineer.md

**Summary**:
- **Motivation**: Enable reliable, scalable, secure software delivery through automation, IaC, and observability.
- **Pain Points**: Manual deployments, configuration drift, lack of visibility, secrets in source control, inconsistent environments.
- **Success Criteria**: Fully automated CI/CD, declarative infrastructure, comprehensive monitoring, zero-downtime deployments, secure secrets.

**Collaboration Preferences**:
- Infrastructure changes as PRs with clear descriptions
- Declarative configurations over imperative scripts
- "Everything as code" - version-controlled infrastructure
- GitOps workflows where source of truth is in version control
- Values comprehensive documentation of operational runbooks

---

### Ruleset Context (for service lifecycle operations)

The DevOps Engineer persona references rules for CI/CD pipelines, Helm packaging, secrets management, and cloud authentication — all relevant when considering how decommissioning integrates with existing pipeline and deployment infrastructure.
