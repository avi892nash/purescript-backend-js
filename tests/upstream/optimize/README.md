# Upstream optimizer tests

Copies of `tests/purs/optimize/*.{purs,out.js,js}` from
[purescript/purescript@c4a35b3](https://github.com/purescript/purescript)
(BSD-3-Clause, see `LICENSE` in the upstream repo).

Each `Foo.purs` is a regression test for a specific codegen / optimizer
case; `Foo.out.js` is the expected JS output. The upstream Haskell test
runner (`TestCompiler.hs::optimizeTests`) compiles the `.purs` with the
full purs pipeline and diffs the result against `.out.js`. We do the same
in `bin/run-upstream-tests.sh` but plug in our PureScript codegen.

## The tests

| File                       | What it exercises                                          |
|----------------------------|------------------------------------------------------------|
| `2866.purs`                | newtype apply (#2866)                                      |
| `4179.purs`                | TCO + unsafePartial; complex mutual recursion in 4 bindings |
| `4229.purs`                | constructors named like type-class methods                 |
| `4386.purs`                | `Control.Monad.ST.Uncurried` (`mkSTFn1`/`runSTFn2`)         |
| `Foreign.purs` + `.js`     | foreign imports                                            |
| `Monad.purs`               | Monad super-class plumbing                                 |
| `ObjectUpdate.purs`        | Static + dynamic record update                             |
| `Primitives.purs`          | `Int` arithmetic inlining (`x * (y + 1) | 0`)              |
| `RecursiveInstances.purs`  | Generic deriving — type-class instances that reference each other |
| `Symbols.purs`             | `IsSymbol` / `Proxy` / `unsafeGet`                         |

## Running

```
$ ./bin/run-upstream-tests.sh
$ SEMANTIC=1 ./bin/run-upstream-tests.sh    # normalize $N fresh-name numbering
$ VERBOSE=1 ./bin/run-upstream-tests.sh     # show diffs for failures
```
