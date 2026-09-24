#!/bin/bash
# check-bib-fixture-consistency.sh — cross-package APA bibliography fixture contract
#
# bib-apa-to-html-swift, bib-apa-to-md-swift and bib-apa-to-json-swift each
# bundle their own copy of `portable-references.bib` (Bundle.module resources
# can't reach across package boundaries), so the three files are edited by
# hand and can silently drift apart. This script is the machine-checkable
# contract macdoc#189 asked for: it normalizes away pure BibLaTeX whitespace
# formatting (multi-line "pretty" vs. single-line "compact" entries — both
# styles are used across the three fixtures today) and then requires the
# three normalized fixtures to be byte-identical. Any difference in an entry
# type, field name or field value fails the check.
#
# Usage: scripts/tests/check-bib-fixture-consistency.sh
# Exit status: 0 if all three fixtures are semantically identical, 1 otherwise.

set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)

FIXTURES=(
    "packages/bib-apa-to-html-swift/Tests/BibAPAToHTMLTests/Resources/portable-references.bib"
    "packages/bib-apa-to-md-swift/Tests/BibAPAToMDTests/Resources/portable-references.bib"
    "packages/bib-apa-to-json-swift/Tests/BibAPAToJSONTests/Resources/portable-references.bib"
)

# Collapse all whitespace runs to a single space, then remove the whitespace
# BibLaTeX allows around structural punctuation (`{ x }` vs `{x}`, `key = {v}`
# vs `key={v}`, trailing spaces before a comma). This is the only class of
# difference the three fixtures are allowed to have; any other difference
# (an entry type, a field name, a field value) survives normalization and
# fails the comparison below.
normalize() {
    tr -s '[:space:]' ' ' < "$1" \
        | sed -e 's/{ */{/g' -e 's/ *}/}/g' -e 's/ *,/,/g' -e 's/ *= */=/g' \
        | sed 's/^ *//; s/ *$//'
}

TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/macdoc-bib-fixture-check.XXXXXX")
trap 'rm -rf "$TMP_DIR"' EXIT

STATUS=0
FIRST=""
for fixture in "${FIXTURES[@]}"; do
    path="$ROOT/$fixture"
    if [ ! -f "$path" ]; then
        echo "MISSING fixture: $fixture" >&2
        STATUS=1
        continue
    fi
    normalized="$TMP_DIR/$(echo "$fixture" | tr '/' '_').normalized"
    normalize "$path" > "$normalized"
    if [ -z "$FIRST" ]; then
        FIRST="$normalized"
        FIRST_LABEL="$fixture"
    elif ! diff -q "$FIRST" "$normalized" > /dev/null; then
        echo "DRIFT between fixtures (after normalizing whitespace-only formatting):" >&2
        echo "  $FIRST_LABEL" >&2
        echo "  $fixture" >&2
        diff -u "$FIRST" "$normalized" >&2 || true
        STATUS=1
    fi
done

if [ "$STATUS" -eq 0 ]; then
    echo "OK: ${#FIXTURES[@]} bib fixtures are semantically identical (portable-references.bib)."
fi

exit "$STATUS"
