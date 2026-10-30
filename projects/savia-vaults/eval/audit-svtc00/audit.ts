import * as fs from 'node:fs';
import * as os from 'node:os';
import * as path from 'node:path';
import { fileURLToPath } from 'node:url';
import { execFileSync } from 'node:child_process';

// Ningún servicio recibe defaults de producción. El cwd también aísla logs/cuotas.
const project = fileURLToPath(new URL('../../', import.meta.url));
// La ruta de salida se ancla al cwd original: tras el chdir al tmp efímero se borraría con él.
const output = process.argv[3] ? path.resolve(process.argv[3]) : undefined;
const root = fs.mkdtempSync(path.join(os.tmpdir(), 'svtc00-'));
process.env.AUDIT_TMP = root;
// HOME propio: ninguna ruta derivada de os.homedir() puede tocar el directorio real.
process.env.HOME = path.join(root, 'home');
fs.mkdirSync(process.env.HOME, { recursive: true });
if (!os.homedir().startsWith(root)) throw new Error('aislamiento de HOME no efectivo');
const isolated = {
  SAVIA_RAG_HOME: 'rag', SAVIA_FILES_HOME: 'files', SAVIA_FILES_KEYS_HOME: 'keys',
  SAVIA_SEARCH_CACHE: 'search-cache', SAVIA_VAULTS_HOME: 'vaults',
};
// Ninguna otra variable SAVIA_* del operador (proveedor RAG, token...) llega a los servicios.
for (const key of Object.keys(process.env)) if (key.startsWith('SAVIA_') && !(key in isolated)) delete process.env[key];
for (const [key, dir] of Object.entries(isolated)) process.env[key] = path.join(root, dir);
process.chdir(root);
const chosen = process.argv[2] ?? 'all';
let failed = false;
const git = (...args: string[]): string => {
  try { return execFileSync('git', ['-C', project, ...args], { encoding: 'utf8' }).trim(); } catch { return 'unknown'; }
};
try {
  const { probes } = await import('./probes.js');
  const { surfaces } = await import('./surfaces.js');
  const { mutationApplied } = await import('./common.js');
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
      const message = error instanceof Error ? (process.env.AUDIT_STACK ? error.stack : error.message) : String(error);
      console.error(`${id}: FAIL: ${message}`);
      // Sobrescribe el JSON de una ejecución anterior para que un caso fallido no conserve un PASS viejo.
      if (output) { fs.mkdirSync(output, { recursive: true }); fs.writeFileSync(path.join(output, `${id}.json`), JSON.stringify({ case: id, run: 'FAIL', error: String(message).split(root).join('<TMP>') }, null, 2) + '\n'); }
    }
  }
  if (process.env.AUDIT_MUTATE_CHECK && !mutationApplied()) {
    failed = true;
    console.error(`AUDIT_MUTATE_CHECK=${process.env.AUDIT_MUTATE_CHECK}: ninguna etiqueta coincide (la mutación no se aplicó)`);
  }
  if (output) {
    const envFile = path.join(output, 'environment.json');
    fs.writeFileSync(envFile, JSON.stringify({
      // `head` es el checkout ejecutado; `base` es el origin/main con el que se contrasta (la base auditada).
      head: git('rev-parse', 'HEAD'), base: git('merge-base', 'HEAD', 'origin/main'),
      node: process.version, platform: process.platform, arch: process.arch,
      retrieval: 'BM25; HashEmbedder solo para construir el índice; ninguna llamada a Ollama',
      synthetic: true, failed,
    }, null, 2) + '\n');
    if (!fs.existsSync(envFile)) throw new Error(`no se pudo escribir ${envFile}`);
  }
} finally {
  const { Journal } = await import('../../src/files/journal.js');
  Journal.closeAll();
  process.chdir(os.tmpdir());
  fs.rmSync(root, { recursive: true, force: true });
}
if (failed) process.exitCode = 1;
