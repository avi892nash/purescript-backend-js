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

  CoreFn JSON → CoreImp AST → JS text

Identical to `purs` on simple modules without type-class-method usage
(`Simple`, `Data.Boolean`, `Data.Field`, `Data.NaturalTransformation`).

Diff against the full Prelude+Effect+Console set: 4/58 identical, 54/58 differ
by missing optimizations.

## What's not yet ported (causes the diffs)

The `Language.PureScript.CoreImp.Optimizer` pipeline runs many passes after
`CodeGen.JS`; without them, our output is structurally correct but verbose
(IIFEs wrapping each case-expression, helper dictionaries kept that purs
would inline away). Passes to port, in priority order:

  - `evaluateIifes`, `unThunk`, `removeCodeAfterReturnStatements`
    → collapse the case-expression IIFEs we emit
  - `inlineVariables`, `etaConvert`
    → inline trivial single-use locals
  - `collapseNestedBlocks`, `collapseNestedIfs`
    → cleanup
  - `removeUnusedEffectFreeVars`
    → strip dictionary helpers that have been inlined away
  - `inlineCommonOperators`, `inlineCommonValues`
    → turn `Data_Semiring.add(semiringInt)(x)(1)` into `x + 1 | 0`
  - `magicDoEffect`, `magicDoEff`, `magicDoST`, `inlineST`
    → flatten do-notation
  - `tco`
    → tail-call optimization for recursive functions
  - `applyLazinessTransform`, `runtimeLazy`
    → recursive let bindings
