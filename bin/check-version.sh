#!/usr/bin/env bash
# Verify the upstream purescript checkout matches what this branch is pinned to.
#
# Usage:
#   bin/check-version.sh                # report only
#   bin/check-version.sh --strict       # exit 1 on mismatch
#
# See VERSIONING.md for the pin and how to cut version-specific branches.

set -e

PROJECT=/Users/avinashverma/purescriptCodeGen
PURESCRIPT=${PURESCRIPT_REPO:-/Users/avinashverma/purescript}

# Parse VERSIONING.md to get the expected pin
EXPECTED_TAG=$(grep '^purescript:' "$PROJECT"/VERSIONING.md | head -1 | awk '{print $2}')
EXPECTED_COMMIT=$(grep '^purescript:' "$PROJECT"/VERSIONING.md | head -1 | grep -oE 'commit [a-f0-9]+' | awk '{print $2}')

if [ -z "$EXPECTED_TAG" ] || [ -z "$EXPECTED_COMMIT" ]; then
  echo "✗ Could not parse expected version from VERSIONING.md" >&2
  exit 1
fi

if [ ! -d "$PURESCRIPT" ]; then
  echo "✗ Upstream purescript repo not found at $PURESCRIPT"
  echo "  Clone with: git clone https://github.com/purescript/purescript $PURESCRIPT"
  [ "$1" = "--strict" ] && exit 1 || exit 0
fi

cd "$PURESCRIPT"
ACTUAL_COMMIT=$(git rev-parse --short=7 HEAD)
ACTUAL_TAG=$(git describe --tags --exact-match 2>/dev/null || git describe --tags 2>/dev/null || echo "no-tag")

echo "Expected: $EXPECTED_TAG ($EXPECTED_COMMIT)"
echo "Actual:   $ACTUAL_TAG ($ACTUAL_COMMIT)"

if [ "$ACTUAL_COMMIT" = "$EXPECTED_COMMIT" ]; then
  echo "✓ Match"
  exit 0
fi

echo ""
echo "✗ Upstream purescript at $PURESCRIPT does not match this branch's pin."
echo "  To re-pin upstream to the expected version:"
echo "    cd $PURESCRIPT"
echo "    git fetch --tags origin"
echo "    git checkout $EXPECTED_TAG"

[ "$1" = "--strict" ] && exit 1 || exit 0
