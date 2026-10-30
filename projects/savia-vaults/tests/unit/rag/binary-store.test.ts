// SE-489 M7 — proyecciones derivadas: binding, cifrado, clasificación, ciclo de vida
import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import * as fs from 'node:fs';
import * as os from 'node:os';
import * as path from 'node:path';
import {
  BinaryProjection, Int8Projection, gcProjections, openProjectionSource, projectionPaths, reconcileProjections, rowWordsFor,
} from '../../../src/rag/binary-store.js';
import { FlatVectorStore, readActive, writeActive } from '../../../src/rag/store.js';
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

  it('openProjectionSource sirve la proyección sin cargar los vectores y con las mismas garantías', async () => {
    const { store, dir } = await makeStore(home, { dims: 32, n: 9 });
    const b = BinaryProjection.build(store, 'N2');
    const src = openProjectionSource(dir);
    expect(src.size).toBe(9);
    expect('vector' in src).toBe(false);
    expect(Array.from(BinaryProjection.load(src, 'N2').words)).toEqual(Array.from(b.words));
    expect(() => BinaryProjection.load(src, 'N3')).toThrow(/classification/);
  });

  it('openProjectionSource: sellado sin clave, contrato manipulado y chunks truncados fallan', async () => {
    const cipher = xorCipher(5);
    const s = await makeStore(home, { n: 4, cipher, dome: 'S' });
    expect(() => openProjectionSource(s.dir)).toThrow(/CORRUPT_INDEX/);
    expect(openProjectionSource(s.dir, cipher).size).toBe(4);
    const c = await makeStore(home, { n: 4, dome: 'P' });
    const mf = path.join(c.dir, 'manifest.json');
    const m = JSON.parse(fs.readFileSync(mf, 'utf-8'));
    fs.writeFileSync(mf, JSON.stringify({ ...m, chunkCount: 5 }));
    expect(() => openProjectionSource(c.dir)).toThrow(/CORRUPT_INDEX/);
    fs.writeFileSync(mf, JSON.stringify({ ...m, contract: { ...m.contract, dims: 31 } }));
    expect(() => openProjectionSource(c.dir)).toThrow(/CORRUPT_INDEX/);
    expect(() => openProjectionSource(path.join(home, 'nada'))).toThrow(/NOT_INDEXED/);
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

  it('cabecera JSON no objeto → RagError, no TypeError', async () => {
    const { store, manifest } = await makeStore(home);
    BinaryProjection.build(store, 'N2');
    fs.writeFileSync(projectionPaths(store.dir, manifest.seq, 'binary').header, 'null');
    expect(() => BinaryProjection.load(store, 'N2')).toThrow(/PROJECTION_MISMATCH.*no válida/);
  });

  it('dims que desbordarían la distancia de 16 bits se rechazan al construir', async () => {
    const { store } = await makeStore(home, { dims: 65536, n: 1 });
    expect(() => BinaryProjection.build(store, 'N2')).toThrow(RangeError);
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

    it('la cabecera de una proyección sellada no filtra el hash del contenido en claro', async () => {
      const cipher = xorCipher(7);
      const { store } = await makeStore(home, { dims: 32, n: 8, cipher });
      const clear = await makeStore(home, { dims: 32, n: 8, dome: 'C' });
      const sealedHeader = BinaryProjection.build(store, 'N2', cipher).header;
      const clearHeader = BinaryProjection.build(clear.store, 'N2').header;
      // mismos vectores (misma semilla): el hash en claro coincidiría si la cabecera sellada lo filtrase
      expect(Array.from(BinaryProjection.load(store, 'N2', cipher).words)).toEqual(Array.from(BinaryProjection.load(clear.store, 'N2').words));
      expect(sealedHeader.payloadHash).not.toBe(clearHeader.payloadHash);
    });

    it('AAD: el payload sellado de otra generación no se acepta aunque se reescriba la cabecera', async () => {
      const cipher = xorCipher(7);
      const a = await makeStore(home, { dims: 32, n: 8, digest: 'dig-A', cipher });
      const b = await makeStore(home, { dims: 32, n: 8, digest: 'dig-B', cipher });
      const ha = BinaryProjection.build(a.store, 'N4', cipher).header;
      const hb = BinaryProjection.build(b.store, 'N4', cipher).header;
      expect(ha.binding).not.toBe(hb.binding);
      const pa = projectionPaths(a.dir, 1, 'binary');
      const pb = projectionPaths(b.dir, 1, 'binary');
      fs.copyFileSync(pa.payload, pb.payload);
      fs.writeFileSync(pb.header, JSON.stringify({ ...hb, payloadHash: ha.payloadHash }));
      expect(() => BinaryProjection.load(b.store, 'N4', cipher)).toThrow(/no se pudo abrir/);
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
      expect(gcProjections(dir, s2.manifest)).toBe(0); // dentro del periodo de gracia no se toca nada
      expect(gcProjections(dir, undefined, 0)).toBe(0); // sin manifest legible tampoco
      expect(gcProjections(dir, s2.manifest, 0)).toBe(4); // json+bin de binary e int8 de seq 1
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
        let model = 'm1';
        const domes: RagDomeRef[] = [{ name: 'Docs', confidentiality: 'N2', path: dome, rag: { enabled: true, model: 'm1' } }];
        const svc = new RagService({ domes: () => domes, home: ragHome, embedderFactory: (cfg) => new HashEmbedder(64, cfg, cfg.model) });
        const genDir = (g: string) => path.join(ragHome, 'Docs', g);
        const projOf = (g: string) => fs.readdirSync(genDir(g)).filter((f) => f.startsWith('proj-'));
        const project = (g: string) => {
          const st = FlatVectorStore.load(genDir(g));
          BinaryProjection.build(st, 'N2');
          Int8Projection.build(st, 'N2');
          return st;
        };

        // activa A (m1) con proyecciones
        const A = (await svc.sync('Docs')).generation;
        project(A);
        expect(projOf(A)).toHaveLength(4);

        // sombra B (otro modelo → otra generación) con las suyas; A sigue activa
        domes[0].rag = { enabled: true, model: 'm2' }; model = 'm2';
        const B = (await svc.sync('Docs')).generation;
        expect(B).not.toBe(A);
        const bStore = project(B);
        expect(readActive(ragHome, 'Docs').active).toBe(A);

        // la proyección de A no sirve contra la fuente de B, ni al revés
        for (const ext of ['json', 'bin']) fs.copyFileSync(path.join(genDir(A), `proj-1-binary.${ext}`), path.join(genDir(B), `proj-1-binary.${ext}`));
        expect(() => BinaryProjection.load(bStore, 'N2')).toThrow(/PROJECTION_MISMATCH/);
        BinaryProjection.build(bStore, 'N2');

        // promote B, rollback a A: cada proyección sigue sirviendo contra su propia fuente
        await svc.promote('Docs', B, true);
        expect(readActive(ragHome, 'Docs')).toMatchObject({ active: B, previous: A });
        await svc.rollback('Docs');
        expect(readActive(ragHome, 'Docs').active).toBe(A);
        expect(() => BinaryProjection.load(FlatVectorStore.load(genDir(A)), 'N2')).not.toThrow();
        expect(() => BinaryProjection.load(FlatVectorStore.load(genDir(B)), 'N2')).not.toThrow();

        // la fuente cambia en A → seq 2; el gc del servicio barre las proyecciones de seq 1
        domes[0].rag = { enabled: true, model: 'm1' }; model = 'm1';
        write('c.md', 'regla gamma');
        await svc.sync('Docs');
        const s2 = FlatVectorStore.load(genDir(A));
        expect(s2.manifest.seq).toBe(2);
        expect(projOf(A).filter((f) => f.startsWith('proj-1-'))).toHaveLength(4);
        expect(() => Int8Projection.load(s2, 'N2')).toThrow(/PROJECTION_MISMATCH/);
        await svc.gc('Docs');
        expect(projOf(A).filter((f) => f.startsWith('proj-1-'))).toHaveLength(4); // gracia, como chunks y vectores
        const old = new Date(Date.now() - 20 * 60 * 1000);
        for (const f of projOf(A).filter((x) => x.startsWith('proj-1-'))) fs.utimesSync(path.join(genDir(A), f), old, old);
        await svc.gc('Docs');
        expect(projOf(A).filter((f) => f.startsWith('proj-1-'))).toEqual([]);
        expect(() => BinaryProjection.load(FlatVectorStore.load(genDir(A)), 'N2')).toThrow(/PROJECTION_MISMATCH/); // la seq 2 aún no se proyectó

        // B sale del puntero: el gc borra la generación entera, con sus proyecciones
        writeActive(ragHome, 'Docs', { active: A });
        await svc.gc('Docs');
        expect(fs.existsSync(genDir(B))).toBe(false);
        expect(model).toBe('m1');
      } finally {
        fs.rmSync(root, { recursive: true, force: true });
        fs.rmSync(ragHome, { recursive: true, force: true });
      }
    });

    it('reconcile no destruye nada si el puntero activo falta o es ilegible', async () => {
      const { store, dir } = await makeStore(home, { n: 3 });
      BinaryProjection.build(store, 'N2');
      expect(reconcileProjections(home, 'D')).toBe(0);
      fs.writeFileSync(path.join(home, 'D', 'active.json'), '{no json');
      expect(reconcileProjections(home, 'D')).toBe(0);
      expect(fs.readdirSync(dir).filter((f) => f.startsWith('proj-'))).toHaveLength(2);
    });

    it('gcProjections respeta el periodo de gracia de los temporales de un build en curso', async () => {
      const { dir, manifest } = await makeStore(home, { n: 3 });
      const tmp = path.join(dir, 'proj-1-binary.bin.tmp-123-1');
      fs.writeFileSync(tmp, 'x');
      expect(gcProjections(dir, manifest)).toBe(0);
      expect(fs.existsSync(tmp)).toBe(true);
      expect(gcProjections(dir, manifest, 0)).toBe(1);
      expect(fs.existsSync(tmp)).toBe(false);
    });

    it('reconcile barre proyecciones sueltas en directorios de generación huérfanos', async () => {
      const { dir } = await makeStore(home, { n: 3 });
      const orphan = path.join(home, 'D', 'cafe00000000');
      fs.mkdirSync(orphan);
      fs.writeFileSync(path.join(orphan, 'proj-1-int8.bin'), 'x');
      fs.writeFileSync(path.join(orphan, 'proj-1-int8.json'), '{}');
      writeActive(home, 'D', { active: path.basename(dir) });
      expect(reconcileProjections(home, 'D')).toBe(2);
      expect(fs.existsSync(dir)).toBe(true);
    });
  });
});
