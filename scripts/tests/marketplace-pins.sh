#!/bin/bash
# Tests for scripts/marketplace-pins.sh (macdoc#279).
#
# Every case builds throw-away git repositories under a temp dir: a bare
# "origin" for the marketplace repo, bare upstream repos standing in for the
# MCP binary repos, and clones of them. The script under test is copied into
# the fixture repo and run from there, so nothing here can touch the real
# checkout. `gh` and `claude` are stub scripts selected through
# MARKETPLACE_PINS_GH / MARKETPLACE_PINS_CLAUDE; installed-version records are
# read from temp dirs selected through MARKETPLACE_PINS_CACHE_ROOT /
# MARKETPLACE_PINS_BIN_DIR. No network access.

set -uo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
SCRIPT_UNDER_TEST="$ROOT/scripts/marketplace-pins.sh"
T=$(mktemp -d "${TMPDIR:-/tmp}/marketplace-pins-test.XXXXXX")
trap 'rm -rf "$T"' EXIT

# Isolate git from the developer's global/system config (signing, hooks,
# default branch) and give it a neutral identity.
export GIT_CONFIG_GLOBAL=/dev/null
export GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.invalid
export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.invalid
export MARKETPLACE_PINS_TODAY=2026-01-02
export MARKETPLACE_PINS_GIT_RUNNING=no

# Guard: the real checkout must look exactly the same after the run.
GUARD_HEAD=$(git -C "$ROOT" rev-parse HEAD)
GUARD_STATUS=$(git -C "$ROOT" status --porcelain=v1 --untracked-files=all)

PASS=0
FAIL=0
FAILED_NAMES=()

ok() { PASS=$((PASS + 1)); echo "  ok   $1"; }
not_ok() {
    FAIL=$((FAIL + 1)); FAILED_NAMES+=("$1"); echo "  FAIL $1"
    if [ -n "${2:-}" ]; then printf '%s\n' "$2" | sed 's/^/       /'; fi
}
check() {   # check <name> <command...>: passes when the command succeeds
    local name=$1; shift
    if "$@" >/dev/null 2>&1; then ok "$name"; else not_ok "$name" "command failed: $*"; fi
}
check_eq() {   # check_eq <name> <expected> <actual>
    if [ "$2" = "$3" ]; then ok "$1"; else not_ok "$1" "expected: $2
actual:   $3"; fi
}
check_contains() {   # check_contains <name> <haystack> <needle>
    case "$2" in
        *"$3"*) ok "$1" ;;
        *) not_ok "$1" "missing: $3
in output:
$2" ;;
    esac
}
check_not_contains() {
    case "$2" in
        *"$3"*) not_ok "$1" "unexpected: $3" ;;
        *) ok "$1" ;;
    esac
}

# The expression is always a literal written in this file, never input data.
json_get() {   # json_get <json> <python expression over `d`>
    python3 -I -c 'import json,sys; d=json.loads(sys.argv[1]); print(eval(sys.argv[2]))' "$1" "$2"
}

# --------------------------------------------------------------------------
# Stubs
# --------------------------------------------------------------------------
STUB_BIN="$T/stub-bin"
mkdir -p "$STUB_BIN"
export GH_STUB_DB="$T/gh-db"
export GH_STUB_LOG="$T/gh.log"
export CLAUDE_STUB_LOG="$T/claude.log"
: > "$GH_STUB_LOG"; : > "$CLAUDE_STUB_LOG"

# gh stub. Release data lives in $GH_STUB_DB/<owner>/<repo>/:
#   latest                         tag name of the latest release
#   releases/<tag>/target          target_commitish
#   releases/<tag>/assets/<name>   asset content
# Release ids are the tag names; asset ids are "<tag>:<name>".
cat > "$STUB_BIN/gh" <<'EOF'
#!/bin/bash
echo "$*" >> "$GH_STUB_LOG"
[ "${GH_STUB_FAIL:-0}" = 1 ] && { echo "gh: stub failure" >&2; exit 1; }
[ "${1:-}" = api ] || { echo "gh stub: unsupported: $*" >&2; exit 64; }
path=${2:-}
case "$path" in
    repos/*/*/releases/latest)
        r=${path#repos/}; r=${r%/releases/latest}
        f="$GH_STUB_DB/$r/latest"; [ -f "$f" ] || { echo 'HTTP 404' >&2; exit 1; }
        cat "$f" ;;
    repos/*/*/releases/tags/*)
        r=${path#repos/}; tag=${r##*/releases/tags/}; r=${r%/releases/tags/*}
        d="$GH_STUB_DB/$r/releases/$tag"; [ -d "$d" ] || { echo 'HTTP 404' >&2; exit 1; }
        printf '%s\t%s\n' "$tag" "$(cat "$d/target" 2>/dev/null)" ;;
    repos/*/*/releases/assets/*)
        r=${path#repos/}; aid=${r##*/releases/assets/}; r=${r%/releases/assets/*}
        tag=${aid%%:*}; name=${aid#*:}
        f="$GH_STUB_DB/$r/releases/$tag/assets/$name"; [ -f "$f" ] || { echo 'HTTP 404' >&2; exit 1; }
        cat "$f" ;;
    repos/*/*/releases/*/assets)
        r=${path#repos/}; r=${r%/assets}; id=${r##*/releases/}; r=${r%/releases/*}
        d="$GH_STUB_DB/$r/releases/$id"; [ -d "$d" ] || { echo 'HTTP 404' >&2; exit 1; }
        for a in "$d"/assets/*; do [ -e "$a" ] && printf '%s:%s\t%s\n' "$id" "${a##*/}" "${a##*/}"; done
        exit 0 ;;
    *) echo "gh stub: unsupported path $path" >&2; exit 64 ;;
esac
EOF
cat > "$STUB_BIN/claude" <<'EOF'
#!/bin/bash
echo "$*" >> "$CLAUDE_STUB_LOG"
[ "${CLAUDE_STUB_FAIL:-0}" = 1 ] && { echo "claude: stub failure" >&2; exit 1; }
exit 0
EOF
chmod +x "$STUB_BIN/gh" "$STUB_BIN/claude"
export MARKETPLACE_PINS_GH="$STUB_BIN/gh"
export MARKETPLACE_PINS_CLAUDE="$STUB_BIN/claude"

SHA_OLD=1111111111111111111111111111111111111111111111111111111111111111
SHA_NEW=2222222222222222222222222222222222222222222222222222222222222222

gh_release() {   # gh_release <owner/repo> <tag> <asset names...>
    local d="$GH_STUB_DB/$1/releases/$2"; shift 2
    mkdir -p "$d/assets"; echo main > "$d/target"
    local a; for a in "$@"; do echo "content of $a" > "$d/assets/$a"; done
}
gh_latest() { mkdir -p "$GH_STUB_DB/$1"; echo "$2" > "$GH_STUB_DB/$1/latest"; }

# --------------------------------------------------------------------------
# Fixture
# --------------------------------------------------------------------------
# Upstream binary repos (shared by all cases; read-only after creation).
UP="$T/upstream"
make_upstream() {   # make_upstream <name> <tag...>; last tag is annotated
    local name=$1; shift
    local w="$UP/PsychQuant/$name.work"
    git init -q -b main "$w"
    local tag i=0 n=$#
    for tag in "$@"; do
        i=$((i + 1))
        echo "$tag" > "$w/version"; git -C "$w" add version; git -C "$w" commit -qm "release $tag"
        if [ "$i" = "$n" ]; then git -C "$w" tag -a -m "$tag" "$tag"; else git -C "$w" tag "$tag"; fi
    done
    git clone -q --bare "$w" "$UP/PsychQuant/$name.git"
}
make_upstream che-word-mcp v4.9.0 v4.10.0
make_upstream che-pdf-mcp v0.2.0 v0.3.0
peeled() { git -C "$UP/PsychQuant/$1.git" rev-parse "$2^{commit}"; }
WORD_V4_9=$(peeled che-word-mcp v4.9.0)
WORD_V4_10=$(peeled che-word-mcp v4.10.0)
PDF_V0_2=$(peeled che-pdf-mcp v0.2.0)

