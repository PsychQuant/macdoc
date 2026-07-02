#!/bin/bash
# Version-aware auto-download wrapper for CheWordMCP.
#
# Design:
# - Reads desired version from plugin.json (plugin's intended binary version)
# - Compares against ~/bin/.CheWordMCP.version sidecar
# - Re-downloads when plugin has been updated but binary is stale
# - Unique temp file (mktemp, same fs) + atomic mv so partial downloads never break things
# - Pinned version does NOT fall back to releases/latest (supply-chain pinning);
#   latest is used only when plugin.json carries no version
#
# Supply-chain verification (PsychQuant/macdoc#112 security review R1+R2):
# - sha256 (MANDATORY): release must ship CheWordMCP.sha256; missing/malformed/
#   mismatching asset refuses install (fail-closed integrity gate)
# - Code signature (AUTHENTICITY): requirement-based codesign check pins the
#   Apple chain + Team OU 6W377FS7BS. NOTE: a grep on `codesign -dvv` output is
#   spoofable via the attacker-controlled Identifier field, and --verify alone
#   accepts ad-hoc signatures (empirically reproduced in #112 verify round 1) —
#   only the -R requirement form is sound.
# - On any verification failure: keep + exec the existing binary if present
#   (fail-to-known-good), else exit 1.

set -u

REPO="PsychQuant/che-word-mcp"
BINARY_NAME="CheWordMCP"
INSTALL_DIR="$HOME/bin"
BINARY="$INSTALL_DIR/$BINARY_NAME"
VERSION_FILE="$INSTALL_DIR/.${BINARY_NAME}.version"
SCRIPT_ARGS=("$@")

# Locate plugin root via wrapper's own path (more reliable than $CLAUDE_PLUGIN_ROOT
# which isn't guaranteed in MCP spawn env). Wrapper lives at PLUGIN_ROOT/bin/*.sh.
PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLUGIN_JSON="$PLUGIN_ROOT/.claude-plugin/plugin.json"

verify_binary() {
    # Developer ID Application (marker OIDs) + Team OU pin. Runs on every
    # candidate before exec — download-time AND exec-time (#112 verify R2:
    # binaries installed by the pre-hardening wrapper — including ad-hoc
    # ones — carry a matching sidecar and would otherwise never be re-checked).
    codesign --verify --strict \
        -R '=anchor apple generic and certificate 1[field.1.2.840.113635.100.6.2.6] exists and certificate leaf[field.1.2.840.113635.100.6.1.13] exists and certificate leaf[subject.OU] = "6W377FS7BS"' \
        "$1" 2>/dev/null
}

run_existing_or_die() {
    # $1 = error message. Fail-to-VERIFIED-good: prefer the already-installed
    # binary over aborting the MCP server spawn — but only if it passes the
    # same signature gate as a fresh download.
    echo "$BINARY_NAME: ERROR — $1" >&2
    rm -f "${TMP_FILE:-}" 2>/dev/null   # trap EXIT does not fire across exec — clean up rejected download here
    if [[ -x "$BINARY" ]] && verify_binary "$BINARY"; then
        echo "$BINARY_NAME: keeping existing (signature-verified) binary" >&2
        exec "$BINARY" ${SCRIPT_ARGS[@]+"${SCRIPT_ARGS[@]}"}
    fi
    exit 1
}

