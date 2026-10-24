// SE-421 — almacén en streaming de extremo a extremo: alta y lectura por streams en claras y
// cifradas (AC1/AC2), rangos (AC3), integridad al final (AC4), límites (AC5), antivirus por stdin
// (AC6), tope de extracción (AC7), SVFU1 (AC8) y gc con altas en curso.
import { describe, it, expect, beforeAll, beforeEach, afterEach } from 'vitest';
import * as fs from 'node:fs';
import * as os from 'node:os';
import * as path from 'node:path';
import { createHash, randomBytes } from 'node:crypto';
import { Readable } from 'node:stream';
import { FileStore, TypeSniffer, detectType, textEncoding } from '../../../src/files/store.js';
import { FilesService, type FilesDomeRef } from '../../../src/files/service.js';
import { Journal } from '../../../src/files/journal.js';
import { scanStream, scannerAvailable } from '../../../src/files/scan.js';
import { STALE_AFTER_H, Tools } from '../../../src/files/setup.js';
import {
  FRAME_PLAIN_BYTES, UPLOAD_MAGIC, encryptStream, decryptStream, openUploadChunks, randomKey, sealUploadChunk, sodiumReady,
} from '../../../src/files/crypto.js';

const sha = (b: Buffer) => createHash('sha256').update(b).digest('hex');
const chunks = (b: Buffer, size = 64 * 1024) => Readable.from((function* () { for (let i = 0; i < b.length; i += size) yield b.subarray(i, i + size); })());
const collect = async (r: Readable) => { const out: Buffer[] = []; for await (const c of r) out.push(c as Buffer); return Buffer.concat(out); };
const EICAR = 'X5O!P%@AP[4\\PZX54(P^)7CC)7}$EICAR-STANDARD-ANTIVIRUS-TEST-FILE!$H+H*';
const FIX = path.resolve('tests/fixtures/files');

beforeAll(async () => { await sodiumReady(); });

