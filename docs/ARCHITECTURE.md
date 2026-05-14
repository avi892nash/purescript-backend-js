# Architecture & key decisions

A map of the codegen pipeline and every place where this PureScript port
deliberately differs from the upstream Haskell compiler (purescript@c4a35b3).

## Pipeline at a glance

```
  ┌────────────────────────────────────────────────────────────────────┐
  │  PureScript source (Foo.purs)                                      │
  └─────────────────────────────────┬──────────────────────────────────┘
                                    │
                                    │   Haskell only — we do NOT replicate this:
                                    │     • Parsing (CST → AST)
                                    │     • Type-checking, kind-checking
                                    │     • Desugar (case-guards, where-clauses,
                                    │       type-class dictionary lookup)
                                    │     • CoreFn lowering + CSE
                                    │     • Renamer (avoids JS shadowing)
                                    │
                                    │   ↓ all of these allocate from one shared
                                    │     SupplyT counter — see "Fresh names" below
                                    ▼
  ┌────────────────────────────────────────────────────────────────────┐
  │  Foo/corefn.json                  ← our entry point                │
  └─────────────────────────────────┬──────────────────────────────────┘
                                    │
  ╔═════════════════════════════════╪══════════════════════════════════╗
  ║                            PursJS pipeline                          ║
  ║  ┌──────────────────────────────▼──────────────────────────────┐   ║
  ║  │ ① CoreFn.FromJSON.parseModule         CoreFn/FromJSON.hs    │   ║
  ║  │    JSON → CoreFn AST                                        │   ║
  ║  └──────────────────────────────┬──────────────────────────────┘   ║
  ║                                 ▼                                   ║
  ║  ┌─────────────────────────────────────────────────────────────┐   ║
  ║  │ ② CodeGen.JS.moduleToJs               CodeGen/JS.hs         │   ║
  ║  │    CoreFn → CoreImp.AST                                     │   ║
  ║  │                                                              │   ║
  ║  │      ┌────────────────────────────────────────┐             │   ║
  ║  │      │   CodeGen.Laziness (for `Rec` binds)   │             │   ║
  ║  │      │   Detect eager sibling refs,           │             │   ║
  ║  │      │   wrap with $runtime_lazy              │             │   ║
  ║  │      └────────────────────────────────────────┘             │   ║
  ║  └──────────────────────────────┬──────────────────────────────┘   ║
  ║                                 ▼                                   ║
  ║  ┌─────────────────────────────────────────────────────────────┐   ║
  ║  │ ③ CoreImp.Optimizer.optimize          CoreImp/Optimizer.hs  │   ║
  ║  │                                                              │   ║
  ║  │    Round 1 — inliner pipeline (until fixpoint)              │   ║
  ║  │      inlineCommonValues   (zero/one/+/-/* for Int)          │   ║
  ║  │      inlineCommonOperators (Eq, Ord, <>, &&, etc.)          │   ║
  ║  │      inlineFnComposition   (<<< chains)        [monadic]    │   ║
  ║  │      inlineFnIdentity, inlineUnsafeCoerce                   │   ║
  ║  │      inlineUnsafePartial, inlineUnsafeIndex                 │   ║
  ║  │      mkFn/runFn/mkEffectFn/runEffectFn (×11 arities)        │   ║
  ║  │      tidyUp (block flatten, IIFE collapse,                  │   ║
  ║  │              dead-code removal, var inlining)               │   ║
  ║  │                                                              │   ║
  ║  │    Round 2 — magic-do (until fixpoint)                       │   ║
  ║  │      magicDoEffect / magicDoEff / magicDoST                  │   ║
  ║  │      (>>= chains → `function __do() { ... }`)                │   ║
  ║  │                                                              │   ║
  ║  │    Round 3 — tail-call elimination                           │   ║
  ║  │      tco ($tco_loop, $tco_done, $copy_*, $tco_var_*)         │   ║
  ║  │                                                              │   ║
  ║  │    Round 4 — checkIntegers                                   │   ║
  ║  │      Fold Unary Negate (Lit i) → Lit (-i)                    │   ║
  ║  │                                                              │   ║
  ║  │    Round 5 — removeUnusedEffectFreeVars                      │   ║
  ║  │      Drop top-level vars nothing references                  │   ║
  ║  └──────────────────────────────┬──────────────────────────────┘   ║
  ║                                 ▼                                   ║
  ║  ┌─────────────────────────────────────────────────────────────┐   ║
  ║  │ ④ annotatePure                        CodeGen/JS.hs:89-131  │   ║
  ║  │    Add /* #__PURE__ */ to top-level effect-free vars        │   ║
  ║  └──────────────────────────────┬──────────────────────────────┘   ║
  ║                                 ▼                                   ║
  ║  ┌─────────────────────────────────────────────────────────────┐   ║
  ║  │ ⑤ walkModule (replaceModuleAccessors)  CodeGen/JS.hs:182    │   ║
  ║  │    ModuleAccessor → Indexer(Var alias)                      │   ║
  ║  │    Drop unused imports                                      │   ║
  ║  └──────────────────────────────┬──────────────────────────────┘   ║
  ║                                 ▼                                   ║
  ║  ┌─────────────────────────────────────────────────────────────┐   ║
  ║  │ ⑥ CodeGen.Printer.prettyPrintModule   CodeGen/JS/Printer.hs │   ║
  ║  │    CoreImp.Module → JavaScript text                         │   ║
  ║  └──────────────────────────────┬──────────────────────────────┘   ║
  ╚═════════════════════════════════╪═══════════════════════════════════╝
                                    │
                                    │   Haskell only (we don't replicate):
                                    │     • Prepend "// Generated by purs ..."
                                    │     • Source map generation
                                    │     • Write index.js to disk
                                    ▼
  ┌────────────────────────────────────────────────────────────────────┐
  │  Foo/index.js                                                       │
  └────────────────────────────────────────────────────────────────────┘
```

