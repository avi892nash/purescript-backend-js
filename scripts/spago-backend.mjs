#!/usr/bin/env node
// pursjs-codegen — alternative Spago backend that uses the PursJS codegen
// (this repo) instead of purs's built-in JavaScript codegen.
//
// Spago invokes the configured backend command with cwd = output/ after
// it has run `purs compile --codegen corefn`. For each Module/corefn.json
// in cwd, we run our codegen and write Module/index.js next to it.
//
// Usage (in a downstream PureScript project's spago.yaml):
//
//     workspace:
//       backend:
//         cmd: "pursjs-codegen"
//
// Then `spago build` invokes our codegen instead of purs's.

import { readdirSync, readFileSync, writeFileSync, existsSync, copyFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';

const __dirname = dirname(fileURLToPath(import.meta.url));
const PURSJS_MAIN = join(__dirname, '..', 'output', 'PursJS.Main', 'index.js');

if (!existsSync(PURSJS_MAIN)) {
  console.error(`pursjs-codegen: not built at ${PURSJS_MAIN}.`);
  console.error('Run `npm run build` in the pursjs-codegen repo first.');
  process.exit(1);
}

// Spago invokes the backend at the project root. Look for the output
// directory there. Honor --output for spago invocations that pass it.
function findOutputDir() {
  const args = process.argv.slice(2);
  const i = args.indexOf('--output');
  if (i >= 0 && args[i + 1]) return args[i + 1];
  for (const candidate of ['output', '.spago/output', '.']) {
    const p = join(process.cwd(), candidate);
    if (existsSync(p)) {
      const entries = readdirSync(p).filter(d => existsSync(join(p, d, 'corefn.json')));
      if (entries.length > 0) return p;
    }
  }
  return join(process.cwd(), 'output');
}

const outputDir = findOutputDir();
const modules = readdirSync(outputDir)
  .filter(d =>
    !d.startsWith('Prim') &&
    !d.startsWith('.') &&
    existsSync(join(outputDir, d, 'corefn.json'))
  );

if (modules.length === 0) {
  console.error('pursjs-codegen: no corefn.json files in', outputDir);
  console.error('Did purs run with --codegen corefn?');
  process.exit(1);
}

let okCount = 0;
let foreignCount = 0;
let errors = [];

for (const mod of modules) {
  const corefnPath = join(outputDir, mod, 'corefn.json');
  const result = spawnSync('node', [
    '--input-type=module', '-e',
    `import { main } from '${PURSJS_MAIN}';
     process.argv = [process.argv[0], 'main', '${corefnPath}'];
     main();`
  ], { encoding: 'utf8' });

  if (result.status === 0) {
    writeFileSync(join(outputDir, mod, 'index.js'), result.stdout);
    okCount++;

    // Copy the foreign.js sibling if this module has FFI bindings.
    // `purs --codegen js` does this for us, but `--codegen corefn`
    // (which is what spago runs when a backend is configured) does not.
    try {
      const corefn = JSON.parse(readFileSync(corefnPath, 'utf8'));
      if (Array.isArray(corefn.foreign) && corefn.foreign.length > 0 && corefn.modulePath) {
        const foreignSrc = corefn.modulePath.replace(/\.purs$/, '.js');
        const foreignDst = join(outputDir, mod, 'foreign.js');
        if (existsSync(foreignSrc)) {
          copyFileSync(foreignSrc, foreignDst);
          foreignCount++;
        } else {
          errors.push({ mod, code: 0, stderr: `foreign.js not found at ${foreignSrc}` });
        }
      }
    } catch (e) {
      errors.push({ mod, code: 0, stderr: `foreign-copy: ${e.message}` });
    }
  } else {
    errors.push({ mod, code: result.status, stderr: result.stderr });
  }
}

console.log(`pursjs-codegen: ${okCount}/${modules.length} modules generated` +
  (foreignCount > 0 ? ` (+${foreignCount} foreign.js copied)` : ''));

if (errors.length > 0) {
  console.error(`\n${errors.length} failures:`);
  for (const e of errors.slice(0, 10)) {
    console.error(`  ${e.mod}: ${e.stderr?.split('\n')[0] || `exit ${e.code}`}`);
  }
  process.exit(1);
}
