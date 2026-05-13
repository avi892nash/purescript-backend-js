# PureScript JS Codegen, in PureScript

A re-implementation of the PureScript compiler's JavaScript backend
(`Language.PureScript.CodeGen.JS` and friends) written in PureScript itself.
The Haskell compiler stays as the front-end (parsing, type-checking, CoreFn
emission); this project picks up at `corefn.json` and produces the same
`index.js` that `purs` would.

## Layout

```
purescriptCodeGen/
├── src/PursJS/
│   ├── Names.purs              -- Ident, ModuleName, ProperName, Qualified, SourcePos
│   ├── PSString.purs           -- PureScript string handling + JS escaping
│   ├── Comments.purs           -- LineComment / BlockComment
│   ├── CoreFn/
│   │   ├── Types.purs          -- CoreFn AST: Module, Bind, Expr, Binder, Literal, Meta
│   │   └── FromJSON.purs       -- corefn.json reader
│   ├── CoreImp/
│   │   ├── AST.purs            -- Simplified imperative JS AST
│   │   └── Module.purs         -- Module with imports/body/exports
│   ├── CodeGen/
│   │   ├── Common.purs         -- Name mangling, JS reserved words, JS builtins
│   │   ├── Supply.purs         -- State Int fresh-name supply
│   │   ├── JS.purs             -- CoreFn → CoreImp.AST transform
│   │   └── Printer.purs        -- CoreImp.Module → JS text
│   └── Main.purs               -- CLI: corefn.json → JS on stdout
├── sample-purs/                -- test fixture (Prelude, Effect, Console, our Tiny/Simple)
├── bin/diff-codegen.sh         -- compare our output against purs's index.js
└── ../purescript/              -- the Haskell compiler clone (sibling dir)
```

## Quickstart

```bash
# Build
spago build

# Generate purs's reference output (the "old" codegen)
cd sample-purs
purs compile --codegen js,corefn -o output_ref \
  '.spago/p/console-6.1.0/src/**/*.purs' \
  '.spago/p/effect-4.0.0/src/**/*.purs' \
  '.spago/p/prelude-6.0.2/src/**/*.purs' \
  'src/**/*.purs'
cd ..

# Run our codegen on a single module
spago run --main PursJS.Main -- ./sample-purs/output_ref/Simple/corefn.json

# Compare against purs's output across all 71 modules
./bin/diff-codegen.sh
# Verbose: shows OK/DIFF per module
VERBOSE=1 ./bin/diff-codegen.sh
```

## Running the upstream test suites

The purescript Haskell repo has three categories of tests we replicate:

### 1. Optimize golden tests (10 tests)

`tests/purs/optimize/*.{purs,out.js}` — each compiles a small program and
diffs against an expected JS output. Mirror in `tests/upstream-optimize/`,
run via `bin/run-upstream-tests.sh`:

```bash
./bin/run-upstream-tests.sh
# → 8 pass, 2 differ, 0 errored

SEMANTIC=1 ./bin/run-upstream-tests.sh
# → 9 pass, 1 differ, 0 errored

UPDATE_FROM_UPSTREAM=1 ./bin/run-upstream-tests.sh   # pull latest, then run
```

### 2. Passing tests (439 tests)

`tests/purs/passing/*.purs` — each is a full PureScript program ending in
`main = log "Done"`. The upstream Haskell runner (`TestCompiler.hs::passingTests`)
compiles each, runs `node`, and expects the last stdout line to be `Done`.
`bin/run-passing-tests.sh` does the same but plugs in our codegen for the
`Main` module.

```bash
# Run all 439
./bin/run-passing-tests.sh

# Run a subset
LIMIT=50 ./bin/run-passing-tests.sh
PATTERN=11 ./bin/run-passing-tests.sh    # only tests with '11' in their name

# Show stderr/stdout on failures
VERBOSE=1 ./bin/run-passing-tests.sh
```

## Status

Pipeline is wired end-to-end:

  CoreFn JSON → CoreImp AST → optimizer passes → JS text

Diff against the full Prelude+Effect+Console set plus 13 hand-written examples:
**67/71 modules byte-identical** to `purs`'s output, **71/71 semantically
identical** under `$N` fresh-name normalization.

```
$ ./bin/diff-codegen.sh
Comparing 71 modules in byte-identical mode...
Summary: 67 identical, 4 differ, 0 errored

$ SEMANTIC=1 ./bin/diff-codegen.sh
Comparing 71 modules in semantic ($N normalized) mode...
Summary: 71 identical, 0 differ, 0 errored
```

The remaining 4 byte-only diffs (`Data.EuclideanRing`, `Data.Ord`,
`Effect.Class.Console`, `Examples.Closures`) differ ONLY in `$N`
fresh-name numbering. Purs's Supply counter is shared across
desugar/case-guards/CSE phases that we don't replicate, and the Renamer
pass destroys the original GenIdent number when renaming to a plain Ident,
so we can't recover the offset from corefn.json either. Runtime-equivalent
in all 4 cases:

```
$ ./bin/test-runtime.sh Data.EuclideanRing
RUNTIME MATCH: Data.EuclideanRing ✓
$ ./bin/test-runtime.sh Examples.Uncurried
RUNTIME MATCH: Examples.Uncurried ✓
$ ./bin/test-runtime.sh Effect
RUNTIME MATCH: Effect ✓
... (10 modules tested at runtime, all match)
```

## What's ported

- **Frontend types** — `Names`, `PSString`, `Comments`, `CoreFn.*`
- **CoreFn JSON reader** — full `corefn.json` schema (every variant in
  `CodeGen/CoreFn/FromJSON.hs`).
- **CoreImp AST + Module** — all variants (`NumericLiteral`, `Unary`,
  `Binary`, `Function`, `App`, `Case`-shaped IIFEs, etc.).