## Block-by-block: what changed and why

| Block | Haskell file → PursJS file | Key decisions / divergences |
|-------|---------------------------|------------------------------|
| **① FromJSON** | `CoreFn/FromJSON.hs` → `PursJS/CoreFn/FromJSON.purs` | • **Argonaut** instead of aeson — same `Value` shape, different combinators (`note "msg"` instead of `Parser`'s `fail`).<br>• **`Either Integer Double`** → split into two AST constructors `NumericLiteralInt` / `NumericLiteralNumber`. PureScript can't store arbitrary-precision integers, and the Either wrapper adds noise to every pattern match.<br>• **`truncate32` FFI** for `Int 2147483648`: `Int.fromNumber 2147483648` returns `Nothing` (out of 32-bit range), so we fall back to JS `\| 0` which wraps to `−2147483648` — relying on the downstream `checkIntegers` pass to fix the sign.<br>• **`Ann = (SourceSpan, [Comment], Maybe Meta)`** → record `{ ss, comments, meta }`. PureScript's record-dot notation reads cleaner than `fst`/`snd`/`thd`. |
| **Type model** | `Names.hs`, `PSString.hs`, etc. | • **`ProperName (a :: ProperNameType)`** with phantom kind → `newtype ProperName String`. PureScript has DataKinds but the kind tag is never used at codegen time, so we erase it.<br>• **`PSString = [Word16]`** → `String`. JS `String` is already UTF-16 internally; `Char.toCharCode` on each character gives the code unit directly.<br>• **`Rec [((Ann, Ident), Expr Ann)]`** nested tuples → record array `[{ ann, ident, expr }]`. |
| **② CodeGen.JS** | `CodeGen/JS.hs` → `PursJS/CodeGen/JS.purs` | • **`MonadReader Options + MonadError + MonadSupply + MonadWriter Any`** stack → single `State Int` (the `Supply` synonym). We don't need error throwing because `checkIntegers` no longer fails (it always succeeds via `truncate32`), and we don't have warnings to write.<br>• **Source maps deferred** — `withPos` is a no-op. The `Maybe SourceSpan` field is threaded but never consulted by the printer.<br>• **`Rec` lowering** delegated to `CodeGen.Laziness` (see below). |
| **CodeGen.Laziness** | `CoreFn/Laziness.hs` (568 lines) → `PursJS/CodeGen/Laziness.purs` (~140 lines) | • **Simpler algorithm**: wrap a binding iff its initializer has *any* eager reference to a sibling. Haskell does graph analysis to wrap only the minimum set; ours is overcautious but always correct.<br>• **IIFE detection added** — `hasEagerSiblingRef` walks `App _ (Function ...) [...]` patterns into the function body because they execute eagerly. The first version stopped at every `Function` literal and missed this (caught by upstream test 4179).<br>• **Wrap-set processed in reverse corefn order** — matches purs's topological emission for the Effect module without doing the full topological sort. |
| **③ Optimizer.JS** | `CoreImp/Optimizer.hs` and 6 sub-modules | • **`applyAll` direction** — Haskell's `foldl' (.) id` makes the *last* list element run first; we matched this with `foldl (<<<) identity`.<br>• **No `Eq AST`** — we use a 32-iteration cap instead of `untilFixedPoint`. In practice the passes converge in 3-4 iterations.<br>• **View patterns** like `(expander -> App _ (Ref fn) [Ref dict])` → explicit `case expander x of` + helper. Initially I wrote two cascading equations with view-pattern semantics in mind; PureScript's first-match-wins semantics made the wrong one fire (test 4179's compose case). Fixed by using explicit Maybe-returning helpers.<br>• **`magicDo` parametrised** — Haskell has three explicit copies (`magicDoEff`, `magicDoEffect`, `magicDoST`); we share one worker that takes the dictionary refs as a record. |
| **Inliner type-class dicts** | `Constants/Libs.hs` (TH-generated `P_*`) → `PursJS/CoreImp/Optimizer/Constants.purs` | • **Hand-written constant table** instead of Template Haskell. Each `(ModuleName, PSString)` pair is a literal. PureScript has no TH; the upside is the table is readable. |
| **`mkFn` / `runFn` family** | `Inliner.hs:189-234` → `PursJS/CoreImp/Optimizer/Uncurried.purs` | • Same algorithm, but PureScript's lack of `view ->` patterns means we walk `App` chains explicitly. The `isNFn` helper appends the arity to the prefix `PSString` (e.g. `mkEffectFn` + `2` → `mkEffectFn2`) before matching against the actual `ModuleAccessor`. |
| **`tco`** | `CoreImp/Optimizer/TCO.hs` → `PursJS/CoreImp/Optimizer/TCO.purs` | • Uses a separate `State Int` for the `$tco_done` counter (matches Haskell's local `State Int` inside `tco`).<br>• Mutual-recursion case half-ported — `findTailRecursiveFns` walks the worklist correctly but the rewriter only handles single-binding `Rec` groups for now.<br>• `rewriteFunctionsWith`'s view-pattern-heavy nested function shape → straight-line `case`-chain with `Array.uncons` on the block's statements. |
| **④ annotatePure** | `JS.hs:89-131` → inlined into `CodeGen.JS` | • Direct port of `maybePure` / `pureIife` / `pureApp`. Slightly simplified — we don't distinguish "alreadyAnnotated" propagation past `Comment` nodes since our optimizer collapses those before annotation. |
| **⑤ walkModule** | `JS.hs:182-187` (`replaceModuleAccessors`) → inlined | • Haskell uses `everywhereTopDownM` with a `Writer (Set ModuleName)`; we use a custom recursion that returns `{ ast, usedModules }`. Equivalent. |
| **⑥ Printer** | `CodeGen/JS/Printer.hs` → `PursJS/CodeGen/Printer.purs` | • **pattern-arrows** library (declarative operator-precedence table) → explicit 17-level precedence enum + `wrapParens ctx p s` helper. Each operator's emission is hand-written but the layering matches the Haskell `OperatorTable`.<br>• **`Number.show`** — JS's `Number.prototype.toString()` uses different scientific-notation thresholds than Haskell's `Show Double`. We replicated Haskell's rule (`0.1 ≤ \|n\| < 10⁷` → fixed; else scientific with explicit mantissa decimal and unsigned exponent) via a custom `showNumber` plus a `_toExponential` FFI.<br>• **PSString escaping** preserved bit-for-bit — same escape table, same `\xNN` vs `\uNNNN` thresholds. |

## Fresh-name supply — the one structural divergence

```
  ┌────── Haskell ──────┐                  ┌────── PursJS ──────┐
  │  SupplyT 0          │                  │  State Int (start 0)│
  │     ↓               │                  │     ↓               │
  │  desugar      (5)   │                  │  (we don't run this)│
  │     ↓               │                  │                     │
  │  caseGuards   (10)  │                  │  (we don't run this)│
  │     ↓               │                  │                     │
  │  CSE          (15)  │                  │  (we don't run this)│
  │     ↓               │                  │                     │
  │  Renamer            │                  │                     │
  │  (no Supply)        │                  │                     │
  │     ↓               │                  │                     │
  │  codegen   N+...    │                  │  codegen   0+...    │
  │  optimizer N+...    │                  │  optimizer 0+...    │
  └─────────────────────┘                  └─────────────────────┘
                                                     ↑
                                                     │ counter STARTS at 0,
                                                     │ purs's is at N (≈ 24-89
                                                     │ depending on module).
                                                     │
                                            ⇒ `$N` numbers differ;
                                              structure is identical.
                                              `SEMANTIC=1` mode normalizes
                                              both sides to `$0`, `$1`, …
                                              for byte-equality testing.
```

The Renamer (`Renamer.hs:62-86`) destroys the `GenIdent` *number* when
renaming back to plain `Ident` (it just keeps the name hint and picks the
next unused suffix), so we can't recover the offset from `corefn.json`
either. This is the source of the 4 remaining byte-only diffs in the
sample diff suite (`Data.EuclideanRing`, `Data.Ord`, `Effect.Class.Console`,
`Examples.Closures`) — they're all structurally identical under
`SEMANTIC=1`.

## Test infrastructure: what we mirror from upstream

```
  purescript@v0.15.15/tests/purs/         purescript-backend-js/tests/upstream/
  ────────────────────────────       ──>  ───────────────────────────────────
    optimize/  passing/  warning/           optimize/  passing/  warning/
    (vendored verbatim via `npm run sync-tests` from `git archive`)

    Run with: npm test | npm run test:optimize | …

  purescript/src/Language/...        ──>  purescript-backend-js/src/PursJS/...
  (every .hs file)                        (every .purs file with a header
                                           line-range cross-reference pinned
                                           to commit 5589e81 / v0.15.15)
```

## Summary of every divergence point

| # | Where | Haskell does | We do | Why |
|---|-------|-------------|-------|-----|
| 1 | NumericLiteral encoding | `Either Integer Double` | `NumericLiteralInt Int` / `NumericLiteralNumber Number` | PureScript has no `Integer`; split is clearer |
| 2 | Int parsing | `Integer` (unbounded) | `Int` (32-bit) + `truncate32` FFI | PureScript Int is 32-bit |
| 3 | `checkIntegers` | Lives in `moduleToJs`, can throw | Pure rewrite pass in `Optimizer` | We don't have an error monad threaded |
| 4 | PSString | `[Word16]` UTF-16 list | `String` (JS native) | JS String *is* UTF-16 |
| 5 | Ann | 3-tuple `(SS, [Comment], Maybe Meta)` | record `{ ss, comments, meta }` | Record dot is clearer |
| 6 | ProperName kind | `(a :: ProperNameType)` phantom | erased | Codegen never inspects the kind |
| 7 | Supply | Shared SupplyT across all phases | `State Int` for codegen only | We don't run the upstream phases |
| 8 | `applyAll` | `foldl' (.) id` | `foldl (<<<) identity` | Match semantics |
| 9 | Fixed-point | `untilFixedPoint` (needs `Eq a`) | 32-iteration cap | `AST` has no `Eq` |
| 10 | View patterns | `(expander -> App _ ...)` | explicit `case expander x of` | PureScript has no view patterns |
| 11 | Laziness algorithm | Per-binding dependency analysis | Wrap all-or-none in group | Smaller code, slightly over-wraps |
| 12 | IIFE detection | Implicit in eager-position tracking | Explicit `App _ (Function _ ...) [_]` case | Caught a bug in test 4179 |
| 13 | `magicDo` variants | Three named functions | One parametrised on `EffDicts` | Less duplication |
| 14 | Printer precedence | `pattern-arrows` declarative table | Explicit `Prec` enum + `wrapParens` | No pattern-arrows in PureScript registry |
| 15 | `Number.show` | Haskell `showFloat` generic mode | Custom `showNumber` + `_toExponential` FFI | JS's default formatter has a different threshold |
| 16 | `runtimeLazy` line numbers | Source span of reference site | Source span of binding's annotation | We don't track per-reference spans |
| 17 | Source maps | `prettyPrintJSWithSourceMaps` | Not yet ported | Deferred |
| 18 | `magicDoST` (full ST) | Includes `inlineST` for STRef new/read/write | Just the bind/discard/pure inlining | `inlineST` would require porting STRef analysis (~50 lines more) |
| 19 | TCO (mutual recursion) | Wraps mutually-tail-recursive groups | Only handles single-binding groups | Edge case; none of our tests need it |
| 20 | Header comment | `// Generated by purs version X.X.X` | Not emitted (added by `Make.Actions` wrapper) | Out of codegen scope |