write_json() {   # write_json <path> <python literal>; same serialisation as the repo
    mkdir -p "$(dirname "$1")"
    python3 -I -c 'import ast,json,sys; open(sys.argv[1],"w",encoding="utf-8").write(json.dumps(ast.literal_eval(sys.argv[2]),indent=2,ensure_ascii=False)+"\n")' "$1" "$2"
}

# build_fixture <dir>: creates <dir>/origin.git, <dir>/seed (pushes to
# origin) and <dir>/clone (the checkout under test). Resets gh data and the
# installed-version records so that everything is consistent and up to date.
build_fixture() {
    local F=$1 S
    mkdir -p "$F"; S="$F/seed"
    git init -q -b main "$S"
    write_json "$S/.claude-plugin/marketplace.json" "{
      'name': 'macdoc',
      'plugins': [
        {'name': 'che-word-mcp', 'version': '4.9.0', 'description': 'Word ── 測試', 'source': './plugins/che-word-mcp', 'binary_version': '4.9.0'},
        {'name': 'macdoc', 'version': '1.14.0', 'source': './plugins/macdoc', 'binary_version': '0.17.0', 'binary_sha256': '$SHA_OLD'},
        {'name': 'che-pdf-mcp', 'version': '0.1.3', 'source': './plugins/che-pdf-mcp', 'binary_version': '0.2.0'},
        {'name': 'docflow', 'version': '1.0.1', 'source': './plugins/docflow'}
      ]}"
    local p
    for p in che-word-mcp che-pdf-mcp; do
        local bin=CheWordMCP; [ "$p" = che-pdf-mcp ] && bin=ChePDFMCP
        mkdir -p "$S/plugins/$p/bin"
        printf '#!/bin/bash\nREPO="PsychQuant/%s"\nBINARY_NAME="%s"\n' "$p" "$bin" > "$S/plugins/$p/bin/$p-wrapper.sh"
    done
    mkdir -p "$S/plugins/macdoc/hooks" "$S/plugins/docflow/.claude-plugin"
    printf '#!/bin/bash\nREPO="PsychQuant/macdoc"\nBINARY_NAME="macdoc"\n' > "$S/plugins/macdoc/hooks/session-start.sh"
    # plugin.json files are hand-formatted like the real ones (not re-serialised).
    mkdir -p "$S/plugins/che-word-mcp/.claude-plugin" "$S/plugins/che-pdf-mcp/.claude-plugin" "$S/plugins/macdoc/.claude-plugin"
    cat > "$S/plugins/che-word-mcp/.claude-plugin/plugin.json" <<'J'
{
  "name": "che-word-mcp",
  "description": "Word",
  "version": "4.9.0",
  "binary_version": "4.9.0",
  "keywords": [
    "mcp"
  ]
}
J
    cat > "$S/plugins/che-pdf-mcp/.claude-plugin/plugin.json" <<'J'
{
  "name": "che-pdf-mcp",
  "version": "0.1.3",
  "binary_version": "0.2.0"
}
J
    cat > "$S/plugins/macdoc/.claude-plugin/plugin.json" <<J
{
  "name": "macdoc",
  "version": "1.14.0",
  "binary_version": "0.17.0",
  "binary_sha256": "$SHA_OLD"
}
J
    echo '{"name": "docflow", "version": "1.0.1"}' > "$S/plugins/docflow/.claude-plugin/plugin.json"
    for p in che-word-mcp che-pdf-mcp; do
        printf '# Changelog\n\nIntro.\n\n## [0.0.1] - 2025-01-01\n\n### Changed\n\n- old entry\n' > "$S/plugins/$p/CHANGELOG.md"
    done
    printf '# Changelog\n\n## [Unreleased]\n\n### Added\n\n- pending\n\n## [1.14.0] - 2025-01-01\n\n- old entry\n' > "$S/plugins/macdoc/CHANGELOG.md"
    mkdir -p "$S/docs" "$S/scripts"
    printf '# Marketplace pin history\n\n| 日期 | plugin | 舊 binary | 新 binary | release commit |\n|---|---|---|---|---|\n' > "$S/docs/marketplace-pin-history.md"
    cp "$SCRIPT_UNDER_TEST" "$S/scripts/marketplace-pins.sh" 2>/dev/null || echo 'exit 99' > "$S/scripts/marketplace-pins.sh"
    printf '[submodule "mcp/che-word-mcp"]\n\tpath = mcp/che-word-mcp\n\turl = %s\n[submodule "mcp/che-pdf-mcp"]\n\tpath = mcp/che-pdf-mcp\n\turl = %s\n' \
        "$UP/PsychQuant/che-word-mcp.git" "$UP/PsychQuant/che-pdf-mcp.git" > "$S/.gitmodules"
    git -C "$S" add -A
    git -C "$S" update-index --add --cacheinfo "160000,$WORD_V4_9,mcp/che-word-mcp"
    git -C "$S" update-index --add --cacheinfo "160000,$PDF_V0_2,mcp/che-pdf-mcp"
    git -C "$S" commit -qm baseline
    git -C "$S" tag v0.17.0
    echo cli > "$S/cli.txt"; git -C "$S" add cli.txt; git -C "$S" commit -qm "cli 0.18.0"
    git -C "$S" tag -a -m v0.18.0 v0.18.0
    git -C "$S" reset -q --hard HEAD~1   # main stays at baseline; the tag keeps the cli commit
    git init -q --bare -b main "$F/origin.git"
    git -C "$S" remote add origin "$F/origin.git"
    git -C "$S" push -q origin main --tags
    git -C "$S" branch -q -u origin/main
    git clone -q "$F/origin.git" "$F/clone" 2>/dev/null

    # gh data: every pin equals the latest release, all assets present.
    rm -rf "$GH_STUB_DB"
    gh_release PsychQuant/che-word-mcp v4.9.0 CheWordMCP CheWordMCP.sha256
    gh_release PsychQuant/che-word-mcp v4.10.0 CheWordMCP CheWordMCP.sha256
    gh_release PsychQuant/che-pdf-mcp v0.2.0 ChePDFMCP ChePDFMCP.sha256
    gh_release PsychQuant/che-pdf-mcp v0.3.0 ChePDFMCP ChePDFMCP.sha256
    gh_release PsychQuant/macdoc v0.17.0 macdoc macdoc.sha256
    gh_release PsychQuant/macdoc v0.18.0 macdoc macdoc.sha256
    printf '%s  macdoc\n' "$SHA_NEW" > "$GH_STUB_DB/PsychQuant/macdoc/releases/v0.18.0/assets/macdoc.sha256"
    gh_latest PsychQuant/che-word-mcp v4.9.0
    gh_latest PsychQuant/che-pdf-mcp v0.2.0
    gh_latest PsychQuant/macdoc v0.17.0

    # Installed-version records matching the pins.
    export MARKETPLACE_PINS_CACHE_ROOT="$F/cache"
    export MARKETPLACE_PINS_BIN_DIR="$F/home-bin"
    mkdir -p "$F/cache/che-word-mcp/.bin-cache" "$F/cache/che-pdf-mcp/.bin-cache" "$F/cache/macdoc" "$F/home-bin"
    echo 4.9.0 > "$F/cache/che-word-mcp/.bin-cache/.CheWordMCP.version"
    echo 0.2.0 > "$F/cache/che-pdf-mcp/.bin-cache/.ChePDFMCP.version"
    echo 0.17.0 > "$F/home-bin/.macdoc.installed_version"
    printf '#!/bin/sh\n' > "$F/home-bin/macdoc"; chmod +x "$F/home-bin/macdoc"
    : > "$GH_STUB_LOG"; : > "$CLAUDE_STUB_LOG"
}

