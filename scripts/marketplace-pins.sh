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
#       Report: per plugin the plugin.json and marketplace values, the
#       upstream latest release, whether that release ships the binary and its
#       .sha256, and the locally installed version; plus the state of this
#       checkout relative to its upstream branch. Changes no file in the
#       working tree, the index or any local branch; it does run `git fetch`
#       (no --prune), which updates remote-tracking refs.
#   update <plugin> [--to X.Y.Z] [--plugin-version X.Y.Z] [--dry-run]
#       Moves one plugin's pin to a release (default: latest), commits the
#       change locally and appends a row to docs/marketplace-pin-history.md.
#       Never pushes.
#   sync-local [--no-plugins]
#       Fast-forwards this checkout when it is strictly behind its upstream;
#       when already in sync it skips the git step. Any other state (ahead,
#       diverged, locked, operation in progress, no upstream, undeterminable)
#       is refused with HEAD unchanged. Then refreshes the locally installed
#       marketplace and the binary-backed plugins that have a directory in the
#       plugin cache.
#
# status exit codes
#    0  everything consistent and up to date
#   10  something is known to be behind or inconsistent: a pin older than the
#       latest release, a pinned release (= the latest) missing its binary or
#       .sha256, a marketplace entry that differs from its plugin.json, an
#       installed version that differs from the pin, or a checkout that is not
#       in sync with its upstream (including upstream-gone: the configured
#       upstream branch does not exist on the remote)
#    2  nothing is known to be behind, but something could not be determined
#       (release lookup failed, a pin or latest tag that is not X.Y.Z, plugin
#       installed but its installed-version record missing or unreadable,
#       fetch failed)
#   10 takes precedence over 2: a known problem is reported even when other
#   facts are unknown. A plugin that is not installed at all (MCP: no
#   directory in the plugin cache; CLI: no binary in the install dir) affects
#   neither: it is shown as 未安裝 and as installed_state "not-installed".
#   Notes that never change the exit code: the latest release is older than
#   the pin (it may be a prerelease or withdrawn), a newer latest release is
#   missing an asset, a plugin.json key that the wrappers read appears twice.
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
# Every git call in this script runs with submodule recursion off, so a user's
# submodule.recurse=true never makes it touch a submodule working directory.
# diff.ignoreSubmodules=none makes gitlink changes visible to the staged-path
# checks even when the user's config hides submodules (per-submodule
# `ignore` settings are overridden by --ignore-submodules=none at the call
# sites that inspect the index).
g() { git -c submodule.recurse=false -c diff.ignoreSubmodules=none -C "$ROOT" "$@"; }
# Never block on a credential prompt during fetch / ls-remote.
export GIT_TERMINAL_PROMPT=0

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
        dups = []
        try:
            dups = duplicate_keys(f"{root}/{src}/.claude-plugin/plugin.json")
        except OSError:
            pass
        row = [e["name"], src, e.get("version"), e.get("binary_version"), e.get("binary_sha256"),
               pj.get("version"), pj.get("binary_version"), pj.get("binary_sha256"), ",".join(dups)]
        print("\t".join("-" if v in (None, "") else str(v) for v in row))

PIN_KEYS = ("version", "binary_version", "binary_sha256")

def duplicate_keys(path):
    """Pin keys that occur more than once in the file text. The wrappers and
    hooks read the first textual occurrence while JSON parsing keeps the last."""
    with open(path, encoding="utf-8") as f:
        text = f.read()
    return [k for k in PIN_KEYS if len(re.findall(r'"%s"\s*:' % k, text)) > 1]

