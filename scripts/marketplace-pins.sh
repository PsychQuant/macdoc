#!/bin/bash
# marketplace-pins.sh — maintainer tool for this repo's plugin marketplace
# binary pins (macdoc#279).
#
# A "pin" is the binary_version (and, for the macdoc CLI, binary_sha256) that
# a binary-backed plugin carries in two places that must agree:
#   .claude-plugin/marketplace.json            plugins[] entry
#   plugins/<name>/.claude-plugin/plugin.json
# MCP plugins additionally pin a submodule gitlink under mcp/<name>.
#
# Subcommands
#   status [--json]
#       Read-only report: per plugin the plugin.json and marketplace values,
#       the upstream latest release, whether that release ships the binary and
#       its .sha256, and the locally installed version; plus the state of this
#       checkout relative to its upstream branch.
#   update <plugin> [--to X.Y.Z] [--plugin-version X.Y.Z] [--dry-run]
#       Moves one plugin's pin to a release (default: latest), commits the
#       change locally and appends a row to docs/marketplace-pin-history.md.
#       Never pushes.
#   sync-local [--no-plugins]
#       Fast-forwards this checkout when it is strictly behind its upstream,
#       then refreshes the locally installed marketplace and plugins.
#
# status exit codes
#    0  everything consistent and up to date
#   10  something is known to be behind or inconsistent: a pin older than the
#       latest release, a marketplace entry that differs from its plugin.json,
#       an installed version that differs from the pin, or a checkout that is
#       not in sync with its upstream
#    2  nothing is known to be behind, but something could not be determined
#       (release lookup failed, no installed-version record, fetch failed)
#   10 takes precedence over 2: a known problem is reported even when other
#   facts are unknown.
# Other subcommands: 0 success, 1 refused or failed, 64 usage error.
#
# Environment overrides (used by scripts/tests/marketplace-pins.sh)
#   MARKETPLACE_PINS_ROOT        repo root (default: parent of this script's dir)
#   MARKETPLACE_PINS_GH          gh command (default: gh)
#   MARKETPLACE_PINS_CLAUDE      claude command (default: claude)
#   MARKETPLACE_PINS_CACHE_ROOT  plugin cache of this marketplace
#                                (default: ~/.claude/plugins/cache/<marketplace>)
#   MARKETPLACE_PINS_BIN_DIR     install dir of the CLI (default: MACDOC_INSTALL_DIR or ~/bin)
#   MARKETPLACE_PINS_TODAY       date written to CHANGELOG / history (default: today, Asia/Taipei)
#   MARKETPLACE_PINS_GIT_RUNNING yes|no — override the "is a git process running" probe
#
# User-facing messages are Traditional Chinese (repo convention).

set -uo pipefail

ROOT=${MARKETPLACE_PINS_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}
GH=${MARKETPLACE_PINS_GH:-gh}
CLAUDE=${MARKETPLACE_PINS_CLAUDE:-claude}
TODAY=${MARKETPLACE_PINS_TODAY:-$(TZ=Asia/Taipei date +%F)}
MARKETPLACE="$ROOT/.claude-plugin/marketplace.json"
HISTORY="$ROOT/docs/marketplace-pin-history.md"
HISTORY_REL="docs/marketplace-pin-history.md"
MARKETPLACE_REL=".claude-plugin/marketplace.json"

die() { echo "錯誤：$*" >&2; exit 1; }
usage_error() { echo "用法錯誤：$*" >&2; echo "用法：$(basename "$0") status [--json] | update <plugin> [--to X.Y.Z] [--plugin-version X.Y.Z] [--dry-run] | sync-local [--no-plugins]" >&2; exit 64; }
g() { git -C "$ROOT" "$@"; }

