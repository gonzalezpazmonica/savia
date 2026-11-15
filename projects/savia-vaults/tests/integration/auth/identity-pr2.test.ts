// SE-423 PR 2 — revocación en transferencias en curso (AC3), autorizaciones svt1 ligadas a la
// credencial que las emitió (AC3) y listas por documento por subjectId con `user rename` (AC7).
import { describe, it, expect, beforeAll, beforeEach, afterEach, vi } from 'vitest';
import * as fs from 'node:fs';
import * as http from 'node:http';
import * as os from 'node:os';
import * as path from 'node:path';
import { randomBytes } from 'node:crypto';
import { Readable } from 'node:stream';
import { DomeRegistry } from '../../../src/registry/domes.js';
import { UserStore } from '../../../src/auth/store.js';
import { AccessController } from '../../../src/auth/controller.js';
import { FilesHttpServer } from '../../../src/server/http.js';
import { FilesService } from '../../../src/files/service.js';
import { Journal } from '../../../src/files/journal.js';
import { sodiumReady } from '../../../src/files/crypto.js';

const MiB = 1024 * 1024;

describe('SE-423 PR 2: revocación en curso, svt1 y subjectId', () => {
  let root: string;
  let usersFile: string;
  let reg: DomeRegistry;
  let users: UserStore;
  let access: AccessController;
  let env: NodeJS.ProcessEnv;
  let servers: FilesHttpServer[];
  let token: string;

  const edit = (fn: (s: UserStore) => void) => {
    const s = new UserStore(usersFile);
    s.load();
    fn(s);
    s.save();
  };
  const principalId = () => users.listTokens('eva').find((c) => c.name === 'principal')!.id;
  const revokePrincipal = () => { const id = principalId(); edit((s) => s.revokeToken('eva', id)); };
  /** Servicio con la identidad de un usuario, como lo construye MCP o HTTP. */
  const as = (username: string, credentialId?: string) => new FilesService({
    domes: () => reg.listActive().map((d) => ({ name: d.name, confidentiality: d.confidentiality, files: d.files })), env,
    authorize: (dome, action, tool) => access.authorizeUser({ username, credentialId, dome, action, tool }),
    subjects: access.subjects,
  });
  const serve = async (fence?: { bytes: number; ms: number }) => {
    const s = new FilesHttpServer({ domes: reg, users, access, env, host: '127.0.0.1', port: 0, ...(fence ? { fence } : {}) });
    servers.push(s);
    return (await s.start()).url;
  };
  const put = async (name: string, data: Buffer) => {
    const [r] = await as('eva').putMany({ dome: 'A', files: [{ name, size: data.length, stream: () => Readable.from((function* () { for (let i = 0; i < data.length; i += MiB) yield data.subarray(i, i + MiB); })()) }] });
    return r.documentId;
  };

  beforeAll(async () => { await sodiumReady(); });
  beforeEach(() => {
    root = fs.mkdtempSync(path.join(os.tmpdir(), 'savia-se423-pr2-'));
    fs.mkdirSync(path.join(root, 'A'));
    fs.writeFileSync(path.join(root, 'domes.json'), JSON.stringify({ version: 1, defaultDome: 'A', domes: {
      A: { name: 'A', path: path.join(root, 'A'), description: '', confidentiality: 'N2', files: { enabled: true, scan: 'off' } },
    } }));
    reg = new DomeRegistry(path.join(root, 'domes.json'));
    reg.load();
    usersFile = path.join(root, 'users.json');
    users = new UserStore(usersFile);
    token = users.createUser('eva');
    users.setPermission('eva', 'A', 'writer');
    users.createUser('luis');
    users.setPermission('luis', 'A', 'writer');
    users.save();
    access = new AccessController(users, reg);
    env = { SAVIA_FILES_HOME: path.join(root, 'files'), SAVIA_FILES_KEYS_HOME: path.join(root, 'keys'), HOME: root, PATH: process.env.PATH };
    servers = [];
  });
  afterEach(async () => {
    for (const s of servers) await s.stop();
    Journal.closeAll();
    fs.rmSync(root, { recursive: true, force: true });
  });

  it('AC3: una descarga de 64 MiB se corta en la siguiente ventana de 8 MiB tras revocar la credencial', async () => {
    const id = await put('grande.bin', randomBytes(64 * MiB));
    const url = await serve(); // umbrales reales: 8 MiB / 30 s
    const res = await fetch(`${url}/v1/files/A/documents/${id}/content`, { headers: { Authorization: `Bearer ${token}` } });
    expect(res.status).toBe(200);
    revokePrincipal(); // antes de leer nada: lo enviado hasta ahora es solo lo que cabe en los búferes
    let got = 0;
    let cut = false;
    try {
      for await (const c of res.body as unknown as AsyncIterable<Uint8Array>) got += c.byteLength;
    } catch { cut = true; }
    expect(cut).toBe(true);
    // Primera comprobación a los 8 MiB servidos; como mucho otra ventana ya en vuelo en los búferes.
    expect(got).toBeLessThanOrEqual(16 * MiB);
    expect((await fetch(`${url}/v1/files/A/documents`, { headers: { Authorization: `Bearer ${token}` } })).status).toBe(401);
  });

  it('AC3: un PATCH en curso se corta con 401 al revocar y no escribe nada más', async () => {
    const url = await serve({ bytes: 64 * MiB, ms: 150 }); // corte por tiempo
    const create = await fetch(`${url}/v1/files/A/uploads`, { method: 'POST', headers: {
      Authorization: `Bearer ${token}`, 'Tus-Resumable': '1.0.0', 'Upload-Length': String(2 * MiB),
      'Upload-Metadata': `filename ${Buffer.from('b.bin').toString('base64')}`,
    } });
    expect(create.status).toBe(201);
    const location = new URL(create.headers.get('location')!, url);
    const status = await new Promise<number>((resolve, reject) => {
      const req = http.request(location, { method: 'PATCH', headers: {
        Authorization: `Bearer ${token}`, 'Tus-Resumable': '1.0.0', 'Upload-Offset': '0', 'Content-Type': 'application/offset+octet-stream',
      } }, (res) => { res.resume(); resolve(res.statusCode ?? 0); });
      req.on('error', reject);
      req.write(Buffer.alloc(MiB, 1));
      setTimeout(() => {
        revokePrincipal();
        setTimeout(() => req.end(Buffer.alloc(MiB, 2)), 200);
      }, 200);
    });
    expect(status).toBe(401);
    // Lo recibido antes de la revocación queda; el segundo MiB, enviado después, no.
    const disk = new UserStore(usersFile);
    disk.load();
    const fresh = disk.createToken('eva', { name: 'nueva', expiresDays: 1 });
    disk.save();
    const head = await fetch(location, { method: 'HEAD', headers: { Authorization: `Bearer ${fresh}`, 'Tus-Resumable': '1.0.0' } });
    expect(Number(head.headers.get('upload-offset'))).toBeLessThanOrEqual(MiB);
  });

  it('AC3: un enlace svt1 deja de valer al revocar la credencial que lo emitió, no otra', async () => {
    const url = await serve();
    env.SAVIA_FILES_HTTP_URL = url;
    const id = await put('nota.bin', Buffer.from('hola'));
    const other = users.createToken('eva', { name: 'otra', expiresDays: 3 });
    users.save();
    const otherId = users.listTokens('eva').find((c) => c.name === 'otra')!.id;
    const link = (await as('eva', principalId()).issueLink({ dome: 'A', id })).url;
    const fromOther = (await as('eva', otherId).issueLink({ dome: 'A', id })).url;
    expect((await fetch(link)).status).toBe(200);
    revokePrincipal();
    expect((await fetch(link)).status).toBe(401);
    expect((await fetch(fromOther)).status).toBe(200); // emitido por la otra credencial, vigente
    expect(other).toMatch(/^sv_/);
  });

  it('SE-528 S3: con la clave de firma inválida el enlace svt1 da 503 sin rotarla; al repararla vuelve a valer', async () => {
    const url = await serve();
    env.SAVIA_FILES_HTTP_URL = url;
    const id = await put('firma.bin', Buffer.from('hola'));
    const link = (await as('eva', principalId()).issueLink({ dome: 'A', id })).url;
    expect((await fetch(link)).status).toBe(200);
    const keyFile = path.join(root, 'keys', '_http', 'token.key');
    const good = fs.readFileSync(keyFile);
    const bad = Buffer.alloc(31, 9);
    fs.writeFileSync(keyFile, bad);
    const errors = vi.spyOn(console, 'error').mockImplementation(() => undefined);
    try {
      const res = await fetch(link);
      expect(res.status).toBe(503);
      expect(((await res.json()) as { error: { code: string } }).error.code).toBe('KEY_UNAVAILABLE');
      expect(fs.readFileSync(keyFile).equals(bad)).toBe(true); // no se regenera sola
      expect(errors.mock.calls.map((c) => String(c[0])).join('\n')).toMatch(/SECURITY.*EINVAL/);
    } finally {
      errors.mockRestore();
    }
    fs.writeFileSync(keyFile, good);
    expect((await fetch(link)).status).toBe(200);
  });

  it('AC7: las listas se guardan por subjectId; renombrar conserva el acceso y el nombre antiguo no se reutiliza', async () => {
    const id = await put('privado.bin', Buffer.from('secreto'));
    const set = await as('eva').policy({ dome: 'A', id, readers: ['luis'], writers: ['eva'] });
    expect(set.readers).toEqual(['luis']); // se muestra por nombre
    const stored = (await as('eva').get({ dome: 'A', id })).acl;
    expect(stored?.readers).toEqual([`sub:${users.getUser('luis')!.subjectId}`]);
    users.renameUser('luis', 'luisa');
    users.save();
    expect((await as('luisa').get({ dome: 'A', id })).id).toBe(id);
    expect(() => users.createUser('luis')).toThrow(/no se reutiliza/);
    expect(users.getUser('luisa')!.formerNames).toEqual(['luis']);
    const shown = await as('eva').policy({ dome: 'A', id, writers: ['eva', 'luisa'] });
    expect(shown.readers).toEqual(['luisa']);
  });

  it('AC6/AC7: una lista antigua por nombre se sigue respetando, también tras renombrar (alias)', async () => {
    const id = await put('viejo.bin', Buffer.from('antiguo'));
    // Política fijada sin resolutor (como antes de SE-423): queda por nombre.
    const legacy = new FilesService({
      domes: () => reg.listActive().map((d) => ({ name: d.name, confidentiality: d.confidentiality, files: d.files })), env,
      authorize: (dome, action, tool) => access.authorizeUser({ username: 'eva', dome, action, tool }),
    });
    await legacy.policy({ dome: 'A', id, readers: ['luis'] });
    expect((await as('luis').get({ dome: 'A', id })).acl?.readers).toEqual(['luis']);
    await expect(as('eva').get({ dome: 'A', id })).rejects.toThrow(/NOT_FOUND|no existe/); // no está en la lista
    users.renameUser('luis', 'luisa');
    users.save();
    expect((await as('luisa').get({ dome: 'A', id })).id).toBe(id);
  });
});
