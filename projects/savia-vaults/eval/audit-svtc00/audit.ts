import * as fs from 'node:fs';
import * as os from 'node:os';
import * as path from 'node:path';
import { fileURLToPath } from 'node:url';
import { execFileSync } from 'node:child_process';

// Ningún servicio recibe defaults de producción. El cwd también aísla logs/cuotas.
const project = fileURLToPath(new URL('../../', import.meta.url));
const root = fs.mkdtempSync(path.join(os.tmpdir(), 'svtc00-'));
process.env.AUDIT_TMP = root;
for (const [key, dir] of Object.entries({
  SAVIA_RAG_HOME: 'rag', SAVIA_FILES_HOME: 'files', SAVIA_FILES_KEYS_HOME: 'keys',
  SAVIA_SEARCH_CACHE: 'search-cache', SAVIA_VAULTS_HOME: 'vaults',
})) process.env[key] = path.join(root, dir);
process.chdir(root);
const chosen = process.argv[2] ?? 'all';
const output = process.argv[3] ? path.resolve(process.argv[3]) : undefined;
let failed = false;
try {
  const { probes } = await import('./probes.js');
  const { surfaces } = await import('./surfaces.js');
  const cases = { ...probes, surfaces };
  if (chosen !== 'all' && !(chosen in cases)) throw new Error(`caso desconocido: ${chosen}`);
  for (const [id, probe] of Object.entries(cases)) {
    if (chosen !== 'all' && chosen !== id) continue;
    try {
      const observation = await probe();
      const result = { case: id, run: 'PASS', ...observation };
      // Sustituye solo la raíz temporal propia; nunca exporta rutas personales.
      const json = JSON.stringify(result, (_k, v) => typeof v === 'string' ? v.split(root).join('<TMP>') : v, 2);
      console.log(json);
      if (output) { fs.mkdirSync(output, { recursive: true }); fs.writeFileSync(path.join(output, `${id}.json`), json + '\n'); }
    } catch (error) {
      failed = true;
      console.error(`${id}: FAIL: ${error instanceof Error ? (process.env.AUDIT_STACK ? error.stack : error.message) : String(error)}`);
    }
  }
  if (output) {
    fs.writeFileSync(path.join(output, 'environment.json'), JSON.stringify({
      head: execFileSync('git', ['-C', project, 'rev-parse', 'HEAD'], { encoding: 'utf8' }).trim(),
      node: process.version, platform: process.platform, arch: process.arch,
      retrieval: 'BM25; HashEmbedder solo para construir el índice; ninguna llamada a Ollama',
      synthetic: true, failed,
    }, null, 2) + '\n');
  }
} finally {
  const { Journal } = await import('../../src/files/journal.js');
  Journal.closeAll();
  process.chdir(os.tmpdir());
  fs.rmSync(root, { recursive: true, force: true });
}
if (failed) process.exitCode = 1;
