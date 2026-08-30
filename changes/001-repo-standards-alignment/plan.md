# Plan: Repo Standards Alignment

**Change**: `001-repo-standards-alignment` | **Date**: 2026-08-30
**Input**: `.specify/drafts/brainstorm-context.md` + spec.md + Fleet Alignment
Constitution (`.specify/memory/constitution.md`, v1.0.0)

## Context

This repo scaffolds apps and drives their CI/CD, so it guarantees *initial*
conformance but nothing keeps repos aligned afterward — structure, CI/CD methods,
and security implementations drift. The brainstorm recommended a phased hybrid;
the Fleet Alignment Constitution now mandates the exact sequence (Core Principle
I): gate compliance first, then shared versioned artifacts, then tracked re-sync.
Phase 1 is the implementable slice; Phases 2–3 are recorded as RFCs gated by the
Pending Decision Log.

## Approach

### Phase 1 — Compliance-as-a-gate (implementable slice)
- One reusable workflow (`.github/workflows/standards-audit.yml`, `workflow_call`)
  that every app repo calls, executing a single local runner
  (`standards-audit/runner.sh`) shared between CI and local — closing the
  "works on my machine" gap.
- Checks are small, deterministic, offline, and reviewable (structure, offline
  secret scan, manifest-policy consistency). Each output is one line per check
  plus an actionable fix, satisfying Gate Ergonomics.
- Conformance fixtures + bats make the audit self-validating; a caller example
  shows org-level import.

### Phase 2 — Shared versioned artifacts (RFC, gated)
- Promote `build.sh` logic into org-level reusable workflows **pinned by tag
  (`@vX.Y.Z`)**, moving K8s templates toward a shared chart/platform catalog;
  bake in External Secrets + workload identity as the default.
- Gated by Pending Decision Log: Infra (provider), Ownership, Scope.

### Phase 3 — Tracked template re-sync (RFC, gated)
- Provenance ships in P1 (`init.sh` stamps `.template-version`).
- Later: tracked update path for file-level structure.
- Gated by Pending Decision Log: Tooling (copier), Migration (brownfield path).

## Key Technical Decisions & Rationale

| Decision | Rationale |
|----------|-----------|
| Single offline runner shared by CI + local | One source of truth; testable via bats; satisfies Gate Ergonomics |
| Checks as separate scripts under `standards-audit/checks/` | Reviewable, individually testable ruleset vs. monolith |
| Provenance = single `init/template-version` constant copied at scaffold | Cheapest durable drift signal; zero new dependency |
| Copier/Cruft deferred to RFC | Imported toolchain needs its own approval (Pending Decision Log: Tooling) |
| No cloud credentials in workflows | github-actions skill; OIDC/workload identity only |
| `workflow_call` + least-privilege `permissions` + pin-by-SHA | Safe-PR posture; pins avoid unpinned-ref prohibition (Constitution I) |
| P2/P3 as RFCs only | Constitution mandates gate-first sequence and decision-gated rollout |

## Files to Modify

- **ADDED**: `.github/workflows/standards-audit.yml`, `examples/standards-audit-caller.yml`
- **ADDED**: `standards-audit/{runner.sh, checks/, tests/, fixtures/}`
- **ADDED**: `init/template-version`
- **MODIFIED**: `init/init.sh`, `init/gitignore`, `cicd-tests/init_env.bats`, `README.md`

## Migration & Rollback

- **Migration**: additive only; app repos opt in by adding the caller workflow.
  Nothing breaks if they don't.
- **Rollback**: revert added files; stop stamping `.template-version` (or ignore
  it). No merge-time enforcement is wired during this change, so rollback is
  trivial.
- **Phases 2–3**: separate RFCs; P1 ships independently and satisfies the
  constitution's gate-first ordering.

## Verification

- `bats cicd-tests/` — all suites pass (no new failures).
- `bats standards-audit/tests/` — checks pass on the conformant fixture, fail on
  the non-conformant one, and each failure names the file and fix.
- `shellcheck standards-audit/runner.sh build.sh init/init.sh` — no new warnings.
- If a GitHub runner is reachable, dry-run the caller workflow on the conformant
  fixture; otherwise document the manual invocation (`runner.sh <repo-root>`).