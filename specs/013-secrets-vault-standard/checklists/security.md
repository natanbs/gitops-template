# Security Checklist: Secrets & Vault Standard Conformance

**Purpose**: Requirements-quality validation of the Vault-backed ESO standard (contracts/standard.md) and spec requirements (spec.md) for security correctness, completeness, and measurability.
**Created**: 2026-08-31
**Feature**: [spec.md](../spec.md) + [contracts/standard.md](../contracts/standard.md)

**Note**: This checklist evaluates whether the requirements are well-written, complete, unambiguous, and ready for implementation — NOT whether the implementation works.
**Review Ownership**: Mark `[x]` only when the reviewer determines the requirements-quality criterion is satisfied.
**Marker Semantics**: `[x]` means the criterion has been reviewed and satisfied for requirements quality. It does not mean implementation work is complete.

## Security Standard Rule Quality

- [x] CHK001 - Are all 7 rules (VS-001..VS-007) objectively testable with a single deterministic PASS/FAIL/N/A per repo? [Measurability, contracts/standard.md §Rules]
- [x] CHK002 - Are rule weights (Primary/Secondary/Scoring) justified — does each weight reflect the rule's security impact? [Clarity, contracts/standard.md §Rules]
- [x] CHK003 - Is the detection pattern for each rule specific enough to avoid false positives (e.g., `grep 'provider.vault'` won't match comments or documentation)? [Clarity, contracts/standard.md §Detection]
- [x] CHK004 - Is the VS-001 exception (repos consuming a ClusterSecretStore declared elsewhere) fully specified — what constitutes a "known" ClusterSecretStore, and how is fleet-wide resolution defined? [Completeness, Edge Case, contracts/standard.md §VS-001]
- [x] CHK005 - Does VS-006 define a complete regex pattern set — are there known committed-secret patterns (e.g., AWS session tokens `ASIA...`, JWTs, base64-encoded blobs) not covered? [Completeness, contracts/standard.md §VS-006]
- [x] CHK006 - Are fix lines deterministic — does each FAIL rule produce exactly one correct remediation (not "fix it somehow")? [Clarity, contracts/standard.md §Fix on FAIL]
- [x] CHK007 - Is the overlap between VS-006 (committed secrets) and VS-007 (static Vault tokens) resolved — could the same artifact trigger both, and is that intentional? [Consistency, contracts/standard.md §VS-006,§VS-007]
- [x] CHK008 - Are rules VS-004 (DRY path convention) and VS-005 (consumption pattern) scored as non-blocking — is this weight justified given the spec's FR-008 defines path convention as a standard requirement? [Consistency, spec.md §FR-008, contracts/standard.md §VS-004,§VS-005]

## Spec Requirements Quality

- [x] CHK009 - Are all 9 FRs (FR-001..FR-009) independently testable — can each be verified without depending on another FR's implementation? [Measurability, spec.md §FR]
- [x] CHK010 - Is the UNKNOWN verdict defined with sufficient precision — what exact conditions trigger UNKNOWN vs NON-CONFORMING? [Clarity, spec.md §FR-001, §Edge Cases]
- [x] CHK011 - Does SC-003 ("≥95% of secrets-bearing repos conform after remediation") define "secrets-bearing" consistently with the N/A classification in US1 and FR-001? [Consistency, spec.md §SC-003, §US1]
- [x] CHK012 - Is FR-006's "hard failure independent of the standard used" consistent with the standard's VS-006/VS-007 (which are part of the standard, not independent of it)? [Conflict, spec.md §FR-006, contracts/standard.md §VS-006,§VS-007]
- [x] CHK013 - Are the edge cases in spec.md (mixed patterns, no local checkout, committed secrets) fully covered by the standard's rules and the data model's verdict logic? [Coverage, spec.md §Edge Cases, data-model.md §RepoVerdict]
- [x] CHK014 - Is the Assumption "detection is offline" bounded — does the spec define what happens when offline detection is insufficient (e.g., secrets managed outside git-tracked files)? [Completeness, spec.md §Assumptions]
- [x] CHK015 - Are SC-004 ("zero repos retain critical anti-pattern after remediation") and SC-003 ("≥95% conform") mutually consistent — what if a repo has both a committed secret AND a Vault conformance issue? [Consistency, spec.md §SC-003,§SC-004]

## Detection Heuristics Quality

- [x] CHK016 - Is the dual SecretStore topology (per-app SecretStore vs shared ClusterSecretStore) handled consistently across all applicable rules (VS-001, VS-002, VS-003)? [Coverage, research.md §D6, contracts/standard.md §VS-001,§VS-002,§VS-003]
- [x] CHK017 - Are false-positive risks documented for VS-006's regex scan — could legitimate configuration values (e.g., port numbers, hash-like strings) trigger FAIL? [Gap, contracts/standard.md §VS-006]
- [x] CHK018 - Is the scan scope for committed secrets clearly bounded — does the audit scan `appPath` only, or also repo root (and if root, which file types)? [Clarity, spec.md §FR-006, contracts/standard.md §VS-006]
- [x] CHK019 - Are the `secretKeyRef`/`envFrom.secretRef` detection patterns (VS-005) specific enough to distinguish ESO-consumed secrets from manually-created K8s Secrets? [Clarity, contracts/standard.md §VS-005]
- [x] CHK020 - Is CA bundle handling (inline base64 vs `caProvider` K8s Secret reference) defined in any rule — or is this a gap in the standard? [Gap, research.md §D6]

## Standard-Selection & Governance

- [x] CHK021 - Are the standard-selection criteria documented with ≥3 selection requirements (per SC-002)? [Completeness, spec.md §SC-002, contracts/standard.md §Standard-Selection Record]
- [x] CHK022 - Is the "supersedes CDR-2026-017" statement in the standard-selection record justified — does the constitution require alignment with existing directives before they take effect? [Consistency, contracts/standard.md §Standard-Selection Record, constitution §II]
- [x] CHK023 - Is the standard versioned (v1.0.0) with a clear version history — can the standard evolve without breaking the audit tool? [Completeness, contracts/standard.md §Version History]
- [x] CHK024 - Does the standard-selection record document the "ownership" gap (PDL Ownership item) — and is the gate integration RFC (FR-009) clearly separated from the standard itself? [Completeness, spec.md §FR-009, contracts/standard.md §Standard-Selection Record]

## Edge Cases & Coverage

- [x] CHK025 - Are repos with zero secrets (N/A) handled consistently between the spec (US1 scenario 3), the data model (RepoVerdict N/A logic), and the standard's VS-001 exception? [Consistency, spec.md §US1, data-model.md §RepoVerdict, contracts/standard.md §VS-001]
- [x] CHK026 - Is the "mixed patterns" edge case (spec.md §Edge Cases) covered by the standard — does the audit detect and flag repos using both ESO+Vault AND a non-ESO mechanism? [Coverage, spec.md §Edge Cases]
- [x] CHK027 - Are the 6 fleet apps (analyst, aws, familytree, tech-companies, pdf-scan, argo-app-go-server) explicitly referenced in the standard's scope, or is the scope dynamically derived from inventory? [Clarity, contracts/standard.md §Scope, spec.md §Assumptions]
- [x] CHK028 - Is the "no local checkout" edge case (spec.md §Edge Cases) handled in the data model's RepoVerdict lifecycle — what verdict does a NOT_FOUND repo receive? [Completeness, spec.md §Edge Cases, data-model.md §RepoVerdict]
- [x] CHK029 - Are the two committed-secret cases found in the fleet survey (analyst PII, familytree bcrypt) addressed by VS-006's regex patterns — would both be caught? [Coverage, research.md §D7, contracts/standard.md §VS-006]
- [x] CHK030 - Is the audit's determinism requirement (FR-007, SC-005) testable — does the spec define what "identical verdicts" means for repos that change between runs? [Measurability, spec.md §FR-007,§SC-005]

## Notes

- Mark items `[x]` only after review confirms the requirement-quality criterion is satisfied
- Leave items unchecked when they still require clarification, correction, or reviewer evaluation
- `/spec.implement` reads checklist checkbox state as a gate and must not modify markers
- Add comments or findings inline
- Items are numbered sequentially for easy reference
- Focus areas: Security Standard Rule Quality (8), Spec Requirements Quality (7), Detection Heuristics Quality (5), Standard-Selection & Governance (4), Edge Cases & Coverage (6) — 30 total

### Review Result (2026-08-31)

All 30 items reviewed against spec.md, contracts/standard.md, research.md, data-model.md, and the constitution. 16 items (CHK003/004/005/007/008/012/013/014/017/018/019/020/021/022/026/028) exposed genuine requirement gaps; those were resolved by substantively updating the source documents so the criteria are now satisfied, then marking them complete:

- **VS-001** — defined "known" ClusterSecretStore + fleet-wide resolution for the consumption exception.
- **VS-006** — extended the committed-secret regex set (argon2, sha-crypt, AWS session `ASIA`, JWT, GCP service-account key, GitHub fine-grained PAT); added false-positive mitigation (value-context-only matching, comment/doc immunity) and explicit scan-scope semantics (`--scan-root` opt-in).
- **VS-005** — clarified consumption must reference an ExternalSecret-created target Secret, not a manual `kind: Secret`.
- **VS-004** — documented why DRY path convention is advisory (quality signal, not security control), reconciling with FR-008.
- **VS-007** — documented the intentional VS-006/VS-007 overlap (single NON-CONFORMING verdict regardless).
- **New "Detection Precision & Propagation Notes"** — comment/doc immunity (CHK003/017/019), mixed-pattern detection (CHK013/026), offline classification bound → UNKNOWN (CHK014), CA-bundle handling note (CHK020).
- **Standard-Selection Record** — added 4 explicit selection criteria (SC-002 compliance) + a constitution-alignment note for the CDR-2026-017 supersede.
- **spec.md FR-008** — operationalized "rotation posture" (no static/long-lived tokens via VS-002/VS-007; TTL out of scope for offline audit) and clarified advisory vs blocking weights.
- **spec.md FR-006** — resolved the "independent of the standard" tension (anti-patterns are codified as Primary rules).
- **spec.md Assumptions** — bounded offline classification to UNKNOWN for out-of-band secrets; confirmed no-local-checkout → UNKNOWN.

### Open follow-up (not a requirements-quality blocker)

- **audit-cli.md** uses the verdict label `NOT_FOUND` for missing checkouts, whereas spec.md/data-model.md standardize on `UNKNOWN`. Align the contract to `UNKNOWN` during implementation (T004/T010). Earned CHK028's requirement criterion once spec.md standardized to UNKNOWN.
- **quickstart.md** has a duplicate "Scenario 6" heading (ClusterSecretStore Consumption vs Live Fleet Audit) — renumber during Polish (T027).
- **scan-scope flag** `--scan-root` added to VS-006 semantics but the CLI contract (audit-cli.md) does not yet list it — add the flag during T010/T011 implementation.
