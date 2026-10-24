import * as path from 'node:path';
import { buildAll, syncFrozen } from './freeze.js';
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
const drift = syncFrozen(dir, files, write);
for (const name of drift) console.error(`DRIFT ${name}`);
console.log(write ? `escrito en ${dir}` : drift.length ? `${drift.length} artefactos difieren` : 'artefactos congelados coinciden');
process.exit(drift.length ? 1 : 0);
