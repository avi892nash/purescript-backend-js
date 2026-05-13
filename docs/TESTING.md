# Testing infrastructure

Four runner scripts cover three categories of "is our codegen correct?"
checks:

| Script | What it tests | How it tests | Inputs |
|---|---|---|---|
| `bin/diff-codegen.sh` | Output bytes for hand-curated modules | text diff against purs's output | `sample-purs/src/**/*.purs` + Prelude/Effect/Console |
| `bin/run-upstream-tests.sh` | Output bytes for upstream golden tests | text diff against checked-in `.out.js` files | `tests/upstream-optimize/*.{purs,out.js}` |
| `bin/run-passing-tests.sh` | Runtime behavior — `Done` assertion | execute via node, check last stdout line | `purescript/tests/purs/passing/*.purs` |
| `bin/test-runtime.sh` | Runtime behavior — function-by-function equivalence | execute exports via both codegens, compare | one module at a time |

## Overall flow

```
                    ┌───────────────────────────────────────────────────┐
                    │                  INPUTS                            │
                    │                                                    │
                    │  ┌─────────────────────────────────────────┐     │
                    │  │ sample-purs/src/*.purs                  │     │
                    │  │ (Tiny, Simple, Examples.*  — 13 modules)│     │
                    │  └─────────────────────────────────────────┘     │
                    │  ┌─────────────────────────────────────────┐     │
                    │  │ tests/upstream-optimize/*.{purs,out.js} │     │
                    │  │ (10 golden tests, locally mirrored)     │     │
                    │  └─────────────────────────────────────────┘     │
                    │  ┌─────────────────────────────────────────┐     │
                    │  │ ../purescript/tests/purs/passing/*.purs │     │
                    │  │ (439 runtime tests, end with log "Done")│     │
                    │  └─────────────────────────────────────────┘     │
                    └────────────────────┬───────────────────────────────┘
                                         │
                  ┌──────────────────────┼────────────────────────────────┐
                  │                      │                                │
                  ▼                      ▼                                ▼
       ┌──────────────────┐   ┌──────────────────┐            ┌──────────────────┐
       │  purs compile    │   │  purs compile    │            │  purs compile    │
       │  --codegen       │   │  --codegen       │            │  --codegen       │
       │  js,corefn       │   │  js,corefn       │            │  js,corefn       │
       └────────┬─────────┘   └────────┬─────────┘            └────────┬─────────┘
                │                      │                               │
                ▼                      ▼                               ▼
        ┌─────────────────┐    ┌─────────────────┐            ┌─────────────────┐
        │ Foo/corefn.json │    │ Foo/corefn.json │            │ Foo/corefn.json │
        │ Foo/index.js    │    │ Foo/index.js    │            │ Foo/index.js    │
        │   (reference)   │    │   (reference)   │            │   (reference)   │
        └─────┬───────┬───┘    └─────┬───────┬───┘            └────────┬────────┘
              │       │              │       │                         │
              │       │ (ref)        │       │ (ref)                   │
              ▼       │              ▼       │                         │
     ┌──────────────┐ │     ┌──────────────┐ │     ┌─────────────┐    │
     │ PursJS Main  │ │     │ PursJS Main  │ │     │PursJS Main  │    │
     │ (our codegen)│ │     │ (our codegen)│ │     │ replaces    │    │
     └──────┬───────┘ │     └──────┬───────┘ │     │ Main/index.js│   │
            ▼         │            ▼         │     └──────┬──────┘    │
       [our JS]       │       [our JS]       │            ▼           ▼
            │         │            │         │      ┌────────────────────┐
            │         │            │         │      │  node index.js     │
            └────┬────┘            └─────┬───┘      │  → stdout          │
                 ▼                       ▼          └──────────┬─────────┘
        ┌────────────────┐      ┌─────────────────┐            │
        │bin/diff-       │      │bin/run-upstream-│            ▼
        │ codegen.sh     │      │ tests.sh        │   [last line == "Done"?]
        │═══════════════ │      │═══════════════  │            │
        │1. Strip lines: │      │1. Strip lines:  │            ▼
        │  "// Generated │      │  "// Generated  │     ┌────────────┐
        │   by purs ..." │      │   by purs ..." │     │bin/run-     │
        │  "//# source-  │      │  "//# source-  │     │ passing-   │
        │   MappingURL"  │      │   MappingURL"  │     │ tests.sh   │
        │                │      │                │     │ ═════════  │
        │2. If SEMANTIC: │      │2. If SEMANTIC: │     └────┬───────┘
        │  rename $N→$0  │      │  rename $N→$0  │          │
        │  on both sides │      │  on both sides │          │
        │                │      │                │          │
        │3. Compare line │      │3. Compare line │          │
        │   by line      │      │   by line      │          │
        └────────┬───────┘      └────────┬───────┘          │
                 ▼                       ▼                  │
            ┌────────┐               ┌────────┐             │
            │  OK    │   ┌──────┐    │  OK    │  ┌──────┐   ▼
            └────────┘   │ DIFF │    └────────┘  │ DIFF │  ┌───────┐ ┌──────┐
                         └──────┘                └──────┘  │ Done  │ │ FAIL │
                                                           │ PASS  │ └──────┘
                                                           └───────┘ (codegen err
                                                                      / node err
                                                                      / no Done)
```

