import { afterEach, describe, expect, it } from 'vitest';
import { Client } from '@modelcontextprotocol/sdk/client/index.js';
import { StdioClientTransport } from '@modelcontextprotocol/sdk/client/stdio.js';
import { spawn, type ChildProcess } from 'node:child_process';
import * as fs from 'node:fs';
import * as net from 'node:net';
import * as os from 'node:os';
import * as path from 'node:path';

const cli = path.resolve('node_modules/tsx/dist/cli.mjs');
const source = path.resolve('src/cli/index.ts');
const LIVE_TOKEN = 'live-'.padEnd(40, 'x');
const temporaryPaths: string[] = [];
const children: ChildProcess[] = [];

function temporaryVault(prefix: string): string {
  const vault = fs.mkdtempSync(path.join(os.tmpdir(), prefix));
  temporaryPaths.push(vault);
  return vault;
}

async function availablePort(): Promise<number> {
  const server = net.createServer();
  await new Promise<void>((resolve) => server.listen(0, '127.0.0.1', resolve));
  const address = server.address();
  const port = typeof address === 'object' && address ? address.port : 0;
  await new Promise<void>((resolve, reject) => server.close((error) => error ? reject(error) : resolve()));
  return port;
}

afterEach(() => {
  for (const child of children.splice(0)) child.kill();
  for (const temporaryPath of temporaryPaths.splice(0)) {
    fs.rmSync(temporaryPath, { recursive: true, force: true });
  }
});

describe('live transport processes', () => {
  it('serves MCP tools over stdio with durable CRUD and search', async () => {
    const vault = temporaryVault('savia-mcp-live-');
    const transport = new StdioClientTransport({
      command: process.execPath,
      args: [cli, source, 'serve', '--transport', 'mcp', '--path', vault],
    });
    const client = new Client({ name: 'savia-vaults-e2e', version: '1.0.0' });

    try {
      await client.connect(transport);
      const tools = await client.listTools();
      expect(tools.tools.map((tool) => tool.name)).toContain('vault_write');

      const write = await client.callTool({
        name: 'vault_write',
        arguments: { path: 'proof.md', content: '# Live proof\nMCP persistence token alpha-731' },
      });
      expect(write.isError).not.toBe(true);
      expect(fs.existsSync(path.join(vault, 'proof.md'))).toBe(true);

      const read = await client.callTool({ name: 'vault_read', arguments: { path: 'proof.md' } });
      expect(JSON.stringify(read.content)).toContain('alpha-731');

      const search = await client.callTool({ name: 'vault_search', arguments: { query: 'alpha-731' } });
      expect(JSON.stringify(search.content)).toContain('proof.md');
    } finally {
      await client.close();
    }
  }, 20_000);

  it('serves A2A health, write, search, and read over HTTP', async () => {
    const vault = temporaryVault('savia-a2a-live-');
    const port = await availablePort();
    const child = spawn(process.execPath, [
      cli, source, 'serve', '--transport', 'a2a', '--host', '127.0.0.1',
      '--port', String(port), '--path', vault,
    ], { stdio: ['ignore', 'ignore', 'pipe'], env: { ...process.env, SAVIA_VAULTS_TOKEN: LIVE_TOKEN } });
    children.push(child);
    const base = `http://127.0.0.1:${port}`;
    // SE-424 H5: A2A no escribe sin credencial; en bucle local vale el secreto del servicio.
    const auth = { Authorization: `Bearer ${LIVE_TOKEN}` };

    let health: Response | undefined;
    for (let attempt = 0; attempt < 50; attempt++) {
      try {
        health = await fetch(`${base}/health`, { headers: auth });
        if (health.ok) break;
      } catch {
        // Process startup is asynchronous.
      }
      await new Promise((resolve) => setTimeout(resolve, 100));
    }
    expect(health?.ok).toBe(true);

    const share = await fetch(`${base}/share`, {
      method: 'POST',
      headers: { 'content-type': 'application/json', ...auth },
      body: JSON.stringify({ path: 'proof.md', content: '# Live proof\nA2A persistence token beta-947' }),
    });
    expect(share.ok).toBe(true);
    expect(fs.existsSync(path.join(vault, 'proof.md'))).toBe(true);

    const search = await (await fetch(`${base}/search?q=beta-947`, { headers: auth })).json() as { results: Array<{ path: string }> };
    expect(search.results.some((result) => result.path === 'proof.md')).toBe(true);

    const read = await fetch(`${base}/context/note/proof.md`, { headers: auth });
    expect(read.ok).toBe(true);
    expect(await read.text()).toContain('beta-947');
  }, 20_000);
});