# --------------------------------------------------------------------------
# Embedded python: all JSON reading/writing. Paths and values are passed as
# argv only; nothing is interpolated into the python source.
# --------------------------------------------------------------------------
py() {
    python3 -I - "$@" <<'PY'
import json, re, sys

def load(path):
    with open(path, encoding="utf-8") as f:
        return json.load(f)

def dumps(obj):
    return json.dumps(obj, indent=2, ensure_ascii=False) + "\n"

def none_if_dash(v):
    return None if v in ("-", "") else v

def plugins(root, marketplace):
    """TSV of binary-backed entries: name source mk_v mk_b mk_sha pj_v pj_b pj_sha."""
    for e in load(marketplace)["plugins"]:
        if "binary_version" not in e:
            continue
        src = e.get("source", "")
        pj = {}
        try:
            pj = load(f"{root}/{src}/.claude-plugin/plugin.json")
        except (OSError, ValueError):
            pass
        row = [e["name"], src, e.get("version"), e.get("binary_version"), e.get("binary_sha256"),
               pj.get("version"), pj.get("binary_version"), pj.get("binary_sha256")]
        print("\t".join("-" if v in (None, "") else str(v) for v in row))

def vtuple(v):
    return tuple(int(x) for x in v.split("."))

def render(fmt, plugin_tsv, *checkout):
    state, behind, ahead, equiv, upstream, detail, lock_mtime, git_running = (none_if_dash(x) for x in checkout)
    co = {
        "state": state,
        "behind": int(behind) if behind is not None else None,
        "ahead": int(ahead) if ahead is not None else None,
        "patch_equivalent": int(equiv) if equiv is not None else None,
        "upstream": upstream,
        "detail": detail,
        "lock": ({"mtime": lock_mtime, "git_running": git_running == "yes"} if state == "locked" else None),
    }
    rows = []
    with open(plugin_tsv, encoding="utf-8") as f:
        for line in f:
            (name, kind, repo, binary, mk_v, mk_b, mk_sha, pj_v, pj_b, pj_sha,
             latest, assets, installed) = (none_if_dash(x) for x in line.rstrip("\n").split("\t"))
            problems, unknown, notes = [], [], []
            if (mk_v, mk_b, mk_sha) != (pj_v, pj_b, pj_sha):
                problems.append("marketplace-mismatch")
            if latest is None:
                unknown.append("latest-release")
            elif pj_b is not None and vtuple(latest) > vtuple(pj_b):
                problems.append("pin-behind-release")
            if latest is not None and assets is None:
                unknown.append("latest-assets")
            elif assets == "no":
                notes.append("latest-assets-incomplete")
            if installed is None:
                unknown.append("installed")
            elif installed != pj_b:
                problems.append("installed-differs")
            rows.append({
                "name": name, "kind": kind, "upstream_repo": repo, "binary": binary,
                "plugin_json": {"version": pj_v, "binary_version": pj_b, "binary_sha256": pj_sha},
                "marketplace": {"version": mk_v, "binary_version": mk_b, "binary_sha256": mk_sha},
                "latest_release": latest,
                "latest_assets_complete": None if assets is None else assets == "yes",
                "installed": installed,
                "problems": problems, "unknown": unknown, "notes": notes,
            })
    any_problem = any(r["problems"] for r in rows) or state not in ("in-sync", "unknown")
    any_unknown = any(r["unknown"] for r in rows) or state == "unknown"
    code = 10 if any_problem else (2 if any_unknown else 0)
    if fmt == "json":
        print(json.dumps({"checkout": co, "plugins": rows, "exit_code": code}, ensure_ascii=False, indent=2))
        return code
    print("本機 checkout：" + describe_checkout(co))
    print()
    U = "未知"
    header = ["plugin", "plugin.json", "marketplace", "最新 release", "asset", "已安裝", "問題"]
    table = [header]
    labels = {"marketplace-mismatch": "marketplace 與 plugin.json 不一致",
              "pin-behind-release": "pin 落後最新 release",
              "installed-differs": "已安裝版本與 pin 不同",
              "latest-release": "最新 release 查不到",
              "latest-assets": "asset 查不到",
              "installed": "已安裝版本未知",
              "latest-assets-incomplete": "最新 release 缺 binary 或 .sha256"}
    for r in rows:
        pj, mk = r["plugin_json"], r["marketplace"]
        assets = {True: "齊全", False: "不齊", None: U}[r["latest_assets_complete"]]
        issues = "；".join(labels[k] for k in r["problems"] + r["unknown"] + r["notes"]) or "—"
        table.append([r["name"], f"{pj['version'] or U} / {pj['binary_version'] or U}",
                      f"{mk['version'] or U} / {mk['binary_version'] or U}",
                      r["latest_release"] or U, assets, r["installed"] or U, issues])
    widths = [max(display_width(row[i]) for row in table) for i in range(len(header) - 1)]
    for row in table:
        cells = [row[i] + " " * (widths[i] - display_width(row[i])) for i in range(len(widths))]
        print("  ".join(cells + [row[-1]]).rstrip())
    print()
    print("（plugin.json 與 marketplace 欄位為 version / binary_version）")
    print({0: "結果：全部一致且是最新（exit 0）",
           10: "結果：有落後或不一致的項目（exit 10）",
           2: "結果：沒有已知的落後，但有查不到的項目（exit 2）"}[code])
    return code

def display_width(s):
    import unicodedata
    return sum(2 if unicodedata.east_asian_width(c) in "WF" else 1 for c in s)

def describe_checkout(co):
    s, up = co["state"], co["upstream"] or "upstream"
    if s == "in-sync":
        return f"同步（與 {up} 一致）"
    if s == "behind":
        return f"單純落後 {up} {co['behind']} 個 commit（可用 sync-local 快轉）"
    if s == "ahead":
        return f"有 {co['ahead']} 個未推送的 commit（領先 {up}）"
    if s == "diverged":
        return (f"與 {up} 分岔：落後 {co['behind']}、領先 {co['ahead']}；本機多出的 commit 中有 "
                f"{co['patch_equivalent']} 個在上游有相同內容（上游的歷史可能被改寫過）")
    if s == "locked":
        lk = co["lock"] or {}
        running = "有" if lk.get("git_running") else "沒有"
        return (f"有 {co['detail']}（修改時間 {lk.get('mtime')}；目前{running} git 程序在跑）。"
                "本腳本不會移除它，確認沒有 git 在執行後請手動處理")
    if s == "in-progress":
        return f"有進行中的 git 操作（{co['detail']}），請先完成或中止"
    if s == "no-upstream":
        return f"目前分支沒有設定 upstream（{co['detail']}）"
    return f"無法判定（{co['detail']}）"

cmd, args = sys.argv[1], sys.argv[2:]
if cmd == "plugins":
    plugins(*args)
elif cmd == "render":
    sys.exit(render(*args))
elif cmd == "mtime":
    import datetime, os
    print(datetime.datetime.fromtimestamp(os.path.getmtime(args[0])).astimezone().isoformat(timespec="seconds"))
else:
    sys.exit(f"internal: unknown py command {cmd}")
PY
}

