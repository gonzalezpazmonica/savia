// vault_write con avisos no bloqueantes y errores con how_to_proceed, por MCP stdio real.
import { afterEach, describe, expect, it } from 'vitest';
import { Client } from '@modelcontextprotocol/sdk/client/index.js';
import { StdioClientTransport } from '@modelcontextprotocol/sdk/client/stdio.js';
import * as fs from 'node:fs';
import * as os from 'node:os';
import * as path from 'node:path';
import { pathToFileURL } from 'node:url';

const folders: string[] = [];
afterEach(() => { for (const f of folders.splice(0)) fs.rmSync(f, { recursive: true, force: true }); });
const text = (r: any, i = 0) => (r.content as { text: string }[])[i].text;

describe('vault_write avisos y how_to_proceed (MCP)', () => {
  it('escribe siempre; avisa sin revelar la nota N4; errores con how_to_proceed', async () => {
    const root = fs.mkdtempSync(path.join(os.tmpdir(), 'savia-mcp-warn-'));
    folders.push(root);
    const vault = path.join(root, 'D');
    fs.mkdirSync(vault);
    fs.writeFileSync(path.join(vault, 'reservada.md'), '---\nconfidentiality: N4\n---\n# Titulo Reservado Garceta\n');
    fs.writeFileSync(path.join(vault, 'abierta.md'), '# Abierta\n\nTexto.\n');
    const registry = path.join(root, 'domes.json');
    fs.writeFileSync(registry, JSON.stringify({ version: 1, defaultDome: 'D', domes: {
      D: { name: 'D', path: vault, description: '', confidentiality: 'N2', rag: { enabled: true } },
    } }));
    const transport = new StdioClientTransport({
      command: process.execPath,
      args: ['--import', pathToFileURL(path.resolve('node_modules/tsx/dist/loader.mjs')).href, path.resolve('src/cli/index.ts'), 'serve', '--transport', 'mcp', '--domes', registry],
      cwd: root,
      env: { PATH: process.env.PATH || '', HOME: root, SAVIA_RAG_HOME: path.join(root, 'rag'), SAVIA_RAG_TEST_PROVIDER: 'hash', SAVIA_SEARCH_CACHE: path.join(root, 'sc') },
    });
    const client = new Client({ name: 'warn-e2e', version: '1' });
    await client.connect(transport);
    try {
      const call = (name: string, args: Record<string, unknown> = {}) => client.callTool({ name, arguments: args });
      // Duplicado con la nota N4 (no se revela), enlace roto y vecina enlazada.
      const w = await call('vault_write', { path: 'nueva.md', content: '# Titulo Reservado Garceta\n\n[[abierta]] [[no-existe]]\n' });
      expect(w.isError).toBeFalsy();
      const body = JSON.parse(text(w));
      expect(body.contentHash).toBeTruthy();
      expect(fs.existsSync(path.join(vault, 'nueva.md'))).toBe(true);
      const codes = body.warnings.map((x: any) => x.code);
      expect(codes).toContain('BROKEN_WIKILINK');
      expect(codes).toContain('NEIGHBOR_NOTE');
      expect(codes).not.toContain('DUPLICATE_TITLE');
      expect(JSON.stringify(body.warnings)).not.toContain('reservada');
      expect(body.warnings_unavailable).toBeUndefined();

      const nf = await call('vault_read', { path: 'reservada.md' });
      expect(nf.isError).toBe(true);
      expect(text(nf)).toMatch(/Note not found/); // texto original intacto
      expect(text(nf, 1)).toMatch(/how_to_proceed: .*vault_search/);
      expect((nf as any).how_to_proceed).toMatch(/vault_search/);

      const dome = await call('vault_read', { vault: 'X', path: 'a.md' });
      expect(text(dome)).toMatch(/Dome "X" not found/);
      expect(text(dome, 1)).toMatch(/vault_domes/);

      const pol = await call('vault_write', { path: 'n2.md', content: '---\nconfidentiality: N3\n---\nx\n' });
      expect(text(pol)).toMatch(/POLICY_DENIED/);
      expect(text(pol, 1)).toMatch(/how_to_proceed: /);

      const bad = await call('vault_write', { path: '/abs.md', content: 'x' });
      expect(bad.isError).toBe(true);
      expect(text(bad, 1)).toMatch(/ruta relativa/);
    } finally {
      await client.close();
    }
  }, 60_000);

  it('modo de una sola cúpula (--path, almacén sin nivel): el filtro propio de los avisos oculta la nota N4', async () => {
    const root = fs.mkdtempSync(path.join(os.tmpdir(), 'savia-mcp-warn1-'));
    folders.push(root);
    const vault = path.join(root, 'V');
    fs.mkdirSync(vault);
    fs.writeFileSync(path.join(vault, 'reservada.md'), '---\nconfidentiality: N4\n---\n# Titulo Reservado Garceta\n');
    fs.writeFileSync(path.join(vault, 'abierta.md'), '# Abierta\n');
    const transport = new StdioClientTransport({
      command: process.execPath,
      args: ['--import', pathToFileURL(path.resolve('node_modules/tsx/dist/loader.mjs')).href, path.resolve('src/cli/index.ts'), 'serve', '--transport', 'mcp', '--path', vault],
      cwd: root,
      env: { PATH: process.env.PATH || '', HOME: root, SAVIA_RAG_HOME: path.join(root, 'rag'), SAVIA_RAG_TEST_PROVIDER: 'hash', SAVIA_SEARCH_CACHE: path.join(root, 'sc') },
    });
    const client = new Client({ name: 'warn-e2e-1', version: '1' });
    await client.connect(transport);
    try {
      const w = await client.callTool({ name: 'vault_write', arguments: { path: 'nueva.md', content: '# Titulo Reservado Garceta\n\n[[abierta]] [[reservada]]\n' } });
      expect(w.isError).toBeFalsy();
      const body = JSON.parse(text(w));
      expect(body.warnings_unavailable).toBeUndefined();
      const codes = body.warnings.map((x: any) => x.code);
      expect(codes).toContain('NEIGHBOR_NOTE'); // los avisos sí se calculan
      expect(codes).not.toContain('DUPLICATE_TITLE');
      expect(JSON.stringify(body.warnings.filter((x: any) => x.code !== 'BROKEN_WIKILINK'))).not.toContain('reservada');
    } finally {
      await client.close();
    }
  }, 60_000);
});
