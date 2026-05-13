#!/usr/bin/env bash
# Sync the upstream PureScript test suite into tests/upstream/.
#
# Extracts the entire `tests/purs/` tree from the upstream purescript repo
# at a given tag (default: the pinned version from VERSIONING.md) and
# writes it into tests/upstream/ in this repo. Uses `git archive | tar`
# so the upstream working tree is not modified.
#
# Usage:
#   bin/sync-upstream-tests.sh                 # use the pinned tag (from VERSIONING.md)
#   bin/sync-upstream-tests.sh v0.14.9         # use a specific tag
#   TARGET=tests/upstream-v0.14 bin/sync-upstream-tests.sh v0.14.9
#
# After running, the contents under tests/upstream/ are the test set our
# runners use. Run this whenever the version pin changes, or when upstream
# patches a test file we want to pick up.

set -e

PROJECT=/Users/avinashverma/purescriptCodeGen
PURESCRIPT=${PURESCRIPT_REPO:-/Users/avinashverma/purescript}
TARGET=${TARGET:-$PROJECT/tests/upstream}

# Default tag = the pin recorded in VERSIONING.md (line: "purescript: vX.Y.Z (commit ...)")
PINNED_TAG=$(grep '^purescript:' "$PROJECT"/VERSIONING.md | head -1 | awk '{print $2}')
PINNED_COMMIT=$(grep '^purescript:' "$PROJECT"/VERSIONING.md | head -1 | grep -oE 'commit [a-f0-9]+' | awk '{print $2}')
TAG=${1:-$PINNED_TAG}

if [ ! -d "$PURESCRIPT/.git" ]; then
  echo "✗ Upstream purescript repo not found at $PURESCRIPT" >&2
  echo "  Clone: git clone https://github.com/purescript/purescript $PURESCRIPT" >&2
  exit 1
fi

echo "Syncing upstream test suite"
echo "  source: $PURESCRIPT"
echo "  tag:    $TAG"
echo "  target: $TARGET"

# Ensure the tag is available locally
if ! git -C "$PURESCRIPT" rev-parse --verify "refs/tags/$TAG" >/dev/null 2>&1; then
  echo "Tag $TAG not present locally; fetching..."
  git -C "$PURESCRIPT" fetch --depth=1 --tags origin 2>&1 | tail -3
fi

if ! git -C "$PURESCRIPT" rev-parse --verify "refs/tags/$TAG" >/dev/null 2>&1; then
  echo "✗ Tag $TAG still not found after fetch" >&2
  exit 1
fi

ACTUAL_COMMIT=$(git -C "$PURESCRIPT" rev-parse --short=7 "$TAG")

# Wipe any prior content under TARGET except the README (which we write here)
# and the _SOURCE marker (rewritten below).
mkdir -p "$TARGET"
find "$TARGET" -mindepth 1 -maxdepth 1 ! -name 'README.md' -exec rm -rf {} +

# Extract `tests/purs/**` from the tag's tree, stripping the two leading
# path components (`tests/purs/`) so files land directly under TARGET.
git -C "$PURESCRIPT" archive --format=tar "$TAG" tests/purs | tar -x -C "$TARGET" --strip-components=2

# Provenance marker
cat > "$TARGET/_SOURCE" <<EOF
purescript@$ACTUAL_COMMIT ($TAG)
synced: $(date -u +%Y-%m-%dT%H:%M:%SZ)
source: $PURESCRIPT
EOF

# Summary
echo ""
echo "Summary by category:"
for d in "$TARGET"/*/; do
  cat=$(basename "$d")
  [ "$cat" = "_SOURCE" ] && continue
  n=$(find "$d" -name '*.purs' -type f | wc -l | tr -d ' ')
  printf "  %-12s %4d .purs\n" "$cat" "$n"
done
total=$(find "$TARGET" -name '*.purs' -type f | wc -l | tr -d ' ')
echo "  ----------------------"
printf "  %-12s %4d\n" "Total:" "$total"

# Sanity vs pinned commit
if [ -n "$PINNED_COMMIT" ] && [ "$ACTUAL_COMMIT" != "$PINNED_COMMIT" ]; then
  echo ""
  echo "ℹ  Note: synced from $ACTUAL_COMMIT, but VERSIONING.md pin is $PINNED_COMMIT."
  echo "   This is OK if you're explicitly syncing a different tag; otherwise"
  echo "   either re-pin VERSIONING.md or sync the pinned tag."
fi