describe('SE-421 almacén en streaming', () => {
  let root: string;
  let keys: string;
  const mk = (dome: string, encrypt = false, limits = {}) => new FileStore({ home: path.join(root, 'files'), dome, keysHome: keys, encrypt, domeLevel: encrypt ? 'N3' : 'N2', limits });
  beforeEach(() => {
    root = fs.mkdtempSync(path.join(os.tmpdir(), 'savia-stream-'));
    keys = path.join(root, 'keys');
  });
  afterEach(() => { Journal.closeAll(); fs.rmSync(root, { recursive: true, force: true }); });

  for (const encrypt of [false, true]) {
    const label = encrypt ? 'N3 cifrada' : 'N2 en claro';

    it(`AC1/AC2 (${label}): addStream y openRead devuelven los mismos bytes; ${encrypt ? 'nada en claro en disco' : 'blob por SHA-256'}`, async () => {
      const store = mk('D', encrypt);
      const data = Buffer.concat([Buffer.from('%PDF-1.7\n'), randomBytes(3 * FRAME_PLAIN_BYTES + 12345)]);
      const { document, revision } = await store.addStream({ name: 'grande.pdf', source: chunks(data) });
      expect(revision).toMatchObject({ sha256: sha(data), size: data.length, type: 'pdf' });
      expect(sha(await collect(store.openRead(document.id).stream))).toBe(sha(data));
      if (encrypt) {
        const walk = (d: string): string[] => fs.readdirSync(d, { withFileTypes: true }).flatMap((e) => (e.isDirectory() ? walk(path.join(d, e.name)) : [path.join(d, e.name)]));
        const probe = data.subarray(FRAME_PLAIN_BYTES, FRAME_PLAIN_BYTES + 64);
        expect(walk(path.join(root, 'files', 'D')).filter((f) => fs.readFileSync(f).includes(probe))).toEqual([]);
        // Formato SVF1 de SE-417: el descifrado de siempre lo lee
        const blob = fs.readFileSync(path.join(root, 'files', 'D', 'blobs', `${revision.id}.svf`));
        expect(createHash('sha256').update(blob).digest('hex')).toBe(revision.blobHash);
      } else {
        expect(fs.existsSync(store.blobPath(revision.sha256))).toBe(true);
      }
    });

    it(`AC3 (${label}): rangos exactos (inicio, medio, final, fronteras de frame, 1 byte)`, async () => {
      const store = mk('D', encrypt);
      const data = randomBytes(2 * FRAME_PLAIN_BYTES + 777);
      const { document } = await store.addStream({ name: 'x.bin', source: chunks(data) });
      const cases: [number, number][] = [[0, 99], [FRAME_PLAIN_BYTES - 10, FRAME_PLAIN_BYTES + 10], [data.length - 50, data.length - 1],
        [12345, 12345], [0, data.length - 1], [FRAME_PLAIN_BYTES, 2 * FRAME_PLAIN_BYTES]];
      for (const [start, end] of cases) {
        const r = store.openRead(document.id, undefined, { start, end });
        expect((await collect(r.stream)).equals(data.subarray(start, end + 1))).toBe(true);
      }
      expect(() => store.openRead(document.id, undefined, { start: data.length, end: data.length })).toThrow(/INVALID_INPUT/);
      expect(() => store.openRead(document.id, undefined, { start: 10, end: 5 })).toThrow(/INVALID_INPUT/);
    });
  }

  it('AC2: ficheros guardados con add (SE-417) se leen por stream; encryptStream/decryptStream siguen compatibles', async () => {
    const store = mk('S', true);
    const data = randomBytes(FRAME_PLAIN_BYTES + 5);
    const { document } = store.add({ name: 'viejo.bin', bytes: data });
    expect((await collect(store.openRead(document.id).stream)).equals(data)).toBe(true);
    const k = randomKey();
    for (const n of [0, 1, FRAME_PLAIN_BYTES, FRAME_PLAIN_BYTES + 1, 3 * FRAME_PLAIN_BYTES]) {
      const b = randomBytes(n);
      expect(decryptStream(k, encryptStream(k, b, { a: 1 }), { a: 1 }).equals(b)).toBe(true);
    }
  });

  it('AC3/AC4: frame manipulado en el rango ⇒ INTEGRITY; blob en claro manipulado ⇒ error al final del stream', async () => {
    const enc = mk('S', true);
    const data = randomBytes(2 * FRAME_PLAIN_BYTES);
    const a = await enc.addStream({ name: 'x.bin', source: chunks(data) });
    const file = path.join(root, 'files', 'S', 'blobs', `${a.revision.id}.svf`);
    fs.chmodSync(file, 0o600);
    const buf = fs.readFileSync(file);
    buf[buf.length - 100] ^= 1; // segundo frame
    fs.writeFileSync(file, buf);
    await expect(collect(enc.openRead(a.document.id, undefined, { start: FRAME_PLAIN_BYTES + 5, end: FRAME_PLAIN_BYTES + 10 }).stream)).rejects.toThrow(/INTEGRITY/);
    await expect(collect(enc.openRead(a.document.id).stream)).rejects.toThrow(/INTEGRITY/);
    const plain = mk('D');
    const b = await plain.addStream({ name: 'y.bin', source: chunks(data) });
    const blob = plain.blobPath(b.revision.sha256);
    fs.chmodSync(blob, 0o600);
    const pb = fs.readFileSync(blob); pb[7] ^= 1; fs.writeFileSync(blob, pb);
    await expect(collect(plain.openRead(b.document.id).stream)).rejects.toThrow(/INTEGRITY/);
  });

  it('AC5: TOO_LARGE a mitad de stream sin temporales ni envoltura; límite de cúpula; readBytes grande ⇒ TOO_LARGE', async () => {
    const store = mk('S', true, { maxBytes: 3 * 64 * 1024 });
    await expect(store.addStream({ name: 'x.bin', source: chunks(randomBytes(4 * 64 * 1024)) })).rejects.toThrow(/TOO_LARGE/);
    expect(fs.readdirSync(path.join(root, 'files', 'S', 'blobs'))).toEqual([]);
    const wraps = path.join(keys, 'S', 'wraps');
    expect(fs.existsSync(wraps) ? fs.readdirSync(wraps) : []).toEqual([]);
    const small = mk('D', false, { maxTransferBytes: 1000 });
    const { document } = await small.addStream({ name: 'x.bin', source: chunks(randomBytes(2000)) });
    expect(() => small.readBytes(document.id)).toThrow(/TOO_LARGE.*streaming/);
    // files.maxBytes de la cúpula manda si es menor
    const svc = new FilesService({ domes: () => [{ name: 'L', confidentiality: 'N2', files: { enabled: true, maxBytes: 100 } }] as FilesDomeRef[], env: { SAVIA_FILES_HOME: path.join(root, 'files'), SAVIA_FILES_KEYS_HOME: keys }, scanMode: 'off' });
    await expect(svc.putMany({ dome: 'L', files: [{ name: 'a.bin', size: 101, stream: () => chunks(randomBytes(101)) }] })).rejects.toThrow(/TOO_LARGE/);
    await expect(svc.putMany({ dome: 'L', files: [{ name: 'a.bin', stream: () => chunks(randomBytes(101)) }] })).rejects.toThrow(/TOO_LARGE/);
  });

  it('TypeSniffer equivale a detectType/textEncoding sobre el fichero entero', () => {
    const samples: [string, Buffer][] = [
      ['contrato.pdf', fs.readFileSync(path.join(FIX, 'contrato.pdf'))],
      ...fs.readdirSync(FIX).filter((f) => /\.(docx|pptx|xlsx|csv|md|txt|json)$/.test(f)).map((f) => [f, fs.readFileSync(path.join(FIX, f))] as [string, Buffer]),
      ['falso.pdf', Buffer.from('no es pdf')], ['utf8.txt', Buffer.from('ñandú €')], ['cp.csv', Buffer.from([0x61, 0xf1, 0x0a])],
      ['nul.txt', Buffer.from([0x61, 0, 0x62])], ['ctrl.txt', Buffer.from([0x61, 0x01, 0xf1])], ['raro.xyz', Buffer.from('x')],
      ['cortado.txt', Buffer.from('añ€', 'utf-8')],
    ];
    for (const [name, bytes] of samples) {
      for (const size of [1, 3, 7, 1024]) {
        const s = new TypeSniffer(name);
        for (let i = 0; i < bytes.length; i += size) s.feed(bytes.subarray(i, i + size));
        const type = detectType(name, bytes);
        expect(s.result(), `${name} en trozos de ${size}`).toEqual(['txt', 'md', 'csv', 'json'].includes(type) ? { type, encoding: textEncoding(bytes) } : { type });
      }
    }
  });

  it('AC6: antivirus por stdin (falso clamscan): limpio, infectado y tope de tamaño', async () => {
    const fake = path.join(root, 'clamscan');
    fs.writeFileSync(fake, '#!/bin/sh\nif grep -q EICAR -; then echo "stdin: Eicar-Test-Signature FOUND"; exit 1; fi\necho "stdin: OK"\nexit 0\n', { mode: 0o700 });
    expect(await scanStream(() => Readable.from([Buffer.from('limpio')]), 6, { mode: 'required', clamscan: fake })).toEqual({ verdict: 'clean' });
    expect(await scanStream(() => Readable.from([Buffer.from(`x${EICAR}x`)]), 70, { mode: 'auto', clamscan: fake }))
      .toMatchObject({ verdict: 'infected', signature: 'Eicar-Test-Signature' });
    let opened = false;
    expect(await scanStream(() => { opened = true; return Readable.from([]); }, 5 * 1024 ** 3, { mode: 'auto', clamscan: fake }))
      .toEqual({ verdict: 'error', detail: 'too-large-to-scan' });
    expect(opened).toBe(false);
    await expect(scanStream(() => Readable.from([]), 5 * 1024 ** 3, { mode: 'required', clamscan: fake })).rejects.toThrow(/SCAN_REQUIRED/);
  });

  it('AC6: con el ClamAV gestionado real, EICAR cifrado grande se analiza por stdin y queda QUARANTINED', async () => {
    const tools = new Tools();
    if (!scannerAvailable(undefined, tools)) return; // sin ClamAV instalado en esta máquina
    // Con firmas gestionadas de más de 7 días `required` rechaza por diseño: no es lo que se prueba aquí.
    if ((tools.clamav()?.signaturesAgeHours ?? 0) > STALE_AFTER_H) return;
    const store = mk('S', true, { maxExtractBytes: 10 }); // fuerza la vía stdin (por encima del tope de extracción)
    const svc = new FilesService({
      domes: () => [{ name: 'S', confidentiality: 'N3', files: { enabled: true } }] as FilesDomeRef[],
      env: { SAVIA_FILES_HOME: path.join(root, 'files'), SAVIA_FILES_KEYS_HOME: keys, SAVIA_FILES_MAX_EXTRACT_BYTES: '10' }, scanMode: 'required', tools,
    });
    const shm = () => fs.readdirSync('/dev/shm').filter((f) => f.startsWith('savia-files-')).length;
    const before = shm();
    const [r] = await svc.putMany({ dome: 'S', files: [{ name: 'eicar.txt', stream: () => Readable.from([Buffer.from(EICAR)]) }] });
    expect(r.status).toBe('QUARANTINED');
    expect(shm()).toBe(before);
    expect(store.list()).toHaveLength(1);
  }, 180_000);

  it('AC7: un fichero soportado por encima del tope de extracción queda ARCHIVE_ONLY sin worker', async () => {
    const svc = new FilesService({
      domes: () => [{ name: 'D', confidentiality: 'N2', files: { enabled: true } }] as FilesDomeRef[],
      env: { SAVIA_FILES_HOME: path.join(root, 'files'), SAVIA_FILES_KEYS_HOME: keys, SAVIA_FILES_MAX_EXTRACT_BYTES: '1000' },
      scanMode: 'off', python: path.join(root, 'no-hay-python'),
    });
    const pdf = fs.readFileSync(path.join(FIX, 'contrato.pdf'));
    expect(pdf.length).toBeGreaterThan(1000);
    const [r] = await svc.putMany({ dome: 'D', files: [{ name: 'contrato.pdf', stream: () => chunks(pdf, 100) }] });
    expect(r).toMatchObject({ status: 'ARCHIVE_ONLY', skipped: [{ reason: 'too-large-to-extract', count: 1 }] });
    const small = await svc.putMany({ dome: 'D', files: [{ name: 'nota.md', stream: () => chunks(Buffer.from('# Hola\n\ntexto\n'), 3) }] });
    expect(small[0]).toMatchObject({ status: 'READY' });
  });

  it('AC8: SVFU1 — trozos de varias sesiones, orden y manipulación', () => {
    const k = randomKey();
    const parts = [randomBytes(1000), randomBytes(5), Buffer.alloc(0), randomBytes(300)];
    const file = Buffer.concat([UPLOAD_MAGIC, ...parts.map((p, i) => sealUploadChunk(k, 'u1', i, p, i === parts.length - 1))]);
    expect(Buffer.concat([...openUploadChunks(k, 'u1', file)]).equals(Buffer.concat(parts))).toBe(true);
    expect(() => [...openUploadChunks(k, 'otra', file)]).toThrow(/INTEGRITY/);
    const swapped = Buffer.concat([UPLOAD_MAGIC, sealUploadChunk(k, 'u1', 1, parts[1], false), sealUploadChunk(k, 'u1', 0, parts[0], true)]);
    expect(() => [...openUploadChunks(k, 'u1', swapped)]).toThrow(/INTEGRITY/);
    const noFinal = Buffer.concat([UPLOAD_MAGIC, sealUploadChunk(k, 'u1', 0, parts[0], false)]);
    expect(() => [...openUploadChunks(k, 'u1', noFinal)]).toThrow(/INTEGRITY/);
    const bad = Buffer.from(file); bad[UPLOAD_MAGIC.length + 30] ^= 1;
    expect(() => [...openUploadChunks(k, 'u1', bad)]).toThrow(/INTEGRITY/);
  });

  it('gc no borra el temporal ni la envoltura de un alta en streaming en curso', async () => {
    const store = mk('S', true);
    await store.addStream({ name: 'a.bin', source: chunks(randomBytes(10)) });
    let release!: () => void;
    const gate = new Promise<void>((r) => { release = r; });
    const pending = store.addStream({ name: 'b.bin', source: (async function* () { yield randomBytes(100); await gate; yield randomBytes(100); })() });
    await new Promise((r) => setTimeout(r, 50));
    expect(mk('S', true).gc()).toEqual({ blobs: 0, extractions: 0 });
    release();
    const { document } = await pending;
    expect((await collect(store.openRead(document.id).stream)).length).toBe(200);
  });
});
