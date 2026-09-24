#!/bin/bash
# Regression test for the `make test-release` workaround (#188).
#
# #188: a native `swift test -c release` mixed XCTest/Swift Testing run
# passes `--test-bundle-path` to the *product* macdoc executable instead of
# the test host, so the Swift Testing phase fails with "Unknown option
# '--test-bundle-path'". The documented workaround (Tests/MacDocCLITests/
# README.md) runs the default *debug* XCTest bundle with MACDOC_TEST_BINARY
# pointed at the release product and Swift Testing disabled. This test
# asserts `make test-release` actually encodes that exact sequence, using a
# faked `swift` binary so it runs in seconds without a real release build.

set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
MAKEFILE="$ROOT/Makefile"
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/macdoc-test-release-target.XXXXXX")
trap 'rm -rf "$TEST_ROOT"' EXIT

FAKE_PATH="$TEST_ROOT/fake-path"
EVENT_LOG="$TEST_ROOT/events.log"
FAKE_BIN_DIR="$TEST_ROOT/fake-release-bin"
mkdir -p "$FAKE_PATH" "$FAKE_BIN_DIR" "$TEST_ROOT/scripts"
: > "$EVENT_LOG"

cp "$MAKEFILE" "$TEST_ROOT/Makefile"

# `release` (the prerequisite of `test-release`) also runs
# ./scripts/build-metallib.sh; stub it so this test exercises only the
# swift-invocation sequence, not the real Metal shader build.
cat > "$TEST_ROOT/scripts/build-metallib.sh" <<'EOF'
#!/bin/bash
exit 0
EOF
chmod +x "$TEST_ROOT/scripts/build-metallib.sh"

cat > "$FAKE_PATH/swift" <<EOF
#!/bin/bash
if [ "\$1" = "build" ] && [ "\$2" = "-c" ] && [ "\$3" = "release" ]; then
    if [ "\${4:-}" = "--show-bin-path" ]; then
        echo "show-bin-path" >> "$EVENT_LOG"
        echo "$FAKE_BIN_DIR"
        exit 0
    fi
    echo "build-release" >> "$EVENT_LOG"
    exit 0
fi
if [ "\$1" = "test" ]; then
    echo "test-args: \$*" >> "$EVENT_LOG"
    echo "test-env-MACDOC_TEST_BINARY=\${MACDOC_TEST_BINARY:-}" >> "$EVENT_LOG"
    if [[ "\$*" != *"--disable-swift-testing"* ]]; then
        echo "FATAL: swift test invoked without --disable-swift-testing (would trigger #188)" >&2
        exit 1
    fi
    exit 0
fi
echo "unexpected swift invocation: \$*" >&2
exit 1
EOF
chmod +x "$FAKE_PATH/swift"

PATH="$FAKE_PATH:$PATH" make -C "$TEST_ROOT" test-release

# --- Assertions ---
fail() {
    echo "FAIL: $1" >&2
    echo "--- events.log ---" >&2
    cat "$EVENT_LOG" >&2
    exit 1
}

grep -qx "build-release" "$EVENT_LOG" || fail "release build step did not run"
grep -qx "show-bin-path" "$EVENT_LOG" || fail "--show-bin-path resolution step did not run"
grep -q "^test-args:.*--disable-swift-testing" "$EVENT_LOG" \
    || fail "swift test was not invoked with --disable-swift-testing"
grep -qx "test-env-MACDOC_TEST_BINARY=$FAKE_BIN_DIR/macdoc" "$EVENT_LOG" \
    || fail "MACDOC_TEST_BINARY was not set to the resolved release binary path"

echo "PASS: make test-release runs the documented release-mode workaround sequence"
