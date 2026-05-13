# tests/upstream/

A verbatim copy of `tests/purs/**` from the upstream PureScript compiler,
pinned to the version this branch targets (see `../VERSIONING.md`). 1039
`.purs` files plus their companion `.out`, `.out.js`, `.js` golden files
and any test-specific subdirectories.

The test runners under `bin/` read from this directory, so the repo is
self-contained — no need to have a separate purescript clone for testing.

## Provenance

```
$ cat _SOURCE
purescript@5589e81 (v0.15.15)
```

The sync was done with:
```bash
git -C $PURESCRIPT_REPO archive --format=tar v0.15.15 tests/purs \
  | tar -x -C tests/upstream --strip-components=2
```

## Categories

| Category    | Count | Codegen-relevant? | Runner |
|-------------|------:|-------------------|--------|
| `optimize/` | 10    | yes (goldens)     | `bin/run-upstream-tests.sh` |
| `passing/`  | 438   | yes (runtime)     | `bin/run-passing-tests.sh`  |
| `warning/`  | 68    | yes (codegen)     | `bin/run-warning-tests.sh`  |
| `failing/`  | 444   | no — typechecker  | — |
| `docs/`     | 55    | no — `purs docs`  | — |
| `layout/`   | 15    | no — parser       | — |
| `graph/`    | 4     | no — module graph | — |
| `psci/`     | 2     | no — REPL         | — |
| `publish/`  | 1     | no                | — |
| `sourcemaps/` | 2   | future            | — |
| **Total**   | **1039** | | |

The "no" rows are checked in for completeness — they don't exercise codegen
and the corresponding upstream tests run via `purs` directly, not via JS
output. Keeping them here means anyone bumping the version pin gets the
whole picture in one place.

## Refreshing

After bumping the pin in `VERSIONING.md`:

```bash
./bin/sync-upstream-tests.sh                 # pulls the pinned tag
./bin/sync-upstream-tests.sh v0.14.9         # or a specific tag
```

This wipes the contents of `tests/upstream/` (except `README.md`) and
re-extracts the tree from the requested tag. Always commit the diff so the
repo stays consistent with the pin.

## License

These files are copied verbatim from
[purescript/purescript](https://github.com/purescript/purescript), licensed
under BSD-3-Clause. See the upstream `LICENSE` for the full text.
