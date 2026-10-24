import { generateDataset, DEFAULT_SEED } from './generate.js';
import { runAb } from './ab.js';

// Uso: tsx src/federation/benchmark/ab-run.ts [train|calibration|test]  (imprime el AbReport; no escribe nada)
const SPLITS = ['train', 'calibration', 'test'] as const;
const arg = process.argv[2] ?? 'calibration';
if (!(SPLITS as readonly string[]).includes(arg)) { console.error(`split inválido '${arg}'; usa ${SPLITS.join('|')}`); process.exit(2); }
const split = arg as (typeof SPLITS)[number];
const { corpus, dataset } = generateDataset(DEFAULT_SEED);
console.log(JSON.stringify(await runAb(corpus, dataset, split), null, 2));
