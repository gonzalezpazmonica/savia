import { generateDataset, DEFAULT_SEED } from './generate.js';
import { runAb } from './ab.js';

// Uso: tsx src/federation/benchmark/ab-run.ts [train|calibration|test]  (imprime el AbReport; no escribe nada)
const split = (process.argv[2] ?? 'calibration') as 'train' | 'calibration' | 'test';
const { corpus, dataset } = generateDataset(DEFAULT_SEED);
console.log(JSON.stringify(await runAb(corpus, dataset, split), null, 2));
