#!/bin/bash

set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
HOOK="$ROOT/plugins/macdoc/hooks/session-start.sh"
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/macdoc-session-start-test.XXXXXX")
trap 'rm -rf "$TEST_ROOT"' EXIT

FAKE_PATH="$TEST_ROOT/fake-path"
INSTALL_DIR="$TEST_ROOT/install"
EVENT_LOG="$TEST_ROOT/events.log"
HOOK_STDERR="$TEST_ROOT/hook.stderr"
RESIDENT="$INSTALL_DIR/macdoc"
GUARD="$INSTALL_DIR/.macdoc.installed_version"
UNSIGNED_CANDIDATE="$TEST_ROOT/unsigned-candidate"
SIGNED_FIXTURE="${MACDOC_SIGNED_FIXTURE:-$HOME/bin/macdoc}"
REQUIREMENT='=anchor apple generic and certificate 1[field.1.2.840.113635.100.6.2.6] exists and certificate leaf[field.1.2.840.113635.100.6.1.13] exists and certificate leaf[subject.OU] = "6W377FS7BS"'
mkdir -p "$FAKE_PATH" "$INSTALL_DIR"

cat > "$FAKE_PATH/uname" <<'EOF'
#!/bin/bash
echo arm64
EOF

# This deliberate bypass attempt must be ignored by production. Tests set the
# old override variable, but SessionStart must still use /usr/bin/codesign.
cat > "$FAKE_PATH/codesign" <<'EOF'
#!/bin/bash
echo fake-codesign >> "$EVENT_LOG"
exit 0
EOF

cat > "$FAKE_PATH/curl" <<'EOF'
#!/bin/bash
if [ "${FAKE_CURL_MODE:-fail}" != "success" ]; then
    echo curl-download >> "$EVENT_LOG"
    exit 22
fi

output=""
previous=""
for argument in "$@"; do
    if [ "$previous" = "-o" ]; then output="$argument"; fi
    previous="$argument"
done

if [ -n "$output" ]; then
    echo curl-download >> "$EVENT_LOG"
    cp "$DOWNLOAD_SOURCE" "$output"
else
    echo curl-sha >> "$EVENT_LOG"
    if [ "${FAKE_SHA_MODE:-actual}" = "wrong" ]; then
        echo 0000000000000000000000000000000000000000000000000000000000000000
    else
        shasum -a 256 "$DOWNLOAD_SOURCE" | awk '{print $1}'
    fi
fi
EOF

cat > "$RESIDENT" <<'EOF'
#!/bin/bash
echo resident-executed >> "$EVENT_LOG"
echo 'macdoc 0.7.0'
EOF

cat > "$UNSIGNED_CANDIDATE" <<'EOF'
#!/bin/bash
echo candidate-executed >> "$EVENT_LOG"
echo 'macdoc 0.7.0'
EOF

chmod +x "$FAKE_PATH/uname" "$FAKE_PATH/codesign" "$FAKE_PATH/curl" "$RESIDENT" "$UNSIGNED_CANDIDATE"

run_hook() {
    : > "$EVENT_LOG"
    EVENT_LOG="$EVENT_LOG" \
    FAKE_CURL_MODE="$1" \
    DOWNLOAD_SOURCE="$2" \
    FAKE_SHA_MODE="$3" \
    MACDOC_CODESIGN_BIN="$FAKE_PATH/codesign" \
    MACDOC_INSTALL_DIR="$INSTALL_DIR" \
    PATH="$FAKE_PATH:$PATH" \
    bash "$HOOK" >/dev/null 2>"$HOOK_STDERR"
}

assert_no_execution() {
    if grep -q 'executed' "$EVENT_LOG"; then
        echo "FAIL: SessionStart executed resident or candidate: $(tr '\n' ' ' < "$EVENT_LOG")" >&2
        exit 1
    fi
}

# A rejected resident must ignore a hostile verifier override, never execute,
# and force exactly one download attempt even if its sidecar claims WANT.
echo 0.7.0 > "$GUARD"
run_hook fail "$UNSIGNED_CANDIDATE" actual
assert_no_execution
if grep -qx fake-codesign "$EVENT_LOG"; then
    echo "FAIL: production honored MACDOC_CODESIGN_BIN instead of /usr/bin/codesign" >&2
    exit 1
fi
[[ "$(grep -c '^curl-download$' "$EVENT_LOG")" -eq 1 ]] || {
    echo "FAIL: rejected resident must force exactly one download attempt" >&2
    exit 1
}

# A mismatched release digest must be rejected before candidate installation.
rm -f "$GUARD"
run_hook success "$UNSIGNED_CANDIDATE" wrong
assert_no_execution
[[ ! -f "$GUARD" ]]
grep -qx curl-download "$EVENT_LOG"
grep -qx curl-sha "$EVENT_LOG"
grep -q 'resident-executed' "$RESIDENT"
grep -q 'release sha256 asset does not match pinned binary_sha256' "$HOOK_STDERR" || {
    echo "FAIL: mismatched release digest did not trip the pinned-SHA gate" >&2
    exit 1
}

# Full valid-path coverage needs a real Team-signed fixture. Keep the hostile
# cases above mandatory; gate only the positive cases for CI machines without
# the released binary.
if ! /usr/bin/codesign --verify --strict -R "$REQUIREMENT" "$SIGNED_FIXTURE" 2>/dev/null; then
    echo "SKIP: positive signed-fixture cases (set MACDOC_SIGNED_FIXTURE)"
    echo "PASS: rejected resident/candidate are never executed"
    exit 0
fi

# A verified resident with a matching installer sidecar takes a zero-network
# fast path without executing the binary during SessionStart.
cp "$SIGNED_FIXTURE" "$RESIDENT"
chmod +x "$RESIDENT"
echo 0.7.0 > "$GUARD"
run_hook fail "$SIGNED_FIXTURE" actual
assert_no_execution
[[ ! -s "$EVENT_LOG" ]] || {
    echo "FAIL: verified matching resident should not hit test doubles: $(tr '\n' ' ' < "$EVENT_LOG")" >&2
    exit 1
}

# A rejected resident can be replaced only by signed bytes whose release
# digest matches. The candidate is installed but never executed by the hook.
cp "$UNSIGNED_CANDIDATE" "$RESIDENT"
chmod +x "$RESIDENT"
rm -f "$GUARD"
run_hook success "$SIGNED_FIXTURE" actual
assert_no_execution
grep -qx curl-download "$EVENT_LOG"
grep -qx curl-sha "$EVENT_LOG"
cmp -s "$RESIDENT" "$SIGNED_FIXTURE"
[[ "$(cat "$GUARD")" = "0.7.0" ]]

echo "PASS: SessionStart never executes resident binary and installs only a verified candidate"
