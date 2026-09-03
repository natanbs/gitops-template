# Feature Specification: Secrets & Vault Standard Conformance

**Feature Branch**: none (no git.feature hook registered)

**Created**: 2026-08-31

**Status**: Draft

**Input**: User description: "check all repos and confirm they all use the same standard when using secrets and vault. make sure best practice is selected."

## User Scenarios & Testing

### User Story 1 - Fleet Secrets/Vault Standard Audit (Priority: P1)

A platform/security engineer inventories every repo in the fleet and, for each one,
learns which secrets/vault pattern it actually uses and whether that pattern matches
the org's selected best-practice standard — with a single, deterministic verdict per
repo.

**Why this priority**: The user's request is an audit ("check all repos and confirm"),
so fleet-wide detection and verdicting is the core value; nothing else is useful without it.

**Independent Test**: Running the audit against the fleet produces exactly one verdict
(`CONFORMING` / `NON-CONFORMING` / `N/A`) per repo, and any repo whose detected pattern
differs from the standard is listed as `NON-CONFORMING`.

**Acceptance Scenarios**:

1. **Given** a fleet of N repos, **When** the audit runs, **Then** every repo appears in the report with its detected secrets/vault pattern and a verdict — none are skipped silently.
2. **Given** a repo that uses a secrets/vault pattern different from the selected standard, **When** the audit runs, **Then** that repo is `NON-CONFORMING` and the report names the gap.
3. **Given** a repo that uses no secrets or vault at all, **When** the audit runs, **Then** it is reported `N/A`, never a failure.

---

### User Story 2 - Best-Practice Standard Selection (Priority: P1)

Before any scoring, the org's canonical secrets/vault standard is explicitly selected
rather than assumed: candidate approaches are compared against documented criteria, one
best-practice standard is chosen, and the audit measures every repo against that single
choice.

**Why this priority**: The request is explicit ("make sure best practice is selected");
a comparison built against an unstated or mixed standard cannot confirm conformity.

**Independent Test**: The selection is documented with ≥3 criteria, at least one rejected
alternative, and a versioned statement of the chosen standard; each audit check maps 1:1
to a rule of that chosen standard.

**Acceptance Scenarios**:

1. **Given** the candidate standards, **When** the selection is made, **Then** criteria, rejected alternatives, and the chosen standard are recorded in a versioned document the audit references.
2. **Given** the selected standard, **When** the audit runs, **Then** every non-conformance it reports traces back to a specific rule of that standard.

---

### User Story 3 - Actionable Remediation (Priority: P2)

Every repo confirmed as non-conforming receives a concrete, actionable fix rather than a
bare failing verdict, so repo owners can converge on the standard.

**Why this priority**: Without remediation the audit only raises noise; remediation is what
makes conformity achievable (Constitution II-2 Gate Ergonomics).

**Independent Test**: Every `NON-CONFORMING` row in the report carries an explicit `fix:`
remediation naming the file(s) or setting(s) to change; none is verdict-only.

**Acceptance Scenarios**:

1. **Given** a non-conforming repo, **When** the report is generated, **Then** the row identifies the violating artifact and a deterministic remediation.
2. **Given** a remediated repo, **When** the audit re-runs, **Then** the repo flips to `CONFORMING` and stays deterministic.

---

### User Story 4 - Continuous Enforcement (Priority: P3)

The confirmed standard becomes an automated check in the existing standards gate, so new
drift is caught at PR time and on the conformance sweep instead of only in point-in-time audits.

**Why this priority**: The brainstorm recommends gates first (Approach C) and the gate exists
from feature 001; wiring the secrets/vault conformance into it is the durable enforcement
slice. Per Q3 (C) it is a gated RFC follow-on behind the constitution Pending Decision Log
("Ownership") — recorded here, not shipped in this deliverable.

**Independent Test**: The standards-audit workflow (or the sweep caller) includes the
secrets/vault standard check for `app-k8s` repos and fails the job on a non-conformance.

**Acceptance Scenarios**:

1. **Given** a repo with a secrets/vault pattern that drifts from the standard, **When** its PR runs the standards audit, **Then** the audit job fails naming the violation and fix.
2. **Given** a repo with an approved exemption, **When** the audit runs, **Then** the exemption is honored (allowlist) and the repo is not failed.

---

### Edge Cases

- A repo that uses **no secrets or vault** (pure library, no runtime secrets): verdict `N/A`, never `NON-CONFORMING`.
- A repo **mixing multiple patterns** (e.g., External-Secrets for some secrets and a separate static mechanism for others): verdict `NON-CONFORMING` with the mixed patterns named.
- A repo found to have **committed secrets or long-lived credentials** in git-tracked files: hard failure regardless of which vault standard it uses.
- A repo with **no local checkout / unreachable** during the inventory run: reported `UNKNOWN` with the reason — never silently dropped from the fleet count.
- **Two repos using the same tool but different conventions** (store naming, path scheme, rotation cadence): treated as non-conforming to the "same standard" requirement, per the selection's rules.

## Requirements

### Functional Requirements

