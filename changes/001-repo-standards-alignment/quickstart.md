# Quickstart: Repo Standards Alignment (P1)

Validation guide for the P1 compliance gate. Run these to verify the feature
works end-to-end. References [cli contract](contracts/cli.md),
[workflow contract](contracts/workflow.md), [data model](data-model.md) instead
of duplicating them.

## Prerequisites

- macOS or Linux; `bash`, `grep`/`awk`, `git`, `.env` tooling not required.
- `bats` for the test suites; `shellcheck` for lint.
- No cluster, Docker, or network required for the audit/runner scenarios.

## Setup

```bash
bash .specify/scripts/bash/check-prerequisites.sh   # optional env sanity
git clone <this-repo> && cd gitops-template
```

## Scenarios

### 1. Scaffold stamping

```bash
./init.sh --app-name sample-app --dockerfile none
cat sample-app/.template-version   # expect: 1.0.0
```

**Expected**: `.template-version` exists in `sample-app/`, content `1.0.0`,
and is not ignored (i.e., appears in `git add` dry-run).

### 2. Audit a conformant `app-k8s` repo

```bash
standards-audit/runner.sh --repo-root standards-audit/fixtures/conformant-app-k8s --repo-profile app-k8s
echo $?   # expect 0
```

**Expected**: `[PASS]` for `structure-files`, `secrets-scan`, `policy-manifests`;
`AUDIT RESULT: PASS`.

### 3. Audit a non-conformant repo (failure + remediation)

```bash
standards-audit/runner.sh --repo-root standards-audit/fixtures/non-conformant-app-k8s --repo-profile app-k8s
echo $?   # expect 1
```

**Expected**: at least one `[FAIL]` line whose text ends with `fix: <actionable
remediation>` naming the violating file; aggregate `AUDIT RESULT: FAIL`.

### 4. Profile-driven N/A behavior

```bash
standards-audit/runner.sh --repo-root standards-audit/fixtures/app-only --repo-profile app
echo $?   # expect 0
```

**Expected**: `policy-manifests` reports `[N/A]` (no k8s manifests for `app`
profile); `N/A` never fails the run.

### 5. `.env` fallback path (CI-clone layout)

Remove/omit `.env` in a fixture and run scenario 2 again.

**Expected**: policy check still runs cross-manifest internal consistency; result
is deterministic and does not depend on `.env`.

### 6. Workflow wiring (optional live smoke test)

Publish (or fork) this repo with the audit workflow, then in a test repo:

```yaml
jobs:
  standards:
    uses: <org>/gitops-template/.github/workflows/standards-audit.yml@<tag-or-SHA>
    with: { repo-profile: app-k8s }
    permissions: { contents: read }
```

**Expected**: a passing/failing check surviving on the job log in the documented
`[PASS|FAIL|N/A]` per-line format.

## Test Suites

```bash
bats cicd-tests/                 # regression — all pre-existing suites green
bats standards-audit/tests/      # new audit coverage (pass/fail/n-a + fixtures)
shellcheck standards-audit/runner.sh build.sh init/init.sh
```

**Expected**: no new failures or warnings (documented pre-existing ShellCheck
warnings only).

## Exit Criteria

- Scenarios 1–5 pass on both macOS (BSD grep) and Linux (GNU grep).
- Every `FAIL` line embeds `fix:` (Gate Ergonomics gate).
- No unpinned (`@main`) refs anywhere in the added workflow files.