VERSION_RE = re.compile(r"^[0-9]+\.[0-9]+\.[0-9]+$")

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
            (name, kind, repo, binary, mk_v, mk_b, mk_sha, pj_v, pj_b, pj_sha, dups,
             latest, assets, installed, inst_state) = (none_if_dash(x) for x in line.rstrip("\n").split("\t"))
            problems, unknown, notes = [], [], []
            if (mk_v, mk_b, mk_sha) != (pj_v, pj_b, pj_sha):
                problems.append("marketplace-mismatch")
            pin_ok = pj_b is not None and bool(VERSION_RE.match(pj_b))
            latest_ok = latest is not None and bool(VERSION_RE.match(latest))
            if pj_b is not None and not pin_ok:
                unknown.append("pin-unparseable")
            if latest is None:
                unknown.append("latest-release")
            elif not latest_ok:
                unknown.append("latest-unparseable")
            if pin_ok and latest_ok:
                if vtuple(latest) > vtuple(pj_b):
                    problems.append("pin-behind-release")
                elif vtuple(latest) < vtuple(pj_b):
                    notes.append("pin-ahead-of-release")
            if latest_ok and assets is None:
                unknown.append("latest-assets")
            elif assets == "no":
                if latest == pj_b:
                    problems.append("pinned-release-assets-incomplete")
                else:
                    notes.append("latest-assets-incomplete")
            if dups:
                notes.append("duplicate-keys")
            if inst_state == "unknown":
                unknown.append("installed")
            elif inst_state == "known" and installed != pj_b:
                problems.append("installed-differs")
            rows.append({
                "name": name, "kind": kind, "upstream_repo": repo, "binary": binary,
                "plugin_json": {"version": pj_v, "binary_version": pj_b, "binary_sha256": pj_sha},
                "marketplace": {"version": mk_v, "binary_version": mk_b, "binary_sha256": mk_sha},
                "latest_release": latest,
                "latest_assets_complete": None if assets is None else assets == "yes",
                "installed": installed,
                "installed_state": inst_state,
                "duplicate_keys": dups.split(",") if dups else [],
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
              "latest-assets-incomplete": "最新 release 缺 binary 或 .sha256",
              "pinned-release-assets-incomplete": "pin 的 release 缺 binary 或 .sha256（新安裝會失敗）",
              "pin-unparseable": "pin 不是 X.Y.Z，無法比較",
              "latest-unparseable": "最新 release 的 tag 不是 X.Y.Z，無法比較",
              "pin-ahead-of-release": "pin 比最新 release 新（latest 可能是較舊的正式版，pin 可能指向 prerelease 或已撤回的版本）",
              "duplicate-keys": "plugin.json 有重複的 key"}
    for r in rows:
        pj, mk = r["plugin_json"], r["marketplace"]
        assets = {True: "齊全", False: "不齊", None: U}[r["latest_assets_complete"]]
        issues = "；".join(labels[k] + (f"（{', '.join(r['duplicate_keys'])}）" if k == "duplicate-keys" else "")
                          for k in r["problems"] + r["unknown"] + r["notes"]) or "—"
        table.append([r["name"], f"{pj['version'] or U} / {pj['binary_version'] or U}",
                      f"{mk['version'] or U} / {mk['binary_version'] or U}",
                      r["latest_release"] or U, assets,
                      "未安裝" if r["installed_state"] == "not-installed" else (r["installed"] or U),
                      issues])
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
    if s == "upstream-gone":
        return f"已設定 upstream {up}，但遠端沒有這個分支（已被刪除或從未推送）"
    return f"無法判定（{co['detail']}）"

def entry_kind(marketplace, name):
    """exit 0 binary-backed, 3 unknown plugin, 4 no binary_version."""
    for e in load(marketplace)["plugins"]:
        if e.get("name") == name:
            return 0 if "binary_version" in e else 4
    return 3

def consistency(root, marketplace):
    """Compare (version, binary_version, binary_sha256) of every entry with its plugin.json."""
    bad = []
    for e in load(marketplace)["plugins"]:
        src = e.get("source", "")
        try:
            pj = load(f"{root}/{src}/.claude-plugin/plugin.json")
        except (OSError, ValueError) as err:
            bad.append(f"{e.get('name')}: 讀不到 plugin.json（{err}）")
            continue
        for key in ("version", "binary_version", "binary_sha256"):
            if e.get(key) != pj.get(key):
                bad.append(f"{e.get('name')}: {key} marketplace={e.get(key)} plugin.json={pj.get(key)}")
    for line in bad:
        print(line)
    return 1 if bad else 0

def edit_marketplace(path, name, version, binary, sha):
    with open(path, encoding="utf-8") as f:
        text = f.read()
    data = json.loads(text)
    if dumps(data) != text:
        print(f"{path}: 重新序列化後與原檔不同，拒絕改寫（避免動到 pin 以外的內容）", file=sys.stderr)
        return 1
    hits = [e for e in data["plugins"] if e.get("name") == name]
    if len(hits) != 1:
        print(f"{path}: 找到 {len(hits)} 個名為 {name} 的條目", file=sys.stderr)
        return 1
    hits[0]["version"] = version
    hits[0]["binary_version"] = binary
    if sha != "-":
        hits[0]["binary_sha256"] = sha
    with open(path, "w", encoding="utf-8") as f:
        f.write(dumps(data))
    return 0

def edit_plugin_json(path, *triples):
    """Replace the literal `"key": "old"` with `"key": "new"`; each must occur exactly once."""
    with open(path, encoding="utf-8") as f:
        text = f.read()
    for i in range(0, len(triples), 3):
        key, old, new = triples[i:i + 3]
        needle = f'"{key}": "{old}"'
        if text.count(needle) != 1:
            print(f"{path}: {needle} 出現 {text.count(needle)} 次（應為 1 次），拒絕改寫", file=sys.stderr)
            return 1
        text = text.replace(needle, f'"{key}": "{new}"')
    json.loads(text)
    with open(path, "w", encoding="utf-8") as f:
        f.write(text)
    return 0

def changelog(path, version, date, old, new):
    """Insert a section above the first versioned `## [X` heading ([Unreleased] stays on top)."""
    with open(path, encoding="utf-8") as f:
        lines = f.read().splitlines(keepends=True)
    block = [f"## [{version}] - {date}\n", "\n", "### Changed\n", "\n",
             f"- binary {old} → {new}。細節見上游的 CHANGELOG。\n", "\n"]
    at = next((i for i, l in enumerate(lines) if re.match(r"## \[\d", l)), None)
    if at is None:
        if lines and not lines[-1].endswith("\n"):
            lines[-1] += "\n"
        lines += ["\n"] + block[:-1]
    else:
        lines[at:at] = block
    with open(path, "w", encoding="utf-8") as f:
        f.write("".join(lines))
    return 0

HISTORY_HEADER = ("# Marketplace pin 更新紀錄\n\n"
                  "由 `scripts/marketplace-pins.sh update` 附加，一次更新一列，和 pin 的變更在同一個 commit。\n\n"
                  "| 日期 | plugin | 舊 binary | 新 binary | release commit |\n|---|---|---|---|---|\n")

def history(path, date, plugin, old, new, commit):
    try:
        with open(path, encoding="utf-8") as f:
            text = f.read()
    except FileNotFoundError:
        text = HISTORY_HEADER
    if text and not text.endswith("\n"):
        text += "\n"
    text += f"| {date} | {plugin} | {old} | {new} | {commit} |\n"
    import os
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        f.write(text)
    return 0

cmd, args = sys.argv[1], sys.argv[2:]
if cmd == "plugins":
    plugins(*args)
elif cmd == "render":
    sys.exit(render(*args))
elif cmd == "dup-keys":
    dups = duplicate_keys(args[0])
    print(" ".join(dups))
    sys.exit(1 if dups else 0)
elif cmd == "entry-kind":
    sys.exit(entry_kind(*args))
elif cmd == "consistency":
    sys.exit(consistency(*args))
elif cmd == "edit-marketplace":
    sys.exit(edit_marketplace(*args))
elif cmd == "edit-plugin-json":
    sys.exit(edit_plugin_json(*args))
elif cmd == "changelog":
    sys.exit(changelog(*args))
elif cmd == "history":
    sys.exit(history(*args))
elif cmd == "mtime":
    import datetime, os
    print(datetime.datetime.fromtimestamp(os.path.getmtime(args[0])).astimezone().isoformat(timespec="seconds"))
else:
    sys.exit(f"internal: unknown py command {cmd}")
PY
}

