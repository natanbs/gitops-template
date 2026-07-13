# Implementation Plan: YAML Tag Update

**Branch**: `010-yaml-tag-update` | **Date**: 2026-07-13 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/010-yaml-tag-update/spec.md`

## Summary

Extend the existing `tag.sh` script to also update `k8s/deploy.yaml` and `k8s/cronjob.yaml` files with the new image tag. The script will match lines containing `image:` and replace the tag after the last `:` with the new version. YAML updates occur after `.env` update but before Docker push and git tag operations.

## Technical Context

**Language/Version**: POSIX Shell (sh) - compatible with bash and dash

**Primary Dependencies**: sed (GNU and BSD compatible)

**Storage**: N/A (filesystem operations only)

**Testing**: Manual testing + shellcheck for linting

**Target Platform**: macOS and Linux (cross-platform compatible)

**Project Type**: CLI script/tool

**Performance Goals**: YAML updates complete in under 5 seconds

**Constraints**: Must work with both GNU sed (Linux) and BSD sed (macOS)

**Scale/Scope**: Single script modification, ~20-30 lines added

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

The constitution file contains only template placeholders - no active governance rules defined. No gates to evaluate.

**Status**: PASS (no constitution rules to violate)

## Project Structure

### Documentation (this feature)

```text
specs/010-yaml-tag-update/
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
k8s/                      # Kubernetes manifests directory (in app folders)
├── deploy.yaml           # Deployment manifest (to be updated)
└── cronjob.yaml          # CronJob manifest (to be updated)
```

**Structure Decision**: Single script modification. No new files needed beyond documentation. The existing `tag.sh` at repository root will be updated to scan `k8s/` subdirectory for YAML files and update image tags.

## Complexity Tracking

> No constitution violations - no complexity tracking required.