# --------------------------------------------------------------------------
# Checkout state classifier (shared by all subcommands)
# Sets CO_STATE: in-progress | locked | no-upstream | unknown | in-sync |
# behind | ahead | diverged, plus CO_BEHIND CO_AHEAD CO_EQUIV CO_UPSTREAM
# CO_REMOTE CO_DETAIL CO_LOCK_MTIME CO_GIT_RUNNING ("-" when not applicable).
# Only reports; never removes a lock or touches the working tree.
# --------------------------------------------------------------------------
git_path() {   # absolute path of a file in this checkout's git dir
    local p
    p=$(g rev-parse --git-path "$1") || return 1
    case "$p" in /*) echo "$p" ;; *) echo "$ROOT/$p" ;; esac
}

classify_checkout() {
    CO_STATE=unknown; CO_BEHIND=-; CO_AHEAD=-; CO_EQUIV=-; CO_UPSTREAM=-; CO_REMOTE=-
    CO_DETAIL=-; CO_LOCK_MTIME=-; CO_GIT_RUNNING=-
    local p f
    if ! g rev-parse --git-dir >/dev/null 2>&1; then CO_DETAIL="$ROOT 不是 git checkout"; return; fi
    for p in rebase-merge rebase-apply MERGE_HEAD CHERRY_PICK_HEAD REVERT_HEAD; do
        f=$(git_path "$p") || continue
        if [ -e "$f" ]; then CO_STATE=in-progress; CO_DETAIL=$p; return; fi
    done
    f=$(git_path index.lock) || true
    if [ -n "$f" ] && [ -e "$f" ]; then
        CO_STATE=locked; CO_DETAIL=index.lock
        CO_LOCK_MTIME=$(py mtime "$f" 2>/dev/null || echo -)
        case "${MARKETPLACE_PINS_GIT_RUNNING:-}" in
            yes|no) CO_GIT_RUNNING=$MARKETPLACE_PINS_GIT_RUNNING ;;
            *) if pgrep -x git >/dev/null 2>&1; then CO_GIT_RUNNING=yes; else CO_GIT_RUNNING=no; fi ;;
        esac
        return
    fi
    local branch
    if ! branch=$(g symbolic-ref -q --short HEAD); then CO_STATE=no-upstream; CO_DETAIL="detached HEAD"; return; fi
    if ! CO_UPSTREAM=$(g rev-parse -q --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null) || [ -z "$CO_UPSTREAM" ]; then
        CO_UPSTREAM=-; CO_STATE=no-upstream; CO_DETAIL=$branch; return
    fi
    CO_REMOTE=$(g config "branch.$branch.remote" 2>/dev/null || echo -)
    if [ "$CO_REMOTE" = . ] || [ "$CO_REMOTE" = - ]; then
        CO_STATE=unknown; CO_DETAIL="upstream $CO_UPSTREAM 不是遠端分支"; return
    fi
    if ! g fetch --quiet --no-recurse-submodules "$CO_REMOTE" >/dev/null 2>&1; then
        CO_STATE=unknown; CO_DETAIL="fetch $CO_REMOTE 失敗，無法確認與 $CO_UPSTREAM 的關係"; return
    fi
    local counts
    counts=$(g rev-list --left-right --count '@{u}...HEAD') || { CO_STATE=unknown; CO_DETAIL="rev-list 失敗"; return; }
    CO_BEHIND=${counts%%[[:space:]]*}; CO_AHEAD=${counts##*[[:space:]]}
    if [ "$CO_BEHIND" = 0 ] && [ "$CO_AHEAD" = 0 ]; then CO_STATE=in-sync
    elif [ "$CO_AHEAD" = 0 ]; then CO_STATE=behind
    elif [ "$CO_BEHIND" = 0 ]; then CO_STATE=ahead
    else
        CO_STATE=diverged
        CO_EQUIV=$(g cherry '@{u}' HEAD | grep -c '^-' || true)
    fi
}

# --------------------------------------------------------------------------
# Plugin facts
# --------------------------------------------------------------------------
read_var() {   # read_var <file> <NAME>: value of NAME="..." in a shell script
    sed -nE "s/^$2=\"([^\"]+)\".*/\\1/p" "$1" 2>/dev/null | head -1
}