# --------------------------------------------------------------------------
# Checkout state classifier (shared by all subcommands)
# Sets CO_STATE: in-progress | locked | no-upstream | upstream-gone | unknown |
# in-sync | behind | ahead | diverged, plus CO_BEHIND CO_AHEAD CO_EQUIV CO_UPSTREAM
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
    local branch merge remote_refs
    if ! branch=$(g symbolic-ref -q --short HEAD); then CO_STATE=no-upstream; CO_DETAIL="detached HEAD"; return; fi
    # The upstream comes from the branch config, not from @{u}: @{u} needs a
    # remote-tracking ref, which is missing when the branch was never fetched.
    CO_REMOTE=$(g config "branch.$branch.remote" 2>/dev/null) || CO_REMOTE=
    merge=$(g config "branch.$branch.merge" 2>/dev/null) || merge=
    if [ -z "$CO_REMOTE" ] || [ -z "$merge" ]; then
        CO_REMOTE=-; CO_STATE=no-upstream; CO_DETAIL=$branch; return
    fi
    CO_UPSTREAM="$CO_REMOTE/${merge#refs/heads/}"
    if [ "$CO_REMOTE" = . ]; then
        CO_STATE=unknown; CO_DETAIL="upstream ${merge} 是本機分支，不是遠端分支"; return
    fi
    # No --prune: a status run must not delete the user's remote-tracking refs.
    if ! g fetch --quiet --no-recurse-submodules "$CO_REMOTE" </dev/null >/dev/null 2>&1; then
        CO_STATE=unknown; CO_DETAIL="fetch $CO_REMOTE 失敗，無法確認與 $CO_UPSTREAM 的關係"; return
    fi
    # The fetch does not prune, so a stale remote-tracking ref can outlive a
    # deleted upstream branch; ask the remote whether the branch still exists.
    if ! remote_refs=$(g ls-remote "$CO_REMOTE" "$merge" </dev/null 2>/dev/null); then
        CO_STATE=unknown; CO_DETAIL="ls-remote $CO_REMOTE 失敗，無法確認 $CO_UPSTREAM 是否存在"; return
    fi
    if ! printf '%s\n' "$remote_refs" | awk -v r="$merge" '$2 == r { found = 1 } END { exit !found }'; then
        CO_STATE=upstream-gone; CO_DETAIL="遠端 $CO_REMOTE 沒有 $merge"; return
    fi
    if ! g rev-parse -q --verify '@{u}' >/dev/null 2>&1; then
        CO_STATE=unknown; CO_DETAIL="遠端有 ${merge}，但 fetch 後仍沒有對應的 remote-tracking ref（檢查 remote.$CO_REMOTE.fetch）"; return
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
# and PM_PRESENCE (the path whose absence means "not installed").
plugin_meta() {
    local name=$1 dir="$ROOT/${2#./}" f
    PM_KIND=-; PM_REPO=-; PM_BINARY=-; PM_RECORD=-; PM_PRESENCE=-
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
        PM_PRESENCE="$CACHE_ROOT/$name"
    else
        PM_RECORD="$BIN_DIR/.$PM_BINARY.installed_version"
        PM_PRESENCE="$BIN_DIR/$PM_BINARY"
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

# latest_release <owner/repo>: prints the latest release tag without its
# leading "v", as-is (callers check is_version); fails when the lookup fails.
latest_release() {
    local tag
    tag=$("$GH" api "repos/$1/releases/latest" --jq .tag_name </dev/null 2>/dev/null) || return 1
    tag=${tag#v}
    case "$tag" in ''|*[[:space:]]*) return 1 ;; esac
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
    local tsv rows name src mk_v mk_b mk_sha pj_v pj_b pj_sha dups latest assets installed inst_state
    tsv=$(mktemp "${TMPDIR:-/tmp}/marketplace-pins.XXXXXX") || die "mktemp 失敗"
    rows=$(py plugins "$ROOT" "$MARKETPLACE") || { rm -f "$tsv"; die "讀不到 $MARKETPLACE_REL"; }
    while IFS=$'\t' read -r name src mk_v mk_b mk_sha pj_v pj_b pj_sha dups; do
        [ -n "$name" ] || continue
        plugin_meta "$name" "$src"
        latest=-; assets=-; installed=-
        if [ "$PM_REPO" != - ] && latest=$(latest_release "$PM_REPO"); then
            if is_version "$latest" && release_lookup "$PM_REPO" "v$latest"; then
                if [ -n "$(asset_id "$PM_BINARY")" ] && [ -n "$(asset_id "$PM_BINARY.sha256")" ]; then
                    assets=yes
                else
                    assets=no
                fi
            fi
        else
            latest=-
        fi
        # not-installed: MCP has no plugin-cache dir / CLI has no binary.
        # unknown: installed, but the version record is missing or unreadable.
        inst_state=unknown
        if [ "$PM_PRESENCE" != - ] && [ ! -e "$PM_PRESENCE" ]; then
            inst_state=not-installed
        elif [ "$PM_RECORD" != - ] && [ -f "$PM_RECORD" ]; then
            installed=$(tr -d '[:space:]' < "$PM_RECORD" 2>/dev/null)
            if [ -n "$installed" ]; then inst_state=known; else installed=-; fi
        fi
        printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
            "$name" "$PM_KIND" "$PM_REPO" "$PM_BINARY" "$mk_v" "$mk_b" "$mk_sha" \
            "$pj_v" "$pj_b" "$pj_sha" "$dups" "$latest" "$assets" "$installed" "$inst_state" >> "$tsv"
    done <<< "$rows"
    py render "$fmt" "$tsv" "$CO_STATE" "$CO_BEHIND" "$CO_AHEAD" "$CO_EQUIV" \
        "$CO_UPSTREAM" "$CO_DETAIL" "$CO_LOCK_MTIME" "$CO_GIT_RUNNING"
    local rc=$?
    rm -f "$tsv"
    return "$rc"
}

# --------------------------------------------------------------------------
# update
# --------------------------------------------------------------------------
is_sha1() { [[ "$1" =~ ^[0-9a-f]{40}$ ]]; }

# submodule_for_repo <owner/repo>: prints "<path>\t<url>" of the .gitmodules
# entry whose URL ends in that owner/repo (ssh, https or path form; compared
# case-insensitively, as GitHub does).
submodule_for_repo() {
    local want key url name u repo owner
    want=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
    [ -f "$ROOT/.gitmodules" ] || return 1
    while read -r key url; do
        name=${key#submodule.}; name=${name%.url}
        u=${url%/}; u=${u%.git}
        repo=${u##*/}; owner=${u%/*}; owner=${owner##*/}; owner=${owner##*:}
        if [ "$(printf '%s/%s' "$owner" "$repo" | tr '[:upper:]' '[:lower:]')" = "$want" ]; then
            printf '%s\t%s\n' "$(g config -f .gitmodules --get "submodule.$name.path")" "$url"
            return 0
        fi
    done < <(g config -f .gitmodules --get-regexp '^submodule\..*\.url$' 2>/dev/null)
    return 1
}

# tag_commit <url> <tag>: full commit id the tag points at (peeled when annotated).
tag_commit() {
    local out sha
    for ref in "refs/tags/$2^{}" "refs/tags/$2"; do
        out=$(GIT_TERMINAL_PROMPT=0 git ls-remote "$1" "$ref" </dev/null 2>/dev/null) || return 1
        sha=$(printf '%s\n' "$out" | awk 'NR == 1 { print $1 }')
        if [ -n "$sha" ]; then
            is_sha1 "$sha" || return 1
            echo "$sha"; return 0
        fi
    done
    return 1
}

cmd_update() {
    local plugin="" to="" pv="" dry=false
    while [ $# -gt 0 ]; do
        case "$1" in
            --to) [ $# -ge 2 ] || usage_error "--to 需要版本"; to=$2; shift ;;
            --plugin-version) [ $# -ge 2 ] || usage_error "--plugin-version 需要版本"; pv=$2; shift ;;
            --dry-run) dry=true ;;
            -*) usage_error "update 不認得的參數：$1" ;;
            *) [ -z "$plugin" ] || usage_error "只能指定一個 plugin"; plugin=$1 ;;
        esac
        shift
    done
    [ -n "$plugin" ] || usage_error "update 需要 plugin 名稱"
    [ -z "$to" ] || is_version "$to" || die "--to 必須是 X.Y.Z 形式的版本（收到 ${to}）"
    [ -z "$pv" ] || is_version "$pv" || die "--plugin-version 必須是 X.Y.Z 形式的版本（收到 ${pv}）"
    [ -f "$MARKETPLACE" ] || die "找不到 $MARKETPLACE_REL"

    py entry-kind "$MARKETPLACE" "$plugin"
    case $? in
        0) ;;
        3) die "marketplace 裡沒有名為 $plugin 的 plugin" ;;
        4) die "$plugin 沒有 binary_version，不是由本腳本管理的 binary pin" ;;
        *) die "讀不到 $MARKETPLACE_REL" ;;
    esac
    local name src mk_v mk_b mk_sha pj_v pj_b pj_sha dups
    IFS=$'\t' read -r name src mk_v mk_b mk_sha pj_v pj_b pj_sha dups \
        < <(py plugins "$ROOT" "$MARKETPLACE" | awk -F'\t' -v n="$plugin" '$1 == n')
    [ "$name" = "$plugin" ] || die "讀不到 $plugin 的 plugin.json"
    is_version "$pj_b" || die "$plugin 的 plugin.json binary_version 不是 X.Y.Z（${pj_b}）"
    is_version "$pj_v" || die "$plugin 的 plugin.json version 不是 X.Y.Z（${pj_v}）"
    # The wrappers and hooks read the first textual occurrence of a key, JSON
    # parsing the last; with a duplicate, the edit could change the wrong one.
    [ "$dups" = - ] || die "$plugin 的 plugin.json 裡這些 key 重複出現：${dups}。先手動整理成一個再更新"
    plugin_meta "$plugin" "$src"
    [ "$PM_REPO" != - ] && [ "$PM_BINARY" != - ] || die "無法從 $plugin 的 wrapper 或 hook 讀出上游 REPO 與 BINARY_NAME"

    # 1. Checkout must be in sync with its upstream.
    classify_checkout
    [ "$CO_STATE" = in-sync ] || die "本機 checkout 必須與 upstream 同步才能更新 pin（目前狀態：${CO_STATE}；${CO_DETAIL}）。先執行 status 查看"

    # 2. Files to edit: no uncommitted changes, and nothing staged at all
    #    (the commit below takes the whole index; see the commit step).
    local src_rel=${src#./}
    local pj_rel="$src_rel/.claude-plugin/plugin.json" cl_rel="$src_rel/CHANGELOG.md"
    local files=("$MARKETPLACE_REL" "$pj_rel" "$cl_rel" "$HISTORY_REL")
    [ -f "$ROOT/$cl_rel" ] || die "找不到 $cl_rel"
    local dirty
    dirty=$(g status --porcelain=v1 --untracked-files=all -- "${files[@]}") || die "git status 失敗"
    [ -z "$dirty" ] || die "要修改的檔案有未提交的變更：
$dirty"
    g diff --cached --quiet --ignore-submodules=none || die "index 有已暫存的變更，先 commit 或取消暫存再更新 pin：
$(g diff --cached --name-status --ignore-submodules=none)"

    local sub_path="" sub_url="" old_link=""
    if [ "$PM_KIND" = mcp ]; then
        local sub
        sub=$(submodule_for_repo "$PM_REPO") || die ".gitmodules 裡找不到 $PM_REPO 的 submodule"
        sub_path=${sub%%$'\t'*}; sub_url=${sub#*$'\t'}
        old_link=$(g ls-files -s -- "$sub_path" | awk '$1 == "160000" { print $2 }')
        is_sha1 "$old_link" || die "$sub_path 在 index 裡不是 gitlink"
    fi

    # 3. Target release: exists, ships both assets, strictly newer than the pin.
    if [ -z "$to" ]; then
        to=$(latest_release "$PM_REPO") || die "查不到 $PM_REPO 的最新 release（gh 失敗或沒有 release），不更新"
        is_version "$to" || die "$PM_REPO 最新 release 的 tag v$to 不是 X.Y.Z，不更新；需要時用 --to 指定版本"
    fi
    version_gt "$to" "$pj_b" || die "目標 $to 不比目前的 pin $pj_b 新"

    local new_pv
    if [ "$pj_v" = "$pj_b" ]; then
        [ -z "$pv" ] || [ "$pv" = "$to" ] || die "$plugin 的 version 與 binary_version 同步，--plugin-version 必須等於 ${to}（收到 ${pv}）"
        new_pv=$to
    else
        [ -n "$pv" ] || die "$plugin 的 version（${pj_v}）與 binary_version（${pj_b}）不同，必須用 --plugin-version 指定新的 plugin 版本"
        version_gt "$pv" "$pj_v" || die "--plugin-version $pv 必須比目前的 $pj_v 新"
        new_pv=$pv
    fi

    release_lookup "$PM_REPO" "v$to" || die "查不到 $PM_REPO 的 release v${to}（gh 失敗或 release 不存在）"
    local a
    for a in "$PM_BINARY" "$PM_BINARY.sha256"; do
        [ -n "$(asset_id "$a")" ] || die "$PM_REPO 的 release v$to 缺少 asset：$a"
    done
    local new_sha=-
    if [ "$pj_sha" != - ]; then
        new_sha=$("$GH" api "repos/$PM_REPO/releases/assets/$(asset_id "$PM_BINARY.sha256")" \
            -H 'Accept: application/octet-stream' </dev/null 2>/dev/null | awk 'NR == 1 { print $1 }')
        [[ "$new_sha" =~ ^[0-9a-fA-F]{64}$ ]] || die "讀不到 $PM_BINARY.sha256 的內容，或內容不是 64 位 hex"
        # The session-start hook compares sha256 strings; shasum prints lowercase.
        new_sha=$(printf '%s' "$new_sha" | tr 'A-F' 'a-f')
    fi

    # 4. The tag's commit (gitlink target for MCP plugins, history row for all).
    local url=$sub_url
    [ -n "$url" ] || url=$(g remote get-url "$CO_REMOTE" 2>/dev/null) || die "讀不到 remote $CO_REMOTE 的 URL"
    local commit
    commit=$(tag_commit "$url" "v$to") || die "上游（${url}）沒有 tag v${to}，或 ls-remote 失敗"
    if is_sha1 "$REL_TARGET" && [ "$REL_TARGET" != "$commit" ]; then
        echo "警告：release v$to 記錄的 target $REL_TARGET 與 tag 指向的 $commit 不同；以 tag 為準" >&2
    fi

    local msg="chore: $plugin plugin ${new_pv}，binary $pj_b → $to"
    [ -z "$sub_path" ] || msg="${msg}，gitlink 指向 v$to"

    echo "${plugin}：binary $pj_b → ${to}，plugin version $pj_v → $new_pv"
    echo "  上游 $PM_REPO v${to}（tag commit ${commit}）"
    [ -z "$sub_path" ] || echo "  gitlink ${sub_path}：$old_link → $commit"
    [ "$new_sha" = - ] || echo "  binary_sha256：$pj_sha → $new_sha"
    echo "  修改：${files[*]}${sub_path:+ $sub_path}"
    echo "  commit 訊息：$msg"
    if $dry; then
        echo "（--dry-run：沒有修改任何檔案）"
        return 0
    fi

    # 5. Edit, with a backup to restore from on any failure or interruption.
    local backup f base_head
    base_head=$(g rev-parse HEAD) || die "讀不到 HEAD"
    backup=$(mktemp -d "${TMPDIR:-/tmp}/marketplace-pins-backup.XXXXXX") || die "mktemp 失敗"
    for f in "${files[@]}"; do
        mkdir -p "$backup/$(dirname "$f")"
        if [ -f "$ROOT/$f" ]; then cp -p "$ROOT/$f" "$backup/$f"; fi
    done
    restore() {   # idempotent: a second call finds no backup and does nothing
        local f
        [ -d "$backup" ] || return 0
        for f in "${files[@]}"; do
            if [ -f "$backup/$f" ]; then cp -p "$backup/$f" "$ROOT/$f"; else rm -f "$ROOT/$f"; fi
        done
        # HEAD holds the original content of every touched path (checked above).
        g reset -q -- "${files[@]}" ${sub_path:+"$sub_path"} 2>/dev/null
        rm -rf "$backup"
    }
    fail() { trap - INT TERM HUP; restore; die "$1（已還原所有改動）"; }
    # Bash runs a trap only after the foreground command (e.g. git commit and
    # its hooks) returns, so on a signal the commit has either happened or not:
    # decide by HEAD, then re-raise so the caller sees the real termination.
    on_signal() {
        trap - INT TERM HUP
        if [ "$(g rev-parse HEAD 2>/dev/null)" != "$base_head" ]; then
            rm -rf "$backup"
            echo "收到 $1：commit 已完成（$(g log -1 --format='%h %s')），沒有還原；已清除備份。尚未推送" >&2
        else
            restore
            echo "收到 $1：已還原所有改動（檔案、index 與 gitlink），沒有建立 commit" >&2
        fi
        kill -s "$1" $$
    }
    trap 'on_signal INT' INT
    trap 'on_signal TERM' TERM
    trap 'on_signal HUP' HUP

    py edit-marketplace "$MARKETPLACE" "$plugin" "$new_pv" "$to" "$new_sha" || fail "改寫 $MARKETPLACE_REL 失敗"
    local triples=(version "$pj_v" "$new_pv" binary_version "$pj_b" "$to")
    [ "$new_sha" = - ] || triples+=(binary_sha256 "$pj_sha" "$new_sha")
    py edit-plugin-json "$ROOT/$pj_rel" "${triples[@]}" || fail "改寫 $pj_rel 失敗"
    py changelog "$ROOT/$cl_rel" "$new_pv" "$TODAY" "$pj_b" "$to" || fail "改寫 $cl_rel 失敗"
    py history "$HISTORY" "$TODAY" "$plugin" "$pj_b" "$to" "$commit" || fail "改寫 $HISTORY_REL 失敗"
    if [ -n "$sub_path" ]; then
        g update-index --cacheinfo "160000,$commit,$sub_path" || fail "更新 $sub_path 的 gitlink 失敗"
    fi

    # 6. Full-table comparison of every marketplace entry against its plugin.json.
    local mismatch
    if ! mismatch=$(py consistency "$ROOT" "$MARKETPLACE"); then
        fail "marketplace 與 plugin.json 全表比對不一致：
$mismatch"
    fi

    # 7. Commit. Paths are staged explicitly and the commit takes the index as
    #    is: a pathspec commit (`git commit -- <paths>`) re-reads each path from
    #    the working tree, which would drop the gitlink written into the index
    #    above (the submodule working dir is never touched).
    g add -- "${files[@]}" || fail "git add 失敗"
    local expected staged
    expected=$(printf '%s\n' "${files[@]}" ${sub_path:+"$sub_path"} | sort)
    staged=$(g diff --cached --name-only --ignore-submodules=none | sort)
    [ "$staged" = "$expected" ] || fail "暫存區的內容與預期不符：
$staged"
    g commit -q -m "$msg" || fail "git commit 失敗"
    rm -rf "$backup"
    trap - INT TERM HUP
    local changed
    changed=$(g diff-tree --no-commit-id --name-only -r HEAD | sort)
    [ "$changed" = "$expected" ] || echo "警告：commit 的檔案與預期不符，請檢查：$changed" >&2

    local branch=${CO_UPSTREAM#"$CO_REMOTE"/}
    echo
    echo "已建立 commit：$(g log -1 --format='%h %s')"
    [ -z "$sub_path" ] || echo "（之後 git status 會顯示 $sub_path 已修改：gitlink 已前進，submodule 的工作目錄刻意沒有動）"
    echo "沒有推送。確認後在 repo 根目錄推送："
    echo "  git push $CO_REMOTE HEAD:$branch"
}

# --------------------------------------------------------------------------
# sync-local
# --------------------------------------------------------------------------
cmd_sync_local() {
    local plugins=true
    while [ $# -gt 0 ]; do
        case "$1" in
            --no-plugins) plugins=false ;;
            *) usage_error "sync-local 不認得的參數：$1" ;;
        esac
        shift
    done
    classify_checkout
    local ffwd=false
    case "$CO_STATE" in
        behind)
            echo "本機落後 $CO_UPSTREAM ${CO_BEHIND} 個 commit，快轉中…"
            # Never recurse into submodules: their working dirs are left as they are.
            g merge --ff-only --quiet '@{u}' \
                || die "git merge --ff-only 失敗，HEAD 沒有改變"
            ffwd=true
            echo "已快轉到 $(g log -1 --format='%h %s')" ;;
        in-sync) echo "本機已與 $CO_UPSTREAM 同步，沒有需要快轉的 commit" ;;
        ahead) die "本機有 ${CO_AHEAD} 個未推送的 commit，不能快轉；先推送或自行處理" ;;
        diverged) die "本機與 $CO_UPSTREAM 分岔（落後 ${CO_BEHIND}、領先 ${CO_AHEAD}，本機多出的 commit 中有 ${CO_EQUIV} 個在上游有相同內容，上游歷史可能被改寫）。不自動處理，以免丟掉本機的工作" ;;
        locked) die "有 index.lock（修改時間 ${CO_LOCK_MTIME}；目前 git 程序在跑：${CO_GIT_RUNNING}），不能 merge。本腳本不會移除它" ;;
        in-progress) die "有進行中的 git 操作（${CO_DETAIL}），請先完成或中止" ;;
        no-upstream) die "目前分支沒有設定 upstream（${CO_DETAIL}），不知道要快轉到哪裡" ;;
        upstream-gone) die "已設定 upstream ${CO_UPSTREAM}，但遠端沒有這個分支（${CO_DETAIL}），不能快轉" ;;
        *) die "無法判定本機與 upstream 的關係：${CO_DETAIL}" ;;
    esac

    $plugins || return 0
    local rc=0 name src rest
    echo "更新本機的 marketplace 與已安裝的 plugin…"
    "$CLAUDE" plugin marketplace update "$MARKETPLACE_NAME" </dev/null \
        || { echo "錯誤：claude plugin marketplace update $MARKETPLACE_NAME 失敗" >&2; rc=1; }
    while IFS=$'\t' read -r name src rest; do
        [ -n "$name" ] || continue
        # Installed plugins have a directory in this marketplace's plugin cache.
        if [ ! -d "$CACHE_ROOT/$name" ]; then
            echo "  略過 ${name}（本機沒有安裝）"
            continue
        fi
        "$CLAUDE" plugin update "$name@$MARKETPLACE_NAME" </dev/null \
            || { echo "錯誤：claude plugin update $name@$MARKETPLACE_NAME 失敗" >&2; rc=1; }
    done < <(py plugins "$ROOT" "$MARKETPLACE")
    if [ "$rc" != 0 ]; then
        if $ffwd; then
            echo "plugin 更新有失敗的項目；checkout 的快轉已完成，不會還原" >&2
        else
            echo "plugin 更新有失敗的項目（checkout 原本就已同步，沒有變動）" >&2
        fi
    fi
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
    update) cmd_update "$@" ;;
    sync-local) cmd_sync_local "$@" ;;
    -h|--help|help) awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "${BASH_SOURCE[0]}" ;;
    *) usage_error "不認得的子指令：$sub" ;;
esac
