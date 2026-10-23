// CodeQL js/stack-trace-exposure (#1): un fallo interno devolvía e.message al cliente A2A,
// con rutas absolutas del servidor. Ahora la respuesta es genérica y el detalle va al log local.
import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest';
import * as fs from 'node:fs';
import * as os from 'node:os';
import * as path from 'node:path';
import { A2AServer } from '../../../src/server/a2a.js';
import type { VaultConfig } from '../../../src/types.js';

const TOKEN = 'b'.repeat(40);
const SECRET_PATH = '/srv/interno/savia/vault/.privado/notas.db';

describe('A2A: errores internos sin detalle al cliente', () => {
  let tmp: string;
  let server: A2AServer;

  beforeEach(() => {
    tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'savia-a2a-leak-'));
    const config: VaultConfig = { name: 'vault', path: tmp, allowedExtensions: [], deniedPaths: [], maxDepth: 10, maxFileSize: 1024 * 1024 };
    server = new A2AServer(config);
  });
  afterEach(async () => {
    await server.stop();
    vi.restoreAllMocks();
    fs.rmSync(tmp, { recursive: true, force: true });
  });

  it('un 500 no revela el mensaje interno, pero lo registra en local', async () => {
    (server as unknown as { storage: { stats: () => Promise<never> } }).storage.stats = async () => {
      throw new Error(`ENOENT: no such file or directory, open '${SECRET_PATH}'`);
    };
    const logged = vi.spyOn(console, 'error').mockImplementation(() => {});
    const { url } = await server.start(0, '127.0.0.1', TOKEN);
    const r = await fetch(`${url}/stats`, { headers: { Authorization: `Bearer ${TOKEN}` } });
    const body = await r.text();
    expect(r.status).toBe(500);
    expect(JSON.parse(body)).toEqual({ error: 'Internal error' });
    expect(body).not.toContain(SECRET_PATH);
    expect(logged.mock.calls.flat().join(' ')).toContain(SECRET_PATH);
  });

  it('el log escapa CR/LF del detalle (sin líneas falsas)', async () => {
    (server as unknown as { storage: { stats: () => Promise<never> } }).storage.stats = async () => {
      throw new Error('fallo\r\nA2A GET /ok: todo bien');
    };
    const logged = vi.spyOn(console, 'error').mockImplementation(() => {});
    const { url } = await server.start(0, '127.0.0.1', TOKEN);
    const r = await fetch(`${url}/stats`, { headers: { Authorization: `Bearer ${TOKEN}` } });
    expect(r.status).toBe(500);
    const line = logged.mock.calls.flat().join(' ');
    expect(line).toContain('todo bien');
    expect(line).not.toMatch(/[\r\n]/);
  });

  it('una petición correcta sigue respondiendo 200', async () => {
    const { url } = await server.start(0, '127.0.0.1', TOKEN);
    const r = await fetch(`${url}/stats`, { headers: { Authorization: `Bearer ${TOKEN}` } });
    expect(r.status).toBe(200);
  });
});