# Push <n> new commits to origin from the seed (the clone falls behind).
seed_push() {   # seed_push <fixture> <n>
    local i
    for i in $(seq 1 "$2"); do
        echo "upstream $i" >> "$1/seed/upstream.txt"
        git -C "$1/seed" add upstream.txt; git -C "$1/seed" commit -qm "upstream $i"
    done
    git -C "$1/seed" push -q origin main
}
# populate_submodule <fixture>: check out the che-word-mcp submodule at v4.9.0
# with an untracked file in it, and turn on submodule.recurse in the clone, so
# that any command that recursed into it would visibly change it.
populate_submodule() {
    local s="$1/clone/mcp/che-word-mcp"
    rmdir "$s" 2>/dev/null || true
    git clone -q "$UP/PsychQuant/che-word-mcp.git" "$s" 2>/dev/null
    git -C "$s" checkout -q v4.9.0 2>/dev/null
    echo wip > "$s/wip.txt"
    git -C "$1/clone" config submodule.recurse true
}
local_commit() {   # local_commit <fixture> <file>
    echo "local" >> "$1/clone/$2"; git -C "$1/clone" add "$2"; git -C "$1/clone" commit -qm "local $2"
}

pins() {   # pins <fixture> <args...>: run the copy inside the fixture clone
    local F=$1; shift
    # Executed directly so the shebang's interpreter (/bin/bash, 3.2 on macOS)
    # is the one under test, as with the Makefile targets.
    (cd "$F/clone" && ./scripts/marketplace-pins.sh "$@")
}

# Snapshot of everything `update` could touch: HEAD, index, every file.
snapshot() {
    local c=$1
    git -C "$c" rev-parse HEAD
    git -C "$c" ls-files -s | shasum
    git -C "$c" status --porcelain=v1 --untracked-files=all
    (cd "$c" && find . -path ./.git -prune -o -type f -print0 | sort -z | xargs -0 shasum)
}

run_case() { echo "== $1"; }

# ==========================================================================
# Checkout state classifier (via status --json)
# ==========================================================================
checkout_state() {   # checkout_state <fixture>: prints "state behind ahead equiv"
    local out
    out=$(pins "$1" status --json 2>/dev/null)
    json_get "$out" '" ".join(str(d["checkout"].get(k)) for k in ("state","behind","ahead","patch_equivalent"))' 2>/dev/null || echo "no-json"
}

run_case "classifier: in-sync"
F="$T/c-sync"; build_fixture "$F"
check_eq "in-sync" "in-sync 0 0 None" "$(checkout_state "$F")"

run_case "classifier: behind-only"
F="$T/c-behind"; build_fixture "$F"; seed_push "$F" 2
check_eq "behind 2" "behind 2 0 None" "$(checkout_state "$F")"

run_case "classifier: ahead-only"
F="$T/c-ahead"; build_fixture "$F"; local_commit "$F" a.txt
check_eq "ahead 1" "ahead 0 1 None" "$(checkout_state "$F")"

run_case "classifier: diverged with a rewritten (patch-equivalent) commit"
F="$T/c-div"; build_fixture "$F"
echo x > "$F/seed/x.txt"; git -C "$F/seed" add x.txt; git -C "$F/seed" commit -qm "x"
X=$(git -C "$F/seed" rev-parse HEAD)
git -C "$F/clone" fetch -q "$F/seed" main
GIT_COMMITTER_DATE="2001-01-01T00:00:00" git -C "$F/clone" cherry-pick -x "$X" >/dev/null
local_commit "$F" z.txt
echo y > "$F/seed/y.txt"; git -C "$F/seed" add y.txt; git -C "$F/seed" commit -qm "y"
echo w > "$F/seed/w.txt"; git -C "$F/seed" add w.txt; git -C "$F/seed" commit -qm "w"
git -C "$F/seed" push -q origin main
check_eq "diverged behind 3 ahead 2, 1 equivalent" "diverged 3 2 1" "$(checkout_state "$F")"

run_case "classifier: in-progress operation outranks everything"
F="$T/c-prog"; build_fixture "$F"; seed_push "$F" 1
mkdir "$(git -C "$F/clone" rev-parse --absolute-git-dir)/rebase-merge"
touch "$(git -C "$F/clone" rev-parse --absolute-git-dir)/index.lock"
check_eq "in-progress" "in-progress None None None" "$(checkout_state "$F")"

run_case "classifier: index.lock"
F="$T/c-lock"; build_fixture "$F"
touch "$(git -C "$F/clone" rev-parse --absolute-git-dir)/index.lock"
OUT=$(pins "$F" status --json 2>/dev/null)
check_eq "locked" "locked" "$(json_get "$OUT" 'd["checkout"]["state"]' 2>/dev/null)"
check_eq "lock reports git not running" "False" "$(json_get "$OUT" 'd["checkout"]["lock"]["git_running"]' 2>/dev/null)"
check "lock reports mtime" test -n "$(json_get "$OUT" 'd["checkout"]["lock"]["mtime"]' 2>/dev/null)"
check "classifier leaves the lock in place" test -f "$(git -C "$F/clone" rev-parse --absolute-git-dir)/index.lock"

run_case "classifier: no upstream"
F="$T/c-noup"; build_fixture "$F"; git -C "$F/clone" checkout -q -b local-only
check_eq "no-upstream" "no-upstream None None None" "$(checkout_state "$F")"

run_case "classifier: fetch fails"
F="$T/c-fetch"; build_fixture "$F"; git -C "$F/clone" remote set-url origin "$T/does-not-exist.git"
OUT=$(pins "$F" status --json 2>/dev/null); RC=$?
check_eq "fetch failure -> unknown" "unknown" "$(json_get "$OUT" 'd["checkout"]["state"]' 2>/dev/null)"
check_eq "status exit 2 when checkout state unknown" 2 "$RC"

# ==========================================================================
# status
# ==========================================================================
run_case "status: everything consistent and current"
F="$T/s-ok"; build_fixture "$F"
OUT=$(pins "$F" status 2>&1); RC=$?
check_eq "exit 0" 0 "$RC"
check_contains "lists che-word-mcp" "$OUT" "che-word-mcp"
check_contains "lists macdoc" "$OUT" "macdoc"
check_not_contains "skips docflow" "$OUT" "docflow"
check_contains "says checkout in sync" "$OUT" "同步"

run_case "status: pin behind release, inconsistent entry, missing install record"
F="$T/s-bad"; build_fixture "$F"
gh_latest PsychQuant/che-word-mcp v4.10.0
python3 -I - "$F/clone/.claude-plugin/marketplace.json" <<'PY'
import json, sys
p = sys.argv[1]; d = json.load(open(p, encoding="utf-8"))
for e in d["plugins"]:
    if e["name"] == "che-pdf-mcp":
        e["version"] = "0.1.2"
open(p, "w", encoding="utf-8").write(json.dumps(d, indent=2, ensure_ascii=False) + "\n")
PY
git -C "$F/clone" commit -qam "inconsistent"; git -C "$F/clone" push -q origin main
rm "$F/home-bin/.macdoc.installed_version"
OUT=$(pins "$F" status 2>&1); RC=$?
check_eq "exit 10" 10 "$RC"
check_contains "shows latest 4.10.0" "$OUT" "4.10.0"
check_contains "shows unknown install" "$OUT" "未知"
JOUT=$(pins "$F" status --json 2>/dev/null)
check_eq "json exit_code 10" 10 "$(json_get "$JOUT" 'd["exit_code"]' 2>/dev/null)"
check_eq "json word latest" "4.10.0" "$(json_get "$JOUT" '[p for p in d["plugins"] if p["name"]=="che-word-mcp"][0]["latest_release"]' 2>/dev/null)"
check_contains "json word flagged behind" "$(json_get "$JOUT" '[p for p in d["plugins"] if p["name"]=="che-word-mcp"][0]["problems"]' 2>/dev/null)" "pin-behind-release"
check_contains "json pdf flagged inconsistent" "$(json_get "$JOUT" '[p for p in d["plugins"] if p["name"]=="che-pdf-mcp"][0]["problems"]' 2>/dev/null)" "marketplace-mismatch"
check_eq "json macdoc installed unknown" "None" "$(json_get "$JOUT" '[p for p in d["plugins"] if p["name"]=="macdoc"][0]["installed"]' 2>/dev/null)"

