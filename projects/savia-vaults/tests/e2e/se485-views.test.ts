// SE-485 R1/R5 por MCP stdio: backlinks por nombre, includeStale en vault_search, `stale` en
// vault_read y exactMatch/aviso en vault_search y vault_rag.
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

describe('SE-485 MCP', () => {
  it('backlinks por nombre, includeStale, stale en vault_read, exactMatch', async () => {
    const root = fs.mkdtempSync(path.join(os.tmpdir(), 'savia-mcp-se485-'));
    folders.push(root);
    const vault = path.join(root, 'D');
    fs.mkdirSync(vault);
    const put = (p: string, s: string) => fs.writeFileSync(path.join(vault, p), s);
    put('destino.md', '# Destino\nzafiro destino');
    put('enlaza.md', '# Enlaza\nzafiro enlace [[destino]]');
    put('oculta.md', '---\nconfidentiality: N3\n---\n# Oculta\nzafiro [[destino]]');
    put('vieja.md', '---\nstatus: deprecated\n---\n# Vieja\nzafiro obsoleta');
    put('caducada.md', '---\nvalid_until: 2000-01-01\n---\n# Caducada\nzafiro caducada');
    put('contrato.md', '# Contrato\nCT-2026-047: contrato sintético.');
    put('vecino.md', '# Vecino\nCT-2026-048: contrato sintético.');
    const schemaDir = path.join(root, 'schema');
    fs.mkdirSync(schemaDir);
    fs.writeFileSync(path.join(schemaDir, 'document.yaml'), 'type: document\nlabel: Documento\nproperties:\n  title: {type: string}\n');
    const registry = path.join(root, 'domes.json');
    fs.writeFileSync(registry, JSON.stringify({ version: 1, defaultDome: 'D', domes: {
      D: { name: 'D', path: vault, description: '', confidentiality: 'N2', schemaDir, rag: { enabled: true, inlineSyncBudget: 0 } },
    } }));
    const transport = new StdioClientTransport({
      command: process.execPath,
      args: ['--import', pathToFileURL(path.resolve('node_modules/tsx/dist/loader.mjs')).href, path.resolve('src/cli/index.ts'), 'serve', '--transport', 'mcp', '--domes', registry],
      cwd: root,
      env: { PATH: process.env.PATH || '', HOME: root, SAVIA_RAG_HOME: path.join(root, 'rag'), SAVIA_RAG_TEST_PROVIDER: 'hash', SAVIA_SEARCH_CACHE: path.join(root, 'sc') },
    });
    const client = new Client({ name: 'se485-e2e', version: '1' });
    await client.connect(transport);
    try {
      const call = (name: string, args: Record<string, unknown> = {}) => client.callTool({ name, arguments: args });
      // R1: [[destino]] resuelve a destino.md; la nota oculta no aparece.
      const read = JSON.parse(text(await call('vault_read', { path: 'destino.md' })));
      expect(read.backlinks.map((b: { source: string }) => b.source)).toEqual(['enlaza.md']);
      expect(read).not.toHaveProperty('stale');
      // R5: lectura directa de una obsoleta sigue sirviendo, con el motivo.
      const old = JSON.parse(text(await call('vault_read', { path: 'vieja.md' })));
      expect(old.content).toContain('obsoleta');
      expect(old.stale).toBe('status:deprecated');
      const expired = JSON.parse(text(await call('vault_read', { path: 'caducada.md' })));
      expect(expired.stale).toBe('valid_until:2000-01-01');
      // R5: includeStale:false excluye; true incluye.
      const paths = async (extra: Record<string, unknown>) =>
        (JSON.parse(text(await call('vault_search', { query: 'zafiro', ...extra }))) as { path: string }[]).map(r => r.path);
      const off = await paths({ includeStale: false });
      expect(off).not.toContain('vieja.md');
      expect(off).not.toContain('caducada.md');
      expect(off).toContain('destino.md');
      expect(await paths({ includeStale: true })).toEqual(expect.arrayContaining(['vieja.md', 'caducada.md']));
      // R4: vault_search y vault_rag.
      const none = JSON.parse(text(await call('vault_search', { query: 'CT-2099-999' }))) as any[];
      expect(none.length).toBeGreaterThan(0);
      expect(none.every(h => h.exactMatch === false && h.warnings.join(' ').includes('identificador no encontrado literalmente'))).toBe(true);
      const found = JSON.parse(text(await call('vault_search', { query: 'CT-2026-047' }))) as any[];
      expect(found[0]).toMatchObject({ path: 'contrato.md', exactMatch: true });
      const rag = JSON.parse(text(await call('vault_rag', { query: 'CT-2099-999', mode: 'bm25' })));
      expect(rag.results[0].hits.every((h: any) => h.exactMatch === false)).toBe(true);
      expect(rag.results[0].warnings.join(' ')).toContain('identificador no encontrado literalmente');
      const ragOk = JSON.parse(text(await call('vault_rag', { query: 'CT-2026-047', mode: 'bm25' })));
      expect(ragOk.results[0].hits[0]).toMatchObject({ path: 'contrato.md', exactMatch: true });
    } finally {
      await client.close();
    }
  }, 90_000);
});
