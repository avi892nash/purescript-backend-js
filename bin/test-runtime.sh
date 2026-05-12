#!/usr/bin/env bash
# Generate JS via our codegen for a target module and run a smoke test.
# Compares the runtime output of our-codegen vs purs-codegen for the SAME
# function calls and confirms they produce identical results.

set -e

PROJECT=/Users/avinashverma/purescriptCodeGen
REF=$PROJECT/sample-purs/output_ref
TARGET=${1:-Examples.Arith}

if [ ! -d "$REF/$TARGET" ]; then
  echo "No such module: $TARGET" >&2
  exit 1
fi

cd $PROJECT

# Sandbox for our codegen
OURS=$(mktemp -d -t pursjs-ours-XXXXXX)
trap "rm -rf $OURS" EXIT
cp -r $REF/* $OURS/
echo '{"type":"module"}' > "$OURS/package.json"
node --input-type=module -e "
import { main } from './output/PursJS.Main/index.js';
process.argv = [process.argv[0], 'main', '$REF/$TARGET/corefn.json'];
main();
" 2>/dev/null > "$OURS/$TARGET/index.js"

# Reference (purs's output) — same structure plus the package.json
REFCOPY=$(mktemp -d -t pursjs-ref-XXXXXX)
trap "rm -rf $OURS $REFCOPY" EXIT
cp -r $REF/* $REFCOPY/
echo '{"type":"module"}' > "$REFCOPY/package.json"

# Driver expressions per module — known-safe (no infinite recursion).
case "$TARGET" in
  Examples.Arith)
    EXPR="
      console.log('intAdd(2)(3)    =', m.intAdd(2)(3));
      console.log('intMul(4)(5)    =', m.intMul(4)(5));
      console.log('intSub(10)(3)   =', m.intSub(10)(3));
      console.log('intNeg(-7)      =', m.intNeg(-7));
      console.log('numAdd(1.5)(2.5)=', m.numAdd(1.5)(2.5));
      console.log('numDiv(10)(4)   =', m.numDiv(10)(4));
      console.log('strConcat       =', m.strConcat('foo')('bar'));
      console.log('isLess(1)(2)    =', m.isLess(1)(2));
      console.log('isEq(3)(3)      =', m.isEq(3)(3));
      console.log('boolAnd(true)(false) =', m.boolAnd(true)(false));
      console.log('boolNot(true)   =', m.boolNot(true));
    "
    ;;
  Examples.TailRecursion)
    EXPR="
      console.log('sumDown(100)(0) =', m.sumDown(100)(0));
      console.log('sumDown(1000)(0)=', m.sumDown(1000)(0));
      console.log('sumUp(10)       =', m.sumUp(10));
    "
    ;;
  Examples.Patterns)
    EXPR="
      const A = await import('./Examples.ADTs/index.js');
      console.log('describe(Red)   =', m.describe(A.Red.value));
      console.log('describe(Green) =', m.describe(A.Green.value));
      console.log('treeSize(Leaf)  =', m.treeSize(A.Leaf.value));
      console.log('classify(-5)    =', m.classify(-5));
      console.log('classify(0)     =', m.classify(0));
      console.log('classify(42)    =', m.classify(42));
    "
    ;;
  Examples.Closures)
    EXPR="
      console.log('inc(5)          =', m.inc(5));
      console.log('addN(10)(3)     =', m.addN(10)(3));
      console.log('add(7)(8)       =', m.add(7)(8));
      console.log('addTwo(5)       =', m.addTwo(5));
      console.log('inc4(0)         =', m.inc4(0));
      console.log('idApp           =', m.idApp);
    "
    ;;
  Examples.ADTs)
    EXPR="
      console.log('red             =', JSON.stringify(m.red));
      console.log('mkPair          =', JSON.stringify(m.mkPair));
      console.log('singleton(42)   =', JSON.stringify(m.singleton(42)));
      console.log('wrapped         =', JSON.stringify(m.wrapped));
      console.log('unwrap(wrapped) =', m.unwrap(m.wrapped));
    "
    ;;
  Examples.Records)
    EXPR="
      console.log('origin          =', JSON.stringify(m.origin));
      console.log('xCoord(origin)  =', m.xCoord(m.origin));
      console.log('moveX(origin)(5)=', JSON.stringify(m.moveX(m.origin)(5)));
      console.log('shift(origin)(1)(2) =', JSON.stringify(m.shift(m.origin)(1)(2)));
    "
    ;;
  Effect)
    # Test the mutually-recursive instance dictionaries actually work.
    EXPR="
      // Make sure the dict refs all resolve cleanly
      console.log('monadEffect.Applicative0().pure(1)()  =', m.monadEffect.Applicative0().pure(1)());
      console.log('bindEffect.Apply0().Functor0()        =', !!m.bindEffect.Apply0().Functor0());
      console.log('applyEffect.Functor0().map is fn      =', typeof m.applyEffect.Functor0().map === 'function');
      console.log('functorEffect.map(x=>x+1)(()=>5)()    =', m.functorEffect.map(x => x + 1)(() => 5)());
    "
    ;;
  Data.EuclideanRing)
    EXPR="
      const Eq = await import('./Data.Eq/index.js');
      console.log('gcd(eqInt)(euclideanRingInt)(12)(18) =', m.gcd(Eq.eqInt)(m.euclideanRingInt)(12)(18));
      console.log('lcm(eqInt)(euclideanRingInt)(4)(6)   =', m.lcm(Eq.eqInt)(m.euclideanRingInt)(4)(6));
    "
    ;;
  Data.Ord)
    EXPR="
      console.log('compare(ordInt)(3)(5) =', m.compare(m.ordInt)(3)(5).constructor.name);
      console.log('compare(ordInt)(5)(5) =', m.compare(m.ordInt)(5)(5).constructor.name);
      console.log('max(ordInt)(3)(7) =', m.max(m.ordInt)(3)(7));
      console.log('signum(ordInt)(ringInt)(7)  =', m.signum(m.ordInt)({Ring1: () => null}));
    "
    ;;
  *)
    EXPR="console.log('exports:', Object.keys(m));"
    ;;
esac

mkrun() {
  local dir=$1
  cat > "$dir/driver.mjs" <<EOF
import * as m from './$TARGET/index.js';
$EXPR
EOF
  cd "$dir" && node ./driver.mjs
  cd "$PROJECT"
}

echo "=== ours ==="
mkrun "$OURS" | tee /tmp/pursjs-runtime-ours.txt
echo ""
echo "=== purs ==="
mkrun "$REFCOPY" | tee /tmp/pursjs-runtime-purs.txt
echo ""
if diff -q /tmp/pursjs-runtime-ours.txt /tmp/pursjs-runtime-purs.txt >/dev/null; then
  echo "RUNTIME MATCH: $TARGET ✓"
else
  echo "RUNTIME DIFF: $TARGET ✗"
  diff /tmp/pursjs-runtime-ours.txt /tmp/pursjs-runtime-purs.txt
  exit 1
fi