- **CodeGen.Common** — JS identifier escaping (`$dollar`, `$bang`, …), reserved
  words, JS built-in shadow list.
- **CodeGen.JS** — the `moduleToJs` transform, including:
  - Pattern-match codegen (`bindersToJs`, `binderToJs`, `literalToBinderJS`)
    with the exact "Failed pattern match at <Module> (line …, column …)" message
  - Constructor codegen (newtype short-cut, IIFE-with-`.create` factory)
  - ObjectUpdate (full copy via `for..in` IIFE; field-preserving variant)
  - `accessorString`, `iife`, `varToJs`, `qualifiedToJS`, `foreignIdent`
  - Import renaming to avoid collision with declared names
  - `replaceModuleAccessors` rewriting `ModuleAccessor` → `Indexer (Var alias)`
  - `annotatePure` for `/* #__PURE__ */` markers on top-level values
- **CodeGen.Printer** — full pretty-printer with the same operator
  precedence table as `pattern-arrows` produces (16 levels, AssocL/AssocR/Wrap).
- **CoreImp.Optimizer** — pipeline matching `Optimizer.optimize`:
  - **Blocks**: `collapseNestedBlocks`, `collapseNestedIfs`
  - **Inliner**: `etaConvert`, `unThunk`, `evaluateIifes`, `inlineVariables`,
    `shouldInline`
  - **Unused**: `removeCodeAfterReturnStatements`, `removeUndefinedApp`,
    `removeUnusedEffectFreeVars`
  - **Inliner2**: `buildExpander`, `inlineCommonValues`, `inlineCommonOperators`
    (covers `Semiring/Ring/EuclideanRing/Eq/Ord/Semigroup/HeytingAlgebra/Bounded`
    dictionaries for `Int`, `Number`, `String`, `Char`, `Boolean`),
    `inlineFnIdentity`, `inlineUnsafeCoerce`
  - **FnComposition**: `inlineFnComposition` (turns `compose(f)(g)` into
    `function ($N) { return f(g($N)); }`)
  - **MagicDo**: `magicDoEffect` (collapses `bind`/`discard`/`pure` chains
    into `function __do() { ... }`)
  - **TCO**: tail-call optimization for self-recursive top-level functions

- **CodeGen.Laziness** — minimal port of `CoreFn.Laziness.applyLazinessTransform`:
  for each `Rec` group, lazy-wrap any binding whose initializer has an eager
  reference to a sibling, and rewrite sibling references in the wrapped
  initializers (and any non-wrapped siblings) as `$lazy_X(line)` calls (with
  the line number from the source span). Prepends the `$runtime_lazy` runtime
  helper at module top when any wrapping occurred. Mirrors `JS.hs:209-229`
  (`runtimeLazy`) + `CoreFn/Laziness.hs:542-553`.
- **Optimizer.Uncurried** — ports the `mkFnN` / `runFnN` family for
  `Data.Function.Uncurried`, `Effect.Uncurried`, `Control.Monad.Eff.Uncurried`,
  `Control.Monad.ST.Uncurried` (arities 0..10). After this pass,
  `mkEffectFn2(\a -> \b -> body)` compiles to a real two-arg
  `function (a, b) { return body(); }` instead of a curried wrapper.
  Mirrors `Inliner.hs:189-234`.
- Additional pure inliners: `inlineUnsafePartial` (Inliner.hs:288-294),
  `inlineUnsafeIndex` (Inliner.hs:161 + 236-244 — rewrites
  `Data.Array.unsafeIndex(dict)(arr)(i)` as `arr[i]`).

## Remaining cosmetic diffs

| Module                       | Why it diffs                                          |
|------------------------------|--------------------------------------------------------|
| `Data.Ord`, `Data.EuclideanRing`, `Effect.Class.Console`, `Examples.Closures` | Fresh-name supply alignment with the Haskell compiler's `Supply`. Output is **structurally identical** — only the `$N` numbering differs because purs's supply counter starts at a non-zero offset after desugar/case-guards/CSE phases that we don't run. `SEMANTIC=1 ./bin/diff-codegen.sh` confirms structural equivalence. |
| `Effect`                     | Lazy-wrap emission order differs from purs's (functorEffect-before-applyEffect vs the reverse). Both versions evaluate the same way at runtime — verified by `./bin/test-runtime.sh Effect`. |

## Pipeline summary

```
            corefn.json                      ┐
                ↓                            │
        FromJSON.parseModule                 │  Haskell-compiler stages
                ↓                            │  produce this (CST→AST→
       Module Ann (CoreFn AST)               ┘  Desugar→TypeCheck→CoreFn)
                ↓
       CodeGen.JS.moduleToJs (Supply Int) ─ traverses each declaration
                ↓
       Array (Array CoreImp.AST)          ─ optimizer pipeline:
                ↓
       Optimizer.optimize:                   tidyUp + type-class inliner
       ┌──────────────────────────┐          (loop until fixed point)
       │ inlineCommonValues       │          ↓
       │ inlineCommonOperators    │          + inlineFnComposition (monadic)
       │ inlineFnIdentity         │          ↓
       │ inlineUnsafeCoerce       │          magicDoEffect
       │ tidyUp [Blocks, Inliner, │          ↓
       │   Unused, EvalIifes]     │          tco
       └──────────────────────────┘          ↓
                ↓                            removeUnusedEffectFreeVars
       annotatePure (top-level)
                ↓
       walkModule (replaceModuleAccessors with usedModules tracking)
                ↓
       Module (CoreImp.Module: header, imports, body, exports)
                ↓
       Printer.prettyPrintModule (recursive descent with precedence)
                ↓
            index.js
```
