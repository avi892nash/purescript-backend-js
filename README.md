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

| Test suite | Count | Pass rate | Notes |
|---|---|---|---|
| `bin/diff-codegen.sh` (sample modules) | 71 | **67/71 byte / 71/71 semantic** | 4 differ only in `$N` fresh-name numbering — structurally identical |
| `bin/run-upstream-tests.sh` (upstream `optimize/`) | 10 | **8/10 byte / 9/10 semantic** | Mirrors `purescript/tests/purs/optimize/` golden tests |
| `bin/run-passing-tests.sh` (upstream `passing/`) | 319 | **319/319 (100%)** | Mirrors `purescript/tests/purs/passing/` runtime "Done" assertions |
| `bin/test-runtime.sh` | 10 | **10/10** | Loads each module in node and confirms its exports behave identically |

The remaining 4 byte-diff modules pass `SEMANTIC=1` mode (which normalises
`$N` numbering) and pass the runtime test — they diverge only because
purs's fresh-name `Supply` counter is shared with CoreFn-stage phases
(desugar, case-guards, CSE) that we don't replicate.

## What's in this repo

| Path | What it is |
|---|---|
| [`src/PursJS/`](src/PursJS/) | The codegen, written in PureScript. ~2300 lines across 17 modules. Every file's header names its Haskell counterpart and gives a line-by-line cross-reference pinned to purescript@c4a35b3. |
| [`sample-purs/`](sample-purs/) | A spago project with Prelude/Effect/Console + 13 hand-written `Examples.*` modules. We compile this with `purs` to get reference output, then diff against ours. |
| [`tests/upstream-optimize/`](tests/upstream-optimize/) | Verbatim copies of upstream `purescript/tests/purs/optimize/*.{purs,out.js}` for offline runs. |
| [`bin/`](bin/) | Four runner scripts: byte-identical diffs, semantic diffs, upstream optimize tests, upstream passing tests, runtime equivalence. |
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

# 2. Generate purs's reference output (compile the sample-purs project)
cd sample-purs
spago build       # installs prelude/effect/console deps
purs compile --codegen js,corefn -o output_ref \
  '.spago/p/console-6.1.0/src/**/*.purs' \
  '.spago/p/effect-4.0.0/src/**/*.purs' \
  '.spago/p/prelude-6.0.2/src/**/*.purs' \
  'src/**/*.purs'
cd ..

# 3. Run our codegen on a single module
spago run --main PursJS.Main -- ./sample-purs/output_ref/Simple/corefn.json

# 4. Compare against purs's output across all 71 modules
./bin/diff-codegen.sh         # 67/71 byte-identical
SEMANTIC=1 ./bin/diff-codegen.sh   # 71/71 semantic match

# 5. Run the upstream Haskell test suites
./bin/run-upstream-tests.sh   # 10 codegen golden tests
./bin/run-passing-tests.sh    # 319 runtime "Done" tests (100% pass)

# 6. Run a module in node and compare behavior between codegens
./bin/test-runtime.sh Examples.TailRecursion
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
   replaced with ours. Verified by `bin/run-passing-tests.sh`, which
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

## Further reading

- [LEARN.md](LEARN.md) — CoreFn-to-JS mapping in detail, every expression
  variant explained with source / corefn / output triplets.
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) — Pipeline block diagram +
  every decision-point and divergence from Haskell.
- [tests/upstream-optimize/README.md](tests/upstream-optimize/README.md) — What
  each of the 10 upstream optimize tests exercises.
- The upstream Haskell sources cloned at `/Users/avinashverma/purescript/`
  (or wherever `git clone https://github.com/purescript/purescript` puts
  it) are the authoritative reference for every PursJS module.
