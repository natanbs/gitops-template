# Implementation Plan: Tag Script Update

**Branch**: `009-tag-script-update` | **Date**: 2026-07-13 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/009-tag-script-update/spec.md`

## Summary

Update the existing `tag.sh` script to support being invoked from app folders using relative paths. The script derives the Docker image name from the current folder name via `basename "$PWD"`, then executes three sequential operations: update `.env` CURRENT_TAG, push Docker image to local registry, and create/push git tag.

## Technical Context

**Language/Version**: POSIX Shell (sh) - compatible with bash and dash

**Primary Dependencies**: Docker CLI, Git, sed (GNU and BSD compatible)

**Storage**: N/A (filesystem operations only)

**Testing**: Manual testing + shellcheck for linting

**Target Platform**: macOS and Linux (cross-platform compatible)

**Project Type**: CLI script/tool

**Performance Goals**: Complete in under 60 seconds for images under 200MB

**Constraints**: Must work with both GNU sed (Linux) and BSD sed (macOS)

**Scale/Scope**: Single script file, ~100-150 lines

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

The constitution file contains only template placeholders - no active governance rules defined. No gates to evaluate.

**Status**: PASS (no constitution rules to violate)

## Project Structure

### Documentation (this feature)

```text
specs/009-tag-script-update/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
└── tasks.md             # Phase 2 output (NOT created by /spec.plan)
```

### Source Code (repository root)

```text
# Existing script location
tag.sh                    # Main script (to be modified)
.env                      # Environment file (exists, will be updated at runtime)
```

**Structure Decision**: Single script modification. No new files needed beyond documentation. The existing `tag.sh` at repository root will be updated to support relative path invocation and folder-based image name derivation.

## Complexity Tracking

> No constitution violations - no complexity tracking required.
