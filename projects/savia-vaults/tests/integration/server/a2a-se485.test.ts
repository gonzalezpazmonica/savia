// SE-485 R2/R3/R5 — A2A: /stats respeta dome y autoriza por usuario sin contadores de lo oculto;
// /context de una nota oculta responde igual que una inexistente (sin oráculo de existencia);
// /search acepta includeStale.
import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import * as fs from 'node:fs';
import * as os from 'node:os';
import * as path from 'node:path';
import { A2AServer } from '../../../src/server/a2a.js';
import { DomeRegistry } from '../../../src/registry/domes.js';
import { UserStore } from '../../../src/auth/store.js';
import { AccessController } from '../../../src/auth/controller.js';
import type { VaultConfig } from '../../../src/types.js';

describe('SE-485 A2A', () => {
  let tmp: string;
  let server: A2AServer;
  let url: string;
  let onlyX: string;
  const get = (route: string, token?: string) => fetch(url + route, token ? { headers: { Authorization: `Bearer ${token}` } } : {});
  const put = (dome: string, p: string, s: string) => fs.writeFileSync(path.join(tmp, dome, p), s);

  beforeEach(async () => {
    tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'savia-a2a-se485-'));
    for (const d of ['X', 'Y']) {
      fs.mkdirSync(path.join(tmp, d));
      put(d, 'publica.md', `# ${d}\nzafiro visible ${d}\n`);
    }
    put('X', 'segunda.md', '# Segunda\nzafiro otra\n');
    put('X', 'oculta.md', '---\nconfidentiality: N3\n---\n# Oculta\nzafiro secreto\n');
    put('X', 'cuarentena.md', '---\nconfidentiality: [N4\n---\n# Rota\nzafiro roto\n');
    put('X', 'vieja.md', '---\nstatus: deprecated\n---\n# Vieja\nzafiro obsoleto\n');
    put('Y', 'extra.md', '# Extra\nzafiro extra Y\n');
    fs.writeFileSync(path.join(tmp, 'domes.json'), JSON.stringify({ version: 1, defaultDome: 'X', domes: {
      X: { name: 'X', path: path.join(tmp, 'X'), description: '', confidentiality: 'N2' },
      Y: { name: 'Y', path: path.join(tmp, 'Y'), description: '', confidentiality: 'N2' },
    } }));
    const reg = new DomeRegistry(path.join(tmp, 'domes.json'));
    reg.load();
    const users = new UserStore(path.join(tmp, 'users.json'));
    onlyX = users.createUser('luis');
    users.setPermission('luis', 'X', 'reader');
    users.save();
    const config: VaultConfig = { name: 'vault', path: path.join(tmp, 'vault'), allowedExtensions: [], deniedPaths: [], maxDepth: 10, maxFileSize: 1024 * 1024 };
    server = new A2AServer(config, reg, { access: new AccessController(users, reg) });
    ({ url } = await server.start(0, '127.0.0.1'));
  });
  afterEach(async () => { await server.stop(); fs.rmSync(tmp, { recursive: true, force: true }); });

  describe('R2 /stats', () => {
    it('usuario con permiso en X: recuentos de X, sin Y ni contadores de lo oculto', async () => {
      const r = await get('/stats?dome=X', onlyX);
      expect(r.status).toBe(200);
      const body = await r.json();
      expect(body.name).toBe('X');
      expect(body.noteCount).toBe(3); // publica, segunda y vieja; oculta y cuarentena no cuentan
      expect(body).not.toHaveProperty('outOfLevel');
      expect(body).not.toHaveProperty('quarantined');
      expect(body).not.toHaveProperty('commitCount');
    });

    it('dome ajeno ⇒ 403; sin dome en modo usuario ⇒ 400; sin token ⇒ 401', async () => {
      expect((await get('/stats?dome=Y', onlyX)).status).toBe(403);
      expect((await get('/stats', onlyX)).status).toBe(400);
      expect((await get('/stats?dome=X')).status).toBe(401);
    });

    it('el recuento no cambia con notas ocultas (no hay oráculo)', async () => {
      const first = await get('/stats?dome=X', onlyX);
      expect(first.status).toBe(200);
      const before = await first.json();
      put('X', 'otra-oculta.md', '---\nconfidentiality: N4\n---\n# Otra\nx\n');
      const after = await (await get('/stats?dome=X', onlyX)).json();
      expect(after).toEqual(before);
    });
  });

  describe('R3 /context de nota oculta', () => {
    const snapshot = async (route: string) => {
      const r = await get(route, onlyX);
      return { status: r.status, body: await r.text(), type: r.headers.get('content-type'), length: r.headers.get('content-length') };
    };

    it('oculta, en cuarentena e inexistente: misma respuesta 404 byte a byte', async () => {
      const missing = await snapshot('/context/n/no-existe.md?dome=X');
      expect(missing.status).toBe(404);
      for (const p of ['oculta.md', 'cuarentena.md']) {
        const hidden = await snapshot(`/context/n/${p}?dome=X`);
        expect(hidden.status).toBe(404);
        expect(hidden.body).toBe(missing.body.replace('no-existe.md', p)); // el cuerpo no menciona la nota
        expect(hidden).toEqual(missing);
      }
      expect(missing.body).not.toMatch(/no-existe|Note not found/);
    });

    it('una nota visible sigue respondiendo 200; un fallo interno sigue siendo 500 sin detalles', async () => {
      expect((await snapshot('/context/n/publica.md?dome=X')).status).toBe(200);
      fs.mkdirSync(path.join(tmp, 'X', 'carpeta.md'));
      const dir = await snapshot('/context/n/carpeta.md?dome=X');
      expect([404, 500]).toContain(dir.status);
      if (dir.status === 500) expect(dir.body).toBe(JSON.stringify({ error: 'Internal error' }));
    });
  });

  describe('R5 /search includeStale', () => {
    it('includeStale=false excluye lo obsoleto; true lo incluye', async () => {
      const off = await (await get('/search?q=zafiro&dome=X&includeStale=false', onlyX)).json();
      expect(off.results.map((r: { path: string }) => r.path)).not.toContain('vieja.md');
      const on = await (await get('/search?q=zafiro&dome=X&includeStale=true', onlyX)).json();
      expect(on.results.map((r: { path: string }) => r.path)).toContain('vieja.md');
    });
  });
});