run_case "status: installed differs from pin"
F="$T/s-inst"; build_fixture "$F"
echo 4.8.0 > "$F/cache/che-word-mcp/.bin-cache/.CheWordMCP.version"
pins "$F" status >/dev/null 2>&1; check_eq "exit 10" 10 $?

installed_state() {   # installed_state <json> <plugin>
    json_get "$1" '[p for p in d["plugins"] if p["name"]=="'"$2"'"][0]["installed_state"]' 2>/dev/null
}

run_case "status: installed_state is known when the record matches"
F="$T/s-known"; build_fixture "$F"
JOUT=$(pins "$F" status --json 2>/dev/null)
check_eq "MCP known" known "$(installed_state "$JOUT" che-word-mcp)"
check_eq "CLI known" known "$(installed_state "$JOUT" macdoc)"

run_case "status: MCP plugin not installed (no cache dir) is neither a problem nor unknown"
F="$T/s-mcp-ni"; build_fixture "$F"; rm -rf "$F/cache/che-pdf-mcp"
OUT=$(pins "$F" status 2>&1); RC=$?
check_eq "exit 0" 0 "$RC"
check_contains "shows 未安裝" "$OUT" "未安裝"
JOUT=$(pins "$F" status --json 2>/dev/null)
check_eq "installed_state not-installed" not-installed "$(installed_state "$JOUT" che-pdf-mcp)"
check_eq "installed null" None "$(json_get "$JOUT" '[p for p in d["plugins"] if p["name"]=="che-pdf-mcp"][0]["installed"]' 2>/dev/null)"
check_eq "no problems, no unknowns" "[] []" "$(json_get "$JOUT" '" ".join(str(x) for x in [[p for p in d["plugins"] if p["name"]=="che-pdf-mcp"][0][k] for k in ("problems","unknown")])' 2>/dev/null)"

run_case "status: MCP cache dir present but version record missing -> unknown"
F="$T/s-mcp-unk"; build_fixture "$F"; rm "$F/cache/che-pdf-mcp/.bin-cache/.ChePDFMCP.version"
pins "$F" status >/dev/null 2>&1; check_eq "exit 2" 2 $?
check_eq "installed_state unknown" unknown "$(installed_state "$(pins "$F" status --json 2>/dev/null)" che-pdf-mcp)"

run_case "status: CLI not installed (no binary) is neither a problem nor unknown"
F="$T/s-cli-ni"; build_fixture "$F"; rm "$F/home-bin/macdoc" "$F/home-bin/.macdoc.installed_version"
OUT=$(pins "$F" status 2>&1); RC=$?
check_eq "exit 0" 0 "$RC"
check_contains "shows 未安裝" "$OUT" "未安裝"
check_eq "installed_state not-installed" not-installed "$(installed_state "$(pins "$F" status --json 2>/dev/null)" macdoc)"

run_case "status: CLI binary present but record missing -> unknown"
F="$T/s-cli-unk"; build_fixture "$F"; rm "$F/home-bin/.macdoc.installed_version"
check_eq "installed_state unknown" unknown "$(installed_state "$(pins "$F" status --json 2>/dev/null)" macdoc)"

run_case "status: only unknowns -> 2"
F="$T/s-unk"; build_fixture "$F"
rm "$F/home-bin/.macdoc.installed_version"
pins "$F" status >/dev/null 2>&1; check_eq "missing install record alone -> 2" 2 $?
GH_STUB_FAIL=1 pins "$F" status >/dev/null 2>&1; check_eq "gh failure alone -> 2" 2 $?

run_case "status: behind wins over unknown"
F="$T/s-prec"; build_fixture "$F"
rm "$F/home-bin/.macdoc.installed_version"
echo 4.8.0 > "$F/cache/che-word-mcp/.bin-cache/.CheWordMCP.version"
pins "$F" status >/dev/null 2>&1; check_eq "10 beats 2" 10 $?

run_case "status: checkout behind -> 10"
F="$T/s-cb"; build_fixture "$F"; seed_push "$F" 1
pins "$F" status >/dev/null 2>&1; check_eq "exit 10" 10 $?

run_case "status: release missing an asset is reported"
F="$T/s-asset"; build_fixture "$F"
rm "$GH_STUB_DB/PsychQuant/che-pdf-mcp/releases/v0.2.0/assets/ChePDFMCP.sha256"
JOUT=$(pins "$F" status --json 2>/dev/null)
check_eq "assets incomplete" "False" "$(json_get "$JOUT" '[p for p in d["plugins"] if p["name"]=="che-pdf-mcp"][0]["latest_assets_complete"]' 2>/dev/null)"

# ==========================================================================
# update: success paths
# ==========================================================================
mk_field() {   # mk_field <fixture> <plugin> <key>: marketplace entry field
    python3 -I -c 'import json,sys; print([e for e in json.load(open(sys.argv[1],encoding="utf-8"))["plugins"] if e["name"]==sys.argv[2]][0].get(sys.argv[3]))' \
        "$1/clone/.claude-plugin/marketplace.json" "$2" "$3"
}
pj_field() {   # pj_field <fixture> <plugin> <key>
    python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1],encoding="utf-8")).get(sys.argv[2]))' \
        "$1/clone/plugins/$2/.claude-plugin/plugin.json" "$3"
}
first_heading() { grep -m1 '^## \[' "$1"; }
first_version_heading() { grep -m1 -E '^## \[[0-9]' "$1"; }

run_case "update: MCP plugin whose version equals binary_version (che-word-mcp)"
F="$T/u-word"; build_fixture "$F"; gh_latest PsychQuant/che-word-mcp v4.10.0
ORIGIN_BEFORE=$(git -C "$F/origin.git" rev-parse main)
BASE=$(git -C "$F/clone" rev-parse HEAD)
OUT=$(pins "$F" update che-word-mcp 2>&1); RC=$?
check_eq "exit 0" 0 "$RC"
check_eq "plugin.json version" 4.10.0 "$(pj_field "$F" che-word-mcp version)"
check_eq "plugin.json binary_version" 4.10.0 "$(pj_field "$F" che-word-mcp binary_version)"
check_eq "marketplace version" 4.10.0 "$(mk_field "$F" che-word-mcp version)"
check_eq "marketplace binary_version" 4.10.0 "$(mk_field "$F" che-word-mcp binary_version)"
check_eq "marketplace keeps non-ASCII text" "Word ── 測試" "$(mk_field "$F" che-word-mcp description)"
check_eq "plugin.json keeps its hand formatting" "$(sed 's/4\.9\.0/4.10.0/' "$F/seed/plugins/che-word-mcp/.claude-plugin/plugin.json")" "$(cat "$F/clone/plugins/che-word-mcp/.claude-plugin/plugin.json")"
check_eq "gitlink in HEAD points at the tag's commit" "$WORD_V4_10" "$(git -C "$F/clone" ls-tree HEAD mcp/che-word-mcp | awk '{print $3}')"
check_eq "exactly one new commit" "$BASE" "$(git -C "$F/clone" rev-parse HEAD~1)"
check_eq "commit touches exactly the pin files" \
    ".claude-plugin/marketplace.json docs/marketplace-pin-history.md mcp/che-word-mcp plugins/che-word-mcp/.claude-plugin/plugin.json plugins/che-word-mcp/CHANGELOG.md" \
    "$(git -C "$F/clone" diff-tree --no-commit-id --name-only -r HEAD | sort | tr '\n' ' ' | sed 's/ $//')"
check_eq "commit message" "chore: che-word-mcp plugin 4.10.0，binary 4.9.0 → 4.10.0，gitlink 指向 v4.10.0" "$(git -C "$F/clone" log -1 --format=%s)"
check_eq "CHANGELOG new top section" "## [4.10.0] - 2026-01-02" "$(first_heading "$F/clone/plugins/che-word-mcp/CHANGELOG.md")"
check_contains "CHANGELOG bullet" "$(cat "$F/clone/plugins/che-word-mcp/CHANGELOG.md")" "### Changed

- binary 4.9.0 → 4.10.0。細節見上游的 CHANGELOG。

