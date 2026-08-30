# Spec: Repo Standards Alignment

**Status**: Draft
**Date**: 2026-08-30
**Branch**: none (no git.feature hook registered)

## Goal

Make sure every applicative repo stays aligned with the org's shared standards —
directory structure, CI/CD methods, and security implementations — through the
phased hybrid mandated by the Fleet Alignment Constitution (Core Principle I):
**P1** reusable compliance gate, **P2** shared versioned artifacts consumed by
reference, **P3** tracked template re-sync. Phase 1 is the implementable slice of
this change; Phases 2–3 are documented as go-forward scope gated by the
Pending Decision Log.

## Clarifications

### Session 2026-08-30

- Q: For repos not scaffolded by this template, how should the audit treat checks whose inputs don't exist (e.g., no `k8s/` manifests, no Dockerfile)? → A: The calling repo declares a repo profile (`app-k8s` | `app` | `library`) via workflow input; checks adapt per profile, and missing-input checks emit an explicit `N/A` line instead of failing.
- Q: How should the P1 gate be rolled out to app repos — opt-in caller or org-wide enforcement? → A: Opt-in caller now (each repo imports the audit via the standards-audit workflow path), with a documented promotion path to org-level enforcement deferred until the Infra/Ownership Pending Decision Log items are resolved (P2).
- Q: What surface should the P1 secret scan cover — git-tracked files only, or the whole working tree (including gitignored generated `k8s/` manifests)? → A: Git-tracked files only.
- Q: For the `app-k8s` manifest-policy check, what is the authoritative "declared config" given `.env` is gitignored and absent from CI checkouts? → A: Best-effort — when `.env` is available it is authoritative for port/pvc/tag/cronjob settings and manifests must agree with it; when absent, fall back to cross-manifest internal consistency.
- Q: Should `spec.md` add user stories mapped to Success Criteria, or stay FR-based? → A: Add a User Stories section with story→SC mapping (CHK004).
- Q: Should `spec.md` include a Demo Sentence (single observable outcome) as the acceptance anchor? → A: Add a Demo Sentence (CHK006).

## Success Criteria

Checkable, derived from the goal:

- [ ] A reusable standards-audit workflow `.github/workflows/standards-audit.yml`
      (triggered by `workflow_call`) exists and runs structure/required-file checks,
      offline secret scanning, and generated-manifest policy checks, failing the
      job on any violation.
- [ ] A caller example `examples/standards-audit-caller.yml` imports the audit by
      org-level path; a conformant fixture app passes the audit when exercised.
- [ ] `init.sh` stamps every scaffolded app with `.template-version` from the
      canonical `init/template-version` constant, and a bats test asserts the
      file is created with expected content.
- [ ] Every new check ships as a local, offline runner script (`runner.sh`)
      covered by bats tests — no network access or live cluster required.
- [ ] No new external runtime dependency beyond already-used tooling; Copier/Cruft
      is only referenced as a deferred P3 decision gated by the constitution's
      Pending Decision Log.
- [ ] Existing behavior is additive: the curl-based `build.sh` flow and all
      existing `cicd-tests/*.bats` continue to pass.
- [ ] Constitution alignment: P1 (gate-first) lands before any P2/P3 artifact
      work; no @main-style unpinned refs are introduced.

## Constraints

- **Additive only**: existing scaffolded apps and the curl-based `build.sh`
  workflow keep working unchanged. No re-scaffold requirement.
- **Project conventions**: Bash `set -euo pipefail`, BSD/GNU sed/awk portability,
  bats + ShellCheck verification, workflows pinned by tag/SHA.
- **Security baseline (Constitution II. Operational Guardrails)**: workflows never
  store long-lived cloud credentials; OIDC/workload-identity only (github-actions
  skill). Secret scanning must be deterministic and offline.
- **Constitution Pending Decision Log**: Infra, Tooling (copier), Ownership, Scope,
  and Migration parameters remain blocked — P2/P3 must not lock in assumptions that
  contradict these open decisions.
- **Gate Ergonomics (Constitution II)**: every blocking check MUST produce an
  actionable, deterministic remediation path; a fail without a remedy is a defect.
- **Heterogeneous fleet**: the gate must work on repos not scaffolded by this
  template.
- Touch only files in this change's delta; preserve generated-K8s-manifest
  customizations.

## Functional Requirements

- **FR1**: A reusable GitHub workflow performs the standards audit and fails the
  run on any violation (`workflow_call` entry point). Adoption is opt-in: each
  repo imports the audit via its own caller workflow; org-level enforcement
  (required org workflow / branch-protection check) is deferred to P2 and does
  not block P1 delivery.
