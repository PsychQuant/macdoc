#!/bin/bash

set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
HOOK="$ROOT/plugins/macdoc/hooks/session-start.sh"
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/macdoc-session-start-test.XXXXXX")
trap 'rm -rf "$TEST_ROOT"' EXIT

FAKE_PATH="$TEST_ROOT/fake-path"
INSTALL_DIR="$TEST_ROOT/install"
EVENT_LOG="$TEST_ROOT/events.log"
RESIDENT="$INSTALL_DIR/macdoc"
GUARD="$INSTALL_DIR/.macdoc.installed_version"
CANDIDATE="$TEST_ROOT/candidate-macdoc"
mkdir -p "$FAKE_PATH" "$INSTALL_DIR"

cat > "$FAKE_PATH/uname" <<'EOF'
#!/bin/bash
echo arm64
EOF

cat > "$FAKE_PATH/codesign" <<'EOF'
#!/bin/bash
target=""
for target in "$@"; do :; done
echo "codesign:$target" >> "$EVENT_LOG"
if [ "$target" = "$RESIDENT_PATH" ]; then
    exit "${RESIDENT_CODESIGN_EXIT:-0}"
fi
exit "${DOWNLOAD_CODESIGN_EXIT:-0}"
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
    shasum -a 256 "$DOWNLOAD_SOURCE" | awk '{print $1}'
fi
EOF

cat > "$RESIDENT" <<'EOF'
#!/bin/bash
echo resident-executed >> "$EVENT_LOG"
echo 'macdoc 0.7.0'
EOF

cat > "$CANDIDATE" <<'EOF'
#!/bin/bash
echo candidate-executed >> "$EVENT_LOG"
echo 'macdoc 0.7.0'
EOF

chmod +x "$FAKE_PATH/uname" "$FAKE_PATH/codesign" "$FAKE_PATH/curl" "$RESIDENT" "$CANDIDATE"

run_hook() {
    : > "$EVENT_LOG"
    EVENT_LOG="$EVENT_LOG" \
    RESIDENT_PATH="$RESIDENT" \
    RESIDENT_CODESIGN_EXIT="$1" \
    DOWNLOAD_CODESIGN_EXIT="$2" \
    FAKE_CURL_MODE="$3" \
    DOWNLOAD_SOURCE="$CANDIDATE" \
    MACDOC_CODESIGN_BIN="$FAKE_PATH/codesign" \
    MACDOC_INSTALL_DIR="$INSTALL_DIR" \
    PATH="$FAKE_PATH:$PATH" \
    bash "$HOOK" >/dev/null 2>&1
}

# A rejected resident must not execute, even if it prints the pinned version.
rm -f "$GUARD"
run_hook 1 0 fail
grep -qx "codesign:$RESIDENT" "$EVENT_LOG"
! grep -q 'executed' "$EVENT_LOG"
[[ "$(grep -c '^curl-download$' "$EVENT_LOG")" -eq 1 ]] || {
    echo "FAIL: rejected resident must force exactly one download attempt" >&2
    exit 1
}

# A verified resident with a matching installer sidecar takes a zero-network
# fast path without executing the binary during SessionStart.
echo 0.7.0 > "$GUARD"
run_hook 0 0 fail
[[ "$(wc -l < "$EVENT_LOG" | tr -d ' ')" -eq 1 ]] || {
    echo "FAIL: verified matching resident should only be signature-checked; got: $(tr '\n' ' ' < "$EVENT_LOG")" >&2
    exit 1
}
grep -qx "codesign:$RESIDENT" "$EVENT_LOG"
! grep -q 'executed\|curl-' "$EVENT_LOG"

# A rejected resident can be replaced only by bytes whose release digest and
# signature both pass. The candidate is installed but never executed by hook.
run_hook 1 0 success
grep -qx "codesign:$RESIDENT" "$EVENT_LOG"
grep -qx curl-download "$EVENT_LOG"
grep -qx curl-sha "$EVENT_LOG"
[[ "$(grep -c '^codesign:' "$EVENT_LOG")" -eq 2 ]]
! grep -q 'executed' "$EVENT_LOG"
cmp -s "$RESIDENT" "$CANDIDATE"
[[ "$(cat "$GUARD")" = "0.7.0" ]]

echo "PASS: SessionStart never executes resident binary and installs only a verified candidate"
