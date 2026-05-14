# purescript-backend-js

> **A JavaScript codegen for PureScript, ported out of the compiler so
> you can hack on optimisation passes in PureScript itself.**

[![CI](https://github.com/avinashverma/purescript-backend-js/actions/workflows/ci.yml/badge.svg)](https://github.com/avinashverma/purescript-backend-js/actions/workflows/ci.yml)
[![License: BSD-3-Clause](https://img.shields.io/badge/license-BSD--3--Clause-blue.svg)](LICENSE)
[![purs: v0.15.15](https://img.shields.io/badge/purs-v0.15.15-purple.svg)](VERSIONING.md)

The PureScript compiler (`purs`) bundles its parser, type-checker,
desugarer, CoreFn lowering, **and JavaScript codegen** all together in
Haskell. That last part — the JavaScript codegen and its 14 optimiser
passes — is what we've lifted out and re-implemented in PureScript.
Hook it in as a [spago alternate backend](https://github.com/purescript/spago#alternate-backends)
and `spago build` produces JavaScript via this codegen instead of the
one baked into `purs`.

```
.purs   ──┐
          │
  [purs:  parse → typecheck → desugar → CoreFn]      (unchanged, still Haskell)
          │
          ▼
      corefn.json   ─── purescript-backend-js takes over here ───►   index.js
                                                                      foreign.js
```

## Why

Because **the codegen is the part you most want to change**, and Haskell
is the part of the toolchain most PureScript users never touch.

- **Want to add an optimisation?** New pass = new PureScript file under
  [`src/PursJS/CoreImp/Optimizer/`](src/PursJS/CoreImp/Optimizer/).
  No `stack` setup, no GHC versions to wrangle, no separate
  `ghc-options`, no `cabal hell`.
- **Want to experiment with a new lowering?** Edit
  [`src/PursJS/CodeGen/JS.purs`](src/PursJS/CodeGen/JS.purs), `spago
  build`, run the test suite. Round-trip is seconds.
- **Want to study how the codegen works?** Every PursJS module has a
  header naming its Haskell counterpart with line numbers, and
  [`LEARN.md`](LEARN.md) walks the full CoreFn → JS mapping with worked
  examples.
- **Want byte-for-byte parity with stock `purs`?** That's the target,
  and we hit it on 67 of 71 modules in our self-test (the other 4
  differ only in fresh-name numbering — runtime-equivalent and
  semantic-equivalent under `SEMANTIC=1`).

This isn't a rewrite for its own sake — it's a deliberate extraction
that lowers the bar for **anyone with a PureScript optimisation idea**
to try it out.

## Quick start

```bash
# 1. Get the codegen and build it
git clone https://github.com/avinashverma/purescript-backend-js
cd purescript-backend-js
spago build
npm link                          # exposes `purescript-backend-js` on PATH
                                  # (also registers `pursjs-codegen` as an alias)

# 2. In your own PureScript project's spago.yaml:
#
#    workspace:
#      backend:
#        cmd: "purescript-backend-js"
#
# 3. Build as normal
cd ../my-app
spago build
#   ⇒ Compiling with backend "purescript-backend-js"
#   ⇒ purescript-backend-js: N/N modules generated (+M foreign.js copied)

# 4. Run the output
node -e "import('./output/Main/index.js').then(m => m.main());"
```

That's it. Stock `spago` workflow, alternate codegen, same output.

## Results at a glance

Against the full upstream test suite (vendored at
[`tests/upstream/`](tests/upstream/), pinned to `purescript@v0.15.15`):

| Test suite | Count | Pass rate | What it checks |
|---|---|---|---|
| `npm run test:optimize` | 10 | **8/10 byte / 9/10 semantic** | Golden tests — does our codegen produce the exact JS purs's optimiser does? |
| `npm run test:passing`  | 438 | **357/360 codegen-eligible** | Runtime tests — does the program execute and log `Done`? |
| `npm run test:warning`  | 68 | **62/62 codegen-eligible** | Compile-only tests — does codegen complete without crashing? |

Run everything in one go:

```bash
npm test                          # full run, ~10 min
npm run test:quick                # smoke (LIMIT=10 per suite), ~1 min
```

The three remaining `passing` failures are:

- `4179` — runtime error from our minimal `applyLazinessTransform` not
  yet handling purs's selective per-binding wrapping
- `BigFunction` — optimiser times out on a 9.6 MB corefn (16-clause
  pattern match)
- `StringEscapes` — surrogate-pair handling in JSON parsing

The 4 byte-diff `optimize` modules pass `SEMANTIC=1` (which renumbers
`$N` placeholders on both sides) and pass at runtime; they diverge
because `purs`'s fresh-name `Supply` counter is shared with CoreFn-stage
phases (desugar, case-guards, CSE) that we don't replicate.

## How it slots into your build

```
┌──────────────────┐    purs compile         ┌─────────────────┐
│  Your .purs src  │ ─────────────────────►  │  corefn.json    │
└──────────────────┘    (--codegen corefn)   └─────────────────┘
                                                       │
                                                       │  spago invokes the
                                                       │  configured backend
                                                       ▼
                                             ┌────────────────────────┐
                                             │ purescript-backend-js  │
                                             │       (this repo)      │
                                             └────────────────────────┘
                                                       │
                                                       ▼
                                             ┌─────────────────┐
                                             │  index.js       │
                                             │  foreign.js     │
                                             └─────────────────┘
```

What purescript-backend-js does at each module:

1. Parses `corefn.json` (via Argonaut)
2. Lowers CoreFn → CoreImp (simplified imperative JS AST)
3. Runs 14 optimiser passes (see
   [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md))
4. Applies the laziness transform for mutually-recursive instance
   dictionaries
5. Pretty-prints CoreImp → JavaScript text
6. Copies `foreign.js` from the source tree

## What you get vs stock `purs`

| | Stock `purs` codegen | `purescript-backend-js` |
|---|---|---|
| Output format | ES modules | ES modules (byte-identical on 67/71 of our test modules) |
| Optimiser passes | 14 | Same 14, ported faithfully |
| `$runtime_lazy` for mutually-recursive instance dicts | ✅ | ✅ |
| TCO (`$tco_loop`) | ✅ | ✅ |
| Magic-do for `Effect` / `Eff` / `ST` | ✅ | ✅ |
| Uncurried `mkFn` / `runFn` / `mkEffectFn` / `runEffectFn` (arities 0..10) | ✅ | ✅ |
| Source maps | ✅ | not yet |
| Language for adding new passes | Haskell | PureScript |
| Branches based on `purs` version | n/a (it *is* purs) | One per supported `purs` release — see [VERSIONING.md](VERSIONING.md) |

## Architecture

The PursJS code is ~2300 lines across 17 modules. Each module's header
names its Haskell counterpart and the upstream commit it was ported
from.

| Module | Haskell counterpart | Role |
|---|---|---|
| [`PursJS.Names`](src/PursJS/Names.purs) | `Language.PureScript.Names` | `Ident`, `ModuleName`, `ProperName`, `Qualified`, `SourceSpan` |
| [`PursJS.PSString`](src/PursJS/PSString.purs) | `Language.PureScript.PSString` | JS-style string escaping (UTF-16 code units, `\xNN`/`\uNNNN`) |
| [`PursJS.Comments`](src/PursJS/Comments.purs) | `Language.PureScript.Comments` | `LineComment` / `BlockComment` |
| [`PursJS.CoreFn.Types`](src/PursJS/CoreFn/Types.purs) | `CoreFn/{Expr,Binders,Meta,Module,Ann}.hs` | The CoreFn AST |
| [`PursJS.CoreFn.FromJSON`](src/PursJS/CoreFn/FromJSON.purs) | `CoreFn/FromJSON.hs` | Parse `corefn.json`, version-check `builtWith` |
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

## Repository layout

| Path | What it is |
|---|---|
| [`src/PursJS/`](src/PursJS/) | The codegen, in PureScript. |
| [`prelude-pool/`](prelude-pool/) | A spago project that provisions the 40-package prelude source pool the upstream tests need to compile (matches `purescript/tests/support/bower.json`). |
| [`tests/upstream/`](tests/upstream/) | The entire upstream `purescript/tests/purs/**` tree at our pinned version (1039 `.purs` files at `v0.15.15`). Refresh with `npm run sync-tests`. |
| [`scripts/spago-backend.mjs`](scripts/spago-backend.mjs) | The `purescript-backend-js` entry point (exposed via `npm link`; also installs `pursjs-codegen` as an alias). Walks `output/<Module>/corefn.json` and writes `index.js` + sibling `foreign.js`. |
| [`scripts/test.mjs`](scripts/test.mjs) | The Node.js test runner that backs `npm test`. |
| [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) | Pipeline block-diagram + per-decision-point divergence from Haskell. |
| [`docs/TESTING.md`](docs/TESTING.md) | Test-infrastructure block-diagram + per-runner flow. |
| [`LEARN.md`](LEARN.md) | Deep-dive tutorial: every CoreFn expression → JS mapping. |
| [`VERSIONING.md`](VERSIONING.md) | Branch-per-purs-version policy + branch matrix. |
| [`CHANGELOG.md`](CHANGELOG.md) | Release notes. |
| [`CONTRIBUTING.md`](CONTRIBUTING.md) | How to set up, run tests, port a new release. |

## Version pinning

This codegen targets a **specific** `purs` release. `master` is pinned
to **purs v0.15.15** (commit `5589e81`). Every `corefn.json` carries a
`builtWith` field; we compare it against our pin and reject mismatches
(exit code 2) by default. Override with `--skip-version-check` if
you're knowingly experimenting.

For other purs versions, check out the branch matching your target —
see [VERSIONING.md](VERSIONING.md) for the matrix, the historical
schema changes that drove each branch, and the recipe for cutting a
new one.

## Contributing

PRs, issues, and questions are all welcome. See
[CONTRIBUTING.md](CONTRIBUTING.md) for setup, test expectations, and
the porting recipe.

If you want to add a new optimiser pass, the existing passes under
[`src/PursJS/CoreImp/Optimizer/`](src/PursJS/CoreImp/Optimizer/) are
small and self-contained; pick one as a template, drop your file in,
add it to the pipeline in
[`PursJS.CoreImp.Optimizer`](src/PursJS/CoreImp/Optimizer.purs), and
run the test suite.

## License

[BSD-3-Clause](LICENSE) — same as the upstream PureScript compiler.

Portions of this code are derived from the
[PureScript compiler](https://github.com/purescript/purescript)
(copyright Phil Freeman and the PureScript contributors).
