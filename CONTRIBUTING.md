# Contributing to purescript-backend-js

Thanks for your interest. This project is an alternate JavaScript
backend for PureScript, ported from the compiler's built-in codegen so
that optimisation passes can be written and experimented with in
PureScript itself. Contributions of any size are welcome.

## Quick links

- [README.md](README.md) — what the project is and how to use it
- [LEARN.md](LEARN.md) — line-by-line walkthrough of every CoreFn → JS mapping
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) — pipeline diagram + decision points
- [VERSIONING.md](VERSIONING.md) — branch-per-purs-version policy
- [docs/TESTING.md](docs/TESTING.md) — test infrastructure

## Setting up a dev environment

```bash
# Toolchain
brew install purescript spago             # or your platform's equivalent
node --version                            # ≥ 18 required

# Clone and build
git clone https://github.com/<you>/purescript-backend-js
cd purescript-backend-js
spago build                               # builds the codegen
cd prelude-pool && spago build && cd ..   # builds the prelude source pool used by tests

# Sanity check
npm run test:quick                        # ~1 min, all three suites with LIMIT=10
```

Working `purs` reference clone (optional, only needed for `npm run sync-tests`):

```bash
git clone https://github.com/purescript/purescript ../purescript
cd ../purescript && git checkout v0.15.15 && cd -
```

## Running the test suites

```bash
npm test                                  # full run, ~10 min
npm run test:optimize                     # 10 golden tests
npm run test:passing                      # 438 runtime tests
npm run test:warning                      # 68 codegen-only tests
```

A passing run on `main` shows:

```
optimize: 8/10 byte / 9/10 semantic
passing:  357/360 codegen-eligible
warning:  62/62 codegen-eligible
```

Anything below that is a regression and should block a PR.

## What to work on

Open issues are the best signal. If you want to pick something up cold,
the three areas of highest leverage right now are:

1. **The three known failures** — `4179` (selective laziness wrapping),
   `BigFunction` (optimizer perf on 9.6 MB corefn), `StringEscapes`
   (surrogate pairs in JSON parsing). Any of these is a self-contained
   PR.
2. **A new optimisation pass.** Because the codegen lives in
   PureScript, new passes are much cheaper to prototype than they would
   be in Haskell. See `src/PursJS/CoreImp/Optimizer/` for the existing
   passes and how they plug into the pipeline.
3. **Source maps.** Stock `purs` has `--codegen sourcemaps`; we don't.
   A port would land in `src/PursJS/CodeGen/Printer.purs`.

## Code style

- Match the surrounding file. We follow upstream PureScript conventions
  (2-space indent, leading-`|` records, point-free where it's clear).
- Every file's top-of-module comment must name its Haskell counterpart
  and the upstream commit it was ported from. When the upstream commit
  changes, update the header.
- Keep individual functions short — if a function exceeds ~40 lines,
  it's usually a sign you're inlining the Haskell version's `where`
  clauses; extract them.
- No `unsafePartial` in new code without a comment explaining why.

## Pull-request checklist

Before opening a PR:

- [ ] `spago build` succeeds with no warnings.
- [ ] `npm test` shows no regression vs the pass-rate in
      [README.md](README.md#results-at-a-glance).
- [ ] If you touched a file under `src/PursJS/CoreImp/Optimizer/`,
      `npm run test:optimize` shows the new behaviour in at least one
      golden (or you've added one).
- [ ] If you changed `corefn.json` parsing, you've updated
      [LEARN.md](LEARN.md) and (if applicable) the `pinnedPursVersion`
      constant in `src/PursJS/CoreFn/FromJSON.purs`.
- [ ] Commit message follows the existing style — short subject,
      explanatory body, no trailing TODO comments.

## Porting to a new purs release

The project follows a **one-branch-per-purs-version** model
(see [VERSIONING.md](VERSIONING.md)). To cut a branch for a new
upstream release:

1. `git checkout -b purs-<target>`
2. Update `pinnedPursVersion` in `src/PursJS/CoreFn/FromJSON.purs`
3. Update the `sync-tests` script in `package.json` to reference the
   new tag, then run `npm run sync-tests`
4. `npm test` — investigate every new failure
5. Patch the affected PursJS modules (the table in
   [VERSIONING.md](VERSIONING.md#what-changes-across-purs-versions)
   lists the historical change-points)
6. Update [VERSIONING.md](VERSIONING.md) to mark the branch as supported

## Reporting bugs

Open an issue. Please include:

- Your `purs --version`, Node version, and which purescript-backend-js
  branch you're on
- A minimal `.purs` reproducer
- The `corefn.json` for that module (run `purs compile --codegen corefn`
  and attach `output/<Module>/corefn.json`)
- The output you got vs the output you expected (`purs --codegen js`
  gives you the reference)

## License

By contributing you agree that your contributions will be released
under the BSD-3-Clause license, matching the project as a whole
(see [LICENSE](LICENSE)).
