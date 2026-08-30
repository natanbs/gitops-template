# Contract: Standard Audit Reusable Workflow

`.github/workflows/standards-audit.yml` — the org callable that wraps
`runner.sh` into a merge-time gate. Opt-in per repo (clarify Q2, Option A);
promotion to org-level enforcement is P2 scope.

## Entry Point

```yaml
on:
  workflow_call:
    inputs:
      repo-profile:
        type: string
        required: true
        description: "app-k8s | app | library"
      repo-root:
        type: string
        required: false
        default: "."
        description: "path from workspace root to the audited repo"
      allowlist-path:
        type: string
        required: false
        default: ""
        description: "path relative to repo-root to a secrets exemptions file; wired to runner --allowlist (default: runner discovers <repo-root>/standards-audit/allowlist)"
```

Fired from a caller workflow via:

```yaml
jobs:
  standards:
    uses: <org>/<emit-of-audit-repo>/.github/workflows/standards-audit.yml@<tag-or-SHA>
    with:
      repo-profile: app-k8s
    permissions:
      contents: read
```

## Behavior Contract

- Exactly one job, runs `runner.sh --repo-root <input> --repo-profile <input>`
  (+ `--allowlist <repo-root>/<allowlist-path>` when `allowlist-path` is set) on a
  checkout (whole-repo depth, git-tracked surface).
- `permissions`: minimal — `contents: read`. No secrets, no id-token.
- No third-party action pulls at runtime beyond the pinned reusable workflow
  bootstrap; all pinned by full commit SHA (unpinned `@main` refs prohibited by
  Constitution I-2).
- Fail-fast: job `steps` shelled from runner exit code (`0`/`1`/`2`). A failing
  audit marks the job failed, which a consuming PR branch-protection rule may
  require.
- Outputs: runner stdout surfaces in the job log verbatim (same lines CI and devs
  see locally).

## Caller Example Contract (`examples/standards-audit-caller.yml`)

Documented (not enforced) template an app repo copies:

- Declares `repo-profile` matching the repo shape.
- References the audit repo workflow pinned to a tag (`@v1.x.y`) or commit SHA.
- May add `concurrency` / branch triggers; must not add secrets.
- Must pass `permissions: contents: read` on the calling job as documented.

## Constraints (from spec)

- Opt-in only; no org required-workflow wiring in P1.
- Deterministic output format (see `contracts/cli.md`).
- Gate Ergonomics: FAIL lines carry `fix:` remediation — surfaced as-is to the PR.
- P2 note: promote this file to the org-level workflows repository and tag
  `@vX.Y.Z`; add canary (pilot repo) validation before fleet rollout
  (Constitution II — blast-radius isolation).