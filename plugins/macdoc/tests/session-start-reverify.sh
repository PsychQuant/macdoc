#!/bin/bash

set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
HOOK="$ROOT/plugins/macdoc/hooks/session-start.sh"
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/macdoc-session-start-test.XXXXXX")
trap 'rm -rf "$TEST_ROOT"' EXIT

FAKE_PATH="$TEST_ROOT/fake-path"
INSTALL_DIR="$TEST_ROOT/install"
EVENT_LOG="$TEST_ROOT/events.log"
mkdir -p "$FAKE_PATH" "$INSTALL_DIR"

cat > "$FAKE_PATH/uname" <<'EOF'
#!/bin/bash
echo arm64
EOF

cat > "$FAKE_PATH/codesign" <<'EOF'
#!/bin/bash
echo codesign >> "$EVENT_LOG"
exit "${FAKE_CODESIGN_EXIT:-0}"
EOF

cat > "$FAKE_PATH/curl" <<'EOF'
#!/bin/bash
echo curl >> "$EVENT_LOG"
exit 22
EOF

cat > "$INSTALL_DIR/macdoc" <<'EOF'
#!/bin/bash
echo binary >> "$EVENT_LOG"
echo 'macdoc 0.7.0'
EOF

chmod +x "$FAKE_PATH/uname" "$FAKE_PATH/codesign" "$FAKE_PATH/curl" "$INSTALL_DIR/macdoc"

run_hook() {
    : > "$EVENT_LOG"
    EVENT_LOG="$EVENT_LOG" \
    FAKE_CODESIGN_EXIT="$1" \
    MACDOC_INSTALL_DIR="$INSTALL_DIR" \
    PATH="$FAKE_PATH:$PATH" \
    bash "$HOOK" >/dev/null 2>&1
}

run_hook 1
if grep -qx binary "$EVENT_LOG"; then
    echo "FAIL: signature-rejected resident binary was executed" >&2
    exit 1
fi
[[ "$(head -1 "$EVENT_LOG")" == "codesign" ]] || {
    echo "FAIL: resident signature verification was not the first action" >&2
    exit 1
}
grep -qx curl "$EVENT_LOG" || {
    echo "FAIL: rejected resident binary did not force a download attempt" >&2
    exit 1
}

run_hook 0
first_event=$(sed -n '1p' "$EVENT_LOG")
second_event=$(sed -n '2p' "$EVENT_LOG")
[[ "$first_event" == "codesign" && "$second_event" == "binary" ]] || {
    echo "FAIL: verified fast path must verify before executing --version; got: $(tr '\n' ' ' < "$EVENT_LOG")" >&2
    exit 1
}
if grep -qx curl "$EVENT_LOG"; then
    echo "FAIL: verified matching binary unexpectedly hit the network" >&2
    exit 1
fi

echo "PASS: SessionStart verifies resident binary before execution"
