# Research: Tag Script Update

## Decision Log

### R1: Image Name Derivation

**Decision**: Derive image name from current folder name using `basename "$PWD"`

**Rationale**: 
- Simplifies invocation (single argument instead of two)
- Natural mapping: folder name = service name
- Consistent with common Docker conventions

**Alternatives Considered**:
- Accept image name as argument: More flexible but adds complexity
- Read from config file: Over-engineered for this use case
- Environment variable: Less discoverable

---

### R2: Git Tag Format

**Decision**: Use version string directly (e.g., `v2.0.0`) without prefix

**Rationale**:
- Simplest format
- Most common pattern for release tags
- Version itself is sufficient identifier

**Alternatives Considered**:
- Prefixed `release/v2.0.0`: Adds noise without value
- Image-namespaced `myapp/v2.0.0`: Only useful in monorepo scenarios

---

### R3: Operation Order

**Decision**: 1) Update .env, 2) Push Docker image, 3) Git tag

**Rationale**:
- Matches spec requirement
- .env update is idempotent and safe to do first
- Docker push before git tag ensures image is available before marking release
- Git tag is final because it's the "point of no return" marker

**Alternatives Considered**:
- Current implementation does git tag first: Less safe if image push fails

---

### R4: Cross-Platform sed Compatibility

**Decision**: Use sed with portable syntax, avoid GNU-specific extensions

**Rationale**:
- Must work on both macOS (BSD sed) and Linux (GNU sed)
- `sed "s/^CURRENT_TAG=.*/CURRENT_TAG=${NEW_VERSION}/"` is portable
- Using temp file + mv approach works on both platforms

**Alternatives Considered**:
- Use `sed -i`: Not portable (different syntax between GNU/BSD)
- Use awk: Overkill for simple substitution
- Use envsubst: Requires additional dependency

---

### R5: Script Path Resolution

**Decision**: Use `SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"` to resolve script location

**Rationale**:
- Correctly handles symlinks
- Works when invoked via relative path
- Standard POSIX-compatible approach

**Alternatives Considered**:
- `dirname $0`: Doesn't handle symlinks properly
- Hardcoded paths: Not portable

---

### R6: Registry Authentication

**Decision**: No authentication required (local insecure registry)

**Rationale**:
- Assumed local cluster registry at localhost:50000
- Development environment context
- Simplifies script (no credential management)

**Alternatives Considered**:
- Docker credential store: Adds complexity
- Environment-based auth: Not needed for local dev

---

### R7: Error Handling Strategy

**Decision**: Continue using `set -e` with informative error messages

**Rationale**:
- Existing pattern in current implementation
- Fail-fast behavior prevents partial operations
- Clear error messages help debugging

**Alternatives Considered**:
- Manual error checking: More verbose, error-prone
- Trap-based cleanup: Overkill for this script

---

## Research Summary

All technical decisions have been resolved. The implementation will:
1. Modify existing `tag.sh` to support relative path invocation
2. Change argument from `<image> <tag>` to just `<tag>`
3. Derive image name from `basename "$PWD"`
4. Reorder operations to match spec
5. Add progress messages
6. Maintain cross-platform compatibility
