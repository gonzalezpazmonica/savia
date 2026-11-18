// SE-424 H5 — por MCP (stdio real), un permiso sobre una cúpula N1 no da acceso a la N4 vecina con
// rutas relativas, absolutas ni enlaces: el nivel y el permiso se deciden por la cúpula de destino real.
import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { Client } from '@modelcontextprotocol/sdk/client/index.js';
import { StdioClientTransport } from '@modelcontextprotocol/sdk/client/stdio.js';
import * as fs from 'node:fs';
import * as os from 'node:os';
import * as path from 'node:path';
import { UserStore } from '../../src/auth/store.js';

const cli = path.resolve('node_modules/tsx/dist/cli.mjs');
const source = path.resolve('src/cli/index.ts');

describe('SE-424 H5: contención entre cúpulas por MCP (stdio real)', () => {
  let tmp: string;
  let client: Client;

  const call = async (name: string, args: Record<string, unknown>) => {
    const r = await client.callTool({ name, arguments: args });
    return { error: !!r.isError, text: (r.content as { text: string }[])[0]?.text ?? '' };
  };

  beforeEach(async () => {
    tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'savia-mcp-contain-'));
    for (const d of ['Pub', 'Sec']) fs.mkdirSync(path.join(tmp, d));
    fs.writeFileSync(path.join(tmp, 'Pub', 'nota.md'), '# Pub\ncontenido-publico\n');
    fs.writeFileSync(path.join(tmp, 'Sec', 'secreto.md'), '# Sec\ncontenido-secreto-n4\n');
    fs.writeFileSync(path.join(tmp, 'domes.json'), JSON.stringify({ version: 1, defaultDome: 'Pub', domes: {
      Pub: { name: 'Pub', path: path.join(tmp, 'Pub'), description: '', confidentiality: 'N1' },
      Sec: { name: 'Sec', path: path.join(tmp, 'Sec'), description: '', confidentiality: 'N4' },
    } }));
    const s = new UserStore(path.join(tmp, 'savia-vaults.users.json'));
    const token = s.createUser('ana');
    s.setPermission('ana', 'Pub', 'writer');
    s.save();
    const transport = new StdioClientTransport({
      command: process.execPath,
      args: [cli, source, 'serve', '--transport', 'mcp', '--domes', path.join(tmp, 'domes.json')],
      cwd: tmp,
      env: { ...process.env, HOME: tmp, SAVIA_AUTH_TOKEN: token } as Record<string, string>,
      stderr: 'ignore',
    });
    client = new Client({ name: 'se424-h5', version: '1.0.0' });
    await client.connect(transport);
  }, 30_000);

  afterEach(async () => {
    await client.close();
    fs.rmSync(tmp, { recursive: true, force: true });
  });

  it('con permiso en N1: lectura, escritura y comparación no alcanzan la N4', async () => {
    // Control: sin permiso directo en la N4.
    expect((await call('vault_read', { vault: 'Sec', path: 'secreto.md' })).error).toBe(true);
    // Control positivo: la N1 propia funciona.
    expect((await call('vault_read', { vault: 'Pub', path: 'nota.md' })).text).toContain('contenido-publico');

    fs.symlinkSync(path.join(tmp, 'Sec'), path.join(tmp, 'Pub', 'atajo'));
    for (const p of ['../Sec/secreto.md', path.join(tmp, 'Sec', 'secreto.md'), '..\\Sec\\secreto.md', 'atajo/secreto.md']) {
      const r = await call('vault_read', { vault: 'Pub', path: p });
      expect(r.error, p).toBe(true);
      expect(r.text, p).not.toContain('contenido-secreto-n4');
      expect((await call('vault_diff', { vault: 'Pub', path: p })).error, p).toBe(true);
    }
    for (const p of ['../Sec/inyectado.md', 'atajo/inyectado.md', path.join(tmp, 'Sec', 'inyectado.md')]) {
      expect((await call('vault_write', { vault: 'Pub', path: p, content: '# x\n' })).error, p).toBe(true);
    }
    expect(fs.readdirSync(path.join(tmp, 'Sec')).sort()).toEqual(['secreto.md']);
    // Escritura legítima en la N1 sigue funcionando.
    expect((await call('vault_write', { vault: 'Pub', path: 'nueva.md', content: '# nueva\n' })).error).toBe(false);
  }, 60_000);
});
