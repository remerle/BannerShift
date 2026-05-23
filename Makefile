# BannerShift — top-level dev commands.
# Tested with the GNU make that ships with macOS (3.81). All targets are phony.

ROOT       := $(shell pwd)
APP_BUNDLE := $(ROOT)/build/BannerShift.app
SWIFT_FMT  := swift format
SOURCES    := Package.swift Sources Tests

.DEFAULT_GOAL := help

.PHONY: help
help: ## Show this help.
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_.-]+:.*?## / {printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

# ---- Build / test ----

.PHONY: build
build: ## Build the package (debug).
	swift build

.PHONY: test
test: ## Run unit tests.
	swift test

.PHONY: clean
clean: ## Remove build artifacts.
	rm -rf $(ROOT)/.build $(ROOT)/build

# ---- App bundle ----

.PHONY: dev
dev: ## Build a universal, ad-hoc-signed .app at build/BannerShift.app.
	./scripts/build-dev.sh

.PHONY: run
run: dev ## Build then launch the .app via `open`.
	open $(APP_BUNDLE)

# ---- Quality gates ----

.PHONY: format
format: ## Format Swift sources in place (Apple swift-format).
	$(SWIFT_FMT) format -i -r $(SOURCES)

.PHONY: format-check
format-check: ## Verify formatting; nonzero exit on drift.
	$(SWIFT_FMT) lint -s -r $(SOURCES)

.PHONY: validate
validate: format-check build test ## Pre-merge gate: format-check + build + test.
	@echo "validate: all checks ok"

# ---- Release ----

.PHONY: secrets-setup
secrets-setup: ## First-time machine setup: import Developer ID cert then pull secrets.
	./populate-secrets.sh --import-certs

.PHONY: secrets
secrets: ## Pull signing secrets from 1Password into .env + .secrets/ (re-run anytime).
	./populate-secrets.sh

.PHONY: release
release: ## Signed, notarized, stapled release build. Requires `make secrets` first.
	./release.sh

# ---- Logs ----

.PHONY: tail-log
tail-log: ## Tail ~/Library/Logs/BannerShift.log (creates the file if absent).
	@touch ~/Library/Logs/BannerShift.log
	tail -f ~/Library/Logs/BannerShift.log
