# Changelog

All notable changes to this project will be documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project follows the version scheme described in
[VERSIONING.md](VERSIONING.md): `<purs-version>-pursjs.<N>` (e.g.
`0.15.15-pursjs.0`).

## [Unreleased]

## [0.15.15-pursjs.0] — 2024-05

### Initial release

First public version. Targets `purescript@v0.15.15`.

#### Codegen

- Full port of `Language.PureScript.CodeGen.JS` to PureScript
  (~2300 lines across 17 modules under `src/PursJS/`).
- All 14 upstream optimiser passes ported: block flattening, IIFE
  collapse, dead-code removal, common-value inlining, common-operator
  inlining, function composition unfolding, identity removal,
  unsafe-coerce removal, unsafe-partial unfolding, unsafe-index
  unfolding, uncurried-function inlining (arities 0..10),
  magic-do for `Effect` / `Eff` / `ST`, TCO, integer normalisation.
- `applyLazinessTransform` for mutually-recursive instance dictionaries
  (minimal subset of `CoreFn/Laziness.hs`).
- Pretty printer with full operator-precedence handling.

#### Spago backend

- Executable `pursjs-codegen` exposed via `npm link`; drop-in via
  `workspace.backend.cmd: "pursjs-codegen"` in `spago.yaml`.
- `scripts/spago-backend.mjs` walks `output/<Module>/corefn.json`,
  runs our codegen, and copies sibling `foreign.js` files (which
  `purs --codegen corefn` does not do on its own).

#### Tests

- Full upstream test suite vendored at `tests/upstream/` (1039 `.purs`
  files at `purescript@v0.15.15`).
- `npm test` runs three suites (`optimize`, `passing`, `warning`) via
  `scripts/test.mjs`.
- Current pass-rate: `8/10` byte / `9/10` semantic on optimize,
  `357/360` codegen-eligible on passing, `62/62` codegen-eligible on
  warning.

#### Known limitations

- 3 passing-suite failures: `4179` (selective laziness wrapping not
  yet implemented), `BigFunction` (optimiser timeout on 9.6 MB
  corefn), `StringEscapes` (surrogate pair handling in JSON parsing).
- No source maps (purs has `--codegen sourcemaps`; we don't).
- One pinned `purs` version per branch.

[Unreleased]: https://github.com/avinashverma/purescriptCodeGen/compare/v0.15.15-pursjs.0...HEAD
[0.15.15-pursjs.0]: https://github.com/avinashverma/purescriptCodeGen/releases/tag/v0.15.15-pursjs.0
