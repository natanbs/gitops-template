# Non-conformant fixture (app-k8s profile): expects AUDIT RESULT: FAIL.
#
# Violations, each producing a FAIL line with a `fix:`:
#   * Dockerfile missing            -> structure-files FAIL  (missing required file)
#   * .env CONTAINER_PORT=9090 vs k8s/deploy.yaml containerPort 8080
#                                   -> policy-manifests FAIL
#   * secrets/planted.env contains a planted AWS credential (git-tracked)
#                                   -> secrets-scan FAIL
#
# Intentfully seeded violations; used by standards-audit/tests/checks.bats.