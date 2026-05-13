// JS `| 0` truncates a Number to a signed 32-bit Int (wraps 2147483648 to
// -2147483648 etc.). Used by the corefn parser when an IntLiteral is the
// operand of `Unary Negate` and the value just exceeds Int.maxValue.
export const truncate32 = n => n | 0;
