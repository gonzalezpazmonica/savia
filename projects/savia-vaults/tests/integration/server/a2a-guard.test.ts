// SE-424 H2 — guarda mínima de A2A (el modelo por usuario llega con SE-423):
// sin token, solo loopback y solo cúpulas N1/N2; sin CORS abierto; peticiones de navegador
// (con Origin) solo desde orígenes permitidos; /domes sin rutas; token en tiempo constante.
import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import * as fs from 'node:fs';
import * as os from 'node:os';
import * as path from 'node:path';
import { spawnSync } from 'node:child_process';
import { A2AServer } from '../../../src/server/a2a.js';
import { DomeRegistry } from '../../../src/registry/domes.js';
import type { VaultConfig } from '../../../src/types.js';

// TEST-NET-1 (RFC 5737): nunca asignada a este equipo. Si la guarda fallara, no se podría escuchar.
const NON_LOOPBACK = '192.0.2.1';
const TOKEN = 'a'.repeat(40);

describe('SE-424 H2: guarda de A2A', () => {
  let tmp: string;
  let servers: A2AServer[];

  const make = (opts: { corsOrigins?: string[] } = {}) => {
    const config: VaultConfig = { name: 'vault', path: path.join(tmp, 'vault'), allowedExtensions: [], deniedPaths: [], maxDepth: 10, maxFileSize: 1024 * 1024 };
    const reg = new DomeRegistry(path.join(tmp, 'domes.json'));
    reg.load();
    const s = new A2AServer(config, reg, opts);
    servers.push(s);
    return s;
  };

  beforeEach(() => {
    tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'savia-a2a-guard-'));
    servers = [];
    for (const d of ['A', 'B']) {
      fs.mkdirSync(path.join(tmp, d));
      fs.writeFileSync(path.join(tmp, d, 'nota.md'), `# ${d}\npalabra-comun contenido-${d}\n`);
    }
    fs.writeFileSync(path.join(tmp, 'domes.json'), JSON.stringify({ version: 1, defaultDome: 'A', domes: {
      A: { name: 'A', path: path.join(tmp, 'A'), description: '', confidentiality: 'N2' },
      B: { name: 'B', path: path.join(tmp, 'B'), description: '', confidentiality: 'N4' },
    } }));
  });
  afterEach(async () => {
    for (const s of servers) await s.stop();
    fs.rmSync(tmp, { recursive: true, force: true });
  });

  it('AC2: fuera de loopback sin token no arranca (servidor y CLI); en loopback sí', async () => {
    await expect(make().start(0, NON_LOOPBACK)).rejects.toThrow(/SAVIA_VAULTS_TOKEN/);
    const cli = path.join(__dirname, '../../../src/cli/index.ts');
    const tsx = path.join(__dirname, '../../../node_modules/.bin/tsx');
    const r = spawnSync(tsx, [cli, 'serve', '--transport', 'a2a', '--host', NON_LOOPBACK, '--port', '0', '--domes', path.join(tmp, 'domes.json')], {
      cwd: tmp, env: { ...process.env, SAVIA_VAULTS_TOKEN: '', HOME: tmp }, encoding: 'utf-8', timeout: 30_000,
    });
    expect(r.status).toBe(1);
    expect(r.stderr).toMatch(/SAVIA_VAULTS_TOKEN/);
    const { url } = await make().start(0, '127.0.0.1');
    expect((await fetch(`${url}/health`)).status).toBe(200);
  }, 40_000);

  it('AC2: sin token, en loopback, N4 no aparece en /domes, búsqueda, lectura ni escritura; N2 sí', async () => {
    const { url } = await make().start(0, '127.0.0.1');
    const domes = await (await fetch(`${url}/domes`)).json();
    expect(domes.domes.map((d: { name: string }) => d.name)).toEqual(['A']);
    expect(JSON.stringify(domes)).not.toContain(tmp);
    const all = await (await fetch(`${url}/search?q=palabra-comun`)).json();
    expect(all.results.map((r: { dome: string }) => r.dome)).toEqual(['A']);
    expect((await fetch(`${url}/search?q=contenido-B&dome=B`)).status).toBe(404);
    expect((await fetch(`${url}/context/note/nota.md?dome=B`)).status).toBe(404);
    expect((await fetch(`${url}/context/note/nota.md?dome=A`)).status).toBe(200);
    const shareB = await fetch(`${url}/share`, { method: 'POST', body: JSON.stringify({ dome: 'B', path: 'x.md', content: 'x' }) });
    expect(shareB.status).toBe(401); // SE-424 H5: sin credencial, toda escritura es 401 (antes 404 por nivel)
    expect(fs.existsSync(path.join(tmp, 'B', 'x.md'))).toBe(false);
    // SE-424 H5 («sin escritura sin contraseña»): ni siquiera la N2 admite escritura sin credencial.
    const shareA = await fetch(`${url}/share`, { method: 'POST', body: JSON.stringify({ dome: 'A', path: 'x.md', content: 'x' }) });
    expect(shareA.status).toBe(401);
    expect(fs.existsSync(path.join(tmp, 'A', 'x.md'))).toBe(false);
  });

  it('AC2: sin CORS abierto; una petición de navegador de otro origen se rechaza (lectura y escritura)', async () => {
    const { url } = await make().start(0, '127.0.0.1');
    const plain = await fetch(`${url}/search?q=palabra-comun`);
    expect(plain.headers.get('access-control-allow-origin')).toBeNull();
    const evil = { Origin: 'https://sitio-ajeno.example' };
    expect((await fetch(`${url}/search?q=palabra-comun`, { headers: evil })).status).toBe(403);
    // text/plain no provoca preflight en un navegador: la escritura debe rechazarse igual.
    const w = await fetch(`${url}/share`, { method: 'POST', headers: { ...evil, 'Content-Type': 'text/plain' }, body: JSON.stringify({ dome: 'A', path: 'csrf.md', content: 'x' }) });
    expect(w.status).toBe(403);
    expect(fs.existsSync(path.join(tmp, 'A', 'csrf.md'))).toBe(false);
    // Origen permitido explícitamente
    const ok = await make({ corsOrigins: ['https://panel.example'] }).start(0, '127.0.0.1');
    const r = await fetch(`${ok.url}/domes`, { headers: { Origin: 'https://panel.example' } });
    expect(r.status).toBe(200);
    expect(r.headers.get('access-control-allow-origin')).toBe('https://panel.example');
    expect((await fetch(`${ok.url}/domes`, { headers: evil })).status).toBe(403);
  });

  it('AC2: con token, comparación estricta (misma longitud distinta ⇒ 401) y acceso a todas las cúpulas', async () => {
    const { url } = await make().start(0, '127.0.0.1', TOKEN);
    expect((await fetch(`${url}/domes`)).status).toBe(401);
    expect((await fetch(`${url}/domes`, { headers: { Authorization: `Bearer ${'b'.repeat(40)}` } })).status).toBe(401);
    expect((await fetch(`${url}/domes`, { headers: { Authorization: `Bearer ${TOKEN}x` } })).status).toBe(401);
    const domes = await (await fetch(`${url}/domes`, { headers: { Authorization: `Bearer ${TOKEN}` } })).json();
    expect(domes.domes.map((d: { name: string }) => d.name).sort()).toEqual(['A', 'B']);
    expect(JSON.stringify(domes)).not.toContain(tmp);
  });
});