- **FR2**: Audit checks at minimum, adapted by the declared repo profile
  (`app-k8s` | `app` | `library`):
  - *Structure*: required files present and well-formed per profile — Dockerfile
    for `app`/`app-k8s`; `.env` format parseable (`name=value`) when present;
    `k8s/*.yaml` parse as YAML for `app-k8s`.
  - *Secrets*: deterministic offline scan of git-tracked files only for
    credential patterns (pinned ruleset). Documented exemptions via a
    reviewer-owned allowlist file passed with `--allowlist <FILE>`: one pattern
    per line, `#` for comments (an inline trailing comment is accepted as a
    justification), patterns match file paths or line substrings as defined in
    `contracts/cli.md`.
  - *Manifest policy* (`app-k8s`): owns *value-level* agreement (port, PVC,
    image tag, cronjob settings) — best-effort: when `.env` is available it is
    the authoritative source and the generated manifests must agree with it;
    when `.env` is absent (CI checkout), fall back to cross-manifest internal
    consistency (namespace, image reference, ports agree across
    `deploy.yaml`/`svc.yaml`/`ingress.yaml`). Non-overlapping with Structure
    (format vs value-level agreement).
  - A check with no applicable inputs for the declared profile is reported as
    `N/A`, never as a fail.
- **FR3**: Checks produce a machine-parseable one-line-per-check pass/fail/N/A
  summary plus aggregate result; usable as a required PR check and a scheduled
  conformance sweep.
- **FR4**: `init/init.sh` writes `.template-version` into the scaffolded app from
  the canonical `init/template-version` constant; idempotent; safe to commit.
- **FR5**: Every check covered by bats tests over fixture apps (conformant +
  non-conformant; at least one `app`-profile fixture with no `k8s/` manifests)
  with no cluster/Docker/network dependency.
- **FR6 (Gate Ergonomics)**: runner output identifies the violating file and an
  actionable fix for each failing check.

## User Stories

Story → SC mapping (SC = success-criterion checkbox number above):

- **US1** As a platform engineer running the gate locally, I get the same deterministic
  PASS/FAIL/N/A output with remediation as CI, so I can fix issues before pushing.
  → SC4, SC7 (offline runner, deterministic gate).
- **US2** As a repo owner onboarding my app, I add a caller workflow declaring my repo
  profile and get a merge-blocking PR check without re-scaffolding. → SC1, SC2.
- **US3** As a general/app developer, every failing check names the file and the exact
  fix, so a failure is actionable with zero extra tooling. → SC1, SC4, SC6 (Gate
  Ergonomics, offline, additive).
- **US4** As an onboarding administrator, `init.sh` stamps `.template-version`, so any
  scaffolded app can later prove which template version it was built from. → SC3, SC7.
- **US5** As a platform lead, the rollout preserves existing build/CI behavior, so
  adopting the gate does not disturb running repos. → SC6, SC7.

## Demo Sentence

Running `standards-audit/runner.sh --repo-root <conformant fixture> --repo-profile app-k8s`
prints `AUDIT RESULT: PASS` and exits `0`; the same command against the non-conformant
fixture prints failing lines each carrying a `fix:` remediation, ends `AUDIT RESULT:
FAIL`, and exits `1`.

## Delta

**ADDED**:
- `.github/workflows/standards-audit.yml` — reusable `workflow_call` audit.
- `examples/standards-audit-caller.yml` — documented caller for an app repo.
- `examples/standards-audit-sweep.yml` — documented scheduled conformance
  sweep caller (cron `0 2 * * 1`, FR3).
- `standards-audit/runner.sh` — local, offline audit runner (single source of
  check logic shared by CI and local runs).
- `standards-audit/checks/` — structure, secrets, manifest-policy scripts.
- `standards-audit/allowlist.example` — documented secrets exemptions template
  (FR2).
- `standards-audit/tests/*.bats` and `standards-audit/fixtures/` (conformant +
  non-conformant fixture apps).
- `init/template-version` — canonical template version constant.

**MODIFIED**:
- `init/init.sh` — stamp `.template-version` into scaffolded apps.
- `init/gitignore` — verified no `.template-version` rule is present, so the
  stamp is committed, not ignored (no change was required).
- `cicd-tests/init_env.bats` — template-version stamping test.
- `README.md` — "Standards Alignment" section documenting the gate, the opt-in
  caller example, the org-level promotion path, and the constitution-mandated
  phased roadmap.

**REMOVED**: none.

## Risk Register

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Governance: constitution Pending Decision Log items constrain P2/P3 scope | H | M | Spec scopes P2/P3 as RFCs only; flag items owning the gates |
| Audit gates get fatigued / bypassed | M | H | Deterministic one-line outputs + actionable remediation per Gate Ergonomics |
| Copier/Cruft dependency creep if P3 rushed | M | M | Explicitly deferred behind Tooling decision; RFC required |
| Secret-scan false positives block PRs | M | M | Pinned reviewable ruleset; fixtures in-repo; exemption file documented |
| Breaking shared-workflow change hits many repos | M | H | Tag-pinned versions + canary (Constitution II blast-radius isolation) |
| Discovery context unavailable (team-ai-directives KB missing) | H | L | Proceed on repo-internal conventions; revisit via team.discover when KB restored |

## Status

Draft → Active → Implemented → Verified → Complete