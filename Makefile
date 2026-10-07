.PHONY: build build-decommission test test-decommission clean \
	trivy-db trivy-fs trivy-image trivy-sbom trivy-scan trivy-gate

BINARY_DIR := bin
DECOMMISSION_DIR := cmd/decommission
DECOMMISSION_BIN := $(BINARY_DIR)/decommission

$(BINARY_DIR):
	mkdir -p $(BINARY_DIR)

build: build-decommission

build-decommission: $(BINARY_DIR)
	go build -o $(DECOMMISSION_BIN) ./$(DECOMMISSION_DIR)

test: test-decommission

test-decommission:
	go test -v -count=1 ./$(DECOMMISSION_DIR)

test-decommission-short:
	go test -v -count=1 -short ./$(DECOMMISSION_DIR)

clean:
	rm -rf $(BINARY_DIR) $(TRIVY_CACHE_DIR)
	rm -f trivy-*.json trivy-*.sarif sbom.json

# --- Trivy ---------------------------------------------------------------
# All targets read the single policy in trivy.yaml. Flags here are limited to
# target selection and output format; thresholds and scanners come from the
# policy so a local run cannot drift from the CI gate.
#
# trivy-gate passes --exit-code 1 explicitly (the policy defaults to 0) so the
# local gate fails like CI does.
TRIVY ?= trivy
TRIVY_CONFIG := trivy.yaml
TRIVY_CACHE_DIR := .trivycache
TRIVY_TARGET ?= .
TRIVY_IMAGE ?=

# Pre-populate the vuln DB. Run once before a cold scan; CI caches this dir.
trivy-db:
	$(TRIVY) --config $(TRIVY_CONFIG) image --download-db-only

# Report-only source scan: deps + IaC misconfig + secrets. Never fails.
trivy-fs:
	$(TRIVY) --config $(TRIVY_CONFIG) fs $(TRIVY_TARGET)

# Source scan with a blocking exit code, matching the PR gate.
trivy-gate:
	$(TRIVY) --config $(TRIVY_CONFIG) fs --exit-code 1 $(TRIVY_TARGET)

# Scan a local or remote image by digest. Usage: make trivy-image TRIVY_IMAGE=app@sha256:...
trivy-image:
	@test -n "$(TRIVY_IMAGE)" || { echo "TRIVY_IMAGE=<ref> required" >&2; exit 2; }
	$(TRIVY) --config $(TRIVY_CONFIG) image $(TRIVY_IMAGE)

# Emit a CycloneDX SBOM, the artifact that makes a future CVE answerable
# without rebuilding the image.
trivy-sbom:
	$(TRIVY) --config $(TRIVY_CONFIG) image --format cyclonedx --scanners "" \
		--output sbom.json $(TRIVY_IMAGE)

# What CI runs on every PR.
trivy-scan: trivy-fs
