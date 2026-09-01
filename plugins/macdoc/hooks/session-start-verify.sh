#!/bin/bash

# Shared verification primitives for the macdoc SessionStart hook. Production
# and tests call these exact functions; trust-chain executables are fixed.

macdoc_verify_binary() {
    /usr/bin/codesign --verify --strict -R "$2" "$1" 2>/dev/null
}

macdoc_sha256_file() {
    /usr/bin/shasum -a 256 "$1" 2>/dev/null | /usr/bin/awk '{print $1}'
}

# Return codes identify the failed gate without parsing prose:
# 10 = release asset digest differs from plugin pin
# 11 = downloaded bytes differ from plugin pin
# 12 = candidate does not satisfy the Developer ID requirement
macdoc_verify_candidate() {
    local candidate=$1
    local release_sha=$2
    local pinned_sha=$3
    local requirement=$4

    [ "$release_sha" = "$pinned_sha" ] || return 10
    [ "$(macdoc_sha256_file "$candidate")" = "$pinned_sha" ] || return 11
    macdoc_verify_binary "$candidate" "$requirement" || return 12
}
