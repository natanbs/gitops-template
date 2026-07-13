# Research: YAML Tag Update

## Decision Log

### R1: YAML File Location

**Decision**: Look for `k8s/deploy.yaml` and `k8s/cronjob.yaml` in the app folder

**Rationale**:
- Kubernetes manifests are commonly organized in a `k8s/` subdirectory
- Keeps manifest files separate from application code
- Matches common Kubernetes project structure

**Alternatives Considered**:
- Root of app folder: Simpler but clutters app directory
- Configurable path: More flexible but adds complexity

---

### R2: Image Tag Pattern Matching

**Decision**: Match lines containing `image:` and replace the tag after the last `:`

**Rationale**:
- Simple pattern that covers most Kubernetes manifest formats
- `image: <registry>/<image>:<tag>` is the standard format
- Replacing after last `:` handles various registry URLs

**Alternatives Considered**:
- Specific pattern like `image: localhost:50000/<image>:<tag>`: Too restrictive
- YAML parser: Overkill for simple tag replacement
- Configurable pattern: Adds unnecessary complexity

---

### R3: Multiple Image Tags Handling

**Decision**: Update all `image:` lines in the file

**Rationale**:
- Ensures consistency across all container references
- Avoids partial updates that could leave manifests inconsistent
- Simple sed global replacement handles this naturally

**Alternatives Considered**:
- First match only: Could miss important image references
- Specific pattern matching: Too complex for this use case

---

### R4: Error Handling for No Match

**Decision**: Report an error and halt if no `image:` lines are matched

**Rationale**:
- Fails fast prevents silent failures
- User gets clear feedback about what went wrong
- Consistent with existing `set -e` behavior

**Alternatives Considered**:
- Warning and continue: Could hide configuration issues
- Silent skip: Confusing for users

---

### R5: Operation Order

**Decision**: YAML updates after `.env` update, before Docker push and git tag

**Rationale**:
- Logical order: update all manifests first, then push image they reference
- Git tag should be final (point of no return)
- Docker push before git tag ensures image is available before marking release

**Alternatives Considered**:
- After Docker push: Manifests would reference image before it's pushed
- After git tag: Too late in the process

---

### R6: Cross-Platform sed Compatibility

**Decision**: Use sed with portable syntax, avoid GNU-specific extensions

**Rationale**:
- Must work on both macOS (BSD sed) and Linux (GNU sed)
- `sed "s/pattern/replacement/"` is portable
- Using temp file + mv approach works on both platforms

**Alternatives Considered**:
- `sed -i`: Not portable (different syntax between GNU/BSD)
- awk: Overkill for simple substitution
- Python/ruby: Requires additional dependencies

---

### R7: YAML File Validation

**Decision**: Check if file exists and contains at least one `image:` line

**Rationale**:
- Prevents silent failures when YAML files don't have expected content
- Clear error messages help users debug configuration issues
- Consistent with existing error handling patterns

**Alternatives Considered**:
- Skip if no match: Could hide configuration issues
- Create template: Over-engineered for this use case

---

## Research Summary

All technical decisions have been resolved. The implementation will:
1. Add function to update image tags in YAML files
2. Scan `k8s/` subdirectory for `deploy.yaml` and `cronjob.yaml`
3. Match `image:` lines and replace tag after last `:`
4. Update all occurrences in each file
5. Error if file exists but no `image:` lines matched
6. Maintain cross-platform compatibility
