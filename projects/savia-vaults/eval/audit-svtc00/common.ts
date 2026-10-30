import assert from 'node:assert/strict';
import * as fs from 'node:fs';
import * as path from 'node:path';
import { RagService, type RagDomeRef } from '../../src/rag/service.js';
import { HashEmbedder } from '../../src/rag/embedder.js';
import { FlatVectorStore, domeDir, readActive } from '../../src/rag/store.js';
import type { VaultConfig } from '../../src/types.js';

/** Aserciones AS-IS: un arreglo futuro debe romper la expectativa antigua. */
let mutated = false;
/** Falso si `AUDIT_MUTATE_CHECK` no coincidió con ninguna etiqueta (typo): la prueba de sensibilidad no vale. */
export const mutationApplied = (): boolean => mutated;
export function check(label: string, actual: unknown, expected: unknown): void {
  if (process.env.AUDIT_MUTATE_CHECK === label) mutated = true;
  if (process.env.AUDIT_MUTATE_CHECK === label) assert.notDeepEqual(actual, expected, `mutación: ${label}`);
  else assert.deepEqual(actual, expected, label);
}

export function fixture(name: string, level: 'N2' | 'N3' = 'N2', files = false) {
  const root = path.join(process.env.AUDIT_TMP!, name);
  const vault = path.join(root, 'vault');
  fs.mkdirSync(vault, { recursive: true });
  const dome: RagDomeRef = {
    name, path: vault, confidentiality: level,
    rag: { enabled: true, model: 'audit', inlineSyncBudget: 0, halfLifeDays: 0 },
    ...(files ? { files: { enabled: true } } : {}),
  };
  const home = path.join(root, 'rag');
  const rag = new RagService({ domes: () => [dome], home, env: process.env,
    embedderFactory: cfg => new HashEmbedder(64, cfg, cfg.model) });
  const put = (p: string, text: string) => {
    const full = path.join(vault, p);
    fs.mkdirSync(path.dirname(full), { recursive: true });
    fs.writeFileSync(full, text);
  };
  const query = (q: string, includeStale = false) => rag.search({ queries: [q], domes: [name], mode: 'bm25', k: 20, includeStale });
  const store = () => FlatVectorStore.load(path.join(domeDir(home, name), readActive(home, name).active!));
  return { root, vault, dome, home, rag, put, query, store };
}

export function config(vault: string, level: 'N2' | 'N3' = 'N2'): VaultConfig {
  return { name: 'audit', path: vault, confidentiality: level, allowedExtensions: [], deniedPaths: [], maxDepth: 10, maxFileSize: 1024 * 1024 };
}

export const paths = (r: any): string[] => r.results[0].hits.map((h: any) => h.path);
