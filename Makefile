.PHONY: build build-decommission test test-decommission clean

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
	rm -rf $(BINARY_DIR)
