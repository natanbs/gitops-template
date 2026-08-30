## Tasks

### Phase 1 — Standards audit gate (constitution-aligned)

- [ ] 1. Add `init/template-version` (canonical version constant, content `1.0.0`).
- [ ] 2. Modify `init/init.sh` to stamp `.template-version` into the scaffolded app dir during scaffold.
- [ ] 3. Update `init/gitignore` so `.template-version` is committed (not ignored) in new apps.
- [ ] 4. Add a bats test asserting `init.sh` creates `.template-version` with the expected content (`cicd-tests/init_env.bats` or new file).
- [ ] 5. Add `standards-audit/fixtures/` with one conformant and one non-conformant fixture app (minimal layout: `.env`, `k8s/deploy.yaml`, `k8s/svc.yaml`, Dockerfile).
- [ ] 6. Add `standards-audit/checks/structure.sh` (required files + YAML parse of `k8s/*.yaml`).
- [ ] 7. Add `standards-audit/checks/secrets.sh` (offline grep-based credential scan over tracked files; pinned rule list; exemptions file support).
- [ ] 8. Add `standards-audit/checks/manifest-policy.sh` (namespace / image / port consistency across generated manifests vs declared config).
- [ ] 9. Add `standards-audit/runner.sh` (runs all checks, one-line pass/fail per check with actionable fix, aggregate result, exit non-zero on violation; `set -euo pipefail`, BSD/GNU portable).
- [ ] 10. Add `standards-audit/tests/*.bats` covering each check against both fixtures (no cluster/Docker/network), asserting failure text names the file and fix.
- [ ] 11. Add `.github/workflows/standards-audit.yml` (reusable `workflow_call`; inputs for repo-root/config paths; least-privilege `permissions` incl. `contents: read`; no secrets required; pin actions by SHA).
- [ ] 12. Add `examples/standards-audit-caller.yml` documenting org-level import of the audit as a required check.
- [ ] 13. Document the constitution-mandated phased roadmap (P2 shared artifacts, P3 tracked re-sync) and Pending Decision Log gates in `README.md` "Standards Alignment" section.
- [ ] 14. Verify: `bats cicd-tests/` and `bats standards-audit/tests/` all pass; `shellcheck` no new warnings; run `runner.sh` against fixtures manually.

### Phase 2 — Shared versioned artifacts (RFC, gated by Pending Decision Log)

- [ ] 15. Write RFC: promote `build.sh` steps into org-level reusable workflows tagged `@vX.Y.Z` (OIDC auth, no cloud credentials). Gate: Infra/Ownership/Scope decisions.
- [ ] 16. Write RFC: shared K8s deployment catalog (Helm chart / platform catalog) + External Secrets / workload-identity baseline.

### Phase 3 — Tracked template re-sync (RFC, gated by Pending Decision Log)

- [ ] 17. Write RFC: Copier/Cruft-style tracked update path for structure re-sync (Tooling decision) + brownfield onboarding (Migration decision).