# Research: init.sh Syncs K8s Port from CONTAINER_PORT

## Decision 1: Update Mechanism — Targeted In-Place Field Update vs Full Re-Render

**Decision**: Update only the port fields in existing `k8s/svc.yaml`, `k8s/deploy.yaml`, and `k8s/ingress.yaml` in place, preserving all other content. Templates are still only re-rendered for brand-new apps.

**Rationale**: Existing-app manifests are intentionally preserved (never re-rendered) so users can customize replicas, probes, annotations, etc. A full re-render would clobber those. The targeted update mirrors the existing `deploy.yaml` image/IMAGE_TAG update already in `build.sh step_template` — established, trusted pattern.

**Alternatives considered**:
- Always re-render templates for existing apps — rejected: destroys user customizations, contradicts the design intent (`_APP_EXISTS` guard).
- Re-render only with a `--force`-style flag — rejected: forces users to remember a flag and still risks clobbering; targeted update is strictly safer.
- No port sync at all (status quo) — rejected: `.env` becomes a lie and re-deploys apply stale ports.

## Decision 2: Sync Trigger — Only `--build`/`--deploy`

**Decision**: `init.sh` runs the port sync only when `RUN_BUILD=true` (set by `--build` and by `--deploy`, which implies `--build`). A plain `init.sh` run against an existing app leaves manifests untouched.

**Rationale**: User-confirmed scope. Keeps the surprise factor low — scaffolding/sync-only runs don't silently mutate manifests; port changes take effect exactly when the user is building/deploying.

**Alternatives considered**:
- Always sync on any existing-app run — rejected (user chose deploy/build-only scope).
- Sync only on `--deploy` (not `--build`) — rejected: `--deploy` already implies `--build`, and `--build` output feeds deployment; keeping both consistent is simpler.

## Decision 3: build.sh Also Syncs

**Decision**: Extend `build.sh step_template`'s existing-file branch so a direct `build.sh --auto-deploy` applies the same port sync. `deploy.yaml` keeps its image/IMAGE_TAG awk update and additionally rewrites port fields; `svc.yaml` and `ingress.yaml` are no longer skipped (ports updated); `pvc.yaml` still skipped (no ports).

**Rationale**: `init.sh --deploy` delegates to `build.sh`. If only init.sh synced, the next direct `build.sh --auto-deploy` would leave stale ports. Both entry points must agree. The existing deploy.yaml in-place update proves the pattern.

**Alternatives considered**:
- init.sh only — rejected (user chose both; inconsistent behavior).
- Full re-render in build.sh — rejected (same customization-clobber concern as Decision 1).

## Decision 4: BSD-sed Portable Patterns

**Decision**: Use independent `sed` expressions for each field shape. The `port:` matcher is expressed twice — `^[[:space:]]*port:` (own line, template-generated format) and `^[[:space:]]*-[[:space:]]*port:` (compact `- port:` list style) — rather than a `-\?` optional-dash quantifier.

**Rationale**: macOS BSD sed treats `\?` as a literal character (no BRE quantifier support), which silently breaks the own-line match. Two explicit expressions behave identically on both BSD and GNU sed (verified empirically).

**Alternatives considered**:
- Single `-\?` pattern — rejected: verified broken on macOS BSD sed (`port:` lines left unchanged while `targetPort:` updated).
- GNU-only `-r`/`-E` extended regex — rejected: `-E` portability across BSD is acceptable but the two-expression BRE form is simplest and fully portable.

## Decision 5: Port Fields That Constitute "The Port"

**Decision**: Sync exactly these fields to `CONTAINER_PORT`:
- `svc.yaml`: `spec.ports[].port` and `spec.ports[].targetPort`
- `deploy.yaml`: `spec.template.spec.containers[].ports[].containerPort`, `livenessProbe.httpGet.port`, `readinessProbe.httpGet.port`
- `ingress.yaml`: `spec.rules[].http.paths[].backend.service.port.number`

**Rationale**: These are the only port references in the three generated templates. `CONTAINER_PORT` is the single source of truth for app traffic.

**Alternatives considered**:
- Only service port — rejected: `containerPort` and probe ports must match the container's listening port or health checks fail.
- Numeric-only replacement of every `port:`/`number:` occurrence globally — rejected as over-broad; the field-specific patterns are safe for the generated formats.

## Decision 6: Test Sandboxing

**Decision**: Bats tests use a sandboxed copy of the repo (`init/` + wrapper, or `build.sh` + templates) inside the test temp dir so neither `docker` nor the sibling-app-dir resolution (`$(dirname $PROJECT_ROOT)/$APP_NAME`) is needed, and no cluster/docker dependency is introduced.

**Rationale**: `init.sh --build` invokes `build.sh`, which runs `docker build` and resolves the app dir as a sibling of the template repo — both undesirable in unit tests. Copying just the scripts into `$TEST_TEMP_DIR` keeps tests deterministic, offline, and side-effect-free.

**Alternatives considered**:
- Run real `build.sh` against the real repo — rejected: writes manifests to `/Users/…/projects/<app>` and depends on docker.
- Mock docker — rejected: over-engineering; the `--continue-on-error` path already tolerates docker absence.
