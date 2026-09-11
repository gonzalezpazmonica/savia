import { afterEach, describe, expect, it } from 'vitest';
import { Client } from '@modelcontextprotocol/sdk/client/index.js';
import { StdioClientTransport } from '@modelcontextprotocol/sdk/client/stdio.js';
import { UserStore } from '../../src/auth/store.js';
import * as fs from 'node:fs';
import * as os from 'node:os';
import * as path from 'node:path';
import { pathToFileURL } from 'node:url';

const folders: string[] = [];
afterEach(() => { for (const folder of folders.splice(0)) fs.rmSync(folder, { recursive: true, force: true }); });

describe('SE-396 selected dome governs knowledge tools', () => {
  it('a reader of B cannot retrieve A through the global graph/query/introspection', async () => {
    const root = fs.mkdtempSync(path.join(os.tmpdir(), 'savia-dome-isolation-'));
    folders.push(root);
    const schema = path.join(root, 'schema');
    fs.mkdirSync(schema);
    const domes: Record<string, unknown> = {};
    for (const name of ['a', 'b']) {
      const folder = path.join(root, name);
      fs.mkdirSync(folder);
      fs.writeFileSync(path.join(folder, `${name}.md`), `---\nentity:\n  id: sentinel-${name}\n  type: document\n---\n# sentinel-${name}\n`);
      domes[name] = { name, path: folder, description: '', confidentiality: 'N2', schemaDir: schema };
    }
    const registry = path.join(root, 'domes.json');
    fs.writeFileSync(registry, JSON.stringify({ version: 1, defaultDome: 'a', domes }));
    const users = new UserStore(path.join(root, 'savia-vaults.users.json'));
    const token = users.createUser('reader-b');
    users.setPermission('reader-b', 'b', 'reader');
    users.save();
    const loader = pathToFileURL(path.resolve('node_modules/tsx/dist/loader.mjs')).href;
    const transport = new StdioClientTransport({
      command: process.execPath,
      args: ['--import', loader, path.resolve('src/cli/index.ts'), 'serve', '--transport', 'mcp', '--domes', registry],
      cwd: root, env: { PATH: process.env.PATH || '', SAVIA_AUTH_TOKEN: token },
    });
    const client = new Client({ name: 'isolation-test', version: '1' });
    try {
      await client.connect(transport);
      const denied = await client.callTool({ name: 'vault_graph', arguments: { vault: 'a', action: 'search', query: 'sentinel' } });
      expect(denied.isError).toBe(true);
      const graph = await client.callTool({ name: 'vault_graph', arguments: { vault: 'b', action: 'search', query: 'sentinel' } });
      expect(graph.isError).not.toBe(true);
      expect(JSON.stringify(graph.content)).toContain('sentinel-b');
      expect(JSON.stringify(graph.content)).not.toContain('sentinel-a');
      const query = await client.callTool({ name: 'vault_query', arguments: { vault: 'b', expression: 'sentinel-a.type' } });
      expect(JSON.stringify(query.content)).not.toContain('node:sentinel-a');
      const introspection = await client.callTool({ name: 'vault_introspect', arguments: { vault: 'b' } });
      expect(JSON.stringify(introspection.content)).not.toContain('sentinel-a');
      // Rebuild after content removal: an old graph snapshot cannot resurrect it.
      fs.unlinkSync(path.join(root, 'b/b.md'));
      const after = await client.callTool({ name: 'vault_graph', arguments: { vault: 'b', action: 'search', query: 'sentinel-b' } });
      expect(JSON.stringify(after.content)).not.toContain('sentinel-b');
    } finally {
      await client.close();
    }
  }, 20000);
});
