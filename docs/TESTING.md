# Testing infrastructure

Three runner scripts cover the codegen-relevant categories of the
upstream PureScript test suite, plus an aggregator that runs them all
and a few support tools. Everything reads from `tests/upstream/`, which
is a verbatim copy of `purescript@v0.15.15/tests/purs/**` (1039 `.purs`
files); no sibling purescript clone needed for testing.

| Script | What it tests | How |
|---|---|---|
| `bin/run-upstream-tests.sh` | Codegen output bytes for upstream golden tests | text diff against checked-in `.out.js` files in `tests/upstream/optimize/` |
| `bin/run-passing-tests.sh` | Runtime — `log "Done"` assertion | `purs compile` → swap our codegen in → `node` → check last stdout line |
| `bin/run-warning-tests.sh` | Codegen completes + JS parses | `purs compile` → our codegen → `node --check` |
| `bin/test-all.sh` | Roll-up of the three above + version check | runs them in sequence and tabulates results |
| `bin/sync-upstream-tests.sh` | Refresh `tests/upstream/` from a tag | `git archive <tag> tests/purs | tar` |
| `bin/test-inventory.sh` | Count tests per category, optional cross-version | reads `tests/upstream/` + optionally queries the upstream clone |
| `bin/check-version.sh` | Verify the upstream pin | parses `VERSIONING.md`, `git describe` on the clone |

## Overall flow

```
                    ┌───────────────────────────────────────────────────┐
                    │                  INPUTS                            │
                    │                                                    │
                    │  ┌────────────────────────────────────────┐      │
                    │  │ tests/upstream/optimize/ (10 + .out.js)│      │
                    │  │ tests/upstream/passing/  (438 .purs)   │      │
                    │  │ tests/upstream/warning/  (68 + .out)   │      │
                    │  │ (vendored: purescript@v0.15.15)        │      │
                    │  └────────────────────────────────────────┘      │
                    │  ┌────────────────────────────────────────┐      │
                    │  │ sample-purs/.spago/p/                  │      │
                    │  │ 40-package prelude source pool         │      │
                    │  │ (Prelude, Effect, Arrays, etc.)        │      │
                    │  └────────────────────────────────────────┘      │
                    └────────────────────┬───────────────────────────────┘
                                         │
              ┌──────────────────────────┼──────────────────────────────┐
              │                          │                              │
              ▼                          ▼                              ▼
   ┌──────────────────┐       ┌──────────────────┐           ┌──────────────────┐
   │  purs compile    │       │  purs compile    │           │  purs compile    │
   │  --codegen       │       │  --codegen       │           │  --codegen       │
   │  js,corefn       │       │  js,corefn       │           │  js,corefn       │
   └────────┬─────────┘       └────────┬─────────┘           └────────┬─────────┘
            │                          │                               │
            ▼                          ▼                               ▼
    ┌─────────────────┐       ┌─────────────────┐            ┌─────────────────┐
    │ Foo/corefn.json │       │ Foo/corefn.json │            │ Foo/corefn.json │
    │ Foo/index.js    │       │ Foo/index.js    │            │ Foo/index.js    │
    │   (reference)   │       │   (reference)   │            │   (reference)   │
    └─────┬───────┬───┘       └─────┬───────────┘            └────────┬────────┘
          │       │ (ref)           │                                 │
          ▼       │                 ▼                                 ▼
  ┌──────────────┐│        ┌──────────────┐                  ┌─────────────┐
  │ PursJS Main  ││        │ PursJS Main  │                  │ PursJS Main │
  │ (our codegen)││        │ replaces     │                  │             │
  └──────┬───────┘│        │ Main/index.js│                  └──────┬──────┘
         ▼        │        └──────┬───────┘                         ▼
    [our JS]      │               ▼                          ┌────────────────┐
         │        │        ┌────────────────────┐            │ node --check   │
         └────┬───┘        │  node index.js     │            │ on our output  │
              ▼            │  → stdout          │            └──────┬─────────┘
   ┌─────────────────┐     └──────────┬─────────┘                   ▼
   │bin/run-upstream-│                ▼                        ┌─────────┐
   │ tests.sh        │      [last line == "Done"?]             │ OK /    │
   │═══════════════  │                │                        │ Codegen │
   │Strip prefix,    │                ▼                        │ /Parse  │
   │compare bytes    │       ┌────────────┐                    │ fail    │
   │(optional        │       │bin/run-    │                    └─────────┘
   │ SEMANTIC=1)     │       │ passing-   │
   └────────┬────────┘       │ tests.sh   │
            ▼                │ ═════════  │
        ┌────────┐           └────┬───────┘
        │ OK /   │                │
        │ DIFF   │                ▼
        └────────┘         ┌───────┐ ┌──────┐
                           │ Done  │ │ FAIL │
                           │ PASS  │ └──────┘
                           └───────┘
```

## bin/run-upstream-tests.sh — `optimize/` goldens

Each `Foo.purs` has a sibling `Foo.out.js` that's the expected JS output.

