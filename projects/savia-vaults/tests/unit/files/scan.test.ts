// SE-413 F2 — escaneo antivirus opcional (clamscan)
import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import * as fs from 'node:fs';
import * as os from 'node:os';
import * as path from 'node:path';
import { Readable } from 'node:stream';
import { CLAMSCAN_MAX_BYTES, scanFile, scanFiles, scanStream, scannerAvailable } from '../../../src/files/scan.js';
import { Tools } from '../../../src/files/setup.js';
import { fakeClamavDeb, fakeUvTarGz, serve, sha256 } from './fake-artifacts.js';

describe('scanFile', () => {
  let dir: string;
  beforeEach(() => { dir = fs.mkdtempSync(path.join(os.tmpdir(), 'savia-scan-')); });
  afterEach(() => fs.rmSync(dir, { recursive: true, force: true }));

  const fakeScanner = (exit: number, out = '') => {
    const f = path.join(dir, 'clamscan');
    fs.writeFileSync(f, `#!/bin/sh\necho "$2: ${out}"\nexit ${exit}\n`, { mode: 0o700 });
    return f;
  };

  it('off no escanea; auto sin escáner no escanea; required sin escáner falla', async () => {
    const f = path.join(dir, 'a.txt');
    fs.writeFileSync(f, 'x');
    expect((await scanFile(f, { mode: 'off' })).verdict).toBe('skipped');
    expect((await scanFile(f, { mode: 'auto', clamscan: path.join(dir, 'no-existe') })).verdict).toBe('skipped');
    await expect(scanFile(f, { mode: 'required', clamscan: path.join(dir, 'no-existe') })).rejects.toThrow(/SCAN_REQUIRED/);
  });

  it('exit 0 limpio, exit 1 infectado con firma, otro exit error', async () => {
    const f = path.join(dir, 'a.txt');
    fs.writeFileSync(f, 'x');
    expect((await scanFile(f, { mode: 'auto', clamscan: fakeScanner(0, 'OK') })).verdict).toBe('clean');
    const inf = await scanFile(f, { mode: 'auto', clamscan: fakeScanner(1, 'Eicar-Signature FOUND') });
    expect(inf).toMatchObject({ verdict: 'infected', signature: 'Eicar-Signature' });
    await expect(scanFile(f, { mode: 'required', clamscan: fakeScanner(2, 'ERROR') })).rejects.toThrow(/SCAN_REQUIRED/);
    expect((await scanFile(f, { mode: 'auto', clamscan: fakeScanner(2, 'ERROR') })).verdict).toBe('error');
  });

  // SE-424 H1: ClamAV no analiza más de 2 GiB − 1 por fichero y responde «OK»; lo que no lee entero no es «limpio».
  it('SE-424 H1: el tope real es 2 GiB − 1; por encima no se abre el stream ni se da por limpio', async () => {
    expect(CLAMSCAN_MAX_BYTES).toBe(2 ** 31 - 1);
    const clam = fakeScanner(0, 'OK');
    for (const size of [2 ** 31, 3 * 1024 ** 3]) {
      let opened = false;
      expect(await scanStream(() => { opened = true; return Readable.from([]); }, size, { mode: 'auto', clamscan: clam }))
        .toEqual({ verdict: 'error', detail: 'too-large-to-scan' });
      expect(opened).toBe(false);
      await expect(scanStream(() => Readable.from([]), size, { mode: 'required', clamscan: clam })).rejects.toThrow(/too-large-to-scan/);
    }
  });

  it('SE-424 H1: Heuristics.Limits.Exceeded es «no analizado», nunca «infectado»; se pide con --alert-exceeds-max', async () => {
    const f = path.join(dir, 'a.bin');
    fs.writeFileSync(f, 'x');
    const argsLog = path.join(dir, 'args');
    const clam = path.join(dir, 'clamscan-heur');
    fs.writeFileSync(clam, `#!/bin/sh
echo "$@" > ${argsLog}
for a; do last="$a"; done
echo "$last: Heuristics.Limits.Exceeded.MaxScanSize FOUND"
exit 1
`, { mode: 0o700 });
    expect(await scanFile(f, { mode: 'auto', clamscan: clam })).toEqual({ verdict: 'error', detail: 'too-large-to-scan' });
    expect(fs.readFileSync(argsLog, 'utf-8')).toContain('--alert-exceeds-max=yes');
    await expect(scanFile(f, { mode: 'required', clamscan: clam })).rejects.toThrow(/too-large-to-scan/);
    expect(await scanStream(() => Readable.from([Buffer.from('x')]), 1, { mode: 'auto', clamscan: clam })).toEqual({ verdict: 'error', detail: 'too-large-to-scan' });
    expect(fs.readFileSync(argsLog, 'utf-8')).toContain('--alert-exceeds-max=yes');
    await expect(scanStream(() => Readable.from([Buffer.from('x')]), 1, { mode: 'required', clamscan: clam })).rejects.toThrow(/too-large-to-scan/);
    // Una firma real sigue siendo infección.
    expect(await scanFile(f, { mode: 'auto', clamscan: fakeScanner(1, 'Win.Test.Real FOUND') })).toMatchObject({ verdict: 'infected', signature: 'Win.Test.Real' });
  });
});

