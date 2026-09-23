#!/bin/bash

set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
HOOK="$ROOT/plugins/macdoc/hooks/session-start.sh"
VERIFY_LIB="$ROOT/plugins/macdoc/hooks/session-start-verify.sh"
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/macdoc-session-start-test.XXXXXX")
trap 'rm -rf "$TEST_ROOT"' EXIT

FAKE_PATH="$TEST_ROOT/hostile-path"
INSTALL_DIR="$TEST_ROOT/install"
EVENT_LOG="$TEST_ROOT/events.log"
HOOK_STDERR="$TEST_ROOT/hook.stderr"
RESIDENT="$INSTALL_DIR/macdoc"
GUARD="$INSTALL_DIR/.macdoc.installed_version"
UNSIGNED_CANDIDATE="$TEST_ROOT/unsigned-candidate"
SIGNED_FIXTURE="${MACDOC_SIGNED_FIXTURE:-$HOME/bin/macdoc}"
REQUIREMENT='=anchor apple generic and certificate 1[field.1.2.840.113635.100.6.2.6] exists and certificate leaf[field.1.2.840.113635.100.6.1.13] exists and certificate leaf[subject.OU] = "6W377FS7BS"'
# Read the pin from the same plugin.json the hook reads. A hard-coded copy went
# stale when 1.5.2 moved the pin to 0.8.0: the positive path then died on a bare
# `[[ ]]` under `set -e` with no message, and nobody noticed for a release.
PLUGIN_JSON="$ROOT/plugins/macdoc/.claude-plugin/plugin.json"
PINNED_SHA=$(grep -oE '"binary_sha256"[[:space:]]*:[[:space:]]*"[0-9a-f]{64}"' "$PLUGIN_JSON" | grep -oE '[0-9a-f]{64}')
WANT_VERSION=$(grep -oE '"binary_version"[[:space:]]*:[[:space:]]*"[^"]+"' "$PLUGIN_JSON" | sed -E 's/.*"([^"]+)"$/\1/')
[[ ${#PINNED_SHA} -eq 64 && -n "$WANT_VERSION" ]] \
    || { echo "FAIL: cannot read binary_sha256 / binary_version from $PLUGIN_JSON" >&2; exit 1; }
mkdir -p "$FAKE_PATH" "$INSTALL_DIR"

for tool in uname awk codesign curl; do
    cat > "$FAKE_PATH/$tool" <<EOF
#!/bin/bash
echo fake-$tool >> "\$EVENT_LOG"
exit 22
EOF
    chmod +x "$FAKE_PATH/$tool"
done

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
chmod +x "$RESIDENT" "$UNSIGNED_CANDIDATE"

run_hook() {
    : > "$EVENT_LOG"
    EVENT_LOG="$EVENT_LOG" \
    MACDOC_CODESIGN_BIN="$FAKE_PATH/codesign" \
    MACDOC_CURL_BIN="$FAKE_PATH/curl" \
    MACDOC_INSTALL_DIR="$INSTALL_DIR" \
    HTTPS_PROXY="http://127.0.0.1:9" \
    ALL_PROXY="http://127.0.0.1:9" \
    NO_PROXY="" \
    PATH="$FAKE_PATH:$PATH" \
    bash "$HOOK" >/dev/null 2>"$HOOK_STDERR"
}

assert_no_hostile_tool_or_binary() {
    if [ -s "$EVENT_LOG" ]; then
        echo "FAIL: SessionStart executed a hostile PATH/env tool or binary: $(tr '\n' ' ' < "$EVENT_LOG")" >&2
        exit 1
    fi
}

# A rejected resident must ignore hostile command overrides, never execute,
# and fail soft when the real download cannot connect.
echo 0.7.0 > "$GUARD"
run_hook
assert_no_hostile_tool_or_binary
grep -q 'resident binary was not executed' "$HOOK_STDERR"

# Candidate integrity functions are the same fixed-tool functions sourced by
# production. Test each negative gate independently.
# Test derives the checked-out plugin root.
# shellcheck disable=SC1090,SC1091
. "$VERIFY_LIB"

set +e
macdoc_verify_candidate "$UNSIGNED_CANDIDATE" 0000000000000000000000000000000000000000000000000000000000000000 "$PINNED_SHA" "$REQUIREMENT"
rc_asset_pin=$?
macdoc_verify_candidate "$UNSIGNED_CANDIDATE" "$PINNED_SHA" "$PINNED_SHA" "$REQUIREMENT"
rc_bytes=$?
unsigned_sha=$(/usr/bin/shasum -a 256 "$UNSIGNED_CANDIDATE" | /usr/bin/awk '{print $1}')
macdoc_verify_candidate "$UNSIGNED_CANDIDATE" "$unsigned_sha" "$unsigned_sha" "$REQUIREMENT"
rc_signature=$?
set -e

[[ "$rc_asset_pin" -eq 10 ]]
[[ "$rc_bytes" -eq 11 ]]
[[ "$rc_signature" -eq 12 ]]

# Full positive coverage needs a real Team-signed fixture. Mandatory hostile
# cases above still run on CI machines without one.
if ! /usr/bin/codesign --verify --strict -R "$REQUIREMENT" "$SIGNED_FIXTURE" 2>/dev/null; then
    echo "SKIP: positive signed-fixture cases (set MACDOC_SIGNED_FIXTURE)"
    echo "PASS: hostile resident/candidate paths were rejected"
    exit 0
fi

signed_sha=$(/usr/bin/shasum -a 256 "$SIGNED_FIXTURE" | /usr/bin/awk '{print $1}')
if [[ "$signed_sha" != "$PINNED_SHA" ]]; then
    echo "SKIP: positive signed-fixture cases — $SIGNED_FIXTURE is not the pinned v$WANT_VERSION release"
    echo "      (fixture sha256 $signed_sha, pinned $PINNED_SHA; set MACDOC_SIGNED_FIXTURE to the downloaded release binary)"
    echo "PASS: hostile resident/candidate paths were rejected"
    exit 0
fi
macdoc_verify_candidate "$SIGNED_FIXTURE" "$PINNED_SHA" "$PINNED_SHA" "$REQUIREMENT"

# Verified resident + matching sidecar is a zero-network, zero-execution path.
cp "$SIGNED_FIXTURE" "$RESIDENT"
chmod +x "$RESIDENT"
echo "$WANT_VERSION" > "$GUARD"
run_hook
assert_no_hostile_tool_or_binary

echo "PASS: SessionStart uses fixed trust tools and verifies exact candidate bytes"
