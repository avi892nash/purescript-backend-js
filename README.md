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

# Compare against purs's output across all 58 modules
./bin/diff-codegen.sh
# Verbose: shows OK/DIFF per module
VERBOSE=1 ./bin/diff-codegen.sh
```

## Status

Pipeline is wired end-to-end:

  CoreFn JSON → CoreImp AST → optimizer passes → JS text

Diff against the full Prelude+Effect+Console set:
**54/58 modules byte-identical** to `purs`'s output, including all of
`Prelude`, `Tiny` (which uses `+`), `Control.*`, `Data.Eq`, `Data.Function`
(tail-call optimized), `Data.Void`, `Effect.Console` (magic-do optimized),
the `Data.Monoid.*` set, and so on.

```
$ ./bin/diff-codegen.sh
Comparing 58 modules...
Summary: 54 identical, 4 differ, 0 errored
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

## What's NOT yet ported (the remaining 4 diffs)

| Module                       | Pass needed                                          |
|------------------------------|------------------------------------------------------|
| `Effect`                     | `applyLazinessTransform` + `$runtime_lazy` for recursive bindings (~ 568 lines) |
| `Data.Ord`, `Data.EuclideanRing`, `Effect.Class.Console` | Fresh-name supply alignment with the Haskell compiler's `Supply`. Output is **structurally identical** — only the `$N` numbering differs because purs's supply counter starts at a non-zero offset after CoreFn-stage CSE/desugaring passes that we don't run. |

The architecture supports porting these incrementally; the file layout
mirrors `Language.PureScript.CoreImp.Optimizer.*` and
`Language.PureScript.CoreFn.Laziness`.

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
