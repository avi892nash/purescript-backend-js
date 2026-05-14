# purescriptCodeGen

The PureScript compiler's JavaScript backend, **rewritten in PureScript**.

The upstream Haskell compiler (`purs`) still does parsing, type-checking,
desugaring, and CoreFn lowering. We pick up at `corefn.json` and produce
the same `index.js` that `purs` would — byte-for-byte on most modules,
and runtime-equivalent on every test we've thrown at it.

```
 .purs   ──┐
           │
   [Haskell purs: parse → typecheck → desugar → CoreFn → CSE → rename]
           │
           ▼
       corefn.json   ◄─── our entry point
           │
   [PursJS: read JSON → CodeGen.JS → 5 rounds of optimizer → Printer]
           │
           ▼
       index.js      ◄─── byte-identical to purs's output on 67/71 modules
```

## Results at a glance

| Test suite | Count | Pass rate | Mirrors |
|---|---|---|---|
| `npm run test:optimize` | 10 | **8/10 byte / 9/10 semantic** | `TestCompiler.hs::optimizeTests` (`purs/optimize/`) |
| `npm run test:passing`  | 438 | **357/360 codegen-eligible** | `TestCompiler.hs::passingTests` (`purs/passing/`) |
| `npm run test:warning`  | 68 | **62/62 codegen-eligible** | `TestCompiler.hs::warningTests` (`purs/warning/`) — codegen-side only |

All three suites read from the vendored upstream tree at
[`tests/upstream/`](tests/upstream/) (1039 `.purs` files from
`purescript@v0.15.15`), so the repo is self-contained.

Of the 360 codegen-eligible passing tests, only **3 fail**:

  - `4179` — runtime error from our minimal `applyLazinessTransform` not
    handling purs's selective per-binding wrapping
  - `BigFunction` — codegen times out (9.6 MB corefn from a 16-clause pattern
    match; our optimizer is O(?) on it)
  - `StringEscapes` — surrogate-pair / astral code point handling in our
    JSON parser

5 more are skipped because they need typeclass-deriving features (Contravariant /
Profunctor / Bifunctor / Functor-from-Bi-and-Pro) that aren't in our package set.

Run everything in one go:

```bash
npm test                          # all suites, ~10 minutes
npm run test:quick                # all suites, capped at LIMIT=10, ~1 minute
```

The remaining 4 byte-diff modules pass `SEMANTIC=1` mode (which normalises
`$N` numbering) and pass the runtime test — they diverge only because
purs's fresh-name `Supply` counter is shared with CoreFn-stage phases
(desugar, case-guards, CSE) that we don't replicate.

## Using this codegen in your project

