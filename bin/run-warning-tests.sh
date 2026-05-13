#!/usr/bin/env bash
# Run the upstream `tests/purs/warning/` suite against our codegen.
#
# Warning tests are programs that compile but produce a specific warning.
# Most don't have a `main` so we can't assert runtime "Done"; instead we
# check that:
#   (a) our codegen successfully transforms the corefn (no crash, no error)
#   (b) the produced JS parses as valid ES module (node can import it
#       without a SyntaxError)
#
# This catches codegen regressions that the passing/ suite wouldn't reach,
# because warning programs often exercise unusual edge cases (shadowed
# type variables, unused names, redundant cases, etc.).

set -e

PROJECT=/Users/avinashverma/purescriptCodeGen
SAMPLE=$PROJECT/sample-purs
PURESCRIPT=${PURESCRIPT_REPO:-/Users/avinashverma/purescript}
TESTS_DIR=$PURESCRIPT/tests/purs/warning

if [ ! -d "$TESTS_DIR" ]; then
  echo "Not found: $TESTS_DIR" >&2
  exit 1
fi

cd "$PROJECT"
spago build >/dev/null 2>&1 || { spago build; exit 1; }

node --input-type=module -e "import('$PROJECT/output/PursJS.Main/index.js')" 2>/dev/null || true

SOURCES_FILE=$(mktemp -t pursjs-sources-XXXXXX)
SHARED_OUTPUT=$(mktemp -d -t pursjs-shared-output-XXXXXX)
trap "rm -f $SOURCES_FILE; rm -rf $SHARED_OUTPUT" EXIT
find "$SAMPLE"/.spago/p -name "*.purs" -type f > "$SOURCES_FILE"

echo "Pre-compiling prelude/effect/console..."
xargs purs compile --codegen js,corefn -o "$SHARED_OUTPUT" < "$SOURCES_FILE" >/dev/null 2>&1 || true

ok=0
fail=0
codegen_fail=0
parse_fail=0
purs_fail=0
errored=()

PATTERN=${PATTERN:-}
LIMIT=${LIMIT:-0}
count=0

for purs in "$TESTS_DIR"/*.purs; do
  name=$(basename "$purs" .purs)
  [ -n "$PATTERN" ] && [[ "$name" != *"$PATTERN"* ]] && continue
  count=$((count+1))
  [ "$LIMIT" -gt 0 ] && [ "$count" -gt "$LIMIT" ] && break

  extra_files=()
  if [ -d "$TESTS_DIR/$name" ]; then
    while IFS= read -r f; do extra_files+=("$f"); done < <(find "$TESTS_DIR/$name" -name "*.purs" -type f)
  fi

  workdir=$(mktemp -d -t pursjs-warning-XXXXXX)
  cp -al "$SHARED_OUTPUT" "$workdir/output" 2>/dev/null || cp -r "$SHARED_OUTPUT" "$workdir/output"

  # purs compile prints warnings to stderr but exits 0; that's fine.
  if ! xargs purs compile --codegen js,corefn -o "$workdir/output" "$purs" "${extra_files[@]}" < "$SOURCES_FILE" 2>/tmp/purs.err >/dev/null; then
    purs_fail=$((purs_fail+1))
    errored+=("$name:purs-compile")
    rm -rf "$workdir"
    continue
  fi

  # Some warning tests are about parser issues or non-Main modules; find any module that has corefn.
  corefn=""
  for c in "$workdir/output"/*/corefn.json; do
    base=$(basename "$(dirname "$c")")
    # Skip Prim modules and prelude — we want the test's own module
    if [ "$base" != "Prim" ] && [ "$base" != "Main" ]; then continue; fi
    if [ "$base" = "Main" ]; then corefn="$c"; break; fi
  done
  [ -z "$corefn" ] && corefn=$(ls "$workdir/output"/*/corefn.json 2>/dev/null | grep -v "/Prim" | head -1)

  if [ -z "$corefn" ] || [ ! -f "$corefn" ]; then
    purs_fail=$((purs_fail+1))
    errored+=("$name:no-corefn")
    rm -rf "$workdir"
    continue
  fi

  # Generate JS with our codegen
  if ! node --input-type=module -e "
import { main } from '$PROJECT/output/PursJS.Main/index.js';
process.argv = [process.argv[0], 'main', '$corefn'];
main();
" > "$workdir/our-output.js" 2>/tmp/codegen.err; then
    codegen_fail=$((codegen_fail+1))
    errored+=("$name:codegen")
    [ "${VERBOSE:-0}" = "1" ] && { echo "CODEGEN FAIL $name"; cat /tmp/codegen.err | head -5; }
    rm -rf "$workdir"
    continue
  fi

  # Check the produced JS parses (node --check would work, but we use a
  # syntax-only import which doesn't actually evaluate the module if we
  # extract it into a parse-only check).
  # Wrap in an IIFE export so parse failures are caught:
  echo "/*test*/" > "$workdir/check.mjs"
  cat "$workdir/our-output.js" >> "$workdir/check.mjs"
  # Just rely on node --check on the test file
  if ! node --check "$workdir/check.mjs" 2>/tmp/node.err; then
    parse_fail=$((parse_fail+1))
    errored+=("$name:parse")
    [ "${VERBOSE:-0}" = "1" ] && { echo "PARSE FAIL $name"; cat /tmp/node.err | head -5; }
    rm -rf "$workdir"
    continue
  fi

  ok=$((ok+1))
  echo "OK   $name"
  rm -rf "$workdir"
done

total=$((ok + fail + codegen_fail + parse_fail + purs_fail))
echo ""
echo "Warning-tests results:"
echo "  Tests run:    $total"
echo "  OK:           $ok    (codegen succeeded + output parses)"
echo "  Codegen err:  $codegen_fail"
echo "  Parse err:    $parse_fail   (our JS has a syntax error)"
echo "  Purs err:     $purs_fail   (test setup / dep / parser-level failure)"

if [ ${#errored[@]} -gt 0 ] && [ "${VERBOSE:-0}" = "1" ]; then
  echo ""
  echo "Failures (first 20):"
  for e in "${errored[@]:0:20}"; do echo "  $e"; done
fi
