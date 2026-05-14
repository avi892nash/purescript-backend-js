## Summary

<!-- 1-3 bullet points describing what changed and why. -->

## Test results

<!-- Run `npm test` and paste the headline numbers. -->

```
optimize: x/10 byte / y/10 semantic   (baseline: 8/10 byte / 9/10 semantic)
passing:  x/360 codegen-eligible      (baseline: 357/360)
warning:  x/62  codegen-eligible      (baseline: 62/62)
```

## Checklist

- [ ] `spago build` is clean.
- [ ] `npm test` shows no regression vs the numbers in
      [README.md](../README.md#results-at-a-glance).
- [ ] If you added/changed an optimiser pass, a golden test under
      `tests/upstream/optimize/` covers the new behaviour (or you've
      explained why one isn't needed).
- [ ] If you touched `corefn.json` parsing, you've updated
      [LEARN.md](../LEARN.md) and bumped the version pin where
      relevant.
- [ ] Commit messages follow the existing style.

## Related issues

<!-- Closes #N -->