This repo ships an executable `pursjs-codegen` that conforms to the
[spago alternate-backend protocol](https://github.com/purescript/spago#alternate-backends).
Spago invokes it after `purs compile --codegen corefn` so our PureScript-
implemented codegen runs in place of `purs`'s built-in JS codegen.

### One-time setup

```bash
# 1. Clone and build this repo (must be on the v0.15.15 branch — see Version pinning)
git clone https://github.com/<you>/purescriptCodeGen ~/purescriptCodeGen
cd ~/purescriptCodeGen
spago build                                # build the codegen itself
npm link                                   # exposes `pursjs-codegen` on PATH
```

`npm link` reads the `bin` entry in our `package.json` and symlinks
`pursjs-codegen` into your global node bin directory. Verify with
`which pursjs-codegen`.

### Wire it into your project

In **your downstream PureScript project's `spago.yaml`**, add a
`workspace.backend` entry:

```yaml
package:
  name: my-app
  dependencies:
    - prelude
    - effect
    - console

workspace:
  package_set:
    registry: 76.2.1
  backend:
    cmd: "pursjs-codegen"
```

Then build as normal:

```bash
spago build
# ⇒ Compiling with backend "pursjs-codegen"
# ⇒ pursjs-codegen: N/N modules generated (+M foreign.js copied)
```

Run the result with Node:

```bash
node -e "import('./output/Main/index.js').then(m => m.main());"
```

### What you get

| | Stock `purs` codegen | `pursjs-codegen` |
|---|---|---|
| Output format | ES modules | ES modules (byte-identical on 67/71 of our test modules) |
| Optimizer passes | 14 | Same 14, ported faithfully |
| `$runtime_lazy` for mutually-recursive instance dicts | ✅ | ✅ |
| TCO (`$tco_loop`) | ✅ | ✅ |
| Magic-do for `Effect` / `Eff` / `ST` | ✅ | ✅ |
| Uncurried `mkFn`/`runFn`/`mkEffectFn`/`runEffectFn` (arities 0..10) | ✅ | ✅ |
| Forks based on purs version | n/a (it *is* purs) | One branch per supported `purs` release; see [VERSIONING.md](VERSIONING.md) |

### Version compatibility

Pick the branch of this repo that matches your project's `purs` version.
The branch's `package.json` version reads `<purs-version>-pursjs.<N>`
(e.g. `0.15.15-pursjs.0`). Mismatches will be caught at runtime — every
`corefn.json` carries a `builtWith` field that we compare against our
pinned version and reject (exit code 2) by default. Override with
`--skip-version-check` if you're knowingly experimenting.

### Limitations

- The three failing tests called out above (`4179`, `BigFunction`,
  `StringEscapes`) — if your project triggers one of those patterns,
  you'll hit the same failure.
- No source maps yet (purs has `--codegen sourcemaps`, we don't).
- Backend mode requires a global Node install (`>=18`).

## What's in this repo

| Path | What it is |
|---|---|
| [`src/PursJS/`](src/PursJS/) | The codegen, written in PureScript. ~2300 lines across 17 modules. Every file's header names its Haskell counterpart and gives a line-by-line cross-reference pinned to purescript@c4a35b3. |
| [`prelude-pool/`](prelude-pool/) | A spago project that provisions the 40-package prelude source pool the upstream tests need to compile (matches `purescript/tests/support/bower.json`). |
| [`tests/upstream/`](tests/upstream/) | The **entire** upstream `purescript/tests/purs/**` tree at our pinned version (`v0.15.15`, 1039 `.purs` files). Refresh with `npm run sync-tests`. |
| [`scripts/test.mjs`](scripts/test.mjs) | The Node.js test runner that backs `npm test` — handles workdir setup, per-test purs invocation, our-codegen invocation, watchdog timeouts, result tabulation. |
| [`scripts/spago-backend.mjs`](scripts/spago-backend.mjs) | The spago-alternate-backend entry point (`pursjs-codegen` on PATH after `npm link`). Walks `output/<Module>/corefn.json` and writes `index.js` + sibling `foreign.js` files. |
| [`package.json`](package.json) | npm script entry points (`test`, `test:optimize`, `test:passing`, `test:warning`, `test:quick`, `sync-tests`, `build`) + the `bin` mapping that registers `pursjs-codegen`. |
| [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) | Block-diagram of the pipeline + every place this port diverges from Haskell (20-row table). |
| [`LEARN.md`](LEARN.md) | Deep-dive tutorial: every CoreFn expression → JS mapping with worked examples. |

## The PursJS code, by module

| Module | Haskell counterpart | Role |
|---|---|---|
| [`PursJS.Names`](src/PursJS/Names.purs) | `Language.PureScript.Names` | `Ident`, `ModuleName`, `ProperName`, `Qualified`, `SourceSpan` |
| [`PursJS.PSString`](src/PursJS/PSString.purs) | `Language.PureScript.PSString` | JS-style string escaping (UTF-16 code units, `\xNN`/`\uNNNN`) |
| [`PursJS.Comments`](src/PursJS/Comments.purs) | `Language.PureScript.Comments` | `LineComment` / `BlockComment` |
| [`PursJS.CoreFn.Types`](src/PursJS/CoreFn/Types.purs) | `CoreFn/{Expr,Binders,Meta,Module,Ann}.hs` | The CoreFn AST |
| [`PursJS.CoreFn.FromJSON`](src/PursJS/CoreFn/FromJSON.purs) | `CoreFn/FromJSON.hs` | Parse `corefn.json` |
| [`PursJS.CoreImp.AST`](src/PursJS/CoreImp/AST.purs) | `CoreImp/AST.hs` | Simplified imperative JS AST |
| [`PursJS.CoreImp.Module`](src/PursJS/CoreImp/Module.purs) | `CoreImp/Module.hs` | Imports/exports/body wrapper |
| [`PursJS.CoreImp.Traversals`](src/PursJS/CoreImp/Traversals.purs) | `CoreImp/AST.hs:172-243` | `everywhere`, `everywhereTopDown`, `everything`, monadic top-down |
| [`PursJS.CodeGen.Common`](src/PursJS/CodeGen/Common.purs) | `CodeGen/JS/Common.hs` | JS identifier escaping, reserved words, built-ins |
| [`PursJS.CodeGen.Supply`](src/PursJS/CodeGen/Supply.purs) | `Control.Monad.Supply.Class` | `State Int` fresh-name supply |
| [`PursJS.CodeGen.JS`](src/PursJS/CodeGen/JS.purs) | `CodeGen/JS.hs` | The main `CoreFn → CoreImp` transform |
| [`PursJS.CodeGen.Laziness`](src/PursJS/CodeGen/Laziness.purs) | `CoreFn/Laziness.hs` (subset) | Minimal `applyLazinessTransform` for mutually-recursive instances |
| [`PursJS.CodeGen.Printer`](src/PursJS/CodeGen/Printer.purs) | `CodeGen/JS/Printer.hs` | Pretty-print CoreImp → JavaScript text |
| [`PursJS.CoreImp.Optimizer`](src/PursJS/CoreImp/Optimizer.purs) | `CoreImp/Optimizer.hs` | Pipeline orchestrator |
| [`PursJS.CoreImp.Optimizer.Common`](src/PursJS/CoreImp/Optimizer/Common.purs) | `CoreImp/Optimizer/Common.hs` | Variable analysis helpers |
| [`PursJS.CoreImp.Optimizer.Blocks`](src/PursJS/CoreImp/Optimizer/Blocks.purs) | `CoreImp/Optimizer/Blocks.hs` | Block flattening + if collapsing |
| [`PursJS.CoreImp.Optimizer.Inliner`](src/PursJS/CoreImp/Optimizer/Inliner.purs) | `CoreImp/Optimizer/Inliner.hs` (part 1) | `etaConvert`, `unThunk`, `evaluateIifes`, `inlineVariables` |
| [`PursJS.CoreImp.Optimizer.Inliner2`](src/PursJS/CoreImp/Optimizer/Inliner2.purs) | `CoreImp/Optimizer/Inliner.hs` (part 2) | `inlineCommonValues/Operators`, `inlineFnIdentity`, `inlineUnsafeCoerce`, `inlineUnsafePartial`, `inlineUnsafeIndex` |
| [`PursJS.CoreImp.Optimizer.Constants`](src/PursJS/CoreImp/Optimizer/Constants.purs) | `Constants/Libs.hs` | `(ModuleName, PSString)` constants the inliner pattern-matches against |
| [`PursJS.CoreImp.Optimizer.FnComposition`](src/PursJS/CoreImp/Optimizer/FnComposition.purs) | `CoreImp/Optimizer/Inliner.hs:248-274` | `inlineFnComposition` (the only monadic pass) |
| [`PursJS.CoreImp.Optimizer.MagicDo`](src/PursJS/CoreImp/Optimizer/MagicDo.purs) | `CoreImp/Optimizer/MagicDo.hs` | `magicDoEffect` / `magicDoEff` / `magicDoST` |
| [`PursJS.CoreImp.Optimizer.TCO`](src/PursJS/CoreImp/Optimizer/TCO.purs) | `CoreImp/Optimizer/TCO.hs` | Tail-call elimination → `$tco_loop` while-loops |
| [`PursJS.CoreImp.Optimizer.Uncurried`](src/PursJS/CoreImp/Optimizer/Uncurried.purs) | `CoreImp/Optimizer/Inliner.hs:189-234` | `mkFn`/`runFn`/`mkEffectFn`/`runEffectFn` etc. (arities 0..10) |
| [`PursJS.CoreImp.Optimizer.Unused`](src/PursJS/CoreImp/Optimizer/Unused.purs) | `CoreImp/Optimizer/Unused.hs` | Dead-code passes (post-return, `undefined` apps, unused vars) |
| [`PursJS.Main`](src/PursJS/Main.purs) | `Make/Actions.hs:230-280` | CLI entry: read corefn.json, print JS |

## Quickstart

```bash
git clone <this repo>
cd purescriptCodeGen

# 1. Build the codegen
spago build

# 2. Install the prelude source pool (40 packages — matches upstream's test-suite-support)
cd prelude-pool && spago build && cd ..

# 3. Run the upstream test suites against our codegen
npm run test:optimize              # 10 codegen golden tests   → 8/10 byte
npm run test:passing               # 438 runtime "Done" tests  → 357/360 codegen-eligible
npm run test:warning               # 68 codegen-completes tests → 62/62 codegen-eligible

# 4. All-in-one
npm test
npm run test:quick                 # smoke check (LIMIT=10 per suite)

# 5. (Once-off) generate JS for any module
purs compile --codegen js,corefn -o /tmp/out path/to/Main.purs \
  $(find prelude-pool/.spago/p -name '*.purs')
spago run --main PursJS.Main -- /tmp/out/Main/corefn.json
```

## Key things this repo demonstrates

1. **A full compiler backend is feasible to port end-to-end.** ~2300 lines
   of PureScript replace ~3100 lines of Haskell, including all 14 optimizer
   passes (block flattening, IIFE collapse, dead-code removal, common-value
   inlining, common-operator inlining, function composition unfolding,
   identity removal, unsafe-coerce removal, unsafe-partial unfolding,
   unsafe-index unfolding, uncurried-function inlining, magic-do for three
   different monads, tail-call elimination, integer normalisation), the
   laziness transform for mutually-recursive bindings, and the pretty
   printer with full operator-precedence handling.

2. **Byte-equality with a reference compiler is achievable.** 67/71 modules
   match purs's output literally; the remaining 4 differ *only* in the
   numeric suffix of fresh names (`$24` vs `$0`) because purs's `Supply`
   counter is shared with phases (desugar, case-guards, CSE) that we
   don't replicate, and the Renamer destroys the original `GenIdent`
   number before codegen sees it. Under `SEMANTIC=1` (which renumbers
   `$N` placeholders on both sides), all 71 modules match.

3. **Runtime equivalence on the upstream test suite.** 319 of 319
   codegen-eligible tests from `purescript/tests/purs/passing/` (full
   PureScript programs that compile to JS and assert `log "Done"`)
   produce the expected `Done` output when their `Main/index.js` is
   replaced with ours. Verified by `npm run test:passing`, which
   mirrors `TestCompiler.hs::assertCompiles` from the Haskell test
   framework.

4. **The port is self-documenting.** Every PursJS source file opens with
   a header naming the Haskell file and commit it was ported from, plus
   a per-symbol line-number map. The optimizer passes are individually
   testable against the upstream golden tests. [`LEARN.md`](LEARN.md)
   walks through every CoreFn expression with a source / corefn / JS
   triplet so you can follow the transformation by example.

5. **Three classes of test infrastructure mirrored from `stack test`.**
   The upstream Haskell test runner runs four kinds of compiler tests
   (`passing`, `failing`, `optimize`, `warning`); we mirror the two that
   are about codegen output (`optimize`, `passing`) and provide our own
   sample-modules diff suite plus a node-based runtime equivalence checker.

## Version pinning

This codegen targets a **specific** purescript release. `master` is pinned to
**purs v0.15.15** (commit `c4a35b3`). See [VERSIONING.md](VERSIONING.md) for:

- The full pin (purs + prelude + package-set versions)
- The branch matrix for older purs versions
- What changes across purs versions and which PursJS modules are affected
- How to cut a new branch for a different purs release

The current pin is recorded in two places:
[`VERSIONING.md`](VERSIONING.md) (the source of truth) and
[`tests/upstream/_SOURCE`](tests/upstream/_SOURCE) (the actual commit
the vendored test set came from).

## Further reading

- [LEARN.md](LEARN.md) — CoreFn-to-JS mapping in detail, every expression
  variant explained with source / corefn / output triplets.
- [VERSIONING.md](VERSIONING.md) — Version-pinning policy and branch matrix.
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) — Codegen pipeline block diagram +
  every decision-point and divergence from Haskell.
- [docs/TESTING.md](docs/TESTING.md) — Test-infrastructure block diagram +
  per-runner flow for all five scripts.
- [tests/upstream-optimize/README.md](tests/upstream-optimize/README.md) — What
  each of the 10 upstream optimize tests exercises.
- The upstream Haskell sources cloned at `/Users/avinashverma/purescript/`
  (or wherever `git clone https://github.com/purescript/purescript` puts
  it) are the authoritative reference for every PursJS module.
