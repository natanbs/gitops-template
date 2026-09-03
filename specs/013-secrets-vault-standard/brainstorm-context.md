# Brainstorm Context: Multi-Repo Standards Alignment

## Problem Statement

The org maintains several application repositories, all initially scaffolded from
shared templates (gitops-template, dbt-template, etc.). Over time each app evolves
independently, so structure, CI/CD methods, and — most critically — security
implementations (secrets handling, cloud auth, manifest config) drift apart.
We need a durable mechanism to keep every repo aligned with one canonical set of
standards, without re-scaffolding or blocking app-team velocity.

## Key Concepts

- **Template/Scaffold**: This repo's `init.sh` produces an app repo from templates. It guarantees *initial* conformance only — nothing keeps the app aligned afterward.
- **Drift**: Divergence between what the standard says and what a repo actually contains. Both intentional (app-specific customization) and accidental (neglect) drift occur.
- **Single Source of Truth**: Each standard (CI pipeline, security config, manifest shape) must live in exactly one canonical, versioned place — either copied-with-tracking or referenced-by-URL.
- **Enforcement vs. Documentation**: Writing standards down in a README is not compliance. Enforcement requires a mechanism (CI gate, policy check) that runs on every change.
- **Consumption Model**: Apps can get standards by *copy* (template files copied into the repo) or by *reference* (reusable workflow / shared chart / base image the repo points at). Copy drifts; reference drifts less but adds hidden dependencies.
- **Versioned Distribution**: Standards changes must ship as semantic versions (v1, v2) so repos upgrade deliberately, not silently.

## Approaches Considered

### Approach A: Project-Template Evolution (Copier/Cruft-style re-sync)
- **How it works**: Add template metadata to scaffolded apps (template name + version + answers). Maintained template project; apps periodically run a 3-way-merge "update" command that re-applies latest template files on top of app customizations.
- **Tradeoffs**: Keeps *file-level* structure identical; preserves local edits via merge; adds a dependency (copier/cruft) and requires devs to actually run updates on a schedule; updates can produce merge conflicts.
- **Risks**: Update fatigue → repos lag weeks; conflicts discourage running updates; merges can clobber app-specific logic if patterned poorly.
- **Best for**: Enforcing directory structure, required config files, base Dockerfiles, template-shaped manifests.

### Approach B: Shared, Versioned Runtime Artifacts (reference, not copy)
- **How it works**: Move the *behavioral* parts of the standard out of app repos into artifacts apps consume by reference: organization-level reusable GitHub workflows (build/test/deploy/scan), shared base images (`FROM` the org base), one shared Helm chart / Crossplane catalog for resources, External Secrets references for secret store sync, OIDC/workload identity instead of key files.
- **Tradeoffs**: Nothing to drift — standards update in one place. But the app's conformance is implicit ("magic"), requires version pinning discipline, and a bad change can hit many repos at once (mitigated by tags + a pilot repo).
- **Risks**: Break-one-breaks-all; shared-artifact maintenance becomes a platform product needing its own testing/cadence; teams may fork to escape upgrades.
- **Best for**: Security posture, auth/credential handling, and the CI/CD method — the highest-blast-radius standards.

### Approach C: Compliance as a Gate (policy/lint layer on every PR)
- **How it works**: A reusable "standards audit" workflow each repo calls: conftest/OPA over generated manifests, required-file and structure checks, dependency/version checks, secrets scanning (pre-commit parser + CI). Results are enforced via branch protection — PRs can't merge red. Optionally a central crawler aggregates a conformance scoreboard across the fleet.
- **Tradeoffs**: Detection happens at change time, not just at scaffold time; cheap to layer on heterogeneous repos. But gates are only as good as the rules they encode, risk alert fatigue, and still need a remediation path (how do I become compliant?). Needs a small, long-lived rule-set owner.
- **Risks**: Rules lag the standard → false confidence; noisy/failing gates get bypassed (team-confidence), which undermines all enforcement.
- **Best for**: Measuring and *guaranteeing* conformance across a heterogeneous fleet that cannot be fully centralized.

