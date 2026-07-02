#!/bin/bash
# Version-aware auto-download wrapper for ChePPTXMCP.
#
# Design:
# - Reads desired version from plugin.json (plugin's intended binary version)
# - Compares against ~/bin/.ChePPTXMCP.version sidecar
# - Re-downloads when plugin has been updated but binary is stale
# - Atomic file swap (.tmp + mv) so partial downloads never break things
# - Falls back to releases/latest if plugin.json unreadable or pinned tag missing
#

set -u

REPO="PsychQuant/che-pptx-mcp"
BINARY_NAME="ChePPTXMCP"
INSTALL_DIR="$HOME/bin"
BINARY="$INSTALL_DIR/$BINARY_NAME"
VERSION_FILE="$INSTALL_DIR/.${BINARY_NAME}.version"

# Locate plugin root via wrapper's own path (more reliable than $CLAUDE_PLUGIN_ROOT
# which isn't guaranteed in MCP spawn env). Wrapper lives at PLUGIN_ROOT/bin/*.sh.
PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLUGIN_JSON="$PLUGIN_ROOT/.claude-plugin/plugin.json"

# Read desired version from plugin.json (empty string on any failure → fallback to "latest").
DESIRED_VERSION=""
if [[ -f "$PLUGIN_JSON" ]]; then
    DESIRED_VERSION=$(grep -oE '"version":[[:space:]]*"[^"]+"' "$PLUGIN_JSON" 2>/dev/null \
        | head -1 | cut -d'"' -f4 || true)
fi

# Read currently installed version from sidecar (empty string if file missing/unreadable).
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

    # Try pinned tag first, then fall back to latest release.
    URL=""
    for API_URL in \
        "${DESIRED_VERSION:+https://api.github.com/repos/$REPO/releases/tags/v$DESIRED_VERSION}" \
        "https://api.github.com/repos/$REPO/releases/latest"
    do
        [[ -z "$API_URL" ]] && continue
        URL=$(curl -sL --max-time 30 "$API_URL" 2>/dev/null \
            | grep '"browser_download_url"' | grep "/$BINARY_NAME\"" | head -1 \
            | sed 's/.*"\(https[^"]*\)".*/\1/')
        [[ -n "$URL" ]] && break
    done

    if [[ -z "$URL" ]]; then
        if [[ -x "$BINARY" ]]; then
            echo "$BINARY_NAME: WARNING — no download URL found, keeping existing binary" >&2
        else
            echo "$BINARY_NAME: ERROR — no download URL found at $REPO. Install manually: https://github.com/$REPO/releases" >&2
            exit 1
        fi
    else
        if curl -sL --max-time 300 "$URL" -o "${BINARY}.tmp" 2>/dev/null; then
            # --- Supply-chain verification (PsychQuant/macdoc#112 security review) ---
            # 1. sha256: compare against the release's .sha256 asset when present
            #    (fail-closed on mismatch; warn-and-continue when asset missing).
            EXPECTED_SHA=$(curl -sL --max-time 30 "${URL}.sha256" 2>/dev/null | tr -d '[:space:]' | head -c 64)
            if [[ ${#EXPECTED_SHA} -eq 64 ]]; then
                ACTUAL_SHA=$(shasum -a 256 "${BINARY}.tmp" | awk '{print $1}')
                if [[ "$ACTUAL_SHA" != "$EXPECTED_SHA" ]]; then
                    rm -f "${BINARY}.tmp"
                    echo "$BINARY_NAME: ERROR — sha256 mismatch against release asset; refusing to install" >&2
                    [[ -x "$BINARY" ]] && exec "$BINARY" "$@"
                    exit 1
                fi
            else
                echo "$BINARY_NAME: WARNING — no .sha256 asset found; relying on code-signature check" >&2
            fi
            # 2. Code signature: require a valid signature from Team 6W377FS7BS
            #    (Developer ID, CHE CHENG) before executing anything downloaded.
            if ! codesign --verify --strict "${BINARY}.tmp" 2>/dev/null || \
               ! codesign -dvv "${BINARY}.tmp" 2>&1 | grep -q "TeamIdentifier=6W377FS7BS"; then
                rm -f "${BINARY}.tmp"
                echo "$BINARY_NAME: ERROR — code-signature verification failed (not signed by expected Team ID); refusing to install" >&2
                [[ -x "$BINARY" ]] && exec "$BINARY" "$@"
                exit 1
            fi
            chmod +x "${BINARY}.tmp"
            mv "${BINARY}.tmp" "$BINARY"
            echo "${DESIRED_VERSION:-unknown}" > "$VERSION_FILE"
            echo "$BINARY_NAME: installed v${DESIRED_VERSION:-latest}" >&2
        else
            rm -f "${BINARY}.tmp" 2>/dev/null
            if [[ -x "$BINARY" ]]; then
                echo "$BINARY_NAME: WARNING — download failed, keeping existing binary" >&2
            else
                echo "$BINARY_NAME: ERROR — download failed" >&2
                exit 1
            fi
        fi
    fi
fi

exec "$BINARY" "$@"
