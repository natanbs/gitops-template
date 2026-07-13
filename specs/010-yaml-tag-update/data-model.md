# Data Model: YAML Tag Update

## Overview

This feature involves a shell script that updates Kubernetes manifest files. The data model documents the runtime entities and their relationships.

## Entities

### deploy.yaml

**Purpose**: Kubernetes Deployment manifest containing container image references

**Location**: `k8s/deploy.yaml` in the app folder

**Format**: Standard Kubernetes YAML manifest

**Key Fields**:
- `spec.template.spec.containers[].image`: Container image with tag

**Lifecycle**:
- Pre-existing: File must exist before running tag.sh
- Updated: Image tags replaced with new version
- State transitions: `image: <registry>/<image>:<old>` → `image: <registry>/<image>:<new>`

---

### cronjob.yaml

**Purpose**: Kubernetes CronJob manifest containing container image references

**Location**: `k8s/cronjob.yaml` in the app folder

**Format**: Standard Kubernetes YAML manifest

**Key Fields**:
- `spec.jobTemplate.spec.template.spec.containers[].image`: Container image with tag

**Lifecycle**:
- Pre-existing: File must exist before running tag.sh
- Updated: Image tags replaced with new version
- State transitions: `image: <registry>/<image>:<old>` → `image: <registry>/<image>:<new>`

---

### Image Tag Field

**Purpose**: Pattern in YAML files identifying container image references

**Pattern**: Lines containing `image:` followed by a registry/image:tag format

**Replacement Logic**: Replace the tag (after the last `:`) with the new version

**Example**:
```
Before: image: localhost:50000/myapp:v1.0.0
After:  image: localhost:50000/myapp:v2.0.0
```

---

## Relationships

```
┌─────────────────────────────────────────────────────────────┐
│                     tag.sh Execution                        │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌──────────────┐      ┌──────────────┐      ┌──────────┐ │
│  │   .env       │      │   k8s/*.yaml │      │ Docker   │ │
│  │              │      │              │      │  Image   │ │
│  │ CURRENT_TAG  │      │ image: lines │      │          │ │
│  │     ↓        │      │     ↓        │      │     ↓    │ │
│  │ [UPDATED]    │      │ [UPDATED]    │      │ [PUSHED] │ │
│  └──────────────┘      └──────────────┘      └──────────┘ │
│                                                             │
│  Step 1: .env     Step 2: YAML      Step 3: Docker         │
│                   Step 4: Git Tag                           │
└─────────────────────────────────────────────────────────────┘
```

## Validation Rules

### YAML File Validation

- File must exist in `k8s/` subdirectory
- File must contain at least one `image:` line
- If no `image:` lines found, halt with error

### Image Tag Pattern Validation

- Line must match: `^.*image:.*$`
- Tag is everything after the last `:` in the image value
- Replacement uses sed global substitution

### Error Handling

| Scenario | Handling |
|----------|----------|
| YAML file doesn't exist | Skip update, continue |
| YAML file exists but no `image:` lines | Halt with error |
| YAML file has malformed syntax | sed handles typical YAML format |
| Multiple `image:` lines | Update all occurrences |

## Edge Cases

| Scenario | Handling |
|----------|----------|
| `k8s/` directory doesn't exist | Skip YAML updates, continue |
| YAML file has comments with `image:` | Only update actual image fields |
| YAML file has nested image references | Update all `image:` lines |
| YAML file is empty | Halt with error (no `image:` lines) |
