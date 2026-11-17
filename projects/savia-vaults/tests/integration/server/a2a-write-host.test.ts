// SE-424 H5 — A2A local: sin credencial no se escribe en ningún nivel (N1 incluido), una ruta no
// sale de la cúpula pedida, y la cabecera Host debe ser un nombre admitido (reasignación de DNS).
import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import * as fs from 'node:fs';
import * as http from 'node:http';
import * as os from 'node:os';
import * as path from 'node:path';
import { A2AServer } from '../../../src/server/a2a.js';
import { DomeRegistry } from '../../../src/registry/domes.js';
import type { VaultConfig } from '../../../src/types.js';

const TOKEN = 'c'.repeat(40);

/** fetch no deja fijar Host: petición cruda con la cabecera Host que se quiera. */
function rawGet(url: string, host: string | undefined, p: string): Promise<number> {
  const u = new URL(url);
  return new Promise((resolve, reject) => {
    const headers: Record<string, string> = {};
    if (host !== undefined) headers.Host = host;
    const req = http.request({ hostname: u.hostname, port: u.port, path: p, method: 'GET', headers, setHost: host === undefined ? false : true }, (res) => {
      res.resume();
      res.on('end', () => resolve(res.statusCode ?? 0));
    });
    req.on('error', reject);
    req.end();
  });
}

describe('SE-424 H5: escritura con credencial y Host admitido en A2A', () => {
  let tmp: string;
  let servers: A2AServer[];

  const make = (opts: { allowedHosts?: string[] } = {}) => {
    const config: VaultConfig = { name: 'vault', path: path.join(tmp, 'vault'), allowedExtensions: [], deniedPaths: [], maxDepth: 10, maxFileSize: 1024 * 1024 };
    const reg = new DomeRegistry(path.join(tmp, 'domes.json'));
    reg.load();
    const s = new A2AServer(config, reg, opts);
    servers.push(s);
    return s;
  };
  const share = (url: string, body: object, headers: Record<string, string> = {}) =>
    fetch(`${url}/share`, { method: 'POST', headers: { 'Content-Type': 'application/json', ...headers }, body: JSON.stringify(body) });

  beforeEach(() => {
    tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'savia-a2a-h5-'));
    servers = [];
    for (const d of ['P1', 'P2', 'S4']) {
      fs.mkdirSync(path.join(tmp, d));
      fs.writeFileSync(path.join(tmp, d, 'nota.md'), `# ${d}\ncontenido-${d}\n`);
    }
    fs.writeFileSync(path.join(tmp, 'domes.json'), JSON.stringify({ version: 1, defaultDome: 'P1', domes: {
      P1: { name: 'P1', path: path.join(tmp, 'P1'), description: '', confidentiality: 'N1' },
      P2: { name: 'P2', path: path.join(tmp, 'P2'), description: '', confidentiality: 'N2' },
      S4: { name: 'S4', path: path.join(tmp, 'S4'), description: '', confidentiality: 'N4' },
    } }));
  });
  afterEach(async () => {
    for (const s of servers) await s.stop();
    fs.rmSync(tmp, { recursive: true, force: true });
  });

  it('sin credencial: escritura 401 en N1 y N2 (y en la vault por defecto); nada llega a disco', async () => {
    const { url } = await make().start(0, '127.0.0.1');
    for (const dome of ['P1', 'P2']) {
      const r = await share(url, { dome, path: 'anon.md', content: '# anon\n' });
      expect(r.status, dome).toBe(401);
      expect(fs.existsSync(path.join(tmp, dome, 'anon.md'))).toBe(false);
    }
    const r = await share(url, { path: 'anon.md', content: '# anon\n' });
    expect(r.status).toBe(401);
    expect(fs.existsSync(path.join(tmp, 'vault', 'anon.md'))).toBe(false);
    // La lectura pública de N1/N2 no cambia.
    expect((await fetch(`${url}/context/x/nota.md?dome=P1`)).status).toBe(200);
  });

  it('con servicio protegido por secreto: token erróneo 401; token correcto escribe', async () => {
    const { url } = await make().start(0, '127.0.0.1', TOKEN);
    expect((await share(url, { dome: 'P1', path: 'ok.md', content: '# ok\n' }, { Authorization: `Bearer ${'d'.repeat(40)}` })).status).toBe(401);
    expect(fs.existsSync(path.join(tmp, 'P1', 'ok.md'))).toBe(false);
    expect((await share(url, { dome: 'P1', path: 'ok.md', content: '# ok\n' }, { Authorization: `Bearer ${TOKEN}` })).status).toBe(200);
    expect(fs.existsSync(path.join(tmp, 'P1', 'ok.md'))).toBe(true);
  });

  it('con credencial, una ruta no salta de la cúpula N1 a la N4 vecina (lectura ni escritura)', async () => {
    const { url } = await make().start(0, '127.0.0.1', TOKEN);
    const auth = { Authorization: `Bearer ${TOKEN}` };
    const w = await share(url, { dome: 'P1', path: '../S4/inyectado.md', content: '# x\n' }, auth);
    expect(w.status).toBe(400);
    expect(fs.existsSync(path.join(tmp, 'S4', 'inyectado.md'))).toBe(false);
    for (const p of ['..%2FS4%2Fnota.md', '%2e%2e/S4/nota.md', '..%5CS4%5Cnota.md']) {
      const r = await fetch(`${url}/context/x/${p}?dome=P1`, { headers: auth });
      const body = await r.text();
      expect(r.status, p).not.toBe(200);
      expect(body, p).not.toContain('contenido-S4');
    }
    // Sin credencial, tampoco desde la N1 pública.
    const anon = await fetch(`${url.replace('127.0.0.1', 'localhost')}/context/x/..%2FS4%2Fnota.md?dome=P1`);
    expect(await anon.text()).not.toContain('contenido-S4');
  });

  it('Host: bucle local e IP literal sí; nombre ajeno o ausente no; nombre configurado sí', async () => {
    const { url } = await make({ allowedHosts: ['vaults.example'] }).start(0, '127.0.0.1');
    const port = new URL(url).port;
    expect(await rawGet(url, `127.0.0.1:${port}`, '/domes')).toBe(200);
    expect(await rawGet(url, `localhost:${port}`, '/domes')).toBe(200);
    expect(await rawGet(url, `[::1]:${port}`, '/domes')).toBe(200);
    expect(await rawGet(url, `192.0.2.7:${port}`, '/domes')).toBe(200);
    expect(await rawGet(url, `vaults.example:${port}`, '/domes')).toBe(200);
    expect(await rawGet(url, `VAULTS.EXAMPLE`, '/domes')).toBe(200);
    expect(await rawGet(url, `atacante.example:${port}`, '/domes')).toBe(403);
    expect(await rawGet(url, `atacante.example:${port}`, '/context/x/nota.md?dome=P1')).toBe(403);
    expect(await rawGet(url, `localhost.atacante.example`, '/domes')).toBe(403);
    expect(await rawGet(url, `127.0.0.1.nip.example:${port}`, '/domes')).toBe(403);
    // Sin Host: Node ya responde 400 (requireHostHeader); si no lo hiciera, la guarda da 403.
    expect([400, 403]).toContain(await rawGet(url, undefined, '/domes'));
  });

  it('Host: sin lista configurada, un nombre que no es de bucle local se rechaza', async () => {
    const { url } = await make().start(0, '127.0.0.1');
    expect(await rawGet(url, 'vaults.example', '/health')).toBe(403);
    expect(await rawGet(url, 'localhost', '/health')).toBe(200);
  });
});
