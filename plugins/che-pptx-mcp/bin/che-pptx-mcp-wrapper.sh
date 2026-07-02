#!/bin/bash
# Version-aware auto-download wrapper for ChePPTXMCP.
#
# Design:
# - Reads desired version from plugin.json (plugin's intended binary version)
# - Compares against ~/bin/.ChePPTXMCP.version sidecar
# - Re-downloads when plugin has been updated but binary is stale
# - Unique temp file (mktemp, same fs) + atomic mv so partial downloads never break things
# - Pinned version does NOT fall back to releases/latest (supply-chain pinning);
#   latest is used only when plugin.json carries no version
#
# Supply-chain verification (PsychQuant/macdoc#112 security review R1+R2):
# - sha256 (MANDATORY): release must ship ChePPTXMCP.sha256; missing/malformed/
#   mismatching asset refuses install (fail-closed integrity gate)
# - Code signature (AUTHENTICITY): requirement-based codesign check pins the
#   Apple chain + Team OU 6W377FS7BS. NOTE: a grep on `codesign -dvv` output is
#   spoofable via the attacker-controlled Identifier field, and --verify alone
#   accepts ad-hoc signatures (empirically reproduced in #112 verify round 1) —
#   only the -R requirement form is sound.
# - On any verification failure: keep + exec the existing binary if present
#   (fail-to-known-good), else exit 1.

set -u

REPO="PsychQuant/che-pptx-mcp"
BINARY_NAME="ChePPTXMCP"
INSTALL_DIR="$HOME/bin"
BINARY="$INSTALL_DIR/$BINARY_NAME"
VERSION_FILE="$INSTALL_DIR/.${BINARY_NAME}.version"
SCRIPT_ARGS=("$@")

# Locate plugin root via wrapper's own path (more reliable than $CLAUDE_PLUGIN_ROOT
# which isn't guaranteed in MCP spawn env). Wrapper lives at PLUGIN_ROOT/bin/*.sh.
PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLUGIN_JSON="$PLUGIN_ROOT/.claude-plugin/plugin.json"

run_existing_or_die() {
    # $1 = error message. Fail-to-known-good: prefer the already-installed
    # binary over aborting the MCP server spawn entirely.
    echo "$BINARY_NAME: ERROR — $1" >&2
    if [[ -x "$BINARY" ]]; then
        echo "$BINARY_NAME: keeping existing binary" >&2
        exec "$BINARY" ${SCRIPT_ARGS[@]+"${SCRIPT_ARGS[@]}"}
    fi
    exit 1
}

# Read desired version from plugin.json (empty string on any failure → latest).
DESIRED_VERSION=""
if [[ -f "$PLUGIN_JSON" ]]; then
    DESIRED_VERSION=$(grep -oE '"version":[[:space:]]*"[^"]+"' "$PLUGIN_JSON" 2>/dev/null \
        | head -1 | cut -d'"' -f4 || true)
fi

# Read currently installed version from sidecar (empty string if missing).
INSTALLED_VERSION=""
[[ -f "$VERSION_FILE" ]] && INSTALLED_VERSION=$(tr -d '[:space:]' < "$VERSION_FILE" 2>/dev/null || true)

# Decide whether to download.
NEED_DOWNLOAD=false
REASON=""
if [[ ! -x "$BINARY" ]]; then
    NEED_DOWNLOAD=true
    REASON="binary not installed"
elif [[ -n "$DESIRED_VERSION" ]] && [[ "$INSTALLED_VERSION" != "$DESIRED_VERSION" ]]; then
    NEED_DOWNLOAD=true
    REASON="plugin wants v${DESIRED_VERSION}, installed is v${INSTALLED_VERSION:-unknown}"
fi

if $NEED_DOWNLOAD; then
    echo "$BINARY_NAME: $REASON — downloading from $REPO..." >&2
    mkdir -p "$INSTALL_DIR"

    # Resolve release via the API-free direct-download endpoints (unauthenticated
    # api.github.com is rate-limited to 60 req/hr per IP and fails closed here;
    # the /releases/download/ redirect endpoints have no such limit).
    # Pinned version does NOT fall back to latest — a missing pinned tag is a
    # release-channel fault, not a downgrade licence.
    if [[ -n "$DESIRED_VERSION" ]]; then
        URL="https://github.com/$REPO/releases/download/v$DESIRED_VERSION/$BINARY_NAME"
        TARGET_DESC="v$DESIRED_VERSION"
    else
        URL="https://github.com/$REPO/releases/latest/download/$BINARY_NAME"
        TARGET_DESC="latest"
    fi

    TMP_FILE=$(mktemp "$INSTALL_DIR/.${BINARY_NAME}.download.XXXXXX") || run_existing_or_die "mktemp failed"
    trap 'rm -f "$TMP_FILE"' EXIT

    # -w url_effective: after redirects the final URL contains /download/vX.Y.Z/,
    # which is the authoritative resolved version (needed for the latest path).
    EFFECTIVE_URL=$(curl -fsSL --proto '=https' --tlsv1.2 --max-time 300 "$URL" -o "$TMP_FILE" -w '%{url_effective}' 2>/dev/null) \
        || run_existing_or_die "download failed for $TARGET_DESC at $REPO (pinned versions do not fall back to latest). Install manually: https://github.com/$REPO/releases"
    RESOLVED_VERSION=$(printf '%s' "$EFFECTIVE_URL" | sed -En 's#.*/download/v?([^/]+)/[^/]+$#\1#p')

    # 1. sha256 — mandatory fail-closed integrity gate.
    EXPECTED_SHA=$(curl -fsSL --proto '=https' --tlsv1.2 --max-time 30 "${URL}.sha256" 2>/dev/null \
        | head -1 | awk '{print $1}')
    [[ "$EXPECTED_SHA" =~ ^[0-9a-fA-F]{64}$ ]] \
        || run_existing_or_die "missing/malformed .sha256 release asset — refusing to install"
    ACTUAL_SHA=$(shasum -a 256 "$TMP_FILE" | awk '{print $1}')
    [[ "$ACTUAL_SHA" == "$EXPECTED_SHA" ]] \
        || run_existing_or_die "sha256 mismatch against release asset — refusing to install"

    # 2. Code signature — requirement-based authenticity gate (see header).
    codesign --verify --strict \
        -R '=anchor apple generic and certificate leaf[subject.OU] = "6W377FS7BS"' \
        "$TMP_FILE" 2>/dev/null \
        || run_existing_or_die "code-signature verification failed (not Developer ID Team 6W377FS7BS) — refusing to install"

    chmod +x "$TMP_FILE"
    mv "$TMP_FILE" "$BINARY"
    trap - EXIT
    echo "${RESOLVED_VERSION:-${DESIRED_VERSION:-unknown}}" > "$VERSION_FILE"
    echo "$BINARY_NAME: installed v${RESOLVED_VERSION:-${DESIRED_VERSION:-unknown}} (sha256 + Developer ID verified)" >&2
fi

exec "$BINARY" ${SCRIPT_ARGS[@]+"${SCRIPT_ARGS[@]}"}