## bin/diff-codegen.sh — sample module diffs

The fastest sanity check during development. Iterates every module under
`sample-purs/output_ref/` and compares our codegen against purs's.

```
   sample-purs/output_ref/<Mod>/corefn.json
            │
            ▼
   ┌──────────────────────┐
   │  spago build         │  Re-build our codegen (only on first call;
   │  (once)              │  spago caches after that)
   └──────────┬───────────┘
              │
              ▼
   ┌──────────────────────────────────────────┐
   │  For each Mod under output_ref/:         │
   │                                          │
   │    ours = node Main(corefn.json)         │
   │    ref  = output_ref/Mod/index.js        │
   │                                          │
   │    Strip "// Generated by..." prefix     │
   │    Strip "//# sourceMappingURL"          │
   │                                          │
   │    [if SEMANTIC=1] renumber $N           │
   │                                          │
   │    if ours == ref:  OK                   │
   │    else:            DIFF (save to /tmp)  │
   └──────────────────────────────────────────┘
              │
              ▼
   Summary: 67 identical, 4 differ, 0 errored
   (in /tmp/pursjs-diff/ — DIFF saves both files for inspection)
```

**Modes:**
- default: byte-identical
- `SEMANTIC=1`: also renumber `$N` and `$tco_doneN` placeholders to 0..M
  in order of first appearance on both sides. Reveals when output differs
  *only* in fresh-name numbering (the known 4-module gap).
- `VERBOSE=1`: print OK/DIFF per module + show first 10 diffs at end

## bin/run-upstream-tests.sh — upstream `optimize/` goldens

Same algorithm as `diff-codegen.sh`, but inputs come from the upstream
purescript repo's golden suite. Each `Foo.purs` has a sibling `Foo.out.js`
that the upstream Haskell test runner produces and validates against.

```
   tests/upstream-optimize/Foo.purs
   tests/upstream-optimize/Foo.out.js  ← upstream's "expected output"
            │
            │
            ▼
   ┌──────────────────────────────────────────┐
   │  workdir = mktemp                         │
   │  Copy Foo.purs into workdir               │
   │  (Foreign.purs also gets Foreign.js)      │
   │                                           │
   │  Collect all prelude sources from         │
   │    sample-purs/.spago/p/*/src             │
   │                                           │
   │  purs compile --codegen js,corefn \       │
   │    -o workdir/output                      │
   │    workdir/Foo.purs                       │
   │    <all .spago sources>                   │
   └────────────┬──────────────────────────────┘
                ▼
        workdir/output/Main/corefn.json
                │
                ▼
   ┌──────────────────────────────────────────┐
   │  ours = node PursJS.Main(corefn) \        │
   │           --with-comments                 │
   │  (the upstream tests preserve --comments) │
   │                                           │
   │  ref = Foo.out.js                         │
   │                                           │
   │  Strip prefix lines, compare              │
   └────────────┬──────────────────────────────┘
                ▼
            OK or DIFF
```

**Modes:**
- `UPDATE_FROM_UPSTREAM=1`: re-fetch and re-sync from upstream first
  (clones if needed). Use this when the upstream repo has been bumped.