## [0.0.1]"
check_eq "history row" "| 2026-01-02 | che-word-mcp | 4.9.0 | 4.10.0 | $WORD_V4_10 |" "$(tail -1 "$F/clone/docs/marketplace-pin-history.md")"
check_eq "nothing pushed" "$ORIGIN_BEFORE" "$(git -C "$F/origin.git" rev-parse main)"
check_contains "prints the push command" "$OUT" "git push origin HEAD:main"
check_eq "submodule working dir untouched (still empty)" "" "$(ls -A "$F/clone/mcp/che-word-mcp")"
check_eq "worktree clean afterwards" "" "$(git -C "$F/clone" status --porcelain=v1 --untracked-files=all)"
JOUT=$(pins "$F" status --json 2>/dev/null)
# The installed record still says 4.9.0, so only that remains for che-word-mcp.
check_eq "status afterwards: pin current, entries consistent" "['installed-differs']" "$(json_get "$JOUT" '[p for p in d["plugins"] if p["name"]=="che-word-mcp"][0]["problems"]' 2>/dev/null)"
check_eq "status afterwards: checkout ahead by the new commit" "ahead" "$(json_get "$JOUT" 'd["checkout"]["state"]' 2>/dev/null)"

run_case "update: MCP plugin with separate plugin version (che-pdf-mcp, annotated tag)"
F="$T/u-pdf"; build_fixture "$F"
OUT=$(pins "$F" update che-pdf-mcp --to 0.3.0 --plugin-version 0.1.4 2>&1); RC=$?
check_eq "exit 0" 0 "$RC"
check_eq "plugin.json version" 0.1.4 "$(pj_field "$F" che-pdf-mcp version)"
check_eq "plugin.json binary_version" 0.3.0 "$(pj_field "$F" che-pdf-mcp binary_version)"
check_eq "marketplace version" 0.1.4 "$(mk_field "$F" che-pdf-mcp version)"
check_eq "marketplace binary_version" 0.3.0 "$(mk_field "$F" che-pdf-mcp binary_version)"
check_eq "gitlink peeled from annotated tag" "$(peeled che-pdf-mcp v0.3.0)" "$(git -C "$F/clone" ls-tree HEAD mcp/che-pdf-mcp | awk '{print $3}')"
check_eq "commit message" "chore: che-pdf-mcp plugin 0.1.4，binary 0.2.0 → 0.3.0，gitlink 指向 v0.3.0" "$(git -C "$F/clone" log -1 --format=%s)"

run_case "update: CLI plugin with sha256 pin (macdoc)"
F="$T/u-cli"; build_fixture "$F"; gh_latest PsychQuant/macdoc v0.18.0
OUT=$(pins "$F" update macdoc --plugin-version 1.15.0 2>&1); RC=$?
check_eq "exit 0" 0 "$RC"
check_eq "plugin.json version" 1.15.0 "$(pj_field "$F" macdoc version)"
check_eq "plugin.json binary_version" 0.18.0 "$(pj_field "$F" macdoc binary_version)"
check_eq "plugin.json binary_sha256" "$SHA_NEW" "$(pj_field "$F" macdoc binary_sha256)"
check_eq "marketplace binary_sha256" "$SHA_NEW" "$(mk_field "$F" macdoc binary_sha256)"
check_eq "marketplace binary_version" 0.18.0 "$(mk_field "$F" macdoc binary_version)"
check_eq "commit message has no gitlink clause" "chore: macdoc plugin 1.15.0，binary 0.17.0 → 0.18.0" "$(git -C "$F/clone" log -1 --format=%s)"
check_eq "commit touches exactly the pin files" \
    ".claude-plugin/marketplace.json docs/marketplace-pin-history.md plugins/macdoc/.claude-plugin/plugin.json plugins/macdoc/CHANGELOG.md" \
    "$(git -C "$F/clone" diff-tree --no-commit-id --name-only -r HEAD | sort | tr '\n' ' ' | sed 's/ $//')"
check_eq "[Unreleased] stays on top" "## [Unreleased]" "$(first_heading "$F/clone/plugins/macdoc/CHANGELOG.md")"
check_eq "new section is the first versioned one" "## [1.15.0] - 2026-01-02" "$(first_version_heading "$F/clone/plugins/macdoc/CHANGELOG.md")"
check_eq "history row records the tag commit" "| 2026-01-02 | macdoc | 0.17.0 | 0.18.0 | $(git -C "$F/seed" rev-parse 'v0.18.0^{commit}') |" "$(tail -1 "$F/clone/docs/marketplace-pin-history.md")"

run_case "update: checked-out submodule is left alone"
F="$T/u-sub"; build_fixture "$F"; gh_latest PsychQuant/che-word-mcp v4.10.0; populate_submodule "$F"
pins "$F" update che-word-mcp >/dev/null 2>&1; RC=$?
check_eq "exit 0" 0 "$RC"
check_eq "gitlink in HEAD points at the new tag" "$WORD_V4_10" "$(git -C "$F/clone" ls-tree HEAD mcp/che-word-mcp | awk '{print $3}')"
check_eq "submodule HEAD unchanged" "$WORD_V4_9" "$(git -C "$F/clone/mcp/che-word-mcp" rev-parse HEAD)"
check_eq "submodule untracked work kept" "wip" "$(cat "$F/clone/mcp/che-word-mcp/wip.txt" 2>/dev/null)"

run_case "update: refusal with a checked-out submodule leaves it alone"
F="$T/u-subr"; build_fixture "$F"; gh_latest PsychQuant/che-word-mcp v4.10.0; populate_submodule "$F"
sed -i '' 's/"version": "0.1.3"/"version": "0.1.2"/' "$F/clone/plugins/che-pdf-mcp/.claude-plugin/plugin.json"
git -C "$F/clone" commit -qam "pdf plugin.json drifted"; git -C "$F/clone" push -q origin main
pins "$F" update che-word-mcp >/dev/null 2>&1
check "refused" test $? -ne 0
check_eq "gitlink restored in the index" "$WORD_V4_9" "$(git -C "$F/clone" ls-files -s mcp/che-word-mcp | awk '{print $2}')"
check_eq "submodule HEAD unchanged" "$WORD_V4_9" "$(git -C "$F/clone/mcp/che-word-mcp" rev-parse HEAD)"
check_eq "submodule untracked work kept" "wip" "$(cat "$F/clone/mcp/che-word-mcp/wip.txt" 2>/dev/null)"

run_case "update: --dry-run changes nothing"
F="$T/u-dry"; build_fixture "$F"; gh_latest PsychQuant/che-word-mcp v4.10.0
BEFORE=$(snapshot "$F/clone")
OUT=$(pins "$F" update che-word-mcp --dry-run 2>&1); RC=$?
check_eq "exit 0" 0 "$RC"
check_contains "describes the change" "$OUT" "4.9.0 → 4.10.0"
check_contains "names the gitlink" "$OUT" "$WORD_V4_10"
check_eq "files, index and HEAD unchanged" "$BEFORE" "$(snapshot "$F/clone")"

# ==========================================================================
# update: refusals — each must leave every file, the index and HEAD as-is
# ==========================================================================
refuses() {   # refuses <name> <fixture> <expected reason substring> <update args...>
    local name=$1 F=$2 reason=$3 before out rc; shift 3
    before=$(snapshot "$F/clone")
    out=$(pins "$F" update "$@" 2>&1); rc=$?
    if [ "$rc" -ne 0 ]; then ok "$name: refused"; else not_ok "$name: refused" "$out"; fi
    check_contains "$name: says why" "$out" "$reason"
    check_eq "$name: nothing changed" "$before" "$(snapshot "$F/clone")"
}

