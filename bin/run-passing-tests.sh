#!/usr/bin/env bash
# Run the upstream `tests/purs/passing/` suite against our codegen.
#
# For each Foo.purs in passing/ (plus any companion modules under
# passing/Foo/):
#   1. Compile with `purs --codegen js,corefn`
#   2. Replace `output/Main/index.js` with our codegen's output for Main's
#      corefn.json
#   3. Write an entry point and run via node
#   4. Expect the last line of stdout to be "Done"
#
# This mirrors `assertCompiles` in `purescript/tests/TestCompiler.hs:131-152`.
#
# Modes:
#   default              Test all passing/*.purs files
#   LIMIT=<n>            Stop after <n> tests
#   PATTERN=<glob>       Only test files matching the pattern (e.g. PATTERN=11)
#   VERBOSE=1            Show stderr/stdout on failures
#   ONLY_OURS=1          Skip the purs-baseline run (assume it always passes)
#   KEEP_GOING=1         Don't stop after errors; report totals

set -e

PROJECT=/Users/avinashverma/purescriptCodeGen
SAMPLE=$PROJECT/sample-purs
PURESCRIPT=${PURESCRIPT_REPO:-/Users/avinashverma/purescript}
TESTS_DIR=$PURESCRIPT/tests/purs/passing

if [ ! -d "$TESTS_DIR" ]; then
  echo "Not found: $TESTS_DIR" >&2
  exit 1
fi

cd "$PROJECT"
echo "Building codegen..."
spago build >/dev/null 2>&1 || { spago build; exit 1; }

# Pre-warm node ESM module cache
node --input-type=module -e "import('$PROJECT/output/PursJS.Main/index.js')" 2>/dev/null || true

# Collect prelude/effect/console/etc. sources once
SOURCES_FILE=$(mktemp -t pursjs-sources-XXXXXX)
SHARED_OUTPUT=$(mktemp -d -t pursjs-shared-output-XXXXXX)
trap "rm -f $SOURCES_FILE; rm -rf $SHARED_OUTPUT" EXIT
find "$SAMPLE"/.spago/p -name "*.purs" -type f > "$SOURCES_FILE"

# Pre-compile all deps to a shared output dir so per-test purs invocations
# only need to compile the test itself (purs picks up the existing externs).
echo "Pre-compiling prelude/effect/console/etc. once..."
xargs purs compile --codegen js,corefn -o "$SHARED_OUTPUT" < "$SOURCES_FILE" >/dev/null 2>&1 || {
  echo "Pre-compile failed:" >&2
  xargs purs compile --codegen js,corefn -o "$SHARED_OUTPUT" < "$SOURCES_FILE" 2>&1 | tail -10 >&2
  exit 1
}

ok=0
fail=0
codegen_fail=0
runtime_fail=0
diverged=0  # purs runs but ours doesn't (or vice versa)
purs_fail=0
errored=()

PATTERN=${PATTERN:-}
LIMIT=${LIMIT:-0}

count=0