```
   tests/upstream/optimize/Foo.purs
   tests/upstream/optimize/Foo.out.js  ← expected
            │
            ▼
   ┌──────────────────────────────────────────┐
   │  workdir = mktemp                         │
   │  Copy Foo.purs into workdir               │
   │  (Foreign.purs also gets Foreign.js)      │
   │                                           │
   │  purs compile --codegen js,corefn \       │
   │    -o workdir/output                      │
   │    workdir/Foo.purs                       │
   │    <all sample-purs/.spago sources>       │
   └────────────┬──────────────────────────────┘
                ▼
   ┌──────────────────────────────────────────┐
   │  ours = node PursJS.Main(corefn) \        │
   │           --with-comments                 │
   │  ref = Foo.out.js                         │
   │  Strip prefix lines, compare              │
   └────────────┬──────────────────────────────┘
                ▼
            OK or DIFF
```

Modes: `SEMANTIC=1` (renumber `$N` placeholders), `VERBOSE=1` (show diffs).

## bin/run-passing-tests.sh — `passing/` runtime tests

Mirrors `tests/TestCompiler.hs::assertCompiles`. Compiles each test,
swaps our codegen for the `Main` module, runs node, expects "Done".

```
   tests/upstream/passing/Foo.purs
   tests/upstream/passing/Foo/*.purs   (optional companion modules)
            │
   ┌────────▼──────────────────────────────────────────────┐
   │  ONE-TIME SETUP:                                       │
   │    Pre-compile prelude → $SHARED_OUTPUT                │
   │    (shared across tests via `cp -al` hardlinks)        │
   └────────────┬──────────────────────────────────────────┘
                │   for each test:
                ▼
   ┌──────────────────────────────────────────┐
   │  workdir = mktemp                         │
   │  cp -al $SHARED_OUTPUT $workdir/output    │
   │  purs compile ... -o $workdir/output ...  │
   └────────────┬──────────────────────────────┘
                ▼
   ┌──────────────────────────────────────────┐
   │  REPLACE $workdir/output/Main/index.js    │
   │  with our codegen's output                │
   │  (60s watchdog timeout via kill -9)       │
   └────────────┬──────────────────────────────┘
                ▼
   ┌──────────────────────────────────────────┐
   │  Write entry-point + run node             │
   │  Check last stdout line == "Done"         │
   └────────────┬──────────────────────────────┘
                ▼
        ┌──────────────────────────┐
        │ Done (PASS) | No-Done    │
        │ Codegen err | Timeout    │
        │ Runtime err | Purs err   │
        └──────────────────────────┘
```

## bin/run-warning-tests.sh — `warning/` programs

Programs that compile + produce a specified warning. Most don't have
`main`, so we just check that our codegen processes the corefn without
crashing and the emitted JS parses (`node --check`).

## bin/test-all.sh — aggregator

```
═════════════════════════════════════════════════════════════
ROLL-UP
═════════════════════════════════════════════════════════════
  Suite                          Pass      Fail   Skipped
  ─────                          ────      ────   ───────
  [1] Upstream optimize             8         2         0
  [2] Upstream passing            357         3         5
  [3] Upstream warning             62         0         6
═════════════════════════════════════════════════════════════
```

Modes:
- `QUICK=1` — LIMIT=20 per suite (~30s smoke check)
- `SKIP=2,3` — comma-separated list of suite numbers
- `CI=1` — exit 1 on any failure

## bin/sync-upstream-tests.sh — vendor refresher

```
$ bin/sync-upstream-tests.sh            # uses VERSIONING.md pin
$ bin/sync-upstream-tests.sh v0.14.9    # explicit tag
```

Wipes `tests/upstream/` (preserving `README.md`) and re-extracts the
test tree from the requested tag via `git archive | tar`. Writes a
`_SOURCE` provenance marker.

## SEMANTIC=1 normalization

```
  Before:                                  After (both sides):
    var $24 = eq(b)(zero);                   var $0 = eq(b)(zero);
    if ($24) { ... }                         if ($0) { ... }

  vs                                       vs

    var $1 = eq(b)(zero);                    var $0 = eq(b)(zero);
    if ($1) { ... }                          if ($0) { ... }
```

A Python one-liner renumbers each `$N` placeholder to `$0..$M` in order
of first appearance on both sides before diffing. Reveals that some
byte-level diffs are pure fresh-name numbering offsets (cosmetic — purs's
`Supply` counter is shared with desugar/case-guards/CSE phases that we
don't replicate).

## Why some upstream categories aren't tested

The upstream `tests/purs/` directory has 10 categories; we cover the 3
that exercise codegen (`optimize`, `passing`, `warning`). The other 7
are vendored to `tests/upstream/` for completeness but no runner exercises
them:

| Category | What it tests | Why we don't run it |
|---|---|---|
| `failing/` (444) | Programs that should fail to compile | Never reaches codegen |
| `docs/` (55) | `purs docs` output | Different format, not JS |
| `layout/` (15) | Parser layout rules | Parser, not codegen |
| `graph/` (4) | `purs graph` module dependencies | CLI feature |
| `psci/` (2) | REPL | Not JS codegen |
| `sourcemaps/` (2) | Source map generation | We don't emit source maps yet |
| `publish/` (1) | `purs publish` | Not codegen |

## Combined results

| Suite | Mode | Pass | Notes |
|---|---|---|---|
| run-upstream-tests.sh | byte | 8/10 | 4179 (selective lazy wrap), ObjectUpdate ($N) |
| run-upstream-tests.sh | semantic | **9/10** | only 4179 truly differs |
| run-passing-tests.sh | runtime | **357/360** of eligible | 3 failures: 4179, BigFunction, StringEscapes |
| run-warning-tests.sh | codegen | **62/62** of eligible | (5 skipped for missing prelude deps) |
