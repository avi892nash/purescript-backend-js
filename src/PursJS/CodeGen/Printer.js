// FFI for PursJS.CodeGen.Printer.
//
// `_toExponential` calls JS's `Number.prototype.toExponential()`. Used by
// `showNumber` when the value falls outside Haskell's "fixed format" range
// (0.1 <= |n| < 1e7).

export const _toExponential = n => n.toExponential();
