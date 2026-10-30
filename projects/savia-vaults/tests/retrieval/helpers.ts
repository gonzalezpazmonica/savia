// SE-489 — utilidades de tests de rutas: cúpulas temporales con índice RAG de hash (sin red).
import * as fs from 'node:fs';
import * as os from 'node:os';
import * as path from 'node:path';
import { RagService, type RagDomeRef } from '../../src/rag/service.js';
import { HashEmbedder } from '../../src/rag/embedder.js';
import type { ResolvedRagConfig } from '../../src/rag/types.js';

export const long = (s: string): string => `${s}. `.repeat(12);

export const note = (title: string, body: string, extra = ''): string =>
  `---\ntitle: ${title}\n${extra}---\n# ${title}\n\n${body}\n`;

export function writeDocs(dir: string, docs: Record<string, string>): void {
  for (const [p, c] of Object.entries(docs)) {
    fs.mkdirSync(path.dirname(path.join(dir, p)), { recursive: true });
    fs.writeFileSync(path.join(dir, p), c);
  }
}

/** Reescribe un fichero y adelanta su mtime para que el cambio sea visible. */
export function rewrite(file: string, content: string): void {
  fs.writeFileSync(file, content);
  const t = new Date(Date.now() + 5_000);
  fs.utimesSync(file, t, t);
}

export interface Fixture {
  root: string;
  home: string;
  domes: RagDomeRef[];
  /** Cúpulas cuyo `authorize` lanza (denegadas por el plano de control). */
  denied: Set<string>;
  service(): RagService;
  dir(name: string): string;
  cleanup(): void;
}

/** Cúpulas N2 con RAG habilitado; `inlineSyncBudget: 0`: lo servido sale del índice construido. */
export function fixture(names: string[]): Fixture {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'savia-se489-'));
  const home = path.join(root, '.rag');
  fs.mkdirSync(home);
  const domes: RagDomeRef[] = names.map(name => {
    fs.mkdirSync(path.join(root, name));
    return { name, path: path.join(root, name), confidentiality: 'N2', rag: { enabled: true, model: 'm', inlineSyncBudget: 0 } };
  });
  const denied = new Set<string>();
  return {
    root, home, domes, denied,
    service: () => new RagService({
      domes: () => domes, home,
      embedderFactory: (cfg: ResolvedRagConfig) => new HashEmbedder(64, cfg, cfg.model),
      authorize: async (dome) => { if (denied.has(dome)) throw new Error('acceso denegado'); return undefined; },
    }),
    dir: (name) => path.join(root, name),
    cleanup: () => fs.rmSync(root, { recursive: true, force: true }),
  };
}