- **FR-001**: System MUST enumerate the fleet from the ArgoCD applicative apps inventory (`infra/argocd-infra/apps/applicative/*.yaml`) and produce exactly one assessment row per applicative repo (CONFORMING / NON-CONFORMING / N/A / UNKNOWN).
- **FR-002**: System MUST detect, from repo contents and offline (no network, no live cluster), which secrets/vault pattern each repo uses — e.g. synced from a secret store, direct vault references, static/declarative secrets, or none.
- **FR-003**: System MUST emit a versioned, explicit selection of the canonical best-practice secrets/vault standard — criteria, rejected alternatives, and chosen standard — before any repo is scored.
- **FR-004**: System MUST compare each repo's detected pattern against the chosen standard and classify the repo accordingly; detection MUST NOT silently assume a pattern when multiple are present.
- **FR-005**: Every NON-CONFORMING row MUST include a deterministic `fix:` remediation naming the violating artifacts or settings.
- **FR-006**: System MUST flag critical anti-patterns — committed credential material, long-lived cloud credentials, static vault tokens in manifests — as hard failures independent of the standard used. These anti-patterns are codified within the standard as Primary rules (VS-006 committed secrets, VS-007 static tokens); "independent of the standard used" means they fail regardless of which secret-store pattern a repo otherwise employs, not that they exist outside the standard. A repo with any such anti-pattern is NON-CONFORMING.
- **FR-007**: Audit MUST be deterministic and repeatable: unchanged repos yield identical verdicts across runs, and local results equal CI results.
- **FR-008**: System MUST score each repo against the HashiCorp Vault best-practice standard — consistent secret path convention (`/<env>/<service>/<key>`), short-lived/dynamic credential patterns (K8s/VM auth, AppRole) instead of static or long-lived tokens, and absence of committed secret material (Q2 resolved: B — Vault is the single standard). The path convention and consumption-pattern rules are scored as advisory (non-blocking) per the standard's weights; blocking classification depends on the Primary rules (Vault store declared, external-secrets consumption, no committed secrets, no static tokens). "Rotation posture" is operationalized as: no static/long-lived Vault tokens (VS-007) and K8s-Kubernetes-auth (VS-002) — i.e., credentials that are short-lived by construction; a separate absolute TTL threshold is out of scope for the offline audit.
- **FR-009**: Gate integration is a gated follow-on (RFC), NOT part of this deliverable: the Vault-conformance check plugs into the existing standards-audit gate (PR + sweep fail on non-conformance, honoring the allowlist) only after the constitution Pending Decision Log "Ownership" item resolves (Q3 resolved: C).

### Key Entities

- **Repo**: The audited unit; carries a detected pattern and a verdict (CONFORMING / NON-CONFORMING / N/A / UNKNOWN).
- **Secrets/Vault Standard**: The versioned, explicitly selected best-practice definition the fleet is measured against (criteria + chosen standard + rejected alternatives).
- **Conformance Report**: One row per repo (pattern, verdict, fix), plus a fleet-level summary score.
- **Exemption**: An approved, recorded deviation from the standard honored by the audit.

## Success Criteria

### Measurable Outcomes

- **SC-001**: 100% of the repo URLs declared in the ArgoCD applicative inventory receive an assessment row (CONFORMING / NON-CONFORMING / N/A / UNKNOWN) — none left unassessed.
- **SC-002**: A single canonical secrets/vault standard is explicitly selected and documented — with at least 3 selection criteria and at least one rejected alternative — before any scoring.
- **SC-003**: After remediation, ≥95% of secrets-bearing repos conform to the selected standard; every remaining repo holds an approved, dated exemption.
- **SC-004**: Zero repos retain a critical anti-pattern (committed credential / long-lived credential material) after remediation.
- **SC-005**: Re-running the audit against unchanged repos reproduces identical verdicts and the same fleet score.
- **SC-006**: 100% of NON-CONFORMING rows carry an actionable `fix:` (Gate Ergonomics): no verdict-only failures exist.

## Assumptions

- **Repo scope** = the repositories referenced by the ArgoCD applicative apps inventory (`infra/argocd-infra/apps/applicative/*.yaml` — currently `aws`, `analyst`, `familytree`, `argo-app-go-server`, `tech-companies`, `pdf-scan`); each entry's `appPath` (e.g. `k8s`) marks its secrets-bearing manifest subtree — Question 1 resolved (Q1: custom — Argo applicative fleet).
- **Canonical best practice** = HashiCorp Vault as the org's single secret store (Q2 resolved: B). Repos reference secrets from Vault on a consistent path convention (`/<env>/<service>/<key>`), use short-lived/dynamic credentials (K8s/VM auth, AppRole) rather than static or long-lived tokens, and never commit secret material. This selection supersedes the ESO-oriented org secrets rule for this audit — recorded as an explicit standard-selection decision per US2 (with criteria + rejected alternatives: ESO+cloud store, static K8s secrets).
- **Delivery model** = point-in-time fleet audit + report (Q3 resolved: C). Continuous gate enforcement is explicitly a gated follow-on (P3 RFC) behind the constitution Pending Decision Log (Ownership), not part of this deliverable; FR-009 is scoped as an RFC item.
- Detection is offline and reads repo manifests/declarations only; no cloud or vault access is required to classify a repo. If a repo's secret management is not expressible from git-tracked manifests (out-of-band provisioning the manifests do not name), the repo is classified `UNKNOWN` (manual review) — never silently assumed conforming.
- Repos that use no secrets or vault are `N/A`, not failures.
- A repo whose local checkout is absent/unreachable during the audit (inventory references a path with no local repo) is reported `UNKNOWN` with the reason — never silently dropped from the fleet count and never mis-scored CONFORMING.
- Existing repo customizations are preserved; the audit never modifies audited repos.