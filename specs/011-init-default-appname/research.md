# Research: init.sh Default App Name from Folder

## Decision 1: K8s Naming Convention Regex

**Decision**: Use regex `^[a-z0-9]([-a-z0-9]*[a-z0-9])?$` with max length 253 characters.

**Rationale**: This matches the DNS subdomain label format used by Kubernetes for resource names. It enforces:
- Lowercase only
- Starts and ends with alphanumeric
- Hyphens allowed in the middle
- No underscores, dots, uppercase, or special characters

**Alternatives considered**:
- Kubernetes allows labels with `[a-z0-9]([-_.]*[a-z0-9])?` — more permissive. Rejected because underscores and dots cause issues in DNS-based service discovery and some tooling.
- Length-only check (just `<=253 chars`) — rejected because it allows invalid characters that break K8s manifests.

## Decision 2: Blocklist Approach

**Decision**: Maintain an inline array in the script containing known repo-level directory names. Only names that are clearly infrastructure/tooling names are blocklisted.

**Rationale**: The blocklist is small (likely just `gitops-template` and similar tooling names). An inline array is simpler than an external config file and avoids introducing a new file dependency. Users who rename the repo can edit the blocklist directly.

**Alternatives considered**:
- External `.blocklist` file — rejected for over-engineering; adds a file dependency for a 1-2 entry list.
- No blocklist, rely on user judgment — rejected per spec clarification: user explicitly requested a safeguard.
- Hardcoded exclusion of parent directory name — too fragile; doesn't generalize.

## Decision 3: TARGET_DIR Computation

**Decision**: Branch on whether `--app-name` was explicitly provided:
- Not provided → `TARGET_DIR="$PWD"` (current directory)
- Provided → `TARGET_DIR="$(dirname "$PWD")/$APP_NAME"` (existing behavior)

Track via a boolean flag (e.g., `_APP_NAME_EXPLICIT=true/false`) set during arg-parsing.

**Rationale**: The key insight is that when the user runs from within the target directory (the new default flow), the scaffold should land in `$PWD`. When they provide `--app-name` explicitly, they're likely in a parent directory and expect the existing sibling-directory behavior. The flag cleanly separates these two code paths.

**Alternatives considered**:
- Always use `$PWD` — rejected because it breaks existing `--app-name` workflows where the user is in the parent directory.
- Always use `$(dirname "$PWD")/$APP_NAME` — rejected because it creates a subdirectory instead of scaffolding in place.
- Detect by checking if `$PWD/` matches `$APP_NAME` — too fragile; directory might not exist yet.

## Decision 4: Empty String Handling

**Decision**: Normalize `--app-name ""` to empty string, then treat empty string same as not-provided. The branch condition becomes: if `CLI_APP_NAME` is non-empty after trimming, use it; otherwise, use `basename "$PWD"`.

**Rationale**: Bash doesn't naturally distinguish "not provided" from "provided as empty" after the while loop. Both result in `CLI_APP_NAME=""`. Normalizing both to the default path is the simplest correct behavior, matching the spec clarification.

**Alternatives considered**:
- Use a separate `_APP_NAME_PROVIDED` flag — unnecessary complexity; both cases produce the same intent.
- Error on empty string — rejected per spec clarification.
