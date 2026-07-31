# Feature Specification: init.sh Syncs K8s Port from CONTAINER_PORT

**Feature Branch**: `012-init-sync-container-port`

**Created**: 2026-07-31

**Status**: Draft

**Input**: User description: "when running from any repo: ../gitops-template/init.sh --deploy
Should update the k8s port according to CONTAINER_PORT in .env file"

## User Scenarios & Testing

### User Story 1 - Re-deploy an Existing App with a New Port (Priority: P1)

A user edits `CONTAINER_PORT` in an existing app's `.env` (e.g., 9000), then runs
`../gitops-template/init.sh --deploy` from the app repo. The k8s manifests are updated to
use the new port and applied to the cluster.

**Why this priority**: This is the core requested workflow — re-deploying from any repo
must reflect the port configured in `.env`.

**Independent Test**: In an existing app dir with `CONTAINER_PORT=9000`, run
`../gitops-template/init.sh --deploy` and verify `k8s/svc.yaml`, `k8s/deploy.yaml`, and
`k8s/ingress.yaml` all reference port 9000.

**Acceptance Scenarios**:

1. **Given** an existing app whose `k8s/svc.yaml`, `k8s/deploy.yaml`, `k8s/ingress.yaml`
   reference port 8080, **When** the user sets `CONTAINER_PORT=9000` in `.env` and runs
   `init.sh --deploy`, **Then** all port references in the three manifests become 9000 and
   the manifests are applied to the cluster.
2. **Given** the same run repeated with no `.env` change, **When** `init.sh --deploy` runs
   again, **Then** the manifests are unchanged (idempotent) and deploy succeeds.

---

### User Story 2 - Direct build.sh Deploy Also Stays in Sync (Priority: P1)

A user runs `build.sh --auto-deploy` directly (without init.sh) against an existing app;
existing manifests also get their port synced from `.env`.

**Why this priority**: init.sh --deploy delegates to build.sh, so both entry points must
behave consistently; a port change applied only via init.sh would regress on the next
direct build.sh deploy.

**Independent Test**: In an existing app with `CONTAINER_PORT=9000`, run
`build.sh --image-tag v1.0 --auto-deploy` and verify the three manifests use port 9000.

**Acceptance Scenarios**:

1. **Given** an existing app with manifests referencing port 8080 and `.env` setting
   `CONTAINER_PORT=9000`, **When** `build.sh --auto-deploy` runs, **Then** `svc.yaml`,
   `deploy.yaml`, and `ingress.yaml` port references become 9000.

---

### User Story 3 - Customizations Are Preserved (Priority: P2)

The port sync is a targeted field update: custom edits (replicas, annotations, extra
containers, etc.) in existing manifests are never clobbered.

**Why this priority**: Existing-app manifests are intentionally preserved (not re-rendered)
to respect user customization; the port update must not regress that guarantee.

**Independent Test**: Add a custom annotation to an existing manifest, run the deploy flow,
and verify the annotation survives while the port changes.

**Acceptance Scenarios**:

1. **Given** an existing `k8s/deploy.yaml` with a custom `replicas: 3` and a custom
   annotation, **When** the deploy flow updates the port, **Then** `replicas` and the
   annotation remain unchanged.

---

### User Story 4 - New App Scaffolding Unaffected (Priority: P2)

Scaffolding a brand-new app (no `.env`) still renders the default port (8080) exactly as
before.

**Why this priority**: The port-sync feature must not alter first-time scaffolding.

**Independent Test**: Run `init.sh --app-name fresh-app` and verify the rendered manifests
use the default port as today.

**Acceptance Scenarios**:

1. **Given** a new app scaffold, **When** `init.sh` runs without a `.env`, **Then** the
   manifests render with the default port 8080 and the existing test suite passes unchanged.

---

### Edge Cases

- Existing app has no `k8s/` dir or a manifest is missing → **Skipped without error.**
- `CONTAINER_PORT` missing or empty in `.env` → **Default 8080 used (existing merge
  behavior).**
- App has no `.env` at all → **Defaults used; port sync applies to rendered defaults.**
- Manifest contains unrelated `port:`/`number:` fields → **Only the intended port fields
  (svc port/targetPort, deploy containerPort + probe ports, ingress backend number) are
  rewritten.**

## Requirements

### Functional Requirements

- **FR-001**: When `init.sh` runs with `--build` or `--deploy` against an existing app, the
  system MUST update the service `port` and `targetPort` in `k8s/svc.yaml` to match
  `CONTAINER_PORT`.
- **FR-002**: The system MUST update `containerPort` and both liveness/readiness probe
  ports in `k8s/deploy.yaml` to match `CONTAINER_PORT`.
- **FR-003**: The system MUST update the ingress backend service port number in
  `k8s/ingress.yaml` to match `CONTAINER_PORT`.
- **FR-004**: The port update MUST be a targeted in-place change that preserves all other
  content of existing manifests.
- **FR-005**: When `build.sh` processes templates for an existing app, it MUST apply the
  same port updates to existing `svc.yaml`, `deploy.yaml`, and `ingress.yaml`.
- **FR-006**: The port sync MUST be idempotent — re-running with an unchanged
  `CONTAINER_PORT` must not alter the manifests.
- **FR-007**: Missing manifest files MUST be skipped without error.
- **FR-008**: Running `init.sh` against an existing app **without** `--build`/`--deploy`
  MUST NOT modify the k8s manifests.

### Key Entities

- **Container Port Configuration**: The `CONTAINER_PORT` value in `.env` is the single
  source of truth for the app's port across all generated k8s resources.

## Success Criteria

### Measurable Outcomes

- **SC-001**: After `../gitops-template/init.sh --deploy` in an existing repo whose `.env`
  sets `CONTAINER_PORT=9000`, 100% of port references in `k8s/svc.yaml`, `k8s/deploy.yaml`,
  and `k8s/ingress.yaml` equal 9000.
- **SC-002**: 100% of non-port content in existing manifests is preserved after the sync.
- **SC-003**: A direct `build.sh --auto-deploy` run produces the same port values in all
  three manifests.
- **SC-004**: The existing bats regression suite passes with no modifications to unrelated
  tests.

## Assumptions

- `CONTAINER_PORT` is the single source of truth for the app port; intentionally divergent
  probe ports are not expected and will be overwritten.
- The app repo is a sibling of gitops-template whose folder name equals `APP_NAME` (the
  standard layout for `../gitops-template/init.sh`), so both init.sh and build.sh resolve
  the same app directory.
- Port sync runs only when `--build`/`--deploy` is used (user-confirmed scope).

## Clarifications

### Session 2026-07-31

- Q: When should init.sh re-sync the k8s port? → A: Only with `--build`/`--deploy`.
- Q: Should build.sh also sync the port for direct usage? → A: Yes, both entry points.
- Q: Update mechanism? → A: Targeted in-place field update preserving customizations.
