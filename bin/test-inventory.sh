#!/usr/bin/env bash
# Show the local upstream test inventory + (optionally) compare with other tags.
#
# Default: per-category counts of what's checked into tests/upstream/ right now.
# With COMPARE_TAGS="v0.13.8 v0.14.9 v0.15.0 v0.15.15 v0.15.16": also query
# the upstream clone for each tag and print a comparison table.
#
# Usage:
#   bin/test-inventory.sh                                   # local only
#   COMPARE_TAGS="v0.14.9 v0.15.15" bin/test-inventory.sh   # plus those tags

set -e

PROJECT=/Users/avinashverma/purescriptCodeGen
PURESCRIPT=${PURESCRIPT_REPO:-/Users/avinashverma/purescript}
LOCAL=$PROJECT/tests/upstream

# ── Local inventory ──────────────────────────────────────────────────────

if [ ! -d "$LOCAL" ]; then
  echo "tests/upstream/ is missing. Run bin/sync-upstream-tests.sh first." >&2
  exit 1
fi

CATEGORIES=(optimize passing warning failing docs layout graph psci publish sourcemaps)

echo "Local test inventory ($(cat "$LOCAL/_SOURCE" 2>/dev/null | head -1 || echo 'unknown source'))"
echo "─────────────────────────────────────────────"
local_total=0
for cat in "${CATEGORIES[@]}"; do
  if [ -d "$LOCAL/$cat" ]; then
    n=$(find "$LOCAL/$cat" -name '*.purs' -type f | wc -l | tr -d ' ')
  else
    n=0
  fi
  printf "  %-12s %4d\n" "$cat" "$n"
  local_total=$((local_total + n))
done
echo "  ─────────────────"
printf "  %-12s %4d\n" "Total:" "$local_total"
echo ""

# ── Cross-tag comparison ─────────────────────────────────────────────────

if [ -n "${COMPARE_TAGS:-}" ]; then
  if [ ! -d "$PURESCRIPT/.git" ]; then
    echo "(COMPARE_TAGS set but $PURESCRIPT not a git repo — skipping comparison)" >&2
    exit 0
  fi

  echo "Comparison across tags (from $PURESCRIPT):"
  echo "─────────────────────────────────────────────"
  printf "  %-12s" "tag"
  for cat in "${CATEGORIES[@]}"; do printf "%9s" "$cat"; done
  printf "%9s\n" "total"

  for tag in $COMPARE_TAGS; do
    # Make sure tag exists locally; try to fetch if not
    if ! git -C "$PURESCRIPT" rev-parse --verify "refs/tags/$tag" >/dev/null 2>&1; then
      git -C "$PURESCRIPT" fetch --depth=1 --tags origin "$tag" 2>/dev/null || true
    fi
    if ! git -C "$PURESCRIPT" rev-parse --verify "refs/tags/$tag" >/dev/null 2>&1; then
      printf "  %-12s%s\n" "$tag" "  (tag not available)"
      continue
    fi

    total=0
    printf "  %-12s" "$tag"
    for cat in "${CATEGORIES[@]}"; do
      n=$(git -C "$PURESCRIPT" ls-tree -r --name-only "$tag" "tests/purs/$cat/" 2>/dev/null \
            | grep -c '\.purs$' || true)
      printf "%9d" "$n"
      total=$((total + n))
    done
    printf "%9d\n" "$total"
  done
fi
