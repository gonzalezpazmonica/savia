import * as fs from 'node:fs';
import * as path from 'node:path';
import { buildAll } from './freeze.js';
import { canonicalJson } from './canon.js';
import { DEFAULT_SEED, generateDataset } from './generate.js';
import { validateDataset } from './validate.js';

// Uso: tsx src/federation/benchmark/run.ts [--write]
// Sin --write compara con eval/adaptive/ y falla si algo difiere (artefactos congelados).
const dir = path.resolve(import.meta.dirname, '../../../eval/adaptive');
const write = process.argv.includes('--write');
const { corpus, dataset } = generateDataset(DEFAULT_SEED);
const errors = validateDataset(corpus, dataset);
if (errors.length) { console.error(errors.join('\n')); process.exit(1); }
const { report, freeze } = await buildAll(corpus, dataset);
const files: Record<string, unknown> = { 'corpus.json': corpus, 'dataset.json': dataset, 'baseline.json': report, 'freeze.json': freeze };
let drift = 0;
for (const [name, value] of Object.entries(files)) {
  const body = JSON.stringify(JSON.parse(canonicalJson(value)), null, 2) + '\n';
  const file = path.join(dir, name);
  if (write) { fs.mkdirSync(dir, { recursive: true }); fs.writeFileSync(file, body); continue; }
  if (!fs.existsSync(file) || fs.readFileSync(file, 'utf-8') !== body) { console.error(`DRIFT ${name}`); drift++; }
}
console.log(write ? `escrito en ${dir}` : drift ? `${drift} artefactos difieren` : 'artefactos congelados coinciden');
process.exit(drift ? 1 : 0);
