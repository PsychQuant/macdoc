#!/bin/bash
# Regression test for #191: root .gitignore's packages/* un-ignore rules.
#
# packages/* (root .gitignore) is a single-level glob — it only matches
# packages/<pkg> itself, never anything below it. Once a package directory
# is re-included with `!packages/<pkg>/`, git recurses into it and every
# file below is tracked by default (no per-file `!` exceptions needed or
# effective) EXCEPT where a separate, still-applicable rule matches (the
# generic .build/, .swiftpm/, DerivedData/, .DS_Store rules, or that
# package's own nested .gitignore). This script pins that behaviour down so
# it can't silently regress, and pins the exact set of packages intended to
# be tracked so a future package can't be silently un-tracked or a stray
# local-only package silently swept in.
#
# All four checks from the #191 diagnosis / orchestrator decision:
#   (a) a NEW source file in every intended package must NOT be ignored
#   (b) .build/, .swiftpm/, DerivedData/, .DS_Store under a package MUST
#       stay ignored
#   (c) a new file in a non-intended package (and a brand-new package dir)
#       MUST stay ignored
#   (d) `git ls-files packages/` must match the frozen baseline snapshot
#       (proves the .gitignore rewrite tracks/untracks zero files)
#
# Run against the *old* .gitignore (pre-#191 rewrite): (a) fails RED for the
# 6 packages that had tracked files but no `!packages/<pkg>/` line yet
# (html-to-word-swift, md-to-word-swift, pdf-to-docx-swift, pdf-to-md-swift,
# word-to-html-swift, biblatex-apa-swift); (b), (c), (d) already pass.
# After the rewrite, all four pass — GREEN.

set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
cd "$ROOT"

FAIL=0

fail() {
    echo "FAIL: $1" >&2
    FAIL=1
}

# --no-index: probe paths never touch the working tree or the git index, so
# there is no risk of git check-ignore silently short-circuiting on "this
# path is already tracked" (see #191 verdict: that confusion invalidated one
# of the diagnosis's own example checks).
is_ignored() {
    git check-ignore -q --no-index "$1"
}

# Every package under packages/ that currently has tracked content is
# intended to be trackable. Derived from git ls-files, not hardcoded, so
# adding a package's files to git without also opening it in .gitignore is
# exactly the failure this test exists to catch.
mapfile -t INTENDED_PACKAGES < <(
    git ls-files packages/ | sed -E 's#^packages/([^/]+)/.*#\1#' | sort -u
)

if [ "${#INTENDED_PACKAGES[@]}" -eq 0 ]; then
    fail "no tracked packages found under packages/ — git ls-files packages/ came back empty; refusing to run a vacuous test"
fi

# Known local-only packages (separate git repos, cloned on demand per
# reference/README.md-style docs) that must NEVER appear in the intended
# list. If either ever does, the "non-intended package" control in check (c)
# below would silently stop testing anything — so guard it explicitly,
# rather than repeating the #191 diagnosis's own mistake of picking a
# control package that had quietly become intended.
NON_INTENDED_CONTROL="ooxml-swift"
for pkg in "${INTENDED_PACKAGES[@]}"; do
    if [ "$pkg" = "$NON_INTENDED_CONTROL" ]; then
        fail "control package '$NON_INTENDED_CONTROL' has tracked files — pick a different NON_INTENDED_CONTROL, this one is no longer a valid negative control"
    fi
done

echo "Intended packages (${#INTENDED_PACKAGES[@]}): ${INTENDED_PACKAGES[*]}"

# --- (a) new source file in every intended package must NOT be ignored ---
for pkg in "${INTENDED_PACKAGES[@]}"; do
    probe="packages/$pkg/Sources/__gitignore_probe__.swift"
    if is_ignored "$probe"; then
        fail "(a) new file in intended package '$pkg' is still ignored: $probe"
    fi
done

# --- (b) build-artifact directories under a package MUST stay ignored ---
for pkg in "${INTENDED_PACKAGES[@]}"; do
    for artifact in ".build/artifact.o" ".swiftpm/xcode/probe" "DerivedData/probe" ".DS_Store"; do
        probe="packages/$pkg/$artifact"
        if ! is_ignored "$probe"; then
            fail "(b) build artifact under intended package '$pkg' is NOT ignored: $probe"
        fi
    done
done

# --- (c) non-intended packages MUST stay fully ignored ---
# (b2) A library package's Package.resolved is written by every local
# `swift test` inside the package. Un-ignoring the package directory must not
# turn it into an untracked file. A package that deliberately tracks one
# (token-counter-swift pins a third-party fork) is skipped: git ignores
# tracked files' ignore status anyway, and the exception is explicit in
# .gitignore.
for pkg in "${INTENDED_PACKAGES[@]}"; do
    probe="packages/$pkg/Package.resolved"
    if git ls-files --error-unmatch "$probe" >/dev/null 2>&1; then
        continue
    fi
    if ! is_ignored "$probe"; then
        fail "(b2) generated Package.resolved under intended package '$pkg' is NOT ignored: $probe"
    fi
done

brand_new_probe="packages/__gitignore_probe_new_pkg__/Sources/Foo.swift"
if ! is_ignored "$brand_new_probe"; then
    fail "(c) brand-new, never-opened package directory is NOT ignored: $brand_new_probe"
fi

control_probe="packages/$NON_INTENDED_CONTROL/Sources/__gitignore_probe__.swift"
if ! is_ignored "$control_probe"; then
    fail "(c) known local-only package '$NON_INTENDED_CONTROL' is NOT ignored: $control_probe"
fi

# --- (d) git ls-files packages/ must match the frozen baseline snapshot ---
# The .gitignore un-ignore rules never change which files are already
# tracked — they only change which NEW files git would pick up. So this
# baseline must read identically before and after any rewrite of the
# packages/* block; a diff here means files were tracked or untracked as a
# side effect of "just cleaning up .gitignore", which #191 explicitly rules
# out.
BASELINE="$ROOT/scripts/tests/fixtures/gitignore-packages-tracked-files.txt"
if [ ! -f "$BASELINE" ]; then
    fail "(d) missing baseline fixture: $BASELINE"
else
    CURRENT=$(git ls-files packages/ | sort)
    EXPECTED=$(sort "$BASELINE")
    if [ "$CURRENT" != "$EXPECTED" ]; then
        fail "(d) git ls-files packages/ no longer matches $BASELINE"
        diff <(echo "$EXPECTED") <(echo "$CURRENT") >&2 || true
    fi
fi

if [ "$FAIL" -ne 0 ]; then
    exit 1
fi

echo "PASS: packages/* un-ignore rules track exactly the intended packages, nothing more, nothing less"
