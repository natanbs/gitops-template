# Implementation Plan: Fix ArgoCD Gitignore Conflict

**Branch**: `006-fix-argocd-gitignore` | **Date**: 2026-07-10 | **Spec**: specs/006-fix-argocd-gitignore/spec.md

**Input**: Feature specification from specs/006-fix-argocd-gitignore/spec.md

## Summary

Remove `k8s/*.yaml` and `argocd/*.yaml` from `init/gitignore` so that rendered ArgoCD manifests are committed to scaffolded apps' git repos. The ArgoCD Application template references `path: k8s`, but the gitignore prevents those files from being tracked, causing "app path does not exist" errors.

## Technical Context

**Language/Version**: Bash (POSIX-compatible, as used in `init.sh`)

**Primary Dependencies**: None beyond standard Unix utilities (grep, sed, envsubst) and git

**Storage**: N/A — modifying a gitignore template file

**Testing**: Manual verification via `init.sh --app-name test-app` + `git status` in output directory

**Target Platform**: Any platform running git + bash

**Project Type**: Build/Scaffolding scripts (bash + YAML templates)

**Performance Goals**: N/A — template file modification, no runtime impact

**Constraints**:
- Must not break existing `init.sh` or `build.sh` functionality
- Must not affect apps scaffolded before the fix (out of scope)
- The fix is a template-only change — individual apps get it automatically on next scaffold

**Scale/Scope**: Single file modification (`init/gitignore`) — remove 2 lines

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

No constitution file found at `.specify/memory/constitution.md`. **PASS** — no binding rules to violate.

## Project Structure

### Documentation (this feature)

```
specs/006-fix-argocd-gitignore/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/           # Phase 1 output
└── tasks.md             # Phase 2 output
```

### Source Code (repository root)

```
init/
├── init.sh                    # Unchanged (already renders k8s/argocd correctly)
├── gitignore                   # MODIFIED: remove k8s/*.yaml and argocd/*.yaml rules
├── k8s/
│   ├── deploy.tmpl.yaml       # Unchanged
│   ├── svc.tmpl.yaml          # Unchanged
│   ├── ingress.tmpl.yaml      # Unchanged
│   └── pvc.tmpl.yaml          # Unchanged
└── argocd/
    └── application.tmpl.yaml  # Unchanged
```

**Structure Decision**: Single file change to `init/gitignore`. No new files, no script logic changes. The init.sh already renders k8s/argocd manifests and commits them — the gitignore was the only blocker.

## Complexity Tracking

No constitution violations — Complexity Tracking section not required.

## Phase 0: Outline & Research

No NEEDS CLARIFICATION remain from Technical Context — all items are known:
- Language: Bash (existing project standard)
- Dependencies: None new
- File to modify: `init/gitignore` (known location)
- Testing: Manual git status verification
- Platform: Any (git + bash)

No research tasks needed. The fix is a deterministic 2-line deletion from a known file.

Proceeding to Phase 1.

## Phase 1: Design & Contracts

### Data Model

Not applicable — no data entities involved. This is a template file modification.

### Interface Contracts

Not applicable — no external interfaces exposed. The "contract" is the gitignore template's behavior: files not listed as ignored = tracked by git.

### Agent Context Update

Agent-context extension not installed. Skipping.

## Phase 2: Implementation Tasks

### Task Classification

| Task Category | [SYNC] Tasks | [ASYNC] Tasks | Rationale |
|---------------|-------------|--------------|-----------|
| File Modification | 0 | 1 | Simple line deletion, deterministic |
| Verification | 1 | 0 | Requires manual git status inspection |

#### [ASYNC] T-001: Remove gitignore rules from init/gitignore

- **File**: `init/gitignore`
- **Description**: Delete the lines `k8s/*.yaml` and `argocd/*.yaml` from the gitignore template. Keep all other rules intact.
- **Rationale**: Trivial, well-defined edit. The lines to remove are unambiguous. No logic changes.
- **Acceptance**: `init/gitignore` no longer contains `k8s/*.yaml` or `argocd/*.yaml`. All other rules preserved.

#### [SYNC] T-002: Verify fix with init.sh end-to-end

- **Description**: Run `init.sh --app-name argocd-test` from a sibling directory. Verify `k8s/deploy.yaml`, `k8s/svc.yaml`, and `argocd/application.yaml` exist in the output. Run `git status` from the output directory and confirm these files appear as tracked (not untracked/ignored). Run `git log --oneline` to confirm they were included in the initial commit.
- **Rationale**: Full integration verification. Requires developer to inspect output and confirm git behavior.
- **Acceptance**: All three files are git-tracked after scaffolding. `git status` shows no untracked k8s/argocd YAML files.