run_case "update refusals"
F="$T/r"; build_fixture "$F"; gh_latest PsychQuant/che-word-mcp v4.10.0
refuses "unknown plugin" "$F" "nope" nope
refuses "plugin without binary_version" "$F" "binary_version" docflow
refuses "release does not exist" "$F" "v9.9.9" che-word-mcp --to 9.9.9
refuses "target equal to the pin" "$F" "不比目前的 pin" che-word-mcp --to 4.9.0
refuses "target older than the pin" "$F" "不比目前的 pin" che-word-mcp --to 4.8.0
refuses "malformed version" "$F" "X.Y.Z" che-word-mcp --to 4.10
refuses "plugin version differs from target" "$F" "--plugin-version" che-word-mcp --plugin-version 4.11.0
refuses "separate plugin version required" "$F" "--plugin-version" che-pdf-mcp --to 0.3.0
refuses "plugin version not newer" "$F" "--plugin-version" che-pdf-mcp --to 0.3.0 --plugin-version 0.1.3
GH_STUB_FAIL=1 refuses "gh failure" "$F" "查不到" che-word-mcp
rm "$GH_STUB_DB/PsychQuant/che-word-mcp/releases/v4.10.0/assets/CheWordMCP.sha256"
refuses "release missing the .sha256 asset" "$F" "CheWordMCP.sha256" che-word-mcp
gh_release PsychQuant/che-word-mcp v4.11.0 CheWordMCP CheWordMCP.sha256
refuses "tag missing upstream" "$F" "v4.11.0" che-word-mcp --to 4.11.0

F="$T/r-behind"; build_fixture "$F"; gh_latest PsychQuant/che-word-mcp v4.10.0; seed_push "$F" 1
refuses "checkout behind" "$F" "同步" che-word-mcp
F="$T/r-ahead"; build_fixture "$F"; gh_latest PsychQuant/che-word-mcp v4.10.0; local_commit "$F" a.txt
refuses "checkout ahead" "$F" "同步" che-word-mcp
F="$T/r-fetch"; build_fixture "$F"; gh_latest PsychQuant/che-word-mcp v4.10.0
git -C "$F/clone" remote set-url origin "$T/does-not-exist.git"
refuses "checkout state unknown" "$F" "fetch" che-word-mcp
F="$T/r-dirty"; build_fixture "$F"; gh_latest PsychQuant/che-word-mcp v4.10.0
echo " " >> "$F/clone/plugins/che-word-mcp/CHANGELOG.md"
refuses "uncommitted change in a file to edit" "$F" "未提交" che-word-mcp
F="$T/r-staged"; build_fixture "$F"; gh_latest PsychQuant/che-word-mcp v4.10.0
echo new > "$F/clone/other.txt"; git -C "$F/clone" add other.txt
refuses "unrelated staged change" "$F" "已暫存" che-word-mcp

run_case "update: full-table check fails -> everything restored"
F="$T/r-table"; build_fixture "$F"; gh_latest PsychQuant/che-word-mcp v4.10.0
sed -i '' 's/"version": "0.1.3"/"version": "0.1.2"/' "$F/clone/plugins/che-pdf-mcp/.claude-plugin/plugin.json"
git -C "$F/clone" commit -qam "pdf plugin.json drifted"; git -C "$F/clone" push -q origin main
refuses "another plugin inconsistent" "$F" "全表比對不一致" che-word-mcp
check_eq "gitlink restored in the index" "$WORD_V4_9" "$(git -C "$F/clone" ls-files -s mcp/che-word-mcp | awk '{print $2}')"

# ==========================================================================
# sync-local
# ==========================================================================
run_case "sync-local: behind-only fast-forwards, then refreshes plugins"
F="$T/l-behind"; build_fixture "$F"; seed_push "$F" 2
mkdir -p "$F/clone/mcp/che-word-mcp/marker"   # stand-in for submodule content
OUT=$(pins "$F" sync-local 2>&1); RC=$?
check_eq "exit 0" 0 "$RC"
check_eq "HEAD now equals upstream" "$(git -C "$F/origin.git" rev-parse main)" "$(git -C "$F/clone" rev-parse HEAD)"
check_eq "submodule dir untouched" "marker" "$(ls -A "$F/clone/mcp/che-word-mcp")"
check_contains "marketplace refreshed" "$(cat "$CLAUDE_STUB_LOG")" "plugin marketplace update macdoc"
check_contains "installed MCP plugin updated" "$(cat "$CLAUDE_STUB_LOG")" "plugin update che-word-mcp@macdoc"
check_contains "installed CLI plugin updated" "$(cat "$CLAUDE_STUB_LOG")" "plugin update macdoc@macdoc"
check_not_contains "plugin without binary pin skipped" "$(cat "$CLAUDE_STUB_LOG")" "docflow"

run_case "sync-local: plugins without a cache dir are skipped"
F="$T/l-skip"; build_fixture "$F"; seed_push "$F" 1; rm -rf "$F/cache/che-pdf-mcp"
OUT=$(pins "$F" sync-local 2>&1); RC=$?
check_eq "exit 0" 0 "$RC"
check_not_contains "not-installed plugin not updated" "$(cat "$CLAUDE_STUB_LOG")" "che-pdf-mcp"
check_contains "says it skipped it" "$OUT" "略過 che-pdf-mcp"

run_case "sync-local: fast-forward that moves a gitlink leaves the submodule alone"
F="$T/l-sub"; build_fixture "$F"; populate_submodule "$F"
git -C "$F/seed" update-index --cacheinfo "160000,$WORD_V4_10,mcp/che-word-mcp"
git -C "$F/seed" commit -qm "move gitlink"; git -C "$F/seed" push -q origin main
pins "$F" sync-local --no-plugins >/dev/null 2>&1; RC=$?
check_eq "exit 0" 0 "$RC"
check_eq "fast-forwarded" "$(git -C "$F/origin.git" rev-parse main)" "$(git -C "$F/clone" rev-parse HEAD)"
check_eq "HEAD gitlink moved" "$WORD_V4_10" "$(git -C "$F/clone" ls-tree HEAD mcp/che-word-mcp | awk '{print $3}')"
check_eq "submodule HEAD unchanged" "$WORD_V4_9" "$(git -C "$F/clone/mcp/che-word-mcp" rev-parse HEAD)"
check_eq "submodule untracked work kept" "wip" "$(cat "$F/clone/mcp/che-word-mcp/wip.txt" 2>/dev/null)"

run_case "sync-local: in-sync skips the git step and refreshes plugins"
F="$T/l-sync"; build_fixture "$F"
HEAD_BEFORE=$(git -C "$F/clone" rev-parse HEAD)
OUT=$(pins "$F" sync-local 2>&1); RC=$?
check_eq "exit 0" 0 "$RC"
check_eq "HEAD unchanged" "$HEAD_BEFORE" "$(git -C "$F/clone" rev-parse HEAD)"
check_contains "says already in sync" "$OUT" "已與"
check_contains "marketplace refreshed" "$(cat "$CLAUDE_STUB_LOG")" "plugin marketplace update macdoc"
check_contains "installed MCP plugin updated" "$(cat "$CLAUDE_STUB_LOG")" "plugin update che-word-mcp@macdoc"
check_contains "installed CLI plugin updated" "$(cat "$CLAUDE_STUB_LOG")" "plugin update macdoc@macdoc"

run_case "sync-local: in-sync with --no-plugins"
F="$T/l-sync-np"; build_fixture "$F"
HEAD_BEFORE=$(git -C "$F/clone" rev-parse HEAD)
pins "$F" sync-local --no-plugins >/dev/null 2>&1; RC=$?
check_eq "exit 0" 0 "$RC"
check_eq "HEAD unchanged" "$HEAD_BEFORE" "$(git -C "$F/clone" rev-parse HEAD)"
check_eq "claude not called" "" "$(cat "$CLAUDE_STUB_LOG")"

run_case "sync-local: --no-plugins"
F="$T/l-nop"; build_fixture "$F"; seed_push "$F" 1
pins "$F" sync-local --no-plugins >/dev/null 2>&1; RC=$?
check_eq "exit 0" 0 "$RC"
check_eq "fast-forwarded" "$(git -C "$F/origin.git" rev-parse main)" "$(git -C "$F/clone" rev-parse HEAD)"
check_eq "claude not called" "" "$(cat "$CLAUDE_STUB_LOG")"

