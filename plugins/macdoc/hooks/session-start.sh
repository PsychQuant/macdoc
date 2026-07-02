#!/bin/bash
# macdoc plugin SessionStart hook — ensure ~/bin/macdoc matches the plugin's
# pinned binary_version (PsychQuant/macdoc#114).
#
# Contract: FAIL-SOFT for the session (any problem → one stderr line, exit 0 —
# never break session start), FAIL-CLOSED for the artifact (mandatory sha256 +
# Developer ID requirement — the same ruler as the MCP wrappers and the
# release gate — before anything is installed to ~/bin).
#
# Install target is the shared ~/bin ON PURPOSE (unlike the MCP wrappers'
# plugin-scoped .bin-cache, #117): the CLI is a user-facing PATH tool and
# ~/bin IS its destination; the cross-marketplace binary collision problem
# does not apply to a CLI the user invokes by name.

set -u

REPO="PsychQuant/macdoc"
BINARY_NAME="macdoc"
INSTALL_DIR="${MACDOC_INSTALL_DIR:-$HOME/bin}"   # override for tests
BINARY="$INSTALL_DIR/$BINARY_NAME"
REQUIREMENT='=anchor apple generic and certificate 1[field.1.2.840.113635.100.6.2.6] exists and certificate leaf[field.1.2.840.113635.100.6.1.13] exists and certificate leaf[subject.OU] = "6W377FS7BS"'

note() { echo "macdoc plugin: $1" >&2; }
soft_exit() { note "$1"; exit 0; }   # fail-soft: never break session start

[ "$(uname -m)" = "arm64" ] || exit 0   # arm64-only release; Intel builds from source (silent — not an error)

PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLUGIN_JSON="$PLUGIN_ROOT/.claude-plugin/plugin.json"
[ -f "$PLUGIN_JSON" ] || exit 0

WANT=$(grep -oE '"binary_version"[[:space:]]*:[[:space:]]*"[^"]+"' "$PLUGIN_JSON" 2>/dev/null \
    | head -1 | sed -E 's/.*"([^"]+)"$/\1/' || true)
[ -n "$WANT" ] || exit 0   # no pinned CLI version — nothing to manage

HAVE=$("$BINARY" --version 2>/dev/null || true)
[ "$HAVE" = "$WANT" ] && exit 0   # fast path: version matches, zero network

mkdir -p "$INSTALL_DIR" 2>/dev/null || soft_exit "cannot create $INSTALL_DIR — skipping auto-install"
TMP=$(mktemp "$INSTALL_DIR/.${BINARY_NAME}.download.XXXXXX" 2>/dev/null) || soft_exit "mktemp failed — skipping auto-install"
trap 'rm -f "$TMP"' EXIT

URL="https://github.com/$REPO/releases/download/v$WANT/$BINARY_NAME"
curl -fsSL --proto '=https' --tlsv1.2 --max-time 300 "$URL" -o "$TMP" 2>/dev/null \
    || soft_exit "download failed for v$WANT (keeping existing ${HAVE:-none}); manual: https://github.com/$REPO/releases"

EXPECTED=$(curl -fsSL --proto '=https' --tlsv1.2 --max-time 30 "$URL.sha256" 2>/dev/null | head -1 | awk '{print $1}')
[[ "$EXPECTED" =~ ^[0-9a-fA-F]{64}$ ]] \
    || soft_exit "missing/malformed .sha256 asset — refusing to install unverified binary"
[[ "$(shasum -a 256 "$TMP" | awk '{print $1}')" == "$EXPECTED" ]] \
    || soft_exit "sha256 mismatch — refusing to install"
codesign --verify --strict -R "$REQUIREMENT" "$TMP" 2>/dev/null \
    || soft_exit "code-signature verification failed (not Developer ID Team 6W377FS7BS) — refusing to install"

chmod +x "$TMP" || soft_exit "chmod failed"
mv "$TMP" "$BINARY" || soft_exit "install mv failed"
trap - EXIT
note "installed macdoc v$WANT to $INSTALL_DIR (sha256 + Developer ID verified)"
exit 0
