# Versioning policy

This codegen targets a **specific version** of the upstream PureScript
compiler. Because corefn.json's schema, the prelude's signatures, the
optimizer's behaviour, and even the JS runtime helpers (`$runtime_lazy`,
`$tco_loop`, …) change across releases, we maintain **one branch per
supported purs version**.

## The pin

The current `master` is pinned to:

```
purescript: v0.15.15 (commit 5589e81, released 2024-05-09)
prelude:    6.0.2
effect:     4.0.0
console:    6.1.0
package set: registry/76.2.1
```

Every PursJS source file's header records the same commit hash (e.g.
`Ports types from Language.PureScript.Names (purescript@c4a35b3, …)`)
so cross-references stay valid.

## Verifying the pin

Two checks confirm we're talking to the right version:

1. **At runtime**, every corefn.json carries a `"builtWith"` field; spot-
   check it matches the pin if you're debugging a codegen mismatch.
2. **At test time**, the test set under `tests/upstream/` is a verbatim
   copy of `purescript@v0.15.15/tests/purs/` synced via
   `npm run sync-tests`. The `_SOURCE` file there records the
   tag and commit hash for provenance. Test runners read exclusively
   from this directory — no working-tree dependency on a sibling clone.

## Test set on this branch

This branch ships the test set from **v0.15.15** only. Each supported
purs version has its own branch (see "Branch matrix" below) and ships
its own `tests/upstream/` snapshot.

| Category    | Count |
|-------------|------:|
| optimize    |    10 |
| passing     |   438 |
| warning     |    68 |
| failing     |   444 |
| docs        |    55 |
| layout      |    15 |
| graph       |     4 |
| psci        |     2 |
| publish     |     1 |
| sourcemaps  |     2 |
| **Total**   | **1039** |

Provenance: see `tests/upstream/_SOURCE`.

## Branch matrix

| Branch         | purs version | Status      | Notes                       |
|----------------|--------------|-------------|------------------------------|
| `master`       | v0.15.15     | ✅ current  | The active development line |
| `purs-0.15.10` | v0.15.10     | planned     | Diff in `$runtime_lazy` shape introduced 0.15.12 |
| `purs-0.14.x`  | v0.14.9      | planned     | Major schema diff: `Eff` → `Effect`, `MonadEff`, `Function (Maybe Text)` |
| `purs-0.13.x`  | v0.13.8      | not planned | Different optimizer pipeline; substantial port effort |

The supported-versions list will grow as we cut release branches. Each
branch is a complete fork — same code layout, same test fixtures, but
re-pinned to the matching upstream commit + adjusted for any schema or
prelude changes.

## What changes across purs versions

The codegen-relevant things that *have* changed in the past:

| Version     | Change                                                       | Affected PursJS module |
|-------------|--------------------------------------------------------------|------------------------|
| **0.15.16** | (no schema changes; we forward-compatible)                  | —                       |
| **0.15.14** | `--source-globs-file` CLI arg                                | none (we don't shell out to purs) |
| **0.15.12** | `$runtime_lazy` reference-error message format changed       | `CodeGen.Laziness.runtimeLazyAST` |
| **0.15.10** | `IsSyntheticApp` meta added                                  | `CoreFn.Types.Meta`     |
| **0.15.4**  | `applyLazinessTransform` overhauled                          | `CodeGen.Laziness`      |
| **0.15.0**  | Module output went from CommonJS to ES modules                | `CodeGen.Printer` import/export rendering |
| **0.14.0**  | `Effect` replaced `Eff`; `MonadEff`/`bindEff` retained as compat | `Optimizer.MagicDo`, `Optimizer.Constants` |
| **0.13.0**  | CoreFn JSON format introduced (`builtWith` field added)      | `CoreFn.FromJSON`       |

## How to cut a new branch for a different purs version

```bash
# 1. Start from a clean master
git checkout master
git pull

# 2. Make the version-pin branch
TARGET=0.15.10
git checkout -b purs-$TARGET

# 3. Update the upstream checkout
cd ../purescript
git fetch --tags
git checkout v$TARGET

# 4. Re-sync the test set from the new tag
cd ../purescript-backend-js
npm run sync-tests                          # uses the pin from package.json

# 5. Update prelude-pool to use the matching prelude version
cd prelude-pool
# Edit spago.yaml -> change registry version to match
spago install
cd ..

# 6. Build, test, iterate. Patch PursJS modules where the version diverges:
npm run build
npm test

# 7. Update VERSIONING.md to mark this branch as supported
# 8. Commit + push
git commit -am "Pin to purs $TARGET"
git push -u origin purs-$TARGET
```

## Recommended workflow

- For **library authors writing PureScript**: pin your `package.json`
  (or wherever you depend on this codegen) to a specific PursJS *tag*
  matching your project's purs version, not to `master`.
- For **users of the prebuilt JS**: just use the latest tag on the
  branch matching your purs version.
- For **contributors**: target `master` (currently 0.15.15) unless
  fixing a back-ported bug on an older branch.

## Tag naming

Tags on each branch follow the pattern:

```
master:        v0.15.15-pursjs.<N>          (e.g. v0.15.15-pursjs.0, v0.15.15-pursjs.1)
purs-0.15.10:  v0.15.10-pursjs.<N>
purs-0.14.x:   v0.14.9-pursjs.<N>
```

`<N>` increments for PursJS-side improvements that don't require a
purs-version bump.