# plugin_meta <name> <source>: sets PM_KIND (mcp|cli|-) PM_REPO PM_BINARY PM_RECORD
plugin_meta() {
    local name=$1 dir="$ROOT/${2#./}" f
    PM_KIND=-; PM_REPO=-; PM_BINARY=-; PM_RECORD=-
    if [ -f "$dir/bin/$name-wrapper.sh" ]; then
        f="$dir/bin/$name-wrapper.sh"; PM_KIND=mcp
    elif [ -f "$dir/hooks/session-start.sh" ]; then
        f="$dir/hooks/session-start.sh"; PM_KIND=cli
    else
        return
    fi
    PM_REPO=$(read_var "$f" REPO); PM_BINARY=$(read_var "$f" BINARY_NAME)
    [ -n "$PM_REPO" ] || PM_REPO=-
    [ -n "$PM_BINARY" ] || { PM_BINARY=-; return; }
    # Same locations the wrapper / session-start hook write to.
    if [ "$PM_KIND" = mcp ]; then
        PM_RECORD="$CACHE_ROOT/$name/.bin-cache/.$PM_BINARY.version"
    else
        PM_RECORD="$BIN_DIR/.$PM_BINARY.installed_version"
    fi
}

is_version() { [[ "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; }

# version_gt <a> <b>: true when a > b, compared numerically per component.
version_gt() {
    local IFS=. i
    # shellcheck disable=SC2206  # intentional split on dots; inputs are validated X.Y.Z
    local a=($1) b=($2)
    for i in 0 1 2; do
        if ((10#${a[i]} > 10#${b[i]})); then return 0; fi
        if ((10#${a[i]} < 10#${b[i]})); then return 1; fi
    done
    return 1
}

latest_release() {   # latest_release <owner/repo>: prints X.Y.Z, fails when unknown
    local tag
    tag=$("$GH" api "repos/$1/releases/latest" --jq .tag_name </dev/null 2>/dev/null) || return 1
    tag=${tag#v}
    is_version "$tag" || return 1
    echo "$tag"
}

# release_lookup <owner/repo> <tag>: sets REL_ID REL_TARGET REL_ASSETS
# (lines "<asset id>\t<name>"). Assets are listed by release id, not through
# the tag endpoint, whose asset list has been seen to lag behind.
release_lookup() {
    local line
    REL_ID=; REL_TARGET=; REL_ASSETS=
    line=$("$GH" api "repos/$1/releases/tags/$2" --jq '"\(.id)\t\(.target_commitish)"' </dev/null 2>/dev/null) || return 1
    REL_ID=${line%%$'\t'*}; REL_TARGET=${line#*$'\t'}
    [ -n "$REL_ID" ] || return 1
    REL_ASSETS=$("$GH" api "repos/$1/releases/$REL_ID/assets" --paginate --jq '.[] | "\(.id)\t\(.name)"' </dev/null 2>/dev/null) || return 1
}

asset_id() {   # asset_id <name>: id of the asset called <name> in REL_ASSETS
    printf '%s\n' "$REL_ASSETS" | awk -F'\t' -v n="$1" '$2 == n { print $1; exit }'
}

# --------------------------------------------------------------------------
# status
# --------------------------------------------------------------------------
cmd_status() {
    local fmt=text
    while [ $# -gt 0 ]; do
        case "$1" in
            --json) fmt=json ;;
            *) usage_error "status 不認得的參數：$1" ;;
        esac
        shift
    done
    [ -f "$MARKETPLACE" ] || die "找不到 $MARKETPLACE_REL"
    classify_checkout
    local tsv rows name src mk_v mk_b mk_sha pj_v pj_b pj_sha latest assets installed
    tsv=$(mktemp "${TMPDIR:-/tmp}/marketplace-pins.XXXXXX") || die "mktemp 失敗"
    rows=$(py plugins "$ROOT" "$MARKETPLACE") || { rm -f "$tsv"; die "讀不到 $MARKETPLACE_REL"; }
    while IFS=$'\t' read -r name src mk_v mk_b mk_sha pj_v pj_b pj_sha; do
        [ -n "$name" ] || continue
        plugin_meta "$name" "$src"
        latest=-; assets=-; installed=-
        if [ "$PM_REPO" != - ] && latest=$(latest_release "$PM_REPO"); then
            if release_lookup "$PM_REPO" "v$latest"; then
                if [ -n "$(asset_id "$PM_BINARY")" ] && [ -n "$(asset_id "$PM_BINARY.sha256")" ]; then
                    assets=yes
                else
                    assets=no
                fi
            fi
        else
            latest=-
        fi
        if [ "$PM_RECORD" != - ] && [ -f "$PM_RECORD" ]; then
            installed=$(tr -d '[:space:]' < "$PM_RECORD" 2>/dev/null)
            [ -n "$installed" ] || installed=-
        fi
        printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
            "$name" "$PM_KIND" "$PM_REPO" "$PM_BINARY" "$mk_v" "$mk_b" "$mk_sha" \
            "$pj_v" "$pj_b" "$pj_sha" "$latest" "$assets" "$installed" >> "$tsv"
    done <<< "$rows"
    py render "$fmt" "$tsv" "$CO_STATE" "$CO_BEHIND" "$CO_AHEAD" "$CO_EQUIV" \
        "$CO_UPSTREAM" "$CO_DETAIL" "$CO_LOCK_MTIME" "$CO_GIT_RUNNING"
    local rc=$?
    rm -f "$tsv"
    return "$rc"
}

# --------------------------------------------------------------------------
# main
# --------------------------------------------------------------------------
MARKETPLACE_NAME=$(python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1],encoding="utf-8"))["name"])' "$MARKETPLACE" 2>/dev/null || echo macdoc)
CACHE_ROOT=${MARKETPLACE_PINS_CACHE_ROOT:-$HOME/.claude/plugins/cache/$MARKETPLACE_NAME}
BIN_DIR=${MARKETPLACE_PINS_BIN_DIR:-${MACDOC_INSTALL_DIR:-$HOME/bin}}

[ $# -ge 1 ] || usage_error "缺少子指令"
sub=$1; shift
case "$sub" in
    status) cmd_status "$@" ;;
    -h|--help|help) sed -n '2,46p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' ;;
    *) usage_error "不認得的子指令：$sub" ;;
esac