# Iterate tests
for purs in "$TESTS_DIR"/*.purs; do
  name=$(basename "$purs" .purs)

  if [ -n "$PATTERN" ] && [[ "$name" != *"$PATTERN"* ]]; then
    continue
  fi

  count=$((count+1))
  if [ "$LIMIT" -gt 0 ] && [ "$count" -gt "$LIMIT" ]; then
    break
  fi

  # Companion modules under passing/<name>/
  extra_files=()
  if [ -d "$TESTS_DIR/$name" ]; then
    while IFS= read -r f; do extra_files+=("$f"); done < <(find "$TESTS_DIR/$name" -name "*.purs" -type f)
  fi

  workdir=$(mktemp -d -t pursjs-passing-XXXXXX)
  # Copy the shared dependency outputs so per-test compile reuses them.
  # We use hard links instead of `cp -r` to make this O(test) instead of O(deps).
  cp -al "$SHARED_OUTPUT" "$workdir/output" 2>/dev/null || cp -r "$SHARED_OUTPUT" "$workdir/output"

  # Compile only the test source + companions (deps are already in $workdir/output)
  if ! xargs purs compile --codegen js,corefn -o "$workdir/output" "$purs" "${extra_files[@]}" < "$SOURCES_FILE" 2>/tmp/purs.err >/dev/null; then
    if [ "${VERBOSE:-0}" = "1" ]; then echo "PURS FAIL $name"; cat /tmp/purs.err | head -20; fi
    purs_fail=$((purs_fail+1))
    errored+=("$name:purs-compile")
    rm -rf "$workdir"
    continue
  fi

  corefn="$workdir/output/Main/corefn.json"
  if [ ! -f "$corefn" ]; then
    echo "NO COREFN $name"
    purs_fail=$((purs_fail+1))
    errored+=("$name:no-corefn")
    rm -rf "$workdir"
    continue
  fi

  # Generate Main/index.js with OUR codegen, with a 60s watchdog so that
  # pathological cases (BigFunction.purs has a 9MB corefn that we'd churn
  # on for hours) get cut off and reported as a timeout. `set +e` around
  # this block because the kill/wait sequence is naturally exit-code-noisy
  # when the foreground command finishes normally.
  set +e
  node --input-type=module -e "
import { main } from '$PROJECT/output/PursJS.Main/index.js';
process.argv = [process.argv[0], 'main', '$corefn'];
main();
" > "$workdir/output/Main/index.js" 2>/tmp/codegen.err &
  CGPID=$!
  ( sleep 60 && kill -9 $CGPID 2>/dev/null ) &
  WDPID=$!
  wait $CGPID
  CGRC=$?
  kill $WDPID 2>/dev/null
  wait $WDPID 2>/dev/null
  set -e

  if [ "$CGRC" -ne 0 ]; then
    [ "${VERBOSE:-0}" = "1" ] && { echo "CODEGEN FAIL $name (rc=$CGRC)"; head -3 /tmp/codegen.err; }
    codegen_fail=$((codegen_fail+1))
    if [ "$CGRC" -gt 128 ]; then errored+=("$name:codegen-timeout")
    else errored+=("$name:codegen"); fi
    rm -rf "$workdir"
    continue
  fi

  # Write entry point and run
  echo '{"type":"module"}' > "$workdir/output/package.json"
  echo "import('./Main/index.js').then(({ main }) => main());" > "$workdir/output/index.js"

  output=$(node "$workdir/output/index.js" 2>/tmp/run.err) || {
    [ "${VERBOSE:-0}" = "1" ] && { echo "NODE FAIL $name"; cat /tmp/run.err | head -10; }
    runtime_fail=$((runtime_fail+1))
    errored+=("$name:runtime")
    rm -rf "$workdir"
    continue
  }

  last_line=$(echo "$output" | tail -1)
  if [ "$last_line" = "Done" ]; then
    ok=$((ok+1))
    echo "OK   $name"
  else
    fail=$((fail+1))
    errored+=("$name:no-done($last_line)")
    [ "${VERBOSE:-0}" = "1" ] && { echo "FAIL $name (last line: '$last_line')"; echo "$output" | tail -5; }
  fi

  rm -rf "$workdir"
done

total=$((ok + fail + codegen_fail + runtime_fail + purs_fail))
echo ""
echo "Passing-tests results:"
echo "  Tests run:    $total"
echo "  Done (PASS):  $ok"
echo "  No-Done:      $fail"
echo "  Codegen err:  $codegen_fail"
echo "  Runtime err:  $runtime_fail"
echo "  Purs err:     $purs_fail (test setup/dep issue, not our codegen)"

if [ ${#errored[@]} -gt 0 ]; then
  echo ""
  echo "Per-test issues:"
  for e in "${errored[@]}"; do echo "  $e"; done
fi
