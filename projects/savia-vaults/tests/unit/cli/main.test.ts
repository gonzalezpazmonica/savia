// SE-424 H5 — la CLI pasa SAVIA_A2A_ALLOWED_HOSTS al servicio A2A: un nombre configurado se admite
// en la cabecera Host; sin la variable, el mismo nombre se rechaza (proceso real, directorio temporal).
import { describe, it, expect, afterEach } from 'vitest';
import { spawn, type ChildProcess } from 'node:child_process';
import * as fs from 'node:fs';
import * as http from 'node:http';
import * as os from 'node:os';
import * as path from 'node:path';

const tsx = path.resolve('node_modules/.bin/tsx');
const cli = path.resolve('src/cli/index.ts');

function getWithHost(port: string, host: string): Promise<number> {
  return new Promise((resolve, reject) => {
    const req = http.request({ hostname: '127.0.0.1', port, path: '/health', headers: { Host: host } }, (res) => {
      res.resume();
      res.on('end', () => resolve(res.statusCode ?? 0));
    });
    req.on('error', reject);
    req.end();
  });
}

describe('SE-424 H5: CLI serve a2a y SAVIA_A2A_ALLOWED_HOSTS', () => {
  const procs: ChildProcess[] = [];
  const dirs: string[] = [];
  afterEach(() => {
    for (const p of procs.splice(0)) p.kill('SIGKILL');
    for (const d of dirs.splice(0)) fs.rmSync(d, { recursive: true, force: true });
  });

  const serve = async (env: Record<string, string>): Promise<string> => {
    const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'savia-cli-hosts-'));
    dirs.push(tmp);
    fs.mkdirSync(path.join(tmp, 'A'));
    fs.writeFileSync(path.join(tmp, 'domes.json'), JSON.stringify({ version: 1, defaultDome: 'A', domes: {
      A: { name: 'A', path: path.join(tmp, 'A'), description: '', confidentiality: 'N2' },
    } }));
    const p = spawn(tsx, [cli, 'serve', '--transport', 'a2a', '--port', '0', '--domes', path.join(tmp, 'domes.json')], {
      cwd: tmp, env: { ...process.env, HOME: tmp, SAVIA_VAULTS_TOKEN: '', SAVIA_A2A_ALLOWED_HOSTS: '', ...env },
    });
    procs.push(p);
    return new Promise((resolve, reject) => {
      let err = '';
      const t = setTimeout(() => reject(new Error(`sin arrancar: ${err}`)), 30_000);
      p.stderr!.on('data', (d) => {
        err += String(d);
        const m = err.match(/listening on http:\/\/127\.0\.0\.1:(\d+)/);
        if (m) { clearTimeout(t); resolve(m[1]); }
      });
      p.on('exit', (c) => { clearTimeout(t); reject(new Error(`salió ${c}: ${err}`)); });
    });
  };

  it('con la variable, el nombre configurado entra; sin ella, no', async () => {
    const withVar = await serve({ SAVIA_A2A_ALLOWED_HOSTS: 'vaults.example, otro.example' });
    expect(await getWithHost(withVar, `vaults.example:${withVar}`)).toBe(200);
    expect(await getWithHost(withVar, 'otro.example')).toBe(200);
    expect(await getWithHost(withVar, 'ajeno.example')).toBe(403);
    const without = await serve({});
    expect(await getWithHost(without, 'vaults.example')).toBe(403);
    expect(await getWithHost(without, `localhost:${without}`)).toBe(200);
  }, 70_000);
});
