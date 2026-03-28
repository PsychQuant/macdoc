.PHONY: release debug install clean metallib

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

# Clean build artifacts
clean:
	swift package clean
	rm -f .build/release/mlx.metallib .build/debug/mlx.metallib