- `SEMANTIC=1`: as above.
- `VERBOSE=1`: as above.

## bin/run-passing-tests.sh — upstream `passing/` runtime tests

Mirrors the upstream `assertCompiles` flow exactly. The Haskell function
([`tests/TestCompiler.hs:131-152`](../../purescript/tests/TestCompiler.hs))
compiles each test, writes an entry-point JS that imports `Main/index.js`
and calls `main()`, executes via node, and expects the last line of stdout
to be `Done`. We do the same — but plug in **our** codegen for the `Main`
module.

```
   purescript/tests/purs/passing/Foo.purs
   purescript/tests/purs/passing/Foo/*.purs   (optional companion modules)
            │
            │
   ┌────────▼──────────────────────────────────────────────┐
   │  ONE-TIME SETUP (per script invocation):              │
   │                                                       │
   │    Pre-compile prelude/effect/console/etc. to a       │
   │    SHARED output dir. Done once, reused across tests. │
   │                                                       │
   │    purs compile --codegen js,corefn \                 │
   │      -o $SHARED_OUTPUT \                              │
   │      <all .spago sources>                             │
   └────────────┬──────────────────────────────────────────┘
                │
                │   for each test:
                ▼
   ┌──────────────────────────────────────────┐
   │  workdir = mktemp                         │
   │  cp -al $SHARED_OUTPUT $workdir/output    │ ◄ hardlinks (fast!)
   │                                           │   Cuts per-test time
   │  purs compile --codegen js,corefn \       │   from ~3s to ~0.75s.
   │    -o $workdir/output \                   │
   │    $purs $companions \                    │
   │    <all .spago sources>                   │
   │                                           │
   │  → $workdir/output/Main/{corefn.json,     │
   │                          index.js (ref)}  │
   └────────────┬──────────────────────────────┘
                ▼
   ┌──────────────────────────────────────────┐
   │  REPLACE $workdir/output/Main/index.js    │
   │  with the output of:                      │
   │    node PursJS.Main($corefn)              │
   │                                           │
   │  (Other modules — prelude etc. — keep     │
   │   purs's index.js, since we trust those.) │
   └────────────┬──────────────────────────────┘
                ▼
   ┌──────────────────────────────────────────┐
   │  Write entry-point:                       │
   │    $workdir/output/index.js =             │
   │      import('./Main/index.js')            │
   │        .then(({main}) => main());         │
   │                                           │
   │  Run: node $workdir/output/index.js       │
   │                                           │
   │  Check: last stdout line == "Done"        │
   └────────────┬──────────────────────────────┘
                ▼
        ┌──────────────────────────┐
        │ OK    Done (PASS)        │
        │ FAIL  No-Done            │  test ran but didn't print "Done"
        │ FAIL  Codegen err        │  our codegen threw
        │ FAIL  Runtime err        │  node threw on the produced JS
        │ FAIL  Purs err           │  purs couldn't compile (deps missing)
        └──────────────────────────┘
```

**Result classification** — each test ends up in one of five buckets:

| Bucket | Meaning | Our responsibility? |
|---|---|---|
| `Done (PASS)` | Our codegen produced JS that ran and logged "Done" | yes ✓ |
| `No-Done` | Our JS ran but produced wrong output | yes ✗ — semantic bug |
| `Codegen err` | Our codegen threw a runtime error | yes ✗ — codegen bug |
| `Runtime err` | The produced JS crashed in node | yes ✗ — semantic bug |
| `Purs err` | `purs compile` failed (missing dep) | no — test setup, not us |

We hit **319 / 319 in the "our responsibility" bucket** (100%); the 46
`Purs err` tests need modules like `Test.Assert`, `Effect.Ref`,
`Type.Equality` that aren't in our `sample-purs` spago package set.

**Speedup**: pre-compile prelude/effect/console **once** into a shared
output dir, then `cp -al` (hardlink-copy) it into each test's workdir.
The per-test `purs compile` invocation only has to compile the test
source itself. Cuts total runtime from ~22 minutes to ~5 minutes.

## bin/test-runtime.sh — runtime equivalence checker

