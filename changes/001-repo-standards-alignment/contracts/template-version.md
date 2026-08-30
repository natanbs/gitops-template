# Contract: `.template-version` Provenance Stamp

Created by `init.sh` in every scaffolded app; consumed in P3 by re-sync tooling.

## Canonical Source

`init/template-version` — single file, plain semver on one line, trailing newline.

Current value: `1.0.0`

## Artifact (in scaffolded app)

| Field | Rule |
|-------|------|
| path | `<app-root>/.template-version` |
| content | byte-for-byte copy of `init/template-version` (semver line) |
| git | committed (must NOT be matched by `init/gitignore`) |
| immutability | written once at scaffold; P1 never mutates it |

## Consumers

- P1: no consumers beyond creation (structure check recognizes the file as a
  benign, expected config artifact — excluded from secrets scan keys).
- P3 (future): re-sync compares `<app-root>/.template-version` to the upstream
  `init/template-version` constant to detect lineage lag.

## Validation

bats assertion: scaffold a fixture app with `init.sh`, assert the file exists and
its content equals `1.0.0`.