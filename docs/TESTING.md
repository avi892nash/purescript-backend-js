# Testing infrastructure

One Node.js runner (`scripts/test.mjs`) backed by npm scripts. Reads
tests from the vendored `tests/upstream/` (copy of `purescript@v0.15.15/tests/purs/`)
— no sibling purescript clone needed.

## npm scripts

| Command | What it does |
|---|---|
| `npm run build` | `spago build` (build the codegen) |
| `npm test` | Run all three suites in sequence + roll-up table |
| `npm run test:optimize` | The 10 `optimize/` byte-diff golden tests |
| `npm run test:passing` | The 438 `passing/` runtime "Done" assertions |
| `npm run test:warning` | The 68 `warning/` codegen-completes + JS-parses checks |
| `npm run test:quick` | All suites capped at `--limit=10` (~1-minute smoke check) |
| `npm run sync-tests` | Refresh `tests/upstream/` from `git archive v0.15.15 tests/purs` |

CLI flags (pass after `--`):

```bash
npm run test:passing -- --limit=50 --pattern=Newtype --verbose
npm run test:optimize -- --semantic        # normalise $N placeholders
```

## What each suite does

```
                       ┌──────────────────────┐
                       │  tests/upstream/     │
                       │  (vendored at v0.15.15)
                       └──────────┬───────────┘
                                  │
              ┌───────────────────┼───────────────────┐
              ▼                   ▼                   ▼
       ┌──────────────┐    ┌──────────────┐    ┌──────────────┐
       │  optimize/   │    │  passing/    │    │  warning/    │
       │ Foo.purs +   │    │ Foo.purs     │    │ Foo.purs +   │
       │ Foo.out.js   │    │ (logs "Done")│    │ Foo.out      │
       └──────┬───────┘    └──────┬───────┘    └──────┬───────┘
              ▼                   ▼                   ▼
       purs compile         purs compile        purs compile
              ▼                   ▼                   ▼
       corefn.json          corefn.json         corefn.json
              ▼                   ▼                   ▼
       our codegen ───┐     our codegen         our codegen
              ▼       │            ▼                   ▼
       strip prefix   │     replace Main/index.js   node --check
              ▼       │            ▼                   ▼
       diff bytes vs──┘     node ./index.js       OK / FAIL
       Foo.out.js                  ▼
              ▼            check stdout == "Done"
       OK / DIFF                   ▼
                            OK / FAIL
```

## Version check

`PursJS.CoreFn.FromJSON.checkVersion` reads the `"builtWith"` field from
every corefn.json and rejects it if the purs version doesn't match the
constant `pinnedPursVersion` in that module. Bypass with `--skip-version-check`
when invoking `pursjs` directly.

The pin is also recorded statically in [`VERSIONING.md`](../VERSIONING.md)
and dynamically in [`tests/upstream/_SOURCE`](../tests/upstream/_SOURCE).
A bump means updating all three plus running `npm run sync-tests`.

## SEMANTIC normalization

```
  Before:                                  After (both sides):
    var $24 = eq(b)(zero);                   var $0 = eq(b)(zero);
    if ($24) { ... }                         if ($0) { ... }
  vs                                       vs
    var $1 = eq(b)(zero);                    var $0 = eq(b)(zero);
    if ($1) { ... }                          if ($0) { ... }
```

A regex pass renumbers each `$N` and `$tco_doneN` placeholder to `$0..$M`
in order of first appearance on both sides before diffing. Reveals that
some byte-level diffs are pure fresh-name numbering offsets (purs's
`Supply` counter is shared with desugar/case-guards/CSE phases that we
don't replicate; mostly cosmetic).

## Why some upstream categories aren't tested

`tests/upstream/` has 10 categories; we run 3. The other 7 are vendored
for completeness but don't exercise codegen:

| Category | What it tests | Why we don't run it |
|---|---|---|
| `failing/` (444) | Programs that should fail to compile | Never reaches codegen |
| `docs/` (55) | `purs docs` output | Not JS |
| `layout/` (15) | Parser layout rules | Parser, not codegen |
| `graph/` (4) | `purs graph` | CLI feature |
| `psci/` (2) | REPL | Not codegen |
| `sourcemaps/` (2) | Source map generation | Not yet emitted |
| `publish/` (1) | `purs publish` | Not codegen |

## Combined results

| Suite | Mode | Pass | Notes |
|---|---|---|---|
| optimize | byte | 8/10 | 4179 (selective lazy wrap), ObjectUpdate ($N) |
| optimize | --semantic | **9/10** | only 4179 truly differs |
| passing | runtime | **357/360** of eligible | 3 failures: 4179, BigFunction, StringEscapes |
| warning | codegen | **62/62** of eligible | (5 skipped for missing prelude deps) |