run_case "sync-local: plugin refresh failure keeps the fast-forward"
F="$T/l-cfail"; build_fixture "$F"; seed_push "$F" 1
OUT=$(CLAUDE_STUB_FAIL=1 pins "$F" sync-local 2>&1); RC=$?
check "non-zero exit" test "$RC" -ne 0
check_eq "fast-forward kept" "$(git -C "$F/origin.git" rev-parse main)" "$(git -C "$F/clone" rev-parse HEAD)"
check_contains "reports the failure" "$OUT" "失敗"


sync_refuses() {   # sync_refuses <name> <fixture> <reason substring>
    local before out rc
    before=$(git -C "$2/clone" rev-parse HEAD)
    : > "$CLAUDE_STUB_LOG"
    out=$(pins "$2" sync-local 2>&1); rc=$?
    if [ "$rc" -ne 0 ]; then ok "$1: refused"; else not_ok "$1: refused" "$out"; fi
    check_contains "$1: says why" "$out" "$3"
    check_eq "$1: HEAD unchanged" "$before" "$(git -C "$2/clone" rev-parse HEAD)"
    check_eq "$1: claude not called" "" "$(cat "$CLAUDE_STUB_LOG")"
}
run_case "sync-local refusals"
F="$T/l-ahead"; build_fixture "$F"; local_commit "$F" a.txt
sync_refuses "ahead" "$F" "未推送"
F="$T/l-div"; build_fixture "$F"; local_commit "$F" a.txt; seed_push "$F" 1
sync_refuses "diverged" "$F" "分岔"
F="$T/l-lock"; build_fixture "$F"; seed_push "$F" 1
touch "$(git -C "$F/clone" rev-parse --absolute-git-dir)/index.lock"
sync_refuses "locked" "$F" "index.lock"
check "lock left in place" test -f "$(git -C "$F/clone" rev-parse --absolute-git-dir)/index.lock"
F="$T/l-noup"; build_fixture "$F"; git -C "$F/clone" checkout -q -b local-only
sync_refuses "no upstream" "$F" "upstream"
F="$T/l-prog"; build_fixture "$F"; seed_push "$F" 1
mkdir "$(git -C "$F/clone" rev-parse --absolute-git-dir)/rebase-merge"
sync_refuses "operation in progress" "$F" "進行中"
F="$T/l-fetch"; build_fixture "$F"; git -C "$F/clone" remote set-url origin "$T/does-not-exist.git"
sync_refuses "fetch fails" "$F" "fetch"

# ==========================================================================
# Review findings (second round)
# ==========================================================================
backups_left() { ls -d "$1"/marketplace-pins-backup.* 2>/dev/null | wc -l | tr -d ' '; }

# interrupt_update <fixture> <hook exit code> <tmpdir>: runs update with a
# pre-commit hook that signals readiness and sleeps, sends TERM to the script
# while git commit is running, prints the script's exit status.
interrupt_update() {
    local F=$1 hook_rc=$2 tmp=$3 pid i
    local marker="$T/hook-marker.$$.$RANDOM"
    mkdir -p "$tmp"
    printf '#!/bin/sh\ntouch "%s"\nsleep 2\nexit %s\n' "$marker" "$hook_rc" > "$F/clone/.git/hooks/pre-commit"
    chmod +x "$F/clone/.git/hooks/pre-commit"
    (cd "$F/clone" && TMPDIR="$tmp" exec ./scripts/marketplace-pins.sh update che-word-mcp > "$tmp/out" 2>&1) &
    pid=$!
    for i in $(seq 1 100); do [ -e "$marker" ] && break; sleep 0.1; done
    kill -TERM "$pid" 2>/dev/null
    wait "$pid"; echo $?
}

run_case "update interrupted while git commit runs (commit fails) -> restored"
F="$T/x-int"; build_fixture "$F"; gh_latest PsychQuant/che-word-mcp v4.10.0
BEFORE=$(snapshot "$F/clone")
RC=$(interrupt_update "$F" 1 "$T/x-int-tmp")
check_eq "terminated by TERM (143)" 143 "$RC"
check_eq "files, index (gitlink) and HEAD restored" "$BEFORE" "$(snapshot "$F/clone")"
check_eq "backup dir removed" 0 "$(backups_left "$T/x-int-tmp")"
check_contains "says it restored" "$(cat "$T/x-int-tmp/out")" "已還原"

run_case "update interrupted while git commit runs (commit succeeds) -> kept"
F="$T/x-int2"; build_fixture "$F"; gh_latest PsychQuant/che-word-mcp v4.10.0
BASE=$(git -C "$F/clone" rev-parse HEAD)
RC=$(interrupt_update "$F" 0 "$T/x-int2-tmp")
check_eq "terminated by TERM (143)" 143 "$RC"
check_eq "commit kept" "$BASE" "$(git -C "$F/clone" rev-parse HEAD~1)"
check_eq "gitlink committed" "$WORD_V4_10" "$(git -C "$F/clone" ls-tree HEAD mcp/che-word-mcp | awk '{print $3}')"
check_eq "worktree clean (not rolled back)" "" "$(git -C "$F/clone" status --porcelain=v1 --untracked-files=all)"
check_eq "backup dir removed" 0 "$(backups_left "$T/x-int2-tmp")"
check_contains "says the commit is done" "$(cat "$T/x-int2-tmp/out")" "commit 已完成"

run_case "update with submodules configured as ignored"
F="$T/x-ign1"; build_fixture "$F"; gh_latest PsychQuant/che-word-mcp v4.10.0
git -C "$F/clone" config diff.ignoreSubmodules all
pins "$F" update che-word-mcp >/dev/null 2>&1; check_eq "diff.ignoreSubmodules=all: exit 0" 0 $?
check_eq "diff.ignoreSubmodules=all: gitlink committed" "$WORD_V4_10" "$(git -C "$F/clone" ls-tree HEAD mcp/che-word-mcp | awk '{print $3}')"
F="$T/x-ign2"; build_fixture "$F"; gh_latest PsychQuant/che-word-mcp v4.10.0
git -C "$F/clone" config submodule.mcp/che-word-mcp.ignore all
pins "$F" update che-word-mcp >/dev/null 2>&1; check_eq "submodule.<name>.ignore=all: exit 0" 0 $?
check_eq "submodule.<name>.ignore=all: gitlink committed" "$WORD_V4_10" "$(git -C "$F/clone" ls-tree HEAD mcp/che-word-mcp | awk '{print $3}')"
F="$T/x-ign3"; build_fixture "$F"; gh_latest PsychQuant/che-word-mcp v4.10.0
git -C "$F/clone" config submodule.mcp/che-word-mcp.ignore all
git -C "$F/clone" config diff.ignoreSubmodules all
git -C "$F/clone" update-index --cacheinfo "160000,$WORD_V4_10,mcp/che-word-mcp"
refuses "pre-staged gitlink under ignore=all" "$F" "已暫存" che-word-mcp

run_case "status with a pin that is not X.Y.Z"
F="$T/x-rc"; build_fixture "$F"
sed -i '' 's/"binary_version": "4.9.0"/"binary_version": "4.9.0-rc1"/' "$F/clone/plugins/che-word-mcp/.claude-plugin/plugin.json" "$F/clone/.claude-plugin/marketplace.json"
git -C "$F/clone" commit -qam "rc pin"; git -C "$F/clone" push -q origin main
echo 4.9.0-rc1 > "$F/cache/che-word-mcp/.bin-cache/.CheWordMCP.version"
OUT=$(pins "$F" status 2>&1); RC=$?
check_eq "exit 2" 2 "$RC"
check_not_contains "no traceback" "$OUT" "Traceback"
check_contains "shows the value as-is" "$OUT" "4.9.0-rc1"
JOUT=$(pins "$F" status --json 2>/dev/null); RC=$?
check_eq "json exit 2" 2 "$RC"
check_contains "json marks it undeterminable" "$(json_get "$JOUT" '[p for p in d["plugins"] if p["name"]=="che-word-mcp"][0]["unknown"]' 2>/dev/null)" "pin-unparseable"

