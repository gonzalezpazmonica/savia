// SE-481 AC-1/AC-2/AC-6 — e2e MCP stdio: una nota con clasificación explícita no interpretable
// (`[N4`, N7, [N2], anchura cero) en una cúpula N2 no sale por vault_read, vault_list,
// vault_search, vault_rag, vault_graph, vault_query, backlinks ni vault_stats; vault_health la
// cuenta por código sin rutas; vault_write rechaza escribirla. Fixture: eval/fixtures/malformed-meta.json.
import { afterEach, describe, expect, it } from 'vitest';
import { Client } from '@modelcontextprotocol/sdk/client/index.js';
import { StdioClientTransport } from '@modelcontextprotocol/sdk/client/stdio.js';
import * as fs from 'node:fs';
import * as os from 'node:os';
import * as path from 'node:path';
import { pathToFileURL } from 'node:url';

const folders: string[] = [];
afterEach(() => { for (const f of folders.splice(0)) fs.rmSync(f, { recursive: true, force: true }); });
const text = (r: any) => (r.content as { text: string }[])[0].text;

const fixture = JSON.parse(fs.readFileSync(path.resolve('eval/fixtures/malformed-meta.json'), 'utf-8')) as {
  notes: Record<string, { content: string; diagnostic?: string }>;
};
const bad = Object.entries(fixture.notes).filter(([, n]) => n.diagnostic);
const canary = (c: string) => c.match(/CANARIO-[A-Z0-9]+/)![0];

describe('SE-481 MCP cuarentena', () => {
  it('ninguna herramienta sirve una nota en cuarentena; health cuenta por código; write la rechaza', async () => {
    const root = fs.mkdtempSync(path.join(os.tmpdir(), 'savia-mcp-se481-'));
    folders.push(root);
    const vault = path.join(root, 'D');
    for (const [p, n] of Object.entries(fixture.notes)) {
      fs.mkdirSync(path.dirname(path.join(vault, p)), { recursive: true });
      fs.writeFileSync(path.join(vault, p), `${n.content}\nEnlace a [[n2]].\n`);
    }
    const schemaDir = path.join(root, 'schema');
    fs.mkdirSync(schemaDir);
    fs.writeFileSync(path.join(schemaDir, 'document.yaml'), 'type: document\nlabel: Documento\nproperties:\n  title: {type: string}\n');
    const registry = path.join(root, 'domes.json');
    fs.writeFileSync(registry, JSON.stringify({ version: 1, defaultDome: 'D', domes: {
      D: { name: 'D', path: vault, description: '', confidentiality: 'N2', schemaDir, rag: { enabled: true } },
    } }));
    const transport = new StdioClientTransport({
      command: process.execPath,
      args: ['--import', pathToFileURL(path.resolve('node_modules/tsx/dist/loader.mjs')).href, path.resolve('src/cli/index.ts'), 'serve', '--transport', 'mcp', '--domes', registry],
      cwd: root,
      env: { PATH: process.env.PATH || '', HOME: root, SAVIA_RAG_HOME: path.join(root, 'rag'), SAVIA_RAG_TEST_PROVIDER: 'hash', SAVIA_SEARCH_CACHE: path.join(root, 'sc') },
    });
    const client = new Client({ name: 'se481-e2e', version: '1' });
    await client.connect(transport);
    try {
      const call = (name: string, args: Record<string, unknown> = {}) => client.callTool({ name, arguments: args });
      const listed = JSON.parse(text(await call('vault_list'))) as string[];
      const pub = text(await call('vault_read', { path: 'ok/n2.md' })); // backlinks de la nota abierta
      const graph = text(await call('vault_graph', { action: 'search', query: 'mal' }));
      expect(text(await call('vault_graph', { action: 'search', query: 'ok' }))).toContain('ok/n2.md'); // la búsqueda del grafo funciona
      for (const [p, n] of bad) {
        const word = canary(n.content);
        const read = await call('vault_read', { path: p });
        expect(read.isError, p).toBe(true);
        expect(text(read)).toMatch(/Note not found/);
        expect(listed).not.toContain(p);
        expect(text(await call('vault_search', { query: word }))).not.toContain(p);
        expect(pub).not.toContain(p);
        expect(pub).not.toContain(word);
        expect(graph).not.toContain(p);
        const q = text(await call('vault_query', { expression: word }));
        expect(q).not.toContain(p);
        const rag = JSON.parse(text(await call('vault_rag', { query: word, mode: 'bm25', fields: 'full' })));
        expect(JSON.stringify(rag.results[0].hits)).not.toContain(word);
        expect(JSON.stringify(rag.results[0].hits)).not.toContain(p);
      }
      expect(listed).toContain('ok/n2.md'); // caso negativo: lo válido sí se sirve
      const stats = JSON.parse(text(await call('vault_stats')));
      expect(stats).toMatchObject({ quarantined: bad.length, outOfLevel: 1 });
      const health = text(await call('vault_health'));
      const counts = JSON.parse(health.match(/quarantine: (\{.*\})/)![1]);
      expect(counts).toEqual({ total: 5, byCode: { 'yaml-unparsable': 1, 'unknown-level': 2, 'non-string': 1, 'forbidden-char': 1 } });
      expect(health).not.toMatch(/mal\/|CANARIO|Reservada/);
      for (const [p, n] of bad) {
        const target = `nueva/${path.basename(p)}`;
        const w = await call('vault_write', { path: target, content: n.content });
        expect(w.isError, p).toBe(true);
        expect(text(w)).toMatch(/INVALID_CLASSIFICATION/);
        expect(fs.existsSync(path.join(vault, target))).toBe(false);
      }
    } finally {
      await client.close();
    }
  }, 90_000);
});
