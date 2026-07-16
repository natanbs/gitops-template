# Feature Specification: init.sh Default App Name from Folder

**Feature Branch**: `011-init-default-appname`

**Created**: 2026-07-16

**Status**: Draft

**Input**: User description: "init.sh instead of using --app-name tech-companies, set the default app name to the folder name `basename "$PWD"`"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Run init.sh Without --app-name (Priority: P1)

A user navigates to a directory (e.g., `my-api/`) and runs `../gitops-template/init.sh` without providing `--app-name`. The script automatically uses the current folder name (`my-api`) as the application name and scaffolds into the correct location.

**Why this priority**: This is the core feature — eliminating the need to manually specify `--app-name` when the folder name already communicates the intent.

**Independent Test**: Run `init.sh` from within a named directory without `--app-name` and verify the scaffold uses the folder name as the app name.

**Acceptance Scenarios**:

1. **Given** a user is in directory `/projects/my-api/`, **When** they run `../gitops-template/init.sh`, **Then** the app name defaults to `my-api` and scaffolding proceeds using that name.
2. **Given** a user is in directory `/projects/tech-companies/`, **When** they run `../gitops-template/init.sh`, **Then** the app name defaults to `tech-companies`.
3. **Given** a user is in directory `/projects/my-service/`, **When** they run `../gitops-template/init.sh --dockerfile go`, **Then** the app name defaults to `my-service` and a Go Dockerfile is scaffolded.

---

### User Story 2 - Override Default App Name with --app-name (Priority: P1)

A user runs `init.sh` from any directory but explicitly provides `--app-name custom-name`. The explicit value takes precedence over the folder name default.

**Why this priority**: Backward compatibility is critical — existing workflows using `--app-name` must continue to work identically.

**Independent Test**: Run `init.sh` with `--app-name` explicitly set and verify the provided name overrides the folder name.

**Acceptance Scenarios**:

1. **Given** a user is in directory `/projects/my-api/`, **When** they run `../gitops-template/init.sh --app-name other-app`, **Then** the app name is `other-app`, not `my-api`.
2. **Given** a user is in any directory, **When** they run `init.sh --app-name tech-companies`, **Then** the behavior is identical to the current implementation — full backward compatibility.

---

### User Story 3 - Help Text Reflects New Default (Priority: P2)

A user runs `init.sh --help` and sees documentation that explains `--app-name` is now optional with a default derived from the current folder name.

**Why this priority**: Users need to discover the new default behavior through documentation.

**Independent Test**: Run `init.sh --help` and verify the help text mentions the folder-name default.

**Acceptance Scenarios**:

1. **Given** a user runs `init.sh --help`, **When** the help output is displayed, **Then** the `--app-name` description indicates it defaults to the current folder name if omitted.
2. **Given** a user reads the examples section, **When** they see usage examples, **Then** there is at least one example showing usage without `--app-name`.

---

### User Story 4 - Target Directory Computed Correctly (Priority: P1)

When using the folder-name default, the scaffold creates files in the correct target directory — the current working directory, not a subdirectory.

**Why this priority**: The current `TARGET_DIR` computation (`dirname "$PWD"/$APP_NAME`) assumes the user runs the script from a parent directory. With the folder-name default, the target should be the current directory itself.

**Independent Test**: Run `init.sh` without `--app-name` from within a named directory and verify files are created in the current directory, not in a new subdirectory.

**Acceptance Scenarios**:

1. **Given** a user is in directory `/projects/my-api/`, **When** they run `../gitops-template/init.sh`, **Then** `.env`, `k8s/`, and other scaffolded files appear in `/projects/my-api/` (the current directory).
2. **Given** a user is in directory `/projects/my-api/`, **When** they run `../gitops-template/init.sh --app-name other-app`, **Then** scaffolding targets a sibling directory `/projects/other-app/` (preserving existing behavior).

---

### Edge Cases

- What happens when the current folder name contains characters invalid for a Kubernetes-safe app name (e.g., uppercase, underscores, dots)? → **Aborted with error; user must rename folder or provide `--app-name`.**
- What happens when the user runs `init.sh` from the repository root (`gitops-template/`)? → **Rejected by blocklist; `gitops-template` is a known repo-level name.**
- What happens when the current directory is a temporary or non-descriptive name (e.g., `/tmp/xyz/`)? → **Allowed if K8s-valid; user judgment is the guardrail.**
- What happens when `--app-name` is provided as an empty string (`--app-name ""`)? → **Treated as not-provided; folder name default is used.**

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: When `--app-name` is not provided (or provided as an empty string), the system MUST derive the app name from the current working directory name using `basename "$PWD"`.
- **FR-002**: When `--app-name` is explicitly provided, the system MUST use the provided value, overriding the folder-name default.
- **FR-003**: When the folder-name default is active (no `--app-name`), the target directory MUST be the current working directory itself (`$PWD`), not a sibling directory.
- **FR-004**: When `--app-name` is explicitly provided, the target directory MUST remain a sibling of the current directory (existing behavior: `$(dirname "$PWD")/$APP_NAME`).
- **FR-005**: The help text MUST indicate that `--app-name` is optional and defaults to the current folder name.
- **FR-006**: The system MUST validate the derived app name meets Kubernetes naming conventions (lowercase, hyphens, no special characters) and abort with an error message if it does not.
- **FR-007**: The system MUST maintain a blocklist of known repository-level names (e.g., `gitops-template`) and reject them as app names with an error message when derived from the folder name.

### Key Entities

- **App Name**: The identifier for the scaffolded application. Used for directory naming, `.env` configuration, Kubernetes resources, and container registry references.
- **Target Directory**: The filesystem location where scaffolded files are created. Computed differently depending on whether `--app-name` was explicitly provided or defaulted from the folder name.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Users can scaffold an application by running `init.sh` from within a named directory without any required arguments (beyond what's already optional).
- **SC-002**: Existing workflows using `--app-name` produce identical results before and after this change (zero regressions).
- **SC-003**: The help text clearly communicates the new default behavior within 5 seconds of reading.

## Assumptions

- The user is running `init.sh` from within a directory that has a meaningful name intended to be the app name.
- If the folder name contains invalid characters for a Kubernetes-safe name, the script MUST abort with an error — the user must rename the folder or provide `--app-name` explicitly.
- The `TARGET_DIR` behavior change (defaulting to `$PWD` vs. `$(dirname "$PWD")/$APP_NAME`) only applies when `--app-name` is not provided.
- The existing behavior when `--app-name` is explicitly provided remains completely unchanged.
- The script is typically invoked from a directory that is one level below the intended scaffold location (for explicit `--app-name` usage) or from the intended scaffold directory itself (for the new default behavior).

## Clarifications

### Session 2026-07-16

- Q: When folder name produces an invalid K8s app name, warn and proceed or warn and abort? → A: Warn and abort — scaffold stops, user must rename folder or provide `--app-name`.
- Q: How should `--app-name ""` (empty string) be handled? → A: Treat as not-provided — use folder name default.
- Q: When run from repo root, should there be a blocklist safeguard for known repo-level names? → A: Yes — maintain a blocklist (e.g., `gitops-template`) and reject with error.