run_case "status with a latest-release tag that is not X.Y.Z"
F="$T/x-rc2"; build_fixture "$F"; gh_latest PsychQuant/che-word-mcp v4.10.0-beta
OUT=$(pins "$F" status 2>&1); RC=$?
check_eq "exit 2" 2 "$RC"
check_not_contains "no traceback" "$OUT" "Traceback"
check_contains "shows the tag as-is" "$OUT" "4.10.0-beta"
JOUT=$(pins "$F" status --json 2>/dev/null)
check_eq "json latest as-is" "4.10.0-beta" "$(json_get "$JOUT" '[p for p in d["plugins"] if p["name"]=="che-word-mcp"][0]["latest_release"]' 2>/dev/null)"
check_contains "json marks it undeterminable" "$(json_get "$JOUT" '[p for p in d["plugins"] if p["name"]=="che-word-mcp"][0]["unknown"]' 2>/dev/null)" "latest-unparseable"
refuses "update to a non-X.Y.Z latest" "$F" "4.10.0-beta" che-word-mcp

run_case "upstream branch deleted on the remote"
F="$T/x-gone"; build_fixture "$F"
git -C "$F/clone" checkout -q -b feat; git -C "$F/clone" push -q -u origin feat 2>/dev/null
git -C "$F/seed" push -q origin --delete feat 2>/dev/null
JOUT=$(pins "$F" status --json 2>/dev/null); RC=$?
check_eq "state upstream-gone" upstream-gone "$(json_get "$JOUT" 'd["checkout"]["state"]' 2>/dev/null)"
check_eq "status exit 10" 10 "$RC"
check "remote-tracking ref not pruned" git -C "$F/clone" rev-parse -q --verify refs/remotes/origin/feat
gh_latest PsychQuant/che-word-mcp v4.10.0
OUT=$(pins "$F" update che-word-mcp --dry-run 2>&1); RC=$?
check "dry-run refused" test "$RC" -ne 0
check_not_contains "dry-run prints no push command" "$OUT" "git push"
refuses "update with upstream gone" "$F" "upstream" che-word-mcp
sync_refuses "sync-local with upstream gone" "$F" "upstream"

run_case "upstream configured but never fetched / absent on the remote"
F="$T/x-nof"; build_fixture "$F"
git -C "$F/clone" checkout -q -b newb
git -C "$F/clone" config branch.newb.remote origin
git -C "$F/clone" config branch.newb.merge refs/heads/newb
OUT=$(pins "$F" status 2>&1)
check_eq "state upstream-gone" upstream-gone "$(json_get "$(pins "$F" status --json 2>/dev/null)" 'd["checkout"]["state"]' 2>/dev/null)"
check_not_contains "does not claim no upstream is configured" "$OUT" "沒有設定 upstream"
check_contains "names the configured upstream" "$OUT" "origin/newb"

run_case "pinned release missing an asset -> problem, exit 10"
F="$T/x-pinasset"; build_fixture "$F"
rm "$GH_STUB_DB/PsychQuant/che-pdf-mcp/releases/v0.2.0/assets/ChePDFMCP.sha256"
OUT=$(pins "$F" status 2>&1); RC=$?
check_eq "exit 10" 10 "$RC"
check_not_contains "summary does not say all consistent" "$OUT" "全部一致"
check_contains "listed as problem" "$(json_get "$(pins "$F" status --json 2>/dev/null)" '[p for p in d["plugins"] if p["name"]=="che-pdf-mcp"][0]["problems"]' 2>/dev/null)" "pinned-release-assets-incomplete"

run_case "pin newer than the latest release -> note"
F="$T/x-ahead-rel"; build_fixture "$F"
gh_release PsychQuant/che-pdf-mcp v0.1.0 ChePDFMCP ChePDFMCP.sha256; gh_latest PsychQuant/che-pdf-mcp v0.1.0
OUT=$(pins "$F" status 2>&1); RC=$?
check_eq "exit unchanged (0)" 0 "$RC"
check_contains "note listed" "$(json_get "$(pins "$F" status --json 2>/dev/null)" '[p for p in d["plugins"] if p["name"]=="che-pdf-mcp"][0]["notes"]' 2>/dev/null)" "pin-ahead-of-release"
check_contains "note shown" "$OUT" "pin 比最新 release 新"

run_case "duplicate key in plugin.json"
F="$T/x-dup"; build_fixture "$F"; gh_latest PsychQuant/che-word-mcp v4.10.0
sed -i '' 's/"name": "che-word-mcp",/"name": "che-word-mcp",\
  "binary_version": "4.8.0",/' "$F/clone/plugins/che-word-mcp/.claude-plugin/plugin.json"
git -C "$F/clone" commit -qam "duplicate key"; git -C "$F/clone" push -q origin main
refuses "update with duplicate binary_version" "$F" "重複" che-word-mcp
check_contains "status note" "$(pins "$F" status 2>&1)" "重複"

run_case "sync-local in-sync: failure message does not claim a fast-forward"
F="$T/x-syncfail"; build_fixture "$F"
OUT=$(CLAUDE_STUB_FAIL=1 pins "$F" sync-local 2>&1)
check_not_contains "no fast-forward claim" "$OUT" "快轉已完成"
check_contains "reports the failure" "$OUT" "失敗"

run_case "sha256 written in lowercase"
F="$T/x-upper"; build_fixture "$F"; gh_latest PsychQuant/macdoc v0.18.0
printf '%s  macdoc\n' "$(printf '%s' "$SHA_NEW" | sed 's/2/A/g')" > "$GH_STUB_DB/PsychQuant/macdoc/releases/v0.18.0/assets/macdoc.sha256"
pins "$F" update macdoc --plugin-version 1.15.0 >/dev/null 2>&1
check_eq "plugin.json sha lowercase" "$(printf '%s' "$SHA_NEW" | sed 's/2/a/g')" "$(pj_field "$F" macdoc binary_sha256)"
check_eq "marketplace sha lowercase" "$(printf '%s' "$SHA_NEW" | sed 's/2/a/g')" "$(mk_field "$F" macdoc binary_sha256)"

run_case "submodule matched by owner/repo, not just repo name"
F="$T/x-owner"; build_fixture "$F"; gh_latest PsychQuant/che-word-mcp v4.10.0
{ printf '[submodule "vendor/che-word-mcp"]\n\tpath = vendor/che-word-mcp\n\turl = %s\n' "$UP/OtherOwner/che-word-mcp.git"; cat "$F/clone/.gitmodules"; } > "$F/clone/.gitmodules.new"
mv "$F/clone/.gitmodules.new" "$F/clone/.gitmodules"
git -C "$F/clone" commit -qam "decoy submodule"; git -C "$F/clone" push -q origin main
OUT=$(pins "$F" update che-word-mcp 2>&1); RC=$?
check_eq "exit 0" 0 "$RC"
check_eq "gitlink on the right path" "$WORD_V4_10" "$(git -C "$F/clone" ls-tree HEAD mcp/che-word-mcp | awk '{print $3}')"

run_case "MCP update explains the submodule shows as modified"
F="$T/x-note"; build_fixture "$F"; gh_latest PsychQuant/che-word-mcp v4.10.0
check_contains "explains git status" "$(pins "$F" update che-word-mcp 2>&1)" "git status"

# ==========================================================================
# Lint: in a UTF-8 locale bash may read the bytes of a following CJK
# character as part of a bare $name, so every expansion that is directly
# followed by a non-ASCII character must be written ${name}.
# ==========================================================================
run_case "lint"
BARE=$(LC_ALL=C grep -nE '\$[A-Za-z_][A-Za-z0-9_]*[^ -~]' "$SCRIPT_UNDER_TEST" || true)
check_eq "no bare \$name directly followed by non-ASCII" "" "$BARE"

# ==========================================================================
# Summary
# ==========================================================================
check_eq "real checkout HEAD untouched" "$GUARD_HEAD" "$(git -C "$ROOT" rev-parse HEAD)"
check_eq "real checkout status untouched" "$GUARD_STATUS" "$(git -C "$ROOT" status --porcelain=v1 --untracked-files=all)"

echo
echo "marketplace-pins tests: $PASS passed, $FAIL failed"
if [ "$FAIL" -gt 0 ]; then
    printf '  - %s\n' "${FAILED_NAMES[@]}"
    exit 1
fi
