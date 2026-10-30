// SE-489 — e2e MCP por stdio: vault_rag sin `route` responde igual que el pipeline por defecto
// (AC-4); con `route: "M0"` da los mismos hits más evidence/trace/consumed; errores de contrato.
import { afterEach, describe, expect, it } from 'vitest';
import { Client } from '@modelcontextprotocol/sdk/client/index.js';
import { StdioClientTransport } from '@modelcontextprotocol/sdk/client/stdio.js';
import * as fs from 'node:fs';
import * as os from 'node:os';
import * as path from 'node:path';
import { pathToFileURL } from 'node:url';
import { RagService } from '../../src/rag/service.js';
import { HashEmbedder } from '../../src/rag/embedder.js';
import { formatRagResponse } from '../../src/rag/format.js';
import type { RagDomeRef } from '../../src/rag/service.js';

const folders: string[] = [];
afterEach(() => { for (const f of folders.splice(0)) fs.rmSync(f, { recursive: true, force: true }); });

const long = (s: string) => `${s}. `.repeat(12);
const text = (r: any) => (r.content as { text: string }[])[0].text;

async function start() {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'savia-mcp-route-'));
  folders.push(root);
  const domes: Record<string, unknown> = {};
  const content: Record<string, Record<string, string>> = {
    docs: { 'rules/merge.md': `# Merge\n\n${long('nunca merge sin permiso expreso de la operadora')}`, 'rules/SE-481.md': `# SE-481\n\n${long('cierre seguro SE-481')}` },
    learn: { 'l/leccion.md': `# Lección\n\n${long('merge sin permiso rompe la confianza del equipo')}` },
  };
  for (const [name, files] of Object.entries(content)) {
    const folder = path.join(root, name);
    for (const [p, c] of Object.entries(files)) {
      fs.mkdirSync(path.dirname(path.join(folder, p)), { recursive: true });
      fs.writeFileSync(path.join(folder, p), c);
    }
    domes[name] = { name, path: folder, description: '', confidentiality: 'N2', rag: { enabled: true } };
  }
  const registry = path.join(root, 'domes.json');
  fs.writeFileSync(registry, JSON.stringify({ version: 1, defaultDome: 'docs', domes }));
  const env: Record<string, string> = { PATH: process.env.PATH || '', SAVIA_RAG_HOME: path.join(root, 'rag-home'), SAVIA_RAG_TEST_PROVIDER: 'hash' };
  const loader = pathToFileURL(path.resolve('node_modules/tsx/dist/loader.mjs')).href;
  const transport = new StdioClientTransport({
    command: process.execPath,
    args: ['--import', loader, path.resolve('src/cli/index.ts'), 'serve', '--transport', 'mcp', '--domes', registry],
    cwd: root, env,
  });
  const client = new Client({ name: 'route-e2e', version: '1' });
  await client.connect(transport);
  // El mismo índice leído en proceso con RagService: la referencia del pipeline por defecto.
  const refs: RagDomeRef[] = Object.keys(content).map(name => ({ name, path: path.join(root, name), confidentiality: 'N2', rag: { enabled: true } }));
  const direct = new RagService({ domes: () => refs, home: env.SAVIA_RAG_HOME, env: { SAVIA_RAG_TEST_PROVIDER: 'hash' }, embedderFactory: (cfg) => new HashEmbedder(256, cfg, `hash:${cfg.model.replace(/^hash:/, '')}`) });
  return Object.assign(client, { direct });
}

const noTime = (body: any) => JSON.parse(JSON.stringify(body, (k, v) => (k === 'totalMs' || k === 'timings' ? undefined : v)));
/** Hits sin texto (el recorte por maxChars depende del tamaño total de la respuesta) y prefijo del texto. */
const sameHits = (a: any[], b: any[]) => {
  expect(a.map(({ text: _t, ...h }) => h)).toEqual(b.map(({ text: _t, ...h }) => h));
  a.forEach((h, i) => {
    const [x, y] = [h.text.replace(/…$/, ''), b[i].text.replace(/…$/, '')];
    expect(x.startsWith(y) || y.startsWith(x)).toBe(true);
  });
};

describe('SE-489 vault_rag con route', () => {
  it('sin route = pipeline por defecto; con route M0 = mismos hits más evidencia', async () => {
    const client = await start();
    try {
      const tool = (await client.listTools()).tools.find(t => t.name === 'vault_rag')!;
      expect(Object.keys((tool.inputSchema as any).properties)).toEqual(expect.arrayContaining(['route', 'budget', 'seed', 'asOf']));
      for (const d of ['docs', 'learn']) await client.callTool({ name: 'vault_rag_sync', arguments: { dome: d } });

      for (const args of [
        { queries: ['merge sin permiso', 'confianza equipo'], domes: '*' },
        { query: 'SE-481', domes: ['docs'], mode: 'bm25' },
        { query: 'merge', domes: ['docs', 'learn'], k: 2, fields: 'full' },
      ]) {
        const raw = text(await client.callTool({ name: 'vault_rag', arguments: args }));
        const plain = JSON.parse(raw);
        // AC-4: sin route, la respuesta es la de RagService.search con el mismo formato.
        const a = args as any;
        const ref = await client.direct.search({ queries: a.queries ?? [a.query], domes: a.domes, k: a.k, mode: a.mode });
        expect(noTime(plain)).toEqual(noTime(JSON.parse(formatRagResponse(ref, { fields: a.fields === 'full' ? 'full' : 'lean', maxChars: 6000 }))));
        expect(plain.route).toBeUndefined();
        expect(plain.results.every((r: any) => r.evidence === undefined && r.trace === undefined && r.consumed === undefined)).toBe(true);
        const routed = JSON.parse(text(await client.callTool({ name: 'vault_rag', arguments: { ...args, route: 'M0' } })));
        expect(routed.route).toBe('M0');
        expect(routed.results[0].trace.route).toBe('M0');
        expect(routed.results[0].evidence.length).toBe(routed.results[0].hits.length);
        routed.results.forEach((r: any, i: number) => sameHits(r.hits, plain.results[i].hits));
        expect(routed.domes).toEqual(plain.domes);
        expect(routed.fusion).toEqual(plain.fusion);
      }
    } finally { await client.close(); }
  }, 60_000);

  it('errores de contrato: ruta desconocida, presupuesto inválido, as_of inválido', async () => {
    const client = await start();
    try {
      await client.callTool({ name: 'vault_rag_sync', arguments: { dome: 'docs' } });
      const cases: [Record<string, unknown>, RegExp][] = [
        [{ route: 'M99' }, /UNKNOWN_ROUTE/],
        [{ route: 'M0', budget: { maxNodes: -1 } }, /INVALID_BUDGET/],
        [{ route: 'M0', budget: { fooBar: 1 } }, /INVALID_BUDGET/],
        [{ route: 'M0', asOf: 'mañana' }, /INVALID_INPUT/],
        [{ route: 7 }, /UNKNOWN_ROUTE/],
      ];
      for (const [extra, re] of cases) {
        const r = await client.callTool({ name: 'vault_rag', arguments: { query: 'merge', domes: ['docs'], ...extra } });
        expect(r.isError).toBe(true);
        expect(text(r)).toMatch(re);
      }
    } finally { await client.close(); }
  }, 60_000);
});
