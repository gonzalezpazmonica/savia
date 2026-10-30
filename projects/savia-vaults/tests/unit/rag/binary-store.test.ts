// SE-489 M7 — proyecciones derivadas: binding, cifrado, clasificación, ciclo de vida
import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import * as fs from 'node:fs';
import * as os from 'node:os';
import * as path from 'node:path';
import {
  BinaryProjection, Int8Projection, gcProjections, projectionPaths, reconcileProjections, rowWordsFor,
} from '../../../src/rag/binary-store.js';
import { FlatVectorStore, writeActive } from '../../../src/rag/store.js';
import { RagService, type RagDomeRef } from '../../../src/rag/service.js';
import { HashEmbedder } from '../../../src/rag/embedder.js';
import { makeStore, xorCipher } from './quant-fixture.js';

describe('proyecciones M7', () => {
  let home: string;
  beforeEach(() => { home = fs.mkdtempSync(path.join(os.tmpdir(), 'savia-m7-store-')); });
  afterEach(() => { fs.rmSync(home, { recursive: true, force: true }); });

  it('ida y vuelta: lo cargado es idéntico a lo construido (binaria e int8)', async () => {
    const { store } = await makeStore(home, { dims: 45, n: 25 });
    const b = BinaryProjection.build(store, 'N2');
    const b2 = BinaryProjection.load(store, 'N2');
    expect(Array.from(b2.words)).toEqual(Array.from(b.words));
    expect(b2.rowWords).toBe(rowWordsFor(45));
    const i = Int8Projection.build(store, 'N2');
    const i2 = Int8Projection.load(store, 'N2');
    expect(Array.from(i2.codes)).toEqual(Array.from(i.codes));
    expect(Array.from(i2.calibration.scale)).toEqual(Array.from(i.calibration.scale));
  });

  it('la construcción es determinista: mismo payload y mismo hash', async () => {
    const { store } = await makeStore(home, { dims: 40, n: 30 });
    const h1 = BinaryProjection.build(store, 'N2').header.payloadHash;
    const h2 = BinaryProjection.build(store, 'N2').header.payloadHash;
    expect(h1).toBe(h2);
  });

  it('sin proyección → rechazo', async () => {
    const { store } = await makeStore(home);
    expect(() => BinaryProjection.load(store, 'N2')).toThrow(/PROJECTION_MISMATCH/);
  });

  it('cada campo ligado al binding, alterado en la cabecera, hace rechazar la proyección', async () => {
    const { store, manifest } = await makeStore(home, { dims: 32, n: 12 });
    BinaryProjection.build(store, 'N2');
    const p = projectionPaths(store.dir, manifest.seq, 'binary').header;
    const orig = fs.readFileSync(p, 'utf-8');
    const fields: Record<string, unknown> = {
      generation: 'otra', model: 'otro-modelo', modelDigest: 'sha256:otro', dims: 64, chunkCount: 13,
      chunkOrder: '0'.repeat(64), quantizer: 'sq-v0', seq: 99, classification: 'N4', sealed: true, dome: 'X', headerVersion: 2,
    };
    for (const [k, v] of Object.entries(fields)) {
      fs.writeFileSync(p, JSON.stringify({ ...JSON.parse(orig), [k]: v }));
      expect(() => BinaryProjection.load(store, 'N2'), `campo ${k}`).toThrow(new RegExp(`PROJECTION_MISMATCH.*${k}`));
    }
    fs.writeFileSync(p, orig);
    expect(() => BinaryProjection.load(store, 'N2')).not.toThrow();
  });

  it('el binding se rechaza aunque los campos casen si el hash no corresponde', async () => {
    const { store, manifest } = await makeStore(home);
    BinaryProjection.build(store, 'N2');
    const p = projectionPaths(store.dir, manifest.seq, 'binary').header;
    fs.writeFileSync(p, JSON.stringify({ ...JSON.parse(fs.readFileSync(p, 'utf-8')), binding: 'f'.repeat(64) }));
    expect(() => BinaryProjection.load(store, 'N2')).toThrow(/binding/);
  });

  it('reordenar los chunks con la misma seq invalida la proyección', async () => {
    const { store, dir, manifest, chunks, vectors } = await makeStore(home, { n: 10 });
    BinaryProjection.build(store, 'N2');
    const order = [...chunks.keys()].reverse();
    FlatVectorStore.write(dir, manifest, order.map((i) => chunks[i]), order.map((i) => vectors[i]));
    const reloaded = FlatVectorStore.load(dir);
    expect(() => BinaryProjection.load(reloaded, 'N2')).toThrow(/chunkOrder/);
  });

  it('reclasificar un chunk (confidencialidad de nota) invalida la proyección', async () => {
    const { store, dir, manifest, chunks, vectors } = await makeStore(home, { n: 6, confidentiality: 'N2' });
    BinaryProjection.build(store, 'N2');
    const bumped = chunks.map((c, i) => (i === 0 ? { ...c, meta: { ...c.meta, confidentiality: 'N4' } } : c));
    FlatVectorStore.write(dir, manifest, bumped, vectors);
    expect(() => BinaryProjection.load(FlatVectorStore.load(dir), 'N2')).toThrow(/chunkOrder/);
  });

  it('clasificación distinta de la de la cúpula → rechazo', async () => {
    const { store } = await makeStore(home);
    BinaryProjection.build(store, 'N2');
    expect(() => BinaryProjection.load(store, 'N3')).toThrow(/classification/);
  });

  it('payload alterado → rechazo por hash (índice en claro)', async () => {
    const { store, manifest } = await makeStore(home, { dims: 32, n: 8 });
    BinaryProjection.build(store, 'N2');
    const bin = projectionPaths(store.dir, manifest.seq, 'binary').payload;
    const b = fs.readFileSync(bin);
    b[0] ^= 1;
    fs.writeFileSync(bin, b);
    expect(() => BinaryProjection.load(store, 'N2')).toThrow(/alterado/);
  });

  it('proyección de otra generación (copiada) no casa con esta', async () => {
    const a = await makeStore(home, { dims: 32, n: 8, digest: 'dig-A' });
    const b = await makeStore(home, { dims: 32, n: 8, digest: 'dig-B' });
    expect(a.gen).not.toBe(b.gen);
    BinaryProjection.build(a.store, 'N2');
    for (const ext of ['json', 'bin']) {
      fs.copyFileSync(path.join(a.dir, `proj-1-binary.${ext}`), path.join(b.dir, `proj-1-binary.${ext}`));
    }
    expect(() => BinaryProjection.load(b.store, 'N2')).toThrow(/PROJECTION_MISMATCH/);
  });

  describe('cifrado: sigue a la fuente', () => {
    it('fuente sellada → payload sellado en disco y legible solo con el cifrador', async () => {
      const cipher = xorCipher(7);
      const { store, manifest } = await makeStore(home, { dims: 32, n: 8, cipher });
      const b = BinaryProjection.build(store, 'N4', cipher);
      const onDisk = fs.readFileSync(projectionPaths(store.dir, manifest.seq, 'binary').payload);
      expect(onDisk.subarray(0, 20).toString()).toContain('proj-1-binary');
      expect(Buffer.from(b.words.buffer).equals(onDisk)).toBe(false);
      expect(Array.from(BinaryProjection.load(store, 'N4', cipher).words)).toEqual(Array.from(b.words));
      expect(() => BinaryProjection.load(store, 'N4')).toThrow(/cifrador/);
      expect(() => BinaryProjection.load(store, 'N4', xorCipher(9))).toThrow(/PROJECTION_MISMATCH/);
    });

    it('fuente sellada sin cifrador → no se escribe nada en claro', async () => {
      const cipher = xorCipher(7);
      const { store, manifest } = await makeStore(home, { n: 5, cipher });
      expect(() => BinaryProjection.build(store, 'N4')).toThrow(/cifrad/);
      expect(() => Int8Projection.build(store, 'N4')).toThrow(/cifrad/);
      expect(fs.existsSync(projectionPaths(store.dir, manifest.seq, 'binary').payload)).toBe(false);
    });

    it('degradación: proyección en claro reutilizada con fuente sellada se rechaza', async () => {
      const cipher = xorCipher(7);
      const clear = await makeStore(home, { n: 5, dome: 'C' });
      BinaryProjection.build(clear.store, 'N2');
      const sealed = await makeStore(home, { n: 5, dome: 'C', cipher });
      // misma generación y seq: el fichero en claro sigue ahí tras reescribir la fuente sellada
      expect(() => BinaryProjection.load(sealed.store, 'N2', cipher)).toThrow(/PROJECTION_MISMATCH/);
    });
  });

  it('nunca se escribe dentro de un repo git', async () => {
    const repo = fs.mkdtempSync(path.join(os.tmpdir(), 'savia-m7-git-'));
    try {
      const { store, dir } = await makeStore(home, { n: 4 });
      const inRepo = path.join(repo, 'gen');
      fs.mkdirSync(path.join(repo, '.git'));
      fs.writeFileSync(path.join(repo, '.git', 'HEAD'), 'ref: refs/heads/main\n');
      fs.cpSync(dir, inRepo, { recursive: true });
      const moved = FlatVectorStore.load(inRepo);
      expect(() => BinaryProjection.build(moved, 'N2')).toThrow(/UNSAFE_HOME/);
      expect(fs.readdirSync(inRepo).some((f) => f.startsWith('proj-'))).toBe(false);
      expect(store.size).toBe(4);
    } finally { fs.rmSync(repo, { recursive: true, force: true }); }
  });

  it('ficheros 0600', async () => {
    const { store, manifest } = await makeStore(home, { n: 3 });
    BinaryProjection.build(store, 'N2');
    for (const f of Object.values(projectionPaths(store.dir, manifest.seq, 'binary'))) {
      expect(fs.statSync(f).mode & 0o777).toBe(0o600);
    }
  });

  describe('ciclo de vida de la generación (AC-3)', () => {
    it('gcProjections borra las de otra seq y conserva las vigentes', async () => {
      const { store, dir, manifest, chunks, vectors } = await makeStore(home, { n: 6 });
      BinaryProjection.build(store, 'N2');
      Int8Projection.build(store, 'N2');
      const next = { ...manifest, seq: 2 };
      FlatVectorStore.write(dir, next, chunks, vectors);
      const s2 = FlatVectorStore.load(dir);
      BinaryProjection.build(s2, 'N2');
      expect(gcProjections(dir, s2.manifest)).toBe(4); // json+bin de binary e int8 de seq 1
      expect(fs.readdirSync(dir).filter((f) => f.startsWith('proj-1-'))).toEqual([]);
      expect(() => BinaryProjection.load(s2, 'N2')).not.toThrow();
    });

    it('sombra → activa → rollback → GC con el RagService real: no quedan proyecciones obsoletas', async () => {
      const root = fs.mkdtempSync(path.join(os.tmpdir(), 'savia-m7-svc-'));
      const ragHome = fs.mkdtempSync(path.join(os.tmpdir(), 'savia-m7-svc-home-'));
      try {
        const dome = path.join(root, 'Docs');
        fs.mkdirSync(dome, { recursive: true });
        const write = (n: string, t: string) => fs.writeFileSync(path.join(dome, n), `# ${n}\n\n${`${t}. `.repeat(12)}`);
        write('a.md', 'regla alfa'); write('b.md', 'regla beta');
        const domes: RagDomeRef[] = [{ name: 'Docs', confidentiality: 'N2', path: dome, rag: { enabled: true, model: 'm1' } }];
        const svc = new RagService({ domes: () => domes, home: ragHome, embedderFactory: (cfg) => new HashEmbedder(64, cfg, cfg.model) });
        const first = await svc.sync('Docs');
        const genDir = (g: string) => path.join(ragHome, 'Docs', g);
        const projOf = (g: string) => fs.readdirSync(genDir(g)).filter((f) => f.startsWith('proj-'));

        // proyecciones de la activa (seq 1)
        const s1 = FlatVectorStore.load(genDir(first.generation));
        BinaryProjection.build(s1, 'N2');
        Int8Projection.build(s1, 'N2');
        expect(projOf(first.generation)).toHaveLength(4);

        // cambia la fuente → seq 2 en la misma generación, y se proyecta de nuevo
        write('c.md', 'regla gamma');
        await svc.sync('Docs');
        const s2 = FlatVectorStore.load(genDir(first.generation));
        expect(s2.manifest.seq).toBe(2);
        BinaryProjection.build(s2, 'N2');
        expect(projOf(first.generation).filter((f) => f.startsWith('proj-1-'))).toHaveLength(4);

        // gc del servicio: limpia chunks/vectors de seq 1 pero NO las proyecciones (hueco que cubre reconcile)
        await svc.gc('Docs');
        expect(projOf(first.generation).filter((f) => f.startsWith('proj-1-')).length).toBeGreaterThan(0);
        // la proyección obsoleta no se puede cargar contra la fuente vigente
        expect(() => Int8Projection.load(s2, 'N2')).toThrow(/PROJECTION_MISMATCH/);
        expect(reconcileProjections(ragHome, 'Docs')).toBe(4);
        expect(projOf(first.generation).filter((f) => f.startsWith('proj-1-'))).toEqual([]);

        // generación retirada: el directorio entero (con sus proyecciones) se va con el gc del servicio
        const retired = path.join(ragHome, 'Docs', 'deadbeef0000');
        fs.mkdirSync(retired, { recursive: true });
        fs.writeFileSync(path.join(retired, 'proj-1-binary.bin'), 'x');
        writeActive(ragHome, 'Docs', { active: first.generation });
        await svc.gc('Docs');
        expect(fs.existsSync(retired)).toBe(false);

        // rollback: una proyección de la generación anterior solo sirve contra su propia fuente
        writeActive(ragHome, 'Docs', { active: first.generation, previous: first.generation });
        await svc.rollback('Docs');
        expect(reconcileProjections(ragHome, 'Docs')).toBe(0);
      } finally {
        fs.rmSync(root, { recursive: true, force: true });
        fs.rmSync(ragHome, { recursive: true, force: true });
      }
    });

    it('reconcile barre proyecciones sueltas en directorios de generación huérfanos', async () => {
      const { dir } = await makeStore(home, { n: 3 });
      const orphan = path.join(home, 'D', 'cafe00000000');
      fs.mkdirSync(orphan);
      fs.writeFileSync(path.join(orphan, 'proj-1-int8.bin'), 'x');
      fs.writeFileSync(path.join(orphan, 'proj-1-int8.json'), '{}');
      // sin puntero activo: todo directorio de generación es huérfano
      expect(reconcileProjections(home, 'D')).toBe(2);
      expect(fs.existsSync(dir)).toBe(true);
    });
  });
});
