# Data Model: init.sh Default App Name from Folder

## Entity: App Name

The application identifier derived from folder name or explicit CLI argument.

| Attribute | Type | Validation | Source |
|-----------|------|------------|--------|
| value | string | K8s-safe: `^[a-z0-9]([-a-z0-9]*[a-z0-9])?$`, max 253 chars | `basename "$PWD"` or `--app-name` |
| origin | enum | `default` (from folder) or `explicit` (from CLI) | Arg-parsing state |

### Validation Rules

1. **K8s Convention**: Must match `^[a-z0-9]([-a-z0-9]*[a-z0-9])?$`
2. **Length**: Must not exceed 253 characters
3. **Blocklist**: Must not be a known repo-level name (currently: `gitops-template`)

### State Transitions

```
[No --app-name] → derive from PWD → validate → [valid] → use as APP_NAME
                                                → [invalid K8s chars] → abort with error
                                                → [blocklisted] → abort with error

[--app-name provided] → use directly → [valid] → use as APP_NAME
                              → [invalid] → existing error path (unchanged)
```

## Entity: Target Directory

The filesystem path where scaffolded files are created.

| Attribute | Type | Computation |
|-----------|------|-------------|
| path | string | `$PWD` (default) or `$(dirname "$PWD")/$APP_NAME` (explicit) |
| mode | enum | `in-place` (default) or `sibling` (explicit) |

### Rules

- **In-place mode** (`--app-name` not provided): `TARGET_DIR="$PWD"`, `_APP_EXISTS` checks current directory
- **Sibling mode** (`--app-name` provided): `TARGET_DIR="$(dirname "$PWD")/$APP_NAME"`, `_APP_EXISTS` checks sibling directory (existing behavior)
