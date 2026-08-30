# Research: Repo Standards Alignment (Phase 0)

Resolves all design unknowns for the P1 compliance gate and template provenance.
Scope: bash runner + GitHub workflow + init.sh stamping. Outputs feed data-model.md
and the plan.

## Decision 1: Check Adaptation by Repo Profile

**Decision**: The audit is adapted by an explicit repo profile declared by the
caller — `app-k8s`, `app`, or `library`. Checks whose inputs are not applicable emit
`N/A`, never a failure. The workflow input `repo-profile` is mandatory; local runner
accepts `--repo-profile`.

**Rationale**: The spec constraint requires the gate to work on heterogeneous
(non-scaffolded) repos. A uniform required-files check would false-fail a library
repo lacking a Dockerfile, or an app repo without `k8s/` manifests. The profile is
explicit (never auto-detected) so behavior is deterministic and the caller is
accountable for its own declaration. Matches clarify session Q1 (Option C).

**Alternatives considered**:
- Hard-fail on any missing input — rejected: false failures block legitimate repos.
- Unconditional N/A skipping — rejected: gives no per-repo baseline to enforce.
- Auto-detect profile from file presence — rejected: non-deterministic, surprises callers.

## Decision 2: Offline Secret Scan via Pinned Grep Ruleset

**Decision**: Secrets check is a deterministic offline scan over **git-tracked
files only**, using a pinned, reviewable grep ruleset (key names + pattern shapes:
`AKIA[0-9A-Z]{16}`, `-----BEGIN (RSA|EC|OPENSSH) PRIVATE KEY-----`, generic
`(password|token|secret|api_key|access_key)\s*=\s*["'][^"']{8,}` and similar) with
support for an allow-list/exemptions file.

**Rationale**: GitOps repos commit config by design; the failure mode a merge gate
must catch is a credential committed to history or HEAD. Git-tracked-only (clarify
Q3, Option A) avoids noise from gitignored generated manifests. Offline/pinned keeps
the check deterministic and dependency-free (no network, no external scanner API),
satisfying the constitution's deterministic-gate requirement.

**Alternatives considered**:
- External secret-scan SAAS or `gitleaks` binary — rejected: adds a network/first-run
  dependency and runtime install; conflicts with offline constraints. (Note: gitleaks
  may be evaluated later as an optional enhanced mode — Out of P1 scope.)
- Scan whole working tree — rejected (clarify Q3): noise from gitignored output.

## Decision 3: Manifest Policy — `.env` Best-Effort with Internal-Consistency Fallback

**Decision**: For `app-k8s`, when `.env` is present the manifest-policy check uses it
as the authoritative source for port, PVC, image tag, and cronjob settings (per user
clarification). When `.env` is absent (standard CI checkout), the check falls back to
cross-manifest internal consistency across `deploy.yaml`, `svc.yaml`, `ingress.yaml`
(namespace, image reference, and ports agree; PVC references resolve).

**Rationale**: `.env` drives template generation via `envsubst` in `build.sh`, but is
gitignored and cannot be assumed in a PR checkout. Best-effort keeps the check useful
locally (where `.env` exists) and non-blocking but still meaningful in CI. Determinism
is preserved: behavior depends only on file presence, which is fixed per environment.

**Alternatives considered**:
- Internal consistency only, ignore `.env` — rejected: misses the dominant drift
  source (`.env`-driven port/tag/pvc changes).
- Require committed `.env` / secret-provided `.env` — rejected: contradicts the
  gitignore design; CI-copying local config is a security anti-pattern.

## Decision 4: Single Shared Runner (`standards-audit/runner.sh`)

**Decision**: All check logic lives in a local bash runner (`runner.sh`) that both
the GitHub reusable workflow and developers invoke directly. The workflow runs
exactly one command: `runner.sh --repo-root . --repo-profile <input>`. Output is
machine-parseable: one line per check `[PASS|FAIL|N/A] <check-id> <detail + fix>`,
then an aggregate `AUDIT RESULT: PASS|FAIL (N pass, M fail, K n/a)`; exit code `0`
(PASS) or `1` (FAIL).

**Rationale**: One source of truth closes the "CI passes, local fails" gap, satisfies
Gate Ergonomics (each FAIL line embeds an actionable fix), and keeps the workflow a
thin shell with least privilege. Tests run the same binary bats tests CI and devs use.

**Alternatives considered**:
- Inline check logic in workflow YAML — rejected: untestable, duplicated between
  repo copies, no local path.
- Separate CI vs local implementations — rejected: guaranteed drift between the two.

## Decision 5: Provenance as a Single Canonical Constant

**Decision**: Template version is a single file `init/template-version` (content
`1.0.0`); `init/init.sh` copies it into every scaffolded app as `.template-version`
and `init/gitignore` is updated so the file is committed (not ignored).

**Rationale**: Cheapest durable drift signal, zero new dependency, and it satisfies
Core Principle I-3 (Tracked Re-Sync) without waiting on P3. The value lives in
exactly one place so stamping can never lag the canonical version.

**Alternatives considered**:
- Version in `init/init.sh` as a variable — rejected: two truths (script + stamped
  file), easy to forget on bump.
- Version derived from git tag — rejected: not available in the template repo checkout
  used for scaffolding.

## Decision 6: Opt-In `workflow_call` with Least Privilege

**Decision**: The audit is a reusable workflow (`.github/workflows/standards-audit.yml`)
with `workflow_call` inputs (`repo-profile`, optional extra paths). It declares
`permissions: contents: read` (cite via `permissions` block), uses SHA-pinned actions,
and requires no secrets. Adoption is opt-in per repo via a caller workflow; org-level
enforcement is deferred to P2 (clarify Q2, Option A).

**Rationale**: `workflow_call` is the github-actions-skill-recommended composition
primitive; least-privilege `permissions` and SHA pins follow the security-control
pattern; opt-in rollout respects the Pending Decision Log's unresolved Infra
decision and keeps P1 unblocked.

**Alternatives considered**:
- Org-level required workflow now — rejected (clarify Q2): depends on unresolved
  Infra/Ownership decisions.
- Composite action instead of reusable workflow — rejected: reusable workflows are
  the org-level composition primitive and match the tag-pinned `@vX.Y.Z` model P2.

## Decision 7: Fixtures + Bats as the Verification Strategy

**Decision**: `standard-audit/fixtures/` provides conformant and non-conformant
fixture apps (`app-k8s`, `app`, `library` shapes); `standard-audit/tests/*.bats`
assert PASS/FAIL/N/A + remediation text for every check, with no cluster, Docker,
or network dependency.

**Rationale**: The runner is the only testable artifact (workflow shells it), so
bats-covering the runner yields full behavioral coverage. Fixtures mirror real
scaffolded layouts and CI-clone layouts (no `.env`) to verify both `.env`-present
and fallback paths. Matches FR5 and prompt-verified acceptance.

**Alternatives considered**:
- Live CI dry-run as the acceptance gate — rejected: environment-dependent; used only
  as an optional post-implementation smoke test per the spec.