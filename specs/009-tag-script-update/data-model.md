# Data Model: Tag Script Update

## Overview

This feature involves a shell script with no persistent data model. The data model below documents the runtime entities and their relationships.

## Entities

### CURRENT_TAG

**Purpose**: Environment variable tracking the most recently released version

**Location**: `.env` file in repository root

**Format**: `CURRENT_TAG=<version_string>`

**Example**: `CURRENT_TAG=v2.0.0`

**Lifecycle**:
- Created: When `.env` file is first created with CURRENT_TAG entry
- Updated: When tag.sh runs successfully
- Read: By other scripts/processes needing current version

**Validation Rules**:
- Must follow semver-like format (e.g., `v1.2.3`)
- No spaces allowed around `=` sign
- Line must start with `CURRENT_TAG=` (no leading whitespace)

---

### Docker Image

**Purpose**: Container image being released

**Identification**: `<image_name>:latest` (source) → `<registry>/<image_name>:<version>` (target)

**Image Name Derivation**: `basename "$PWD"` (current folder name)

**Registry Target Format**: `localhost:50000/<image_name>:<version>`

**Lifecycle**:
- Pre-existing: Image must be built before running tag.sh
- Tagged: Source image tagged with registry URL + version
- Pushed: Image pushed to local registry

**State Transitions**:
```
<image>:latest → (tagging) → localhost:50000/<image>:<version> → (push) → registry
```

---

### Git Tag

**Purpose**: Annotated reference marking a release point

**Format**: Just the version string (e.g., `v2.0.0`)

**Target**: Pushed to `origin` remote

**Lifecycle**:
- Created: When tag.sh runs
- Force-overwritten: If tag already exists

**State Transitions**:
```
(no tag) → git tag -f -a <version> → git push origin -f <version>
```

---

## Relationships

```
┌─────────────────────────────────────────────────────────────┐
│                     tag.sh Execution                        │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌──────────────┐      ┌──────────────┐      ┌──────────┐ │
│  │   .env       │      │ Docker Image │      │ Git Repo │ │
│  │              │      │              │      │          │ │
│  │ CURRENT_TAG  │      │ <image>      │      │ Tag      │ │
│  │     ↓        │      │     ↓        │      │     ↓    │ │
│  │ [UPDATED]    │      │ [PUSHED]     │      │ [CREATED]│ │
│  └──────────────┘      └──────────────┘      └──────────┘ │
│                                                             │
│  Step 1: .env     Step 2: Docker      Step 3: Git          │
└─────────────────────────────────────────────────────────────┘
```

## Validation Rules

### .env Format Validation

- Line must match: `^CURRENT_TAG=.*$`
- No leading whitespace allowed
- Value must not be empty after `=`

### Image Existence Validation

- Check `docker image inspect <image>:latest`
- Fallback: Check `docker image inspect <image>` (no tag)
- Fail with clear error if neither exists

### Git Tag Validation

- Force-overwrite existing tags (idempotent)
- Always use annotated tags (`-a` flag)
- Message format: `Release version <version>`

## Edge Cases

| Scenario | Handling |
|----------|----------|
| `.env` doesn't exist | Skip update, continue |
| `.env` has unusual formatting | sed handles typical KEY=VALUE format |
| Docker image doesn't exist | Fail with clear error message |
| Git tag already exists | Force-overwrite (local + remote) |
| Git remote unreachable | Fail immediately (set -e) |
| Script invoked from wrong path | Fail with clear error message |
