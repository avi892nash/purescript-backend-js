#!/usr/bin/env bash
# Run every test suite this codegen has and print a single roll-up table.
#
# Equivalent to upstream `stack test` for the codegen-relevant categories:
#
#   Suite                                       Mirrors upstream...
#   ─────────────────────────────────────────   ──────────────────────
#   1. bin/run-upstream-tests.sh  (optimize/)   TestCompiler.hs::optimizeTests
#   2. bin/run-passing-tests.sh   (passing/)    TestCompiler.hs::passingTests
#   3. bin/run-warning-tests.sh   (warning/)    TestCompiler.hs::warningTests   (codegen-side only)
#
# Env:
#   QUICK=1   Run with LIMIT=20 per suite (fast smoke test, ~30s)
#   SKIP=<n>  Comma-separated list of suite numbers to skip ("2,3")
#   CI=1      Exit non-zero if any suite has failures (default: report only)

set -e

PROJECT=/Users/avinashverma/purescriptCodeGen
cd "$PROJECT"

# Verify the upstream pin
echo ""
echo "─── Version check ───────────────────────────────────────────"
./bin/check-version.sh
echo ""

if [ "${QUICK:-0}" = "1" ]; then
  export LIMIT=20
fi

SKIP=${SKIP:-}
skip() { case ",$SKIP," in *,$1,*) return 0;; esac; return 1; }

run_suite() {
  local num="$1"
  local name="$2"
  local cmd="$3"
  local logfile=$(mktemp -t pursjs-test-all-XXXXXX)
  if skip "$num"; then
    echo "── [$num] $name ── (skipped)"
    echo "$num|$name|skipped|skipped|skipped" >> /tmp/pursjs-test-all-summary
    return 0
  fi
  echo "── [$num] $name ────────────────────────────────────────────"
  if ! eval "$cmd" > "$logfile" 2>&1; then
    echo "  (suite errored — see $logfile)"
    tail -5 "$logfile"
  fi
  # Parse the suite's summary line into the rollup
  case "$num" in
    1)
      summary=$(grep "^Upstream optimizer tests:" "$logfile" | tail -1)
      echo "  $summary"
      pass=$(echo "$summary" | grep -oE '[0-9]+ pass' | grep -oE '[0-9]+')
      fail=$(echo "$summary" | grep -oE '[0-9]+ differ' | grep -oE '[0-9]+')
      err=$(echo "$summary" | grep -oE '[0-9]+ errored' | grep -oE '[0-9]+')
      ;;
    2)
      pass=$(grep "Done (PASS):" "$logfile" | tail -1 | grep -oE '[0-9]+' | head -1)
      fail=$(grep "No-Done:\|Codegen err:\|Runtime err:" "$logfile" | grep -oE '[0-9]+' | paste -sd+ - | bc 2>/dev/null || echo 0)
      err=$(grep "Purs err:" "$logfile" | tail -1 | grep -oE '[0-9]+' | head -1)
      echo "  Pass: $pass, Fail: $fail, Skipped (purs err): $err"
      ;;
    3)
      pass=$(grep "OK:" "$logfile" | tail -1 | grep -oE '[0-9]+' | head -1)
      fail=$(grep "Codegen err:\|Parse err:" "$logfile" | grep -oE '[0-9]+' | paste -sd+ - | bc 2>/dev/null || echo 0)
      err=$(grep "Purs err:" "$logfile" | tail -1 | grep -oE '[0-9]+' | head -1)
      echo "  Pass: $pass, Fail: $fail, Skipped (purs err): $err"
      ;;
  esac
  echo "$num|$name|${pass:-?}|${fail:-?}|${err:-?}" >> /tmp/pursjs-test-all-summary
  rm -f "$logfile"
  echo ""
}

rm -f /tmp/pursjs-test-all-summary

run_suite 1 "Upstream optimize" "./bin/run-upstream-tests.sh"
run_suite 2 "Upstream passing" "./bin/run-passing-tests.sh"
run_suite 3 "Upstream warning" "./bin/run-warning-tests.sh"

echo "═════════════════════════════════════════════════════════════"
echo "ROLL-UP"
echo "═════════════════════════════════════════════════════════════"
printf "  %-25s  %8s  %8s  %8s\n" "Suite" "Pass" "Fail" "Skipped"
printf "  %-25s  %8s  %8s  %8s\n" "─────" "────" "────" "───────"
while IFS='|' read -r num name pass fail skipped; do
  printf "  [%s] %-21s  %8s  %8s  %8s\n" "$num" "$name" "$pass" "$fail" "$skipped"
done < /tmp/pursjs-test-all-summary
echo "═════════════════════════════════════════════════════════════"

if [ "${CI:-0}" = "1" ]; then
  any_fail=$(awk -F'|' '$4 != "0" && $4 != "skipped" && $4 != "?" { print }' /tmp/pursjs-test-all-summary | wc -l)
  if [ "$any_fail" -gt 0 ]; then
    echo "FAIL: at least one suite has failures (CI=1)"
    exit 1
  fi
fi
