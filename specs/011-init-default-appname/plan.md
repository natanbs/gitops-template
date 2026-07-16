# Implementation Plan: init.sh Default App Name from Folder

**Branch**: `011-init-default-appname` | **Date**: 2026-07-16 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/011-init-default-appname/spec.md`

## Summary

Make `--app-name` optional in `init/init.sh`. When omitted (or empty), derive the app name from the current directory via `basename "$PWD"`. Validate against K8s naming conventions (abort on failure) and a blocklist of repo-level names (abort on match). Adjust `TARGET_DIR` logic so the default case scaffolds into `$PWD`. Preserve full backward compatibility when `--app-name` is explicitly provided.

## Technical Context

**Language/Version**: Bash (GNU Bash 4+ / POSIX-compatible)
**Primary Dependencies**: Standard Unix tools — `basename`, `grep`, `sed`, `envsubst`, `mkdir`, `git`, `kubectl`
**Storage**: Filesystem only (`.env` file, scaffolded directories)
**Testing**: Manual shell testing + ShellCheck linting
**Target Platform**: Linux, macOS (any POSIX-compatible shell with Bash)
**Project Type**: CLI tool / scaffolding script
**Performance Goals**: N/A (interactive CLI)
**Constraints**: Must maintain zero regressions for existing `--app-name` workflows
**Scale/Scope**: Single file modification (~20 lines changed), help text update

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

**Constitution status**: Template placeholder only — no principles or rules defined.
**Gate result**: PASS (no rules to violate)

## Project Structure

### Documentation (this feature)

```text
specs/011-init-default-appname/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/           # Phase 1 output
└── tasks.md             # Phase 2 output (/spec.tasks - NOT created by /spec.plan)
```

### Source Code (repository root)

```text
init/
├── init.sh              # Primary file to modify
├── k8s/                 # K8s templates (unchanged)
├── argocd/              # ArgoCD templates (unchanged)
└── [lang-scaffolds]/    # Language scaffolds (unchanged)

init.sh                  # Wrapper (unchanged, delegates to init/init.sh)
```

**Structure Decision**: Single file change. The only source modification is `init/init.sh`. No new files, no structural changes.

## Triage Framework: [SYNC] vs [ASYNC] Classification

**Execution Strategy**: Single-file bash script change — primarily [SYNC] for logic changes, [ASYNC] for tests.

### Preliminary Task Classification

| Task Category | Estimated [SYNC] Tasks | Estimated [ASYNC] Tasks | Rationale |
|---------------|----------------------|----------------------|-----------|
| Business Logic | 1 | 0 | Core arg-parsing and TARGET_DIR logic — requires careful review for backward compatibility |
| Documentation | 1 | 0 | Help text update — must match actual behavior precisely |
| Testing | 0 | 2 | Manual test scenarios — can be scripted and delegated |
| Edge Case Handling | 1 | 0 | K8s validation + blocklist — security-adjacent, needs review |

### Triage Decision Criteria Applied

**High-Risk [SYNC] Classifications:**
- Core TARGET_DIR computation change — incorrect logic breaks all scaffolding
- K8s name validation regex — must be correct and comprehensive

**Agent-Delegated [ASYNC] Classification:**
- Smoke test scripts — verify basic flows work
- Regression test for `--app-name` backward compatibility

### Triage Audit Trail

| Task | Classification | Primary Criteria | Risk Level | Rationale |
|------|----------------|------------------|------------|-----------|
| Modify arg-parsing to make --app-name optional | [SYNC] | Backward compatibility | High | Core logic change — must not break existing callers |
| Add K8s name validation + blocklist | [SYNC] | Correctness | Medium | Validation must be accurate; false positives frustrate users |
| Update TARGET_DIR computation | [SYNC] | Correctness | High | Wrong TARGET_DIR creates files in wrong location |
| Update help text | [SYNC] | Accuracy | Low | Must reflect actual behavior |
| Smoke test: default from folder | [ASYNC] | Testability | Low | Scriptable verification |
| Smoke test: explicit --app-name backward compat | [ASYNC] | Testability | Low | Scriptable verification |

## Complexity Tracking

> No constitution violations — constitution is a placeholder template.
