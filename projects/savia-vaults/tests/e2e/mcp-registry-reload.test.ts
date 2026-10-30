// SE-480 — e2e: el MCP en marcha ve los cambios del registro sin reiniciar (AC-1, AC-2, AC-3)
// y el servicio A2A con --rag-autosync sincroniza solo (R2, AC-8).
import { afterEach, describe, expect, it } from 'vitest';
import { Client } from '@modelcontextprotocol/sdk/client/index.js';
import { StdioClientTransport } from '@modelcontextprotocol/sdk/client/stdio.js';
import { spawn, spawnSync, type ChildProcess } from 'node:child_process';
import * as fs from 'node:fs';
import * as net from 'node:net';
import * as os from 'node:os';
import * as path from 'node:path';
import { pathToFileURL } from 'node:url';

const folders: string[] = [];
const procs: ChildProcess[] = [];
const clients: Client[] = [];
afterEach(async () => {
  for (const c of clients.splice(0)) await c.close().catch(() => {});
  for (const p of procs.splice(0)) p.kill();
  for (const f of folders.splice(0)) fs.rmSync(f, { recursive: true, force: true });
});

const long = (s: string) => `${s}. `.repeat(12);
const text = (r: any) => (r.content as { text: string }[])[0].text;
const loader = pathToFileURL(path.resolve('node_modules/tsx/dist/loader.mjs')).href;
const cli = path.resolve('src/cli/index.ts');

function setup() {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'savia-reload-e2e-'));
  folders.push(root);
  for (const n of ['docs', 'learn']) {
    fs.mkdirSync(path.join(root, n));
    fs.writeFileSync(path.join(root, n, 'n.md'), `# Nota ${n}\n\n${long(`contenido de ${n}`)}`);
  }
  const registry = path.join(root, 'domes.json');
  const write = (domes: Record<string, object>) => {
    fs.writeFileSync(registry, JSON.stringify({ version: 1, defaultDome: 'docs', domes }));
    const t = new Date(Date.now() + (++write.n) * 5000);
    fs.utimesSync(registry, t, t);
  };
  write.n = 0;
  const entry = (n: string, rag: object) => ({ name: n, path: path.join(root, n), description: '', confidentiality: 'N2', rag });
  const env = { PATH: process.env.PATH || '', SAVIA_RAG_HOME: path.join(root, 'rag-home'), SAVIA_RAG_TEST_PROVIDER: 'hash', SAVIA_VAULTS_RELOAD_MS: '0' };
  return { root, registry, write, entry, env };
}

async function mcp(s: ReturnType<typeof setup>) {
  const client = new Client({ name: 'reload-e2e', version: '1' });
  await client.connect(new StdioClientTransport({
    command: process.execPath, args: ['--import', loader, cli, 'serve', '--transport', 'mcp', '--domes', s.registry], cwd: s.root, env: s.env,
  }));
  clients.push(client);
  return client;
}

const status = async (c: Client, domes?: string[]) =>
  JSON.parse(text(await c.callTool({ name: 'vault_rag_status', arguments: domes ? { domes } : {} }))) as any[];

describe('SE-480 MCP: registro en caliente', () => {
  it('AC-1: rag.enabled cambia a true en la llamada siguiente a reescribir el fichero', async () => {
    const s = setup();
    s.write({ docs: s.entry('docs', { enabled: false }), learn: s.entry('learn', { enabled: false }) });
    const c = await mcp(s);
    expect((await status(c)).map(d => d.enabled)).toEqual([false, false]);
    s.write({ docs: s.entry('docs', { enabled: true }), learn: s.entry('learn', { enabled: false }) });
    const after = await status(c);
    expect(after.find(d => d.name === 'docs').enabled).toBe(true);
    expect(after.find(d => d.name === 'learn').enabled).toBe(false);
    expect(after[0].registry).toMatchObject({ file: s.registry });
    expect(after[0].registry.error).toBeUndefined();
  });

  it('AC-2: una cúpula eliminada deja de servirse y una nueva aparece', async () => {
    const s = setup();
    s.write({ docs: s.entry('docs', { enabled: true }), learn: s.entry('learn', { enabled: true }) });
    const c = await mcp(s);
    expect(JSON.parse(text(await c.callTool({ name: 'vault_domes', arguments: {} }))).map((d: any) => d.name).sort()).toEqual(['docs', 'learn']);
    s.write({ docs: s.entry('docs', { enabled: true }) });
    expect(JSON.parse(text(await c.callTool({ name: 'vault_domes', arguments: {} }))).map((d: any) => d.name)).toEqual(['docs']);
    const gone = await c.callTool({ name: 'vault_read', arguments: { vault: 'learn', path: 'n.md' } });
    expect(gone.isError).toBe(true);
    expect(text(gone)).toContain('not found');
    fs.mkdirSync(path.join(s.root, 'nueva'));
    s.write({ docs: s.entry('docs', { enabled: true }), nueva: s.entry('nueva', { enabled: true }) });
    expect((await status(c)).map(d => d.name).sort()).toEqual(['docs', 'nueva']);
  });

  it('AC-3: un registro corrupto conserva el último válido y vault_rag_status lo expone', async () => {
    const s = setup();
    s.write({ docs: s.entry('docs', { enabled: true }) });
    const c = await mcp(s);
    expect((await status(c))[0].registry.error).toBeUndefined();
    fs.writeFileSync(s.registry, '{ roto');
    const t = new Date(Date.now() + 999_000);
    fs.utimesSync(s.registry, t, t);
    const broken = await status(c);
    expect(broken[0]).toMatchObject({ name: 'docs', enabled: true });
    expect(broken[0].registry.error).toMatch(/Invalid JSON/);
    const read = await c.callTool({ name: 'vault_read', arguments: { path: 'n.md' } });
    expect(read.isError).not.toBe(true);
    s.write({ docs: s.entry('docs', { enabled: true }) });
    expect((await status(c))[0].registry.error).toBeUndefined();
  });
});

