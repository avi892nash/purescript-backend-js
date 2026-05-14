# LEARN.md — CoreFn → JavaScript mapping in detail

A complete walk-through of how every PureScript expression gets compiled to
JavaScript. For each CoreFn `Expr` and `Binder` variant: source code,
CoreFn shape, the CoreImp.AST our codegen produces, and the final JS.

This is the file you read after the [README](README.md) when you want to
*understand* how the codegen actually works, not just how to run it.

## Table of contents

- [The two ASTs](#the-two-asts)
- [The Meta annotation field](#the-meta-annotation-field)
- [Expressions, one by one](#expressions-one-by-one)
  - [Literal](#literal)
  - [Var](#var)
  - [Constructor](#constructor)
  - [Accessor](#accessor)
  - [ObjectUpdate](#objectupdate)
  - [Abs (lambda)](#abs-lambda)
  - [App (application)](#app-application)
  - [Case (pattern match)](#case-pattern-match)
  - [Let](#let)
- [Binders, one by one](#binders-one-by-one)
- [Top-level binds](#top-level-binds)
- [Imports, exports, foreign](#imports-exports-foreign)
- [Worked example: `module Tiny`](#worked-example-module-tiny)

---

## The two ASTs

```
            CoreFn AST              CoreImp AST              JavaScript
        (typed, language-level)    (untyped, JS-shaped)        (text)

                                  NumericLiteral
   Literal a (Literal …)    ─→    StringLiteral      ─→     42
   Var a (Qualified Ident)        BooleanLiteral             "hi"
   Constructor a tn cn fs         ArrayLiteral               true
   Accessor a prop v              ObjectLiteral
   ObjectUpdate a o copy ps       Var n
   Abs a arg body                 Indexer x y                v[k]
   App a fn arg                   Function name args body    function f(x){}
   Case a scrutinees alts         App fn args                f(x, y)
   Let a binds expr               Block stmts                { ... ; ... }
                                  VariableIntroduction       var n = e
                                  Unary op e                 -e
                                  Binary op a b              a + b
                                  IfElse c t f               if (c) {...}
                                  Return e                   return e
                                  Throw e                    throw e
                                  Comment c e                /* … */ e
                                  ModuleAccessor mn n        (lowered later)
```

`CoreFn AST` is what comes out of `corefn.json` (parsed by
[CoreFn.FromJSON](src/PursJS/CoreFn/FromJSON.purs)).
`CoreImp.AST` is the simplified imperative JS AST defined in
[CoreImp.AST](src/PursJS/CoreImp/AST.purs).
The transform between them is [CodeGen.JS.moduleToJs](src/PursJS/CodeGen/JS.purs)
mirroring Haskell's `Language/PureScript/CodeGen/JS.hs`.

---

## The Meta annotation field

Every CoreFn `Expr` carries an `Ann = { ss, comments, meta :: Maybe Meta }`.
The `meta` field tells codegen *how* to lower an otherwise-ambiguous node:

| `Meta` constructor | Where it appears | Codegen behavior |
|---|---|---|
| `IsConstructor ProductType fields` | `Var` referencing a constructor | Use `.create` to invoke |
| `IsConstructor SumType fields` | `Var` of a multi-ctor type | Use `.create` + `instanceof` checks at binders |
| `IsConstructor _ []` | `Var` of a nullary constructor | Use `.value` (the singleton instance) |
| `IsNewtype` | `Var` of a newtype constructor | **Elide** the constructor entirely — the wrapper has no runtime representation |
| `IsTypeClassConstructor` | `Bind` defining a class dict | **Skip** entirely — class constructors are only ever applied, never used as values |
| `IsForeign` | `Var` of an FFI binding | Emit `$foreign.<name>` if local, otherwise normal cross-module ref |
| `IsWhere` | `Var` bound by a `where` clause | (purely informational) |
| `IsSyntheticApp` | `App` synthesized by the typechecker | Sets `guessEffects` to `NoEffects` so the optimizer can hoist it |

These are central — most of the "wait, why does it emit it this way?"
moments while reading the codegen come down to a `meta` check.

---

## Expressions, one by one

For each variant we show:
- **Source** — what you write in `.purs`
- **CoreFn** — what `corefn.json` contains
- **CoreImp.AST** — what `valueToJs'` produces
- **JS** — the final printed output

### Literal

CoreFn: `Literal Ann (Literal (Expr Ann))`. The inner `Literal` has seven
variants (Int, Number, String, Char, Boolean, Array, Object).

#### Numeric

```purescript
n :: Int     = 42
f :: Number  = 3.14
```

```haskell
Literal _ (NumericLiteral (Left 42))     -- IntLiteral
Literal _ (NumericLiteral (Right 3.14))  -- NumberLiteral
```

```purescript
-- valueToJs' (CF.Literal _ l) = literalToValueJS l
NumericLiteral Nothing (Left 42)
NumericLiteral Nothing (Right 3.14)
```

```js
var n = 42;
var f = 3.14;
```

For very large/small Numbers the printer's `showNumber` (matching Haskell's
`Show Double` generic format) switches to scientific notation:
`1.0e10`, `1.0e-7`.

For `−2147483648` specifically the corefn contains
`Unary Negate (NumericLiteral 2147483648)` — the literal `2147483648`
doesn't fit a 32-bit signed Int, so we wrap it via `truncate32` (JS `| 0`)
in the parser, then collapse `Unary Negate (Lit −2147483648)` back to
`Lit (−(−2147483648))` = `Lit −2147483648` via the `checkIntegers` pass
([Optimizer.purs](src/PursJS/CoreImp/Optimizer.purs)).

#### String / Char

```purescript
greeting :: String  = "Hi!"
letter   :: Char    = 'a'
```

```js
var greeting = "Hi!";
var letter = "a";
```

Char compiles to a 1-char JS string. Strings are escaped using
[PSString.prettyPrintStringJS](src/PursJS/PSString.purs) which iterates UTF-16
code units and emits `\xNN` / `\uNNNN` for non-printable or non-ASCII chars
plus the named escapes (`\n`, `\t`, `\b`, `\f`, `\r`, `\v`, `\"`, `\\`).

#### Boolean

```purescript
flag :: Boolean = true
```

```js
var flag = true;
```

#### Array

```purescript
nums :: Array Int = [1, 2, 3]
```

```haskell
Literal _ (ArrayLiteral [Literal _ (NumericLiteral (Left 1)), ..., ...])
```

```js
var nums = [ 1, 2, 3 ];
```

Printer emits `[ x, y, z ]` with spaces inside the brackets (matching purs).

#### Object (record)

```purescript
p :: { name :: String, age :: Int }
p = { name: "Ada", age: 36 }
```

```haskell
Literal _ (ObjectLiteral [("name", Literal "Ada"), ("age", Literal 36)])
```

```js
var p = {
    name: "Ada",
    age: 36
};
```

Field names that are valid JS identifiers print as `key:`; non-identifier
keys (`"odd-key"`) print quoted: `"odd-key":`.

---

### Var

`Var Ann (Qualified Ident)` — a variable reference. The `Qualified` part
records whether it's local (`BySourcePos`) or comes from another module
(`ByModuleName`). The `meta` tells us if it's a constructor, foreign, etc.

#### Local var

```purescript
foo x = x + 1
```

The `x` inside the body is `Var _ (Qualified (BySourcePos pos) (Ident "x"))`.

```js
return x + 1 | 0;     // after the Semiring.add inliner
```

#### Cross-module var

```purescript
import Data.Array (length)
n = length [1, 2, 3]
```

The `length` is `Var _ (Qualified (ByModuleName Data.Array) (Ident "length"))`.

The codegen emits a `ModuleAccessor`; the later `walkModule` pass rewrites
that to `Indexer (Var Data_Array) (StringLiteral "length")`, and the
printer renders it as `Data_Array.length`.

```js
import * as Data_Array from "../Data.Array/index.js";
var n = Data_Array.length([ 1, 2, 3 ]);
```

#### Constructor var (nullary)

```purescript
data Color = Red | Green | Blue

red :: Color = Red
```

The `Red` reference has `meta = Just (IsConstructor SumType [])`. Since
the field list is empty, we emit `<Mod>.Red.value`:

```js
var red = Color_constructor.Red.value;
```

(Where `Color_constructor` is the synthesized object the `Constructor`
expression below defines.)

#### Constructor var (n-ary)

```purescript
data Pair a b = Pair a b
mk = Pair 1 "hi"
```

Inside `mk`, the `Pair` reference has `meta = Just (IsConstructor _ [a, b])`.
We emit `<Mod>.Pair.create`:

```js
var mk = Pair.create(1)("hi");      // before the IsConstructor short-circuit
var mk = new Pair(1, "hi");          // when saturated (length args == length fields)
```

#### Foreign var

```purescript
foreign import doSomething :: Int -> Effect Unit
```

A reference to a foreign import in *this* module is `Var IsForeign`. We
emit `$foreign.doSomething`.

A reference to a foreign import in *another* module follows the normal
cross-module path (`OtherMod.doSomething`).

---

### Constructor

`Constructor Ann TypeName ConstructorName [Ident]` — defines a data
constructor (not a reference to one). Two shapes:

#### Nullary

```purescript
data Color = Red | Green | Blue
```

```haskell
Constructor _ "Color" "Red" []
```

Codegen emits an IIFE that builds a singleton:

```js
var Red = (function () {
    function Red() {};
    Red.value = new Red();
    return Red;
})();
```

The `Red.value` is referenced wherever `Red` appears as a value, via the
`IsConstructor _ []` meta on the Var.

#### n-ary

```purescript
data Pair a b = Pair a b
```

```haskell
Constructor _ "Pair" "Pair" ["value0", "value1"]
```

Codegen emits an IIFE with the constructor function + a `.create` curried
factory:

```js
var Pair = (function () {
    function Pair(value0, value1) {
        this.value0 = value0;
        this.value1 = value1;
    };
    Pair.create = function (value0) {
        return function (value1) {
            return new Pair(value0, value1);
        };
    };
    return Pair;
})();
```

A use site like `Pair 1 "hi"` becomes:
- if saturated: `new Pair(1, "hi")` (via `IsConstructor` meta + length check)
- if not saturated: `Pair.create(1)` etc.

#### Newtype short-cut

```purescript
newtype Wrap = Wrap Int
```

The constructor has `meta = Just IsNewtype`. The codegen emits:

```js
var Wrap = {
    create: function (value) {
        return value;
    }
};
```

`Wrap.create(7)` returns `7` directly — no wrapper allocation. And any
`Var IsNewtype` reference at an application site is *erased* entirely
(the `App` of a newtype constructor drops to its argument).

---

### Accessor

`Accessor Ann PSString (Expr Ann)` — record field projection.

```purescript
type Pt = { x :: Int, y :: Int }
getX r = r.x
```

```haskell
Accessor _ "x" (Var _ "r")
```

CoreImp:
```
Indexer Nothing (StringLiteral Nothing "x") (Var Nothing "r")
```

The printer recognises the `Indexer (StringLiteral …)` pattern when the
string is a valid JS identifier and prints `r.x` instead of `r["x"]`:

```js
var getX = function (r) {
    return r.x;
};
```

For non-identifier field names like `"odd-key"` the printer falls back to
the bracket form `r["odd-key"]`.

---

### ObjectUpdate

`ObjectUpdate Ann (Expr Ann) (Maybe [PSString]) [(PSString, Expr Ann)]`.
The `Maybe [PSString]` is the list of fields to *copy* (known at compile
time when the typechecker can prove the input type). Two shapes:

#### Static — `copy` is `Just [...]`

```purescript
moveX :: Point -> Int -> Point
moveX p dx = p { x = p.x + dx }
```

```haskell
ObjectUpdate _ (Var "p") (Just ["x", "y"]) [("x", App add ... )]
```

The typechecker knows `p` has exactly fields `x` and `y`, so it lists them.
Codegen emits a single ObjectLiteral combining the copies and the updates:

```js
var moveX = function (p) {
    return function (dx) {
        return {
            x: p.x + dx | 0,
            y: p.y
        };
    };
};
```

Note: if a field is both copied AND updated, the update wins (the updates
come *after* the copies in the resulting `ObjectLiteral`).

#### Dynamic — `copy` is `Nothing`

If the row is polymorphic and the typechecker doesn't know all the fields,
copy-list is `Nothing`. We fall back to a runtime for-in loop (the
`extendObj` helper at `JS.hs:369-386`):

```purescript
forall r. { bravo :: Boolean | r } -> { bravo :: Boolean | r }
dynamicUpdate1 x = x { bravo = true }
```

```js
var dynamicUpdate1 = function (x) {
    var $0 = {};
    for (var $1 in x) {
        if ({}.hasOwnProperty.call(x, $1)) {
            $0[$1] = x[$1];
        };
    };
    $0.bravo = true;
    return $0;
};
```

The `$0` / `$1` come from `freshName`. Three fresh names are allocated
(newObj, key, evObj); the third gets inlined away in this simple case so
only `$0` and `$1` survive.

---

### Abs (lambda)

`Abs Ann Ident (Expr Ann)`. PureScript lambdas are curried — each Abs
takes one argument:

```purescript
inc = \x -> x + 1
add = \x -> \y -> x + y
```

```haskell
Abs _ "x" (App add ... (Var "x") (Literal 1))
Abs _ "x" (Abs _ "y" (App ... (Var "x") (Var "y")))
```

```js
var inc = function (x) {
    return x + 1 | 0;
};
var add = function (x) {
    return function (y) {
        return x + y | 0;
    };
};
```

A function taking the wildcard `_` has the special ident `UnusedIdent`;
codegen emits a zero-arg function for it (so we don't generate
`function ($__unused) {...}`):

```purescript
const x = \_ -> x
```

```js
var const_x_to = function () {     // no parameter
    return x;
};
```

---

### App (application)

`App Ann (Expr Ann) (Expr Ann)`. Curried.

Codegen first walks the App-spine to collect all the arguments (the `unApp`
helper), then decides what to emit based on the head:

#### Newtype constructor — erased

If the head is `Var (Just IsNewtype) _`, the whole application becomes
just its single argument:

```purescript
newtype Wrap = Wrap Int
v = Wrap 7
```

```js
var v = 7;     // Wrap erased
```

#### Saturated regular constructor — `new C(...)`

When the head is `Var (Just (IsConstructor _ fields)) _` AND the number of
args equals the number of fields, we emit `new C(a, b, ...)`:

```purescript
data Pair a b = Pair a b
mk = Pair 1 "hi"
```

```js
var mk = new Pair(1, "hi");
```

#### Anything else — curried JS application

Standard case: emit a chain of single-arg JS calls. PureScript apps are
curried, so `f x y z` becomes `f(x)(y)(z)`:

```purescript
f x y z = ...
res = f 1 2 3
```

```js
var res = f(1)(2)(3);
```

Some inliners then *un-curry* specific call shapes:
- `compose(semigroupoidFn)(f)(g)(x)` → `f(g(x))` ([inlineFnComposition](src/PursJS/CoreImp/Optimizer/FnComposition.purs))
- `Data_Semiring.add(semiringInt)(x)(y)` → `(x + y) | 0` ([inlineCommonValues](src/PursJS/CoreImp/Optimizer/Inliner2.purs))
- `Data_Eq.eq(eqString)(x)(y)` → `x === y`
- `mkEffectFn2(\a -> \b -> body)` → `function (a, b) { return body(); }` ([Uncurried.purs](src/PursJS/CoreImp/Optimizer/Uncurried.purs))

---

### Case (pattern match)

`Case Ann [Expr Ann] [CaseAlternative Ann]`.

The base codegen wraps each `case` in an IIFE: allocate fresh names for
the scrutinees, then test each alternative in order, throwing
`Failed pattern match` if none match.

```purescript
describe :: Color -> String
describe c = case c of
  Red -> "red"
  Green -> "green"
  Blue -> "blue"
```

Pre-optimization:

```js
var describe = function (c) {
    return (function () {
        var $0 = c;
        if ($0 instanceof Red) {
            return "red";
        };
        if ($0 instanceof Green) {
            return "green";
        };
        if ($0 instanceof Blue) {
            return "blue";
        };
        throw new Error("Failed pattern match at Main (line 4, column 1 - line 4, column 28): " + [ $0.constructor.name ]);
    })();
};
```

Post-optimization (`unThunk` + `removeCodeAfterReturnStatements` +
`inlineVariables` collapse the IIFE):

```js
var describe = function (c) {
    if (c instanceof Red) {
        return "red";
    };
    if (c instanceof Green) {
        return "green";
    };
    if (c instanceof Blue) {
        return "blue";
    };
    throw new Error("Failed pattern match...");
};
```

The exact message format is
`"Failed pattern match at <ModuleName> (line L1, column C1 - line L2, column C2): "`
followed by an Array of the failed-binder identifiers (which Node prints
as `[constructor-name]`).

#### Guards

A guarded alternative has its `result` as `Left [(Guard, Body)]` instead
of `Right Body`. Each guard becomes an `if (guard) { return body; }`:

```purescript
classify n
  | n < 0 = "negative"
  | n == 0 = "zero"
  | otherwise = "positive"
```

```js
var classify = function (n) {
    if (n < 0) {
        return "negative";
    };
    if (n === 0) {
        return "zero";
    };
    if (Data_Boolean.otherwise) {
        return "positive";
    };
    throw new Error("Failed pattern match...");
};
```

---

### Let

`Let Ann [Bind Ann] (Expr Ann)`. Compiles to an IIFE so the bindings get
local scope:

```purescript
simple =
  let x = 1
      y = 2
  in x + y
```

```js
var simple = (function () {
    var x = 1;
    var y = 2;
    return x + y | 0;
})();
```

After `unThunk` + `inlineVariables` the IIFE collapses when the bindings
are trivially substitutable:

```js
var simple = 1 + 2 | 0;     // and the inliner folds this further if it can
```

Recursive `let`s become a `Rec` bind, which goes through the
[Laziness transform](src/PursJS/CodeGen/Laziness.purs) — same machinery
as top-level recursive groups, see below.

---

## Binders, one by one

`Binder Ann` is the LHS of a `case` alternative or a `let`. Each variant
is handled by [`binderToJs`](src/PursJS/CodeGen/JS.purs).

### NullBinder

`_` — match anything, bind nothing.

```purescript
case x of _ -> "anything"
```

Codegen: produces *no* code. The continuation (the `"anything"` here)
runs unconditionally.

### VarBinder

`v` — match anything, bind to `v`.

```purescript
case x of v -> show v
```

Codegen prepends `var v = $0;` (where `$0` is the scrutinee's fresh name)
to the continuation.

### LiteralBinder

Match against a literal value. Three sub-shapes:

#### Number/Char/String/Boolean literal

```purescript
case n of 0 -> "zero"; _ -> "other"
```

Codegen wraps the continuation in an `if`:
```js
if ($0 === 0) {
    return "zero";
};
```

For `Boolean true`/`Boolean false` it's just `if ($0)` and `if (!$0)`.

#### Array literal

```purescript
case xs of [a, b] -> a + b
```

Codegen emits a length check + per-element binders:
```js
if ($0.length === 2) {
    var $1 = $0[0];
    var a = $1;
    var $2 = $0[1];
    var b = $2;
    return a + b | 0;
};
```

(The `$1 = $0[0]; var a = $1;` redundancy gets inlined away by
`inlineVariables`.)

#### Object literal

```purescript
case r of { name: n, age: a } -> ...
```

Similar — emit a fresh-name VariableIntroduction per property + the inner
binders.

### ConstructorBinder

Match a constructor. The `meta` distinguishes:

#### Newtype

```purescript
case w of Wrap v -> v
```

Newtype constructors have `meta = Just IsNewtype`. The binder is erased —
just recurse with the single inner binder bound to the same scrutinee.

#### ProductType (single-constructor type, e.g. `Pair`)

No `instanceof` check needed (it's the only inhabitant). Just descend:
```js
var argVar0 = $0.value0;
var a = argVar0;
var argVar1 = $0.value1;
var b = argVar1;
// inner continuation
```

#### SumType (multi-constructor type, e.g. `Maybe`)

Wrap the inner code in an `if ($0 instanceof Ctor)`:
```js
if ($0 instanceof Just) {
    var argVar0 = $0.value0;
    var a = argVar0;
    return ...;
};
```

### NamedBinder

`name @ pat` — bind the whole scrutinee to `name` AND match the inner pat.

```purescript
case x of full @ Pair a b -> [full, ...]
```

Codegen: emit `var full = $0;` plus the inner binder's code.

---

## Top-level binds

A `Bind Ann` is either `NonRec` (single non-recursive binding) or `Rec`
(a mutually-recursive group). The codegen distinguishes both:

### NonRec

```purescript
foo :: Int
foo = 42
```

Becomes a single VariableIntroduction with effect tracking:
```haskell
nonRecToJS ann ident val = do
  js <- valueToJs val
  pure (VariableIntroduction _ (identToJs ident) (Just (guessEffects val, js)))
```

`guessEffects` looks at the AST: `Var BySourcePos` and synthetic `App`s
are `NoEffects`, everything else is `UnknownEffects`. This drives the
`removeUnusedEffectFreeVars` pass at the end — only `NoEffects` bindings
get dropped if unused.

### Rec — single binding

A `Rec` group of one (a self-recursive function) is treated like NonRec
when its initializer doesn't have an *eager* reference to itself. Most
recursive functions fall here:

```purescript
gcd a b = if b == zero then a else gcd b (a `mod` b)
```

The `gcd` reference inside the body is inside a `Function` literal — not
eager. So we emit a plain `var gcd = function (a) { ... gcd(b)(a mod b) ... };`.

### Rec — multiple bindings, eager refs

If any sibling in the group has an *eager* reference to another sibling
(see [`hasEagerSiblingRef`](src/PursJS/CodeGen/Laziness.purs)), we
lazy-wrap the entire group with `$runtime_lazy`:

```purescript
-- Effect module: mutually recursive instance dictionaries
monadEffect = { Applicative0: \_ -> applicativeEffect, ... }
applyEffect = { apply: ap monadEffect, ... }    -- ap evaluates eagerly
```

Output:
```js
var $runtime_lazy = function (name, moduleName, init) {
    var state = 0;
    var val;
    return function (lineNumber) {
        if (state === 2) return val;
        if (state === 1) throw new ReferenceError(...);
        state = 1;
        val = init();
        state = 2;
        return val;
    };
};
var monadEffect = { ... };       // not wrapped — no eager sibling refs
var $lazy_applyEffect = $runtime_lazy("applyEffect", "Effect", function () {
    return { apply: Control_Monad.ap(monadEffect), ... };
});
var applyEffect = $lazy_applyEffect(23);   // line number from source span
```

Sibling refs inside wrapped bindings are rewritten as `$lazy_X(0)` calls
so they pick up the lazy value on first access.

---

## Imports, exports, foreign

### Imports

CoreFn's `Module` has `imports :: [(Ann, ModuleName)]`. After codegen we:

1. Filter to only the modules actually *used* (after `replaceModuleAccessors`
   we know exactly which module aliases were referenced).
2. Drop `Prim*` (built-in, no runtime).
3. Drop the current module (you don't import yourself).
4. Rename to avoid collision with declared names — `Data.Foo` becomes
   `Data_Foo`, but if a top-level value is also named `Data_Foo` we'd
   get `Data_Foo_1`, etc.

The result emits:
```js
import * as Data_Foo from "../Data.Foo/index.js";
```

The path uses `..` because purs's output layout is `output/<Module>/index.js`
flat, and each module imports siblings via `../Sibling/index.js`.

### Exports

CoreFn's `exports :: [Ident]` is split:
- Names also in `foreigns` → emitted in an `export { ... } from "./foreign.js"`
- Everything else → plain `export { ... }`

`reExports :: Map ModuleName [Ident]` becomes `export { ... } from "../<Mod>/index.js"`
— one per source module.

```purescript
module Foo (foo, bar) where
import Other (other)
```

```js
export { foo, bar };
export { other } from "../Other/index.js";   // if `other` is in reExports
```

### Foreign

A module with FFI bindings (`foreign import doSomething :: ...`) gets a
`./foreign.js` import at the top:

```js
import * as $foreign from "./foreign.js";
var doSomething = $foreign.doSomething;
```

The `$foreign` namespace name is a fixed constant; references to local
foreigns become `$foreign.<name>`.

---

## Worked example: `module Tiny`

A complete trace from `.purs` source through every block:

### Source

```purescript
module Tiny where

import Prelude

foo :: Int
foo = 42

bar :: Int -> Int
bar x = x + 1
```

### `corefn.json` (paraphrased)

```
Module Tiny
  imports = [Data.Semiring, Prelude, Prim]
  exports = [foo, bar]
  decls   =
    -- Synthesized by the typechecker for `x + 1`:
    NonRec "add" (IsSyntheticApp meta) =
      App (Var IsForeign Data.Semiring.add) (Var Data.Semiring.semiringInt)

    NonRec "foo" =
      Literal (IntLiteral 42)

    NonRec "bar" =
      Abs "x"
        (App (App (Var Tiny.add) (Var x)) (Literal 1))
```

### After `moduleToJs`

```
var add = Data_Semiring.add(Data_Semiring.semiringInt);     // IsSyntheticApp → NoEffects
var foo = 42;
var bar = function (x) {
    return add(x)(1);     // local 'add' Var
};
```

### After the optimizer

1. `inlineCommonValues` sees `App (App (App (Ref P_add) [Ref P_semiringInt]) [x]) [y]`
   (via the expander inlining `add`) and rewrites to `Binary BitwiseOr (Binary Add x y) (Lit 0)`:
   ```
   var bar = function (x) { return (x + 1) | 0; };
   ```
2. `add` is now unused. `removeUnusedEffectFreeVars` drops it.
3. The `Data_Semiring` import is now unused. `walkModule`'s `usedModules`
   tracking sees this and the import is filtered out.

### Final output

```js
var foo = 42;
var bar = function (x) {
    return x + 1 | 0;
};
export {
    foo,
    bar
};
```

This matches `purs`'s output byte-for-byte. You can reproduce it via:

```bash
# (Run these from your purescript-backend-js checkout.)
# Compile Tiny.purs with purs (uses prelude-pool/.spago/ for prelude)
PROJECT=$(pwd)
mkdir -p /tmp/tiny && cp prelude-pool/src/Tiny.purs /tmp/tiny/Main.purs
cd /tmp/tiny && purs compile --codegen js,corefn -o output Main.purs \
  $(find "$PROJECT/prelude-pool/.spago/p" -name '*.purs')

# Then run our codegen on it
cd "$PROJECT"
spago run --main PursJS.Main -- /tmp/tiny/output/Main/corefn.json
```

---

## Where to go from here

- Run the test suites: [README](README.md#running-the-upstream-test-suites)
- See where the port diverges from Haskell: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)
- Read the cross-referenced source: each file in `src/PursJS/` has a header
  comment naming its Haskell counterpart and a per-symbol line-number map.
