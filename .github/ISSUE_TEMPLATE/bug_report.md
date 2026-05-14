---
name: Bug report
about: A codegen output that's wrong, a runtime crash, or a regression vs stock purs
title: ""
labels: bug
assignees: ""
---

## What happened

A clear, one-line description of the bug.

## Environment

- `pursjs-codegen` branch / commit:
- `purs --version`:
- `node --version`:
- OS:

## Reproducer

Minimal `.purs` source that triggers the bug:

```purescript
module Repro where

-- ...
```

If the bug is in optimiser output, please attach the corresponding
`corefn.json` (run `purs compile --codegen corefn` and find it under
`output/<Module>/corefn.json`).

## Expected output

What `purs --codegen js` produces for the same input:

```js
// stock purs output
```

## Actual output

What pursjs-codegen produces:

```js
// our output
```

## Anything else

Logs, screenshots, hunches.