const freePort = () => new Promise<number>((resolve) => {
  const srv = net.createServer().listen(0, '127.0.0.1', () => { const p = (srv.address() as net.AddressInfo).port; srv.close(() => resolve(p)); });
});
const health = async (port: number) => (await fetch(`http://127.0.0.1:${port}/health`)).json() as Promise<any>;
async function until<T>(fn: () => Promise<T>, ok: (v: T) => boolean, ms = 15_000): Promise<T> {
  const end = Date.now() + ms;
  for (;;) {
    try { const v = await fn(); if (ok(v)) return v; } catch { /* aún no escucha */ }
    if (Date.now() > end) throw new Error('timeout esperando al servicio');
    await new Promise(r => setTimeout(r, 100));
  }
}

describe('SE-480 A2A: --rag-autosync', () => {
  const serve = async (s: ReturnType<typeof setup>, extra: string[], env: Record<string, string> = {}) => {
    const port = await freePort();
    const p = spawn(process.execPath, ['--import', loader, cli, 'serve', '--transport', 'a2a', '--port', String(port), '--domes', s.registry, ...extra], {
      cwd: s.root, env: { ...s.env, ...env }, stdio: 'ignore',
    });
    procs.push(p);
    return port;
  };

  it('R2/AC-4: sincroniza al arrancar y lo refleja en /health', async () => {
    const s = setup();
    s.write({ docs: s.entry('docs', { enabled: true }) });
    const port = await serve(s, ['--rag-autosync', '15'], { SAVIA_RAG_AUTOSYNC_DELAY_MS: '50' });
    const h = await until(() => health(port), v => v.autosync?.lastOk === true);
    expect(h.autosync).toMatchObject({ lastOk: true, consecutiveFailures: 0 });
    expect(fs.readdirSync(path.join(s.root, 'rag-home', 'docs')).length).toBeGreaterThan(0);
  });

  it('AC-8: sin --rag-autosync no hay sincronizador ni sync al arrancar', async () => {
    const s = setup();
    s.write({ docs: s.entry('docs', { enabled: true }) });
    const port = await serve(s, [], { SAVIA_RAG_AUTOSYNC_DELAY_MS: '50' });
    const h = await until(() => health(port), v => v.status === 'ok');
    await new Promise(r => setTimeout(r, 600));
    expect((await health(port)).autosync).toBeUndefined();
    expect(fs.existsSync(path.join(s.root, 'rag-home', 'docs'))).toBe(false);
    expect(h.status).toBe('ok');
  });

  it('rechaza minutos no válidos o un transporte que no es a2a', () => {
    const s = setup();
    s.write({ docs: s.entry('docs', { enabled: true }) });
    const run = (...a: string[]) => spawnSync(process.execPath, ['--import', loader, cli, 'serve', '--domes', s.registry, ...a], { cwd: s.root, env: s.env, encoding: 'utf-8', timeout: 20_000 });
    for (const args of [['--transport', 'a2a', '--rag-autosync', '0'], ['--transport', 'a2a', '--rag-autosync', 'abc'], ['--transport', 'mcp', '--rag-autosync', '15']]) {
      const r = run(...args);
      expect(r.status).toBe(1);
      expect(r.stderr).toContain('--rag-autosync');
    }
  });
});