Used when a byte-diff shows up but we want to know if the JS *behaves*
identically. Generates both codegens' output, executes a known-good driver,
and compares the stdout.

```
   sample-purs/output_ref/<Mod>/corefn.json
            │
            │
            ├────────────────────────────┬──────────────────────────────┐
            │                            │                              │
            ▼                            ▼                              │
   ┌──────────────────┐         ┌──────────────────┐                   │
   │ OURS sandbox:    │         │ PURS sandbox:    │                   │
   │ cp -r output_ref │         │ cp -r output_ref │                   │
   │                  │         │                  │                   │
   │ REPLACE          │         │ (keep purs's     │                   │
   │ Mod/index.js     │         │  Mod/index.js)   │                   │
   │ with our codegen │         │                  │                   │
   └────────┬─────────┘         └────────┬─────────┘                   │
            ▼                            ▼                             │
   ┌──────────────────┐         ┌──────────────────┐                   │
   │ node driver.mjs  │         │ node driver.mjs  │                   │
   │                  │         │                  │                   │
   │ Driver calls a   │         │ Same driver,     │                   │
   │ known set of     │         │ same arguments,  │                   │
   │ exports for that │         │ same module      │                   │
   │ module (e.g.     │         │ structure        │                   │
   │ Arith.intAdd(2,3)│         │                  │                   │
   │  for Arith)      │         │                  │                   │
   └────────┬─────────┘         └────────┬─────────┘                   │
            ▼                            ▼                             │
       [ours stdout]                [purs stdout]                      │
            │                            │                             │
            └────────────────┬───────────┘                             │
                             ▼                                         │
                  ┌─────────────────────┐                              │
                  │ diff -q ours purs   │                              │
                  └──────────┬──────────┘                              │
                             ▼                                         │
                      ┌──────────────┐                                 │
                      │ RUNTIME MATCH│                                 │
                      │ RUNTIME DIFF │                                 │
                      └──────────────┘                                 │
                                                                       │
   The driver expressions are hard-coded per module — Arith calls       │
   intAdd/intMul/...; Effect calls monadEffect.Applicative0().pure(1)() │
   to exercise mutually-recursive dictionaries; TailRecursion calls     │
   sumDown(1000)(0) to exercise TCO; etc. Each driver is small (5-10    │
   lines) and lives in the case statement in test-runtime.sh.            │
```

This is the script that found the original Effect runtime bug
(`Control_Monad.ap(monadEffect)` eagerly evaluating `monadEffect.Applicative0()`
before `applicativeEffect` was defined), which led to porting
`applyLazinessTransform`.

## The SEMANTIC=1 normalization

Three of the four byte-only diffs in the sample suite and one of the two
upstream-optimize diffs are pure `$N` numbering offsets. The `SEMANTIC=1`
mode lets us measure the rate of *structural* equivalence ignoring those.

```
  Before normalization:               After normalization (both sides):

    var $24 = eq(b)(zero);              var $0 = eq(b)(zero);
    if ($24) { ... }                    if ($0) { ... }
    var $26 = ...;                      var $1 = ...;
    if ($26) { ... }                    if ($1) { ... }
                                        
  vs                                  vs
                                      
    var $1 = eq(b)(zero);               var $0 = eq(b)(zero);
    if ($1) { ... }                     if ($0) { ... }
    var $3 = ...;                       var $1 = ...;
    if ($3) { ... }                     if ($1) { ... }
                                       
  → DIFF                             → MATCH
```

Implementation: a Python one-liner walks each side's text, builds a map
`{ "$24": "$0", "$26": "$1", ... }` in order of first appearance,
substitutes through, then text-diffs.

## Combined results table

| Suite | Mode | Pass | Notes |
|---|---|---|---|
| diff-codegen.sh | byte | 67/71 | 4 fresh-name diffs |
| diff-codegen.sh | semantic | **71/71** | every module structurally matches |
| run-upstream-tests.sh | byte | 8/10 | 4179 (selective lazy wrap), ObjectUpdate ($N) |
| run-upstream-tests.sh | semantic | **9/10** | only 4179 truly differs |
| run-passing-tests.sh | runtime | **319/319** | of codegen-eligible tests |
| test-runtime.sh | runtime | **10/10** | hand-picked modules |