# Read desired BINARY version from plugin.json. Since #116 the shell version
# ("version") and the binary release tag ("binary_version") are decoupled —
# shell-only changes bump "version" freely. Prefer "binary_version"; fall back
# to "version" ONLY when the key is absent entirely (plugin.json predates the
# field — backward compat). A binary_version key that exists but is empty or
# malformed fails closed instead of silently chasing the shell version tag.
DESIRED_VERSION=""
if [[ -f "$PLUGIN_JSON" ]]; then
    if grep -qE '"binary_version"[[:space:]]*:' "$PLUGIN_JSON" 2>/dev/null; then
        DESIRED_VERSION=$(grep -oE '"binary_version"[[:space:]]*:[[:space:]]*"[^"]+"' "$PLUGIN_JSON" 2>/dev/null \
            | head -1 | sed -E 's/.*"([^"]+)"$/\1/' || true)
        if [[ -z "$DESIRED_VERSION" ]]; then
            run_existing_or_die "binary_version present in plugin.json but empty/malformed — refusing to guess a release tag"
        fi
    else
        DESIRED_VERSION=$(grep -oE '"version"[[:space:]]*:[[:space:]]*"[^"]+"' "$PLUGIN_JSON" 2>/dev/null \
            | head -1 | sed -E 's/.*"([^"]+)"$/\1/' || true)
    fi
    if [[ -z "$DESIRED_VERSION" ]]; then
        # plugin.json exists but version unparseable — fail closed rather than
        # silently degrading to the unpinned latest channel (#112 verify R2).
        run_existing_or_die "cannot parse version from plugin.json — refusing unpinned download"
    fi
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

    # NOTE: successful downloads redirect to the release-assets CDN, so the
    # effective URL does NOT expose the tag — the sidecar records the pinned
    # version (all shipped plugins pin one; the latest path records "unknown").
    curl -fsSL --proto '=https' --tlsv1.2 --max-time 300 "$URL" -o "$TMP_FILE" 2>/dev/null \
        || run_existing_or_die "download failed for $TARGET_DESC at $REPO (pinned versions do not fall back to latest). Install manually: https://github.com/$REPO/releases"

    # 1. sha256 — mandatory fail-closed integrity gate.
    EXPECTED_SHA=$(curl -fsSL --proto '=https' --tlsv1.2 --max-time 30 "${URL}.sha256" 2>/dev/null \
        | head -1 | awk '{print $1}')
    [[ "$EXPECTED_SHA" =~ ^[0-9a-fA-F]{64}$ ]] \
        || run_existing_or_die "missing/malformed .sha256 release asset — refusing to install"
    ACTUAL_SHA=$(shasum -a 256 "$TMP_FILE" | awk '{print $1}')
    [[ "$ACTUAL_SHA" == "$EXPECTED_SHA" ]] \
        || run_existing_or_die "sha256 mismatch against release asset — refusing to install"

    # 2. Code signature — requirement-based authenticity gate (see header).
    verify_binary "$TMP_FILE" \
        || run_existing_or_die "code-signature verification failed (not a Developer ID Application cert of Team 6W377FS7BS) — refusing to install"

    chmod +x "$TMP_FILE" || run_existing_or_die "chmod failed"
    mv "$TMP_FILE" "$BINARY" || run_existing_or_die "install mv failed"
    trap - EXIT
    echo "${DESIRED_VERSION:-unknown}" > "$VERSION_FILE" \
        || echo "$BINARY_NAME: WARNING — version sidecar write failed (next spawn re-downloads)" >&2
    echo "$BINARY_NAME: installed v${DESIRED_VERSION:-unknown} (sha256 + Developer ID verified)" >&2
fi

# Exec-time re-verification: never exec an unverified binary, even one whose
# sidecar version matches (covers binaries installed by pre-hardening wrappers
# and post-install ~/bin tampering). Failure forces one re-download attempt.
if ! verify_binary "$BINARY"; then
    if $NEED_DOWNLOAD; then
        # We JUST downloaded + verified it; a failure here means tampering
        # mid-flight — refuse outright.
        echo "$BINARY_NAME: ERROR — freshly installed binary failed re-verification" >&2
        exit 1
    fi
    echo "$BINARY_NAME: existing binary failed signature verification — re-downloading" >&2
    rm -f "$BINARY" "$VERSION_FILE"
    exec "${BASH_SOURCE[0]}" ${SCRIPT_ARGS[@]+"${SCRIPT_ARGS[@]}"}
fi

exec "$BINARY" ${SCRIPT_ARGS[@]+"${SCRIPT_ARGS[@]}"}
