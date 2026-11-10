.PHONY: release debug install clean metallib check-bib-fixtures test-release cli-spec \
	pins-status pins-update pins-sync test-pins

# Build release binary + Metal shaders
release:
	swift build -c release
	./scripts/build-metallib.sh .build/release

# Build debug (no metallib — Metal won't work in debug)
debug:
	swift build

# Install to ~/bin
install: release
	cp .build/release/macdoc ~/bin/macdoc
	cp .build/release/mlx.metallib ~/bin/mlx.metallib
	@echo "✓ Installed macdoc + mlx.metallib to ~/bin/"

# Build metallib only (after swift build)
metallib:
	./scripts/build-metallib.sh .build/release

# Run CLI integration tests against the release binary.
#
# Works around a confirmed SwiftPM/Swift Testing release-mode limitation
# (#188): a native `swift test -c release` mixed XCTest/Swift Testing run
# passes `--test-bundle-path` to the *product* macdoc executable instead of
# the test host, so the Swift Testing phase fails with
# "Unknown option '--test-bundle-path'" and OMath/route tests never run.
# See Tests/MacDocCLITests/README.md for the full writeup. This target
# builds release, then runs the default *debug* XCTest bundle with
# MACDOC_TEST_BINARY pointed at the release product and Swift Testing
# disabled — the documented working alternative. Regression coverage:
# scripts/tests/make-test-release.sh.
test-release: release
	@BIN_DIR=$$(swift build -c release --show-bin-path) && \
	MACDOC_TEST_BINARY="$$BIN_DIR/macdoc" \
	  swift test --disable-swift-testing

# Clean build artifacts
clean:
	swift package clean
	rm -f .build/release/mlx.metallib .build/debug/mlx.metallib

# Verify the three bib-apa-to-*-swift packages' bundled portable-references.bib
# fixtures haven't drifted apart (macdoc#189)
check-bib-fixtures:
	./scripts/tests/check-bib-fixture-consistency.sh

# Regenerate cli-spec.yaml — the machine-readable CLI specification — from the
# current ArgumentParser declarations plus the metadata overlay in
# Sources/CLISpec/MacDocCLIMetadata.swift (#72). Runs the drift test in record
# mode; without MACDOC_RECORD_CLI_SPEC=1 the same test fails whenever the
# committed file is stale. Record mode is refused when CI is set, so this
# target is for local use only. Commit the regenerated file.
cli-spec:
	swift build
	MACDOC_RECORD_CLI_SPEC=1 swift test --filter CLISpecDriftTests

# Marketplace binary pins (#279) — see scripts/marketplace-pins.sh.
# pins-status: pin / latest release / installed, plus checkout state (exit 0/10/2).
# pins-update: PLUGIN=<name> [TO=X.Y.Z] [PLUGIN_VERSION=X.Y.Z] [DRY_RUN=1];
#              commits locally, never pushes.
# pins-sync:   fast-forward this checkout when strictly behind, then refresh
#              the locally installed marketplace and plugins.
pins-status:
	./scripts/marketplace-pins.sh status

pins-update:
	@test -n "$(PLUGIN)" || { echo "用法：make pins-update PLUGIN=<name> [TO=X.Y.Z] [PLUGIN_VERSION=X.Y.Z] [DRY_RUN=1]" >&2; exit 64; }
	./scripts/marketplace-pins.sh update "$(PLUGIN)" \
	  $(if $(TO),--to "$(TO)") \
	  $(if $(PLUGIN_VERSION),--plugin-version "$(PLUGIN_VERSION)") \
	  $(if $(DRY_RUN),--dry-run)

pins-sync:
	./scripts/marketplace-pins.sh sync-local

test-pins:
	bash scripts/tests/marketplace-pins.sh