### Approach D: Monorepo Consolidation (rejected)
- **How it works**: Move all apps into one repo so one pipeline and one config apply everywhere.
- **Tradeoffs**: Eliminates cross-repo drift by construction but centralizes ownership, breaks independent release cadences, and is a breaking migration with no rollback.
- **Risks**: Organizational resistance; conflicts scale with repo size.
- **Best for**: Nearly nothing for independent application teams; listed only to document the decision.

## Architecture Notes

**Fits the existing system**: This repo is already the composition point for the
stack (scaffold + CI/CD + K8s/ArgoCD manifests + decommission tooling). The
natural evolution is to make it the *distribution point* for standards, not just a
scaffolder:

- `init/init.sh` gains template-version metadata so scaffolded apps can be tracked and updated (Approach A).
- `build.sh`'s logic is promoted into org-level reusable GitHub workflows (Approach B), versioned by tag, following the OIDC/no-long-lived-credentials pattern; secrets become External Secrets references + workload identity.
- The K8s templates graduate into a shared chart/platform catalog so deploy shapes stay identical across repos (Approach B/C integration point with ArgoCD sync).
- A standards-audit workflow wraps the existing bats/shellcheck/conformity checks (Approach C) and becomes a required PR check via branch protection.

**Integration points**: `init.sh` (scaffold/versioning), `build.sh` (pipeline), GitHub Actions (enforcement), ArgoCD (deploy sync), External Secrets (secret store), GKE Workload Identity (keyless auth).

**Data flows**: template (canonical, versioned) → app repo → CI checks → artifacts/manifests → cluster. Standards changes flow one way (platform → apps); drift feedback flows the other (audit report → remediation).

**Relevant skills to load at spec time**: `github-actions` (reusable org workflows), `helm-charts` (shared chart), `crossplane` (platform catalog), `external-secrets` + `gke-workload-identity` (security standards), `dbt-template` (parallel template in the fleet to keep consistent).

## Risk Register

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Break-one-breaks-all via shared workflow/chart | M | H | Version with tags; pilot repo before fleet rollout; conformance tests on the artifact |
| Copy/template updates never applied (drift again) | H | M | Template-version metadata + update command + scoreboard visibility for stale repos |
| Merge conflicts during template re-sync clobber app config | M | H | 3-way merge tools; conservatively nested template dirs; bats regression suite |
| Gate fatigue → teams bypass checks | M | H | Keep rule set small and owned; fast, deterministic checks; clear remediation docs |
| Security misconfig in an already-live repo during migration | M | H | Phased rollout on pilot apps; baseline audit before enabling enforcement |
| Heterogeneous fleet (apps not from this template) | M | M | Approach C governs heterogeneous repos; A+B govern new/standard ones |

## Open Questions

1. How many app repos, and which languages/stacks (only Go/Python/Node, or more)? Dockerfile variety determines how much base-image abstraction is worth doing.
2. Are all repos on GitHub, or multiple providers? Reusable-workflow enforcement depends on the platform.
3. Do standards changes need to propagate automatically, or is a scheduled/on-request update acceptable?
4. How much autonomy do app teams have? Are they willing to accept required CI checks and pinned shared artifacts?
5. Is there a security/compliance officer in the loop today, anyone owns scanning thresholds?
6. Which repos predate the template (and thus can't be re-scaffolded cleanly)?
7. Is adopting copier/cruft (a Python dependency) acceptable vs. staying zero-dependency (pure Bash + GitHub)?

## Recommended Direction

**Phase the work as a hybrid, ascending from detection up to prevention:**

1. **Approach C first (cheap, immediate)**: a reusable standards-audit workflow (structure, required files, secret scanning, manifest/security policy) that every repo calls and that is a required PR check. This stops *new* drift today across the whole fleet.
2. **Approach B second (highest leverage)**: promote `build.sh` + K8s template logic into versioned org-level reusable workflows and a shared chart/platform catalog, with External Secrets + workload identity baked in. This makes the CI/CD method and security posture the same everywhere by construction.
3. **Approach A third (structure longevity)**: add template-version metadata to `init.sh` scaffolds and a tracked-update path so file-level structure can be re-synced over time.

Rationale: starting with gates (C) gives immediate, org-wide leverage with zero migration; B removes the largest drift sources (builds, secrets, deploy shapes); A is the slow, structural tail. Do not lead with A — copy-tracking tools fail when there's no enforcement to force the updates to happen.