describe('SE-416 antivirus gestionado', () => {
  let dir: string;
  let tools: Tools;
  let pins: ConstructorParameters<typeof Tools>[0]['pins'];
  let close: () => Promise<void>;
  beforeEach(async () => {
    dir = fs.mkdtempSync(path.join(os.tmpdir(), 'savia-scan-m-'));
    const deb = fakeClamavDeb(dir);
    const uv = fakeUvTarGz(dir);
    const srv = await serve({ '/clamav.deb': deb, '/uv.tar.gz': uv });
    close = srv.close;
    pins = {
      clamav: { version: '9.9.9', url: `${srv.url}/clamav.deb`, sha256: sha256(deb) },
      uv: { version: '0.0.1', url: `${srv.url}/uv.tar.gz`, sha256: sha256(uv) },
      python: '3.12', torchIndex: 'http://127.0.0.1:9/none',
    };
    tools = new Tools({ home: path.join(dir, 'tools'), env: { PATH: process.env.PATH, HOME: dir }, pins });
    const [r] = await tools.setup(['antivirus']);
    expect(r.ok).toBe(true);
  });
  // La actualización de firmas corre en segundo plano y escribe en clamav/db: hay que esperarla
  // antes de borrar el directorio, o el borrado compite con ella (ENOTEMPTY en CI).
  afterEach(async () => { await tools.whenRefreshSettled(); await close(); fs.rmSync(dir, { recursive: true, force: true }); });

  const age = (hours: number) => {
    const old = new Date(Date.now() - hours * 3600_000);
    fs.utimesSync(path.join(dir, 'tools', 'clamav', 'db', '.last-update'), old, old);
  };

  it('usa el ClamAV gestionado con su entorno y analiza varios ficheros en una llamada', async () => {
    const clean = path.join(dir, 'limpio.txt');
    const bad = path.join(dir, 'eicar.txt');
    fs.writeFileSync(clean, 'nada');
    fs.writeFileSync(bad, 'EICAR');
    expect(scannerAvailable(undefined, tools)).toBe(true);
    const r = await scanFiles([clean, bad], { mode: 'required', tools });
    expect(r).toEqual([{ verdict: 'clean' }, { verdict: 'infected', signature: 'Eicar-Test-Signature' }]);
  });

  // Toda llamada con firmas viejas lanza un refresco real en segundo plano que, si acaba bien, deja
  // las firmas al día; sin controlarlo, la segunda llamada compite con él (en un runner rápido ya no
  // hay aviso). Aquí freshclam falla siempre: las firmas siguen viejas de forma determinista.
  it('AC5: con firmas de más de 7 días, required rechaza explicando el motivo; auto analiza y pide actualizar', async () => {
    const stale = new Tools({ home: path.join(dir, 'tools'), env: { PATH: process.env.PATH, HOME: dir, FAKE_FRESHCLAM_FAIL: '1' }, pins });
    const f = path.join(dir, 'a.txt');
    fs.writeFileSync(f, 'x');
    age(8 * 24);
    await expect(scanFiles([f], { mode: 'required', tools: stale })).rejects.toThrow(/SCAN_REQUIRED.*firmas.*8 días/);
    await stale.whenRefreshSettled();
    const r = await scanFiles([f], { mode: 'auto', tools: stale });
    await stale.whenRefreshSettled();
    expect(r[0].verdict).toBe('clean');
    expect(r[0].detail).toMatch(/firmas de hace 8 días/);
  });

  it('AC5: si el refresco en segundo plano acaba bien, el siguiente análisis ya no rechaza por firmas viejas', async () => {
    const f = path.join(dir, 'a.txt');
    fs.writeFileSync(f, 'x');
    age(8 * 24);
    await expect(scanFiles([f], { mode: 'required', tools })).rejects.toThrow(/SCAN_REQUIRED/);
    await tools.whenRefreshSettled();
    expect(await scanFiles([f], { mode: 'required', tools })).toEqual([{ verdict: 'clean' }]);
  });

  it('AC5: firmas de más de 24 h lanzan la actualización en segundo plano sin esperar', async () => {
    const f = path.join(dir, 'a.txt');
    fs.writeFileSync(f, 'x');
    age(30);
    const t = Date.now();
    await scanFile(f, { mode: 'auto', tools });
    expect(Date.now() - t).toBeLessThan(2000);
    const marker = path.join(dir, 'tools', 'clamav', 'db', '.last-update');
    await tools.whenRefreshSettled();
    expect(Date.now() - fs.statSync(marker).mtimeMs).toBeLessThan(3600_000);
  });
});

describe('SE-416 actualización de firmas en segundo plano', () => {
  it('whenRefreshSettled resuelve al instante si no hay actualización en curso', async () => {
    const t = new Tools({ home: fs.mkdtempSync(path.join(os.tmpdir(), 'savia-scan-r-')), pins: null });
    await expect(t.whenRefreshSettled()).resolves.toBeUndefined();
  });
});
