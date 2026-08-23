#!/bin/bash

set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
SOURCE_SCRIPT="$ROOT/scripts/release-cli.sh"
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/macdoc-release-source-test.XXXXXX")
trap 'rm -rf "$TEST_ROOT"' EXIT

REPO="$TEST_ROOT/repo"
FAKE_PATH="$TEST_ROOT/fake-path"
EVENT_LOG="$TEST_ROOT/events.log"
mkdir -p "$REPO/scripts" "$FAKE_PATH"
cp "$SOURCE_SCRIPT" "$REPO/scripts/release-cli.sh"
echo original > "$REPO/source.txt"
echo '.build/' > "$REPO/.gitignore"

git -C "$REPO" init -q
git -C "$REPO" config user.name test
git -C "$REPO" config user.email test@example.invalid
git -C "$REPO" add .gitignore scripts/release-cli.sh source.txt
git -C "$REPO" commit -qm baseline
BASELINE_HEAD=$(git -C "$REPO" rev-parse HEAD)
git init -q --bare "$TEST_ROOT/origin.git"
git -C "$REPO" remote add origin "$TEST_ROOT/origin.git"

cat > "$FAKE_PATH/git" <<'EOF'
#!/bin/bash
if [ "${1:-}" = "ls-remote" ]; then exit 0; fi
exec /usr/bin/git "$@"
EOF

cat > "$FAKE_PATH/swift" <<'EOF'
#!/bin/bash
echo swift-build >> "$EVENT_LOG"
case "${MUTATION_MODE:-none}" in
    file) echo changed-during-build >> source.txt ;;
    head)
        echo committed-during-build >> source.txt
        /usr/bin/git add source.txt
        /usr/bin/git commit -qm committed-during-build
        ;;
esac
mkdir -p .build/release
cat > .build/release/macdoc <<'BIN'
#!/bin/bash
echo test-binary
BIN
chmod +x .build/release/macdoc
EOF

cat > "$FAKE_PATH/codesign" <<'EOF'
#!/bin/bash
echo codesign >> "$EVENT_LOG"
exit 0
EOF

cat > "$FAKE_PATH/xcrun" <<'EOF'
#!/bin/bash
echo "xcrun:$*" >> "$EVENT_LOG"
if [ "${2:-}" = "submit" ]; then echo 'status: Accepted'; fi
exit 0
EOF

cat > "$FAKE_PATH/lipo" <<'EOF'
#!/bin/bash
echo arm64
EOF

cat > "$FAKE_PATH/ditto" <<'EOF'
#!/bin/bash
last=""
for last in "$@"; do :; done
: > "$last"
EOF

cat > "$FAKE_PATH/gh" <<'EOF'
#!/bin/bash
if [ "${1:-}" = "release" ] && [ "${2:-}" = "view" ]; then exit 1; fi
if [ "${1:-}" = "release" ] && [ "${2:-}" = "create" ]; then
    echo "gh-release-create:$*" >> "$EVENT_LOG"
    exit 0
fi
exit 1
EOF

chmod +x "$FAKE_PATH"/*

run_release() {
    : > "$EVENT_LOG"
    set +e
    (
        cd "$REPO"
        EVENT_LOG="$EVENT_LOG" MUTATION_MODE="$1" PATH="$FAKE_PATH:$PATH" \
            bash scripts/release-cli.sh 9.9.9
    ) >"$TEST_ROOT/output-$1.log" 2>&1
    RELEASE_RC=$?
    set -e
}

run_release file
[[ "$RELEASE_RC" -eq 3 ]] || {
    echo "FAIL: source mutation must stop release with exit 3; got $RELEASE_RC" >&2
    cat "$TEST_ROOT/output-file.log" >&2
    exit 1
}

if grep -q '^codesign$\|notarytool submit\|^gh-release-create:' "$EVENT_LOG"; then
    echo "FAIL: signing/notarization/upload ran after source mutation" >&2
    cat "$EVENT_LOG" >&2
    exit 1
fi
grep -q 'working tree changed during the build' "$TEST_ROOT/output-file.log"
/usr/bin/git -C "$REPO" checkout -q -- source.txt

run_release none
[[ "$RELEASE_RC" -eq 0 ]]
grep -q '^codesign$' "$EVENT_LOG"
grep -q "^gh-release-create:.*--target $BASELINE_HEAD" "$EVENT_LOG"

run_release head
[[ "$RELEASE_RC" -eq 3 ]]
if grep -q '^codesign$\|notarytool submit\|^gh-release-create:' "$EVENT_LOG"; then
    echo "FAIL: signing/notarization/upload ran after HEAD changed" >&2
    cat "$EVENT_LOG" >&2
    exit 1
fi
grep -q 'working tree changed during the build' "$TEST_ROOT/output-head.log"

echo "PASS: release refuses source/HEAD mutation before signing and pins release target"
