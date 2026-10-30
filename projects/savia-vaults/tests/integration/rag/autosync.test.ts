// SE-480 R2 — sincronizador autónomo: reloj falso, embedder falso, sin esperas reales (AC-4, AC-5, AC-6, AC-8)
import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import * as fs from 'node:fs';
import * as os from 'node:os';
import * as path from 'node:path';
import { RagService, type RagDomeRef } from '../../../src/rag/service.js';
import { envMs } from '../../../src/env-ms.js';
import { RagAutosync, AUTOSYNC_START_DELAY_MS, AUTOSYNC_MAX_INTERVAL_MIN, readAutosyncState, type AutosyncClock } from '../../../src/rag/autosync.js';
import { HashEmbedder, type Embedder } from '../../../src/rag/embedder.js';
import { acquireLock, releaseLock } from '../../../src/rag/indexer.js';
import { domeDir } from '../../../src/rag/store.js';
import { RagError, type ResolvedRagConfig } from '../../../src/rag/types.js';

const long = (s: string) => `${s}. `.repeat(12);

/** Reloj controlado: los temporizadores solo disparan al avanzar el tiempo. */
class FakeClock implements AutosyncClock {
  t = Date.parse('2026-10-30T10:00:00Z');
  private seq = 0;
  private pending = new Map<number, { at: number; fn: () => void }>();
  now() { return this.t; }
  setTimeout(fn: () => void, ms: number) { const id = ++this.seq; this.pending.set(id, { at: this.t + ms, fn }); return id; }
  clearTimeout(h: unknown) { this.pending.delete(h as number); }
  get timers() { return this.pending.size; }
  advance(ms: number) {
    const end = this.t + ms;
    for (;;) {
      const next = [...this.pending.entries()].filter(([, v]) => v.at <= end).sort((a, b) => a[1].at - b[1].at)[0];
      if (!next) break;
      this.pending.delete(next[0]);
      this.t = next[1].at;
      next[1].fn();
    }
    this.t = end;
  }
}

class FlakyEmbedder extends HashEmbedder {
  fail = false;
  calls = 0;
  async contract() { if (this.fail) throw new RagError('EMBEDDER_UNAVAILABLE', 'ollama caído'); return super.contract(); }
  async embed(texts: string[], kind: 'query' | 'doc' = 'doc') {
    this.calls++;
    if (this.fail) throw new RagError('EMBEDDER_UNAVAILABLE', 'ollama caído');
    return super.embed(texts, kind);
  }
}

describe('RagAutosync (SE-480)', () => {
  let root: string;
  let home: string;
  let dome: RagDomeRef;
  let embedder: FlakyEmbedder;
  let rag: RagService;
  let clock: FakeClock;

  const note = (rel: string, body: string) => {
    fs.mkdirSync(path.dirname(path.join(dome.path, rel)), { recursive: true });
    fs.writeFileSync(path.join(dome.path, rel), `# ${rel}\n\n${long(body)}`);
  };
  const autosync = (extra: Partial<ConstructorParameters<typeof RagAutosync>[1]> = {}) => {
    const a = new RagAutosync(rag, { intervalMin: 15, clock, log: () => {}, ...extra });
    rag.setAutosyncState(() => a.getState());
    return a;
  };
  const hits = async (q: string) => (await rag.search({ queries: [q], domes: ['Docs'] }));
  const paths = (res: Awaited<ReturnType<typeof hits>>) => res.results[0].hits.map(h => h.path);

  beforeEach(() => {
    root = fs.mkdtempSync(path.join(os.tmpdir(), 'savia-autosync-'));
    home = fs.mkdtempSync(path.join(os.tmpdir(), 'savia-autosync-home-'));
    embedder = new FlakyEmbedder(64);
    clock = new FakeClock();
    clock.t = Date.now(); // lastRunAt persistido debe ser reciente para status (caducidad)
    dome = { name: 'Docs', confidentiality: 'N2', path: path.join(root, 'Docs'), rag: { enabled: true, model: 'm1' } };
    note('a.md', 'documento inicial sobre pagos');
    rag = new RagService({ domes: () => [dome], home, embedderFactory: (_c: ResolvedRagConfig): Embedder => embedder });
  });
  afterEach(() => {
    fs.rmSync(root, { recursive: true, force: true });
    fs.rmSync(home, { recursive: true, force: true });
  });

  it('AC-4: una nota nueva aparece en vault_rag tras un ciclo, sin cron', async () => {
    const a = autosync();
    a.start();
    clock.advance(AUTOSYNC_START_DELAY_MS);
    await a.whenIdle();
    expect(paths(await hits('pagos'))).toContain('a.md');

    note('b.md', 'jirafa cuántica única');
    expect((await rag.status(['Docs']))[0].pendingDocs).toBe(1); // antes del ciclo, la nota no está indexada
    clock.advance(15 * 60_000 - 1);
    await a.whenIdle();
    expect((await rag.status(['Docs']))[0].pendingDocs).toBe(1); // aún no toca
    clock.advance(1);
    await a.whenIdle();
    expect((await rag.status(['Docs']))[0].pendingDocs).toBe(0);
    expect(paths(await hits('jirafa cuántica'))).toContain('b.md');
    expect(a.getState()).toMatchObject({ lastOk: true, consecutiveFailures: 0 });
    a.stop();
  });

  it('AC-5: con el lock tomado por otro proceso el ciclo termina en skipped:LOCKED y el servicio sigue', async () => {
    const a = autosync();
    const dir = domeDir(home, 'Docs');
    expect(acquireLock(dir)).toBe(true);
    try {
      await a.runCycle();
      expect(a.getState().lastResults).toEqual({ Docs: 'skipped:LOCKED' });
      expect(a.getState().consecutiveFailures).toBe(0);
    } finally {
      releaseLock(dir);
    }
    await a.runCycle();
    expect(a.getState().lastResults).toEqual({ Docs: 'ok' });
    expect(a.getState().lastOk).toBe(true);
  });

  it('AC-6: tres fallos seguidos del embedder → slo.ok:false con autosync-failing y la búsqueda sigue en BM25', async () => {
    await rag.sync('Docs');
    const a = autosync();
    embedder.fail = true;
    for (let i = 1; i <= 2; i++) {
      await a.runCycle();
      expect(a.getState().consecutiveFailures).toBe(i);
      expect((await rag.status(['Docs']))[0].slo.alerts).not.toContain('autosync-failing');
    }
    await a.runCycle();
    const st = (await rag.status(['Docs']))[0];
    expect(a.getState()).toMatchObject({ lastOk: false, consecutiveFailures: 3 });
    expect(a.getState().lastError).toMatch(/ollama caído/);
    expect(st.slo.ok).toBe(false);
    expect(st.slo.alerts).toContain('autosync-failing');
    expect(st.autosync?.consecutiveFailures).toBe(3);

    const res = await hits('documento pagos');
    expect(res.domes[0].status).toBe('degraded');
    expect(paths(res)).toContain('a.md');

    embedder.fail = false;
    await a.runCycle();
    expect(a.getState()).toMatchObject({ lastOk: true, consecutiveFailures: 0 });
    expect((await rag.status(['Docs']))[0].slo.alerts).not.toContain('autosync-failing');
  });

  it('P1 #1418: la alerta autosync-failing llega a un RagService de OTRO proceso (sin provider) vía estado persistido', async () => {
    await rag.sync('Docs');
    const a = autosync({ onState: (st) => rag.persistAutosyncState(st) });
    embedder.fail = true;
    const other = new RagService({ domes: () => [dome], home, embedderFactory: (_c: ResolvedRagConfig): Embedder => embedder });
    for (let i = 1; i <= 2; i++) {
      await a.runCycle();
      const st = (await other.status(['Docs']))[0];
      expect(st.autosync?.consecutiveFailures).toBe(i);
      expect(st.slo.alerts).not.toContain('autosync-failing');
    }
    await a.runCycle();
    const st = (await other.status(['Docs']))[0];
    expect(st.slo.ok).toBe(false);
    expect(st.slo.alerts).toContain('autosync-failing');
    embedder.fail = false;
    await a.runCycle();
    expect((await other.status(['Docs']))[0].slo.alerts).not.toContain('autosync-failing');
  });

  it('P1 #1418 (negativo): sin fichero de estado, o corrupto, status no inventa autosync ni alerta', async () => {
    await rag.sync('Docs');
    expect((await rag.status(['Docs']))[0].autosync).toBeUndefined();
    fs.writeFileSync(path.join(home, 'autosync-state.json'), '{"consecutiveFailures":"tres"');
    expect((await rag.status(['Docs']))[0].autosync).toBeUndefined();
    fs.writeFileSync(path.join(home, 'autosync-state.json'), '{"consecutiveFailures":"3"}');
    const st = (await rag.status(['Docs']))[0];
    expect(st.autosync).toBeUndefined();
    expect(st.slo.alerts).not.toContain('autosync-failing');
  });

  const persisted = (over: object) => fs.writeFileSync(path.join(home, 'autosync-state.json'), JSON.stringify({ intervalMin: 15, running: false, consecutiveFailures: 5, lastOk: false, lastResults: {}, ...over }));

  it('P1 #1418: un estado persistido caducado (servicio parado) no genera alerta ni autosync; uno vivo sí', async () => {
    await rag.sync('Docs');
    persisted({ lastRunAt: new Date(Date.now() - 4 * 15 * 60_000).toISOString() });
    const old = (await rag.status(['Docs']))[0];
    expect(old.autosync).toBeUndefined();
    expect(old.slo.alerts).not.toContain('autosync-failing');
    persisted({ lastRunAt: new Date(Date.now() - 2 * 15 * 60_000).toISOString() });
    const live = (await rag.status(['Docs']))[0];
    expect(live.slo.alerts).toContain('autosync-failing');
    persisted({});
    expect(readAutosyncState(home)).toBeUndefined(); // sin lastRunAt: fail-closed
  });

  it('P1 #1418 (seguridad): el informe de una cúpula no lleva resultados ni errores de otras', async () => {
    const secret: RagDomeRef = { name: 'Secret', confidentiality: 'N4', path: path.join(root, 'Secret'), rag: { enabled: true, model: 'm1' } };
    fs.mkdirSync(secret.path, { recursive: true });
    const two = new RagService({ domes: () => [dome, secret], home, embedderFactory: (_c: ResolvedRagConfig): Embedder => embedder });
    persisted({ lastRunAt: new Date().toISOString(), lastError: 'Secret: ENOENT /n4/privado.md', lastResults: { Docs: 'ok', Secret: 'error:ENOENT /n4/privado.md' } });
    const [docs] = await two.status(['Docs']);
    expect(docs.autosync?.lastResults).toEqual({ Docs: 'ok' });
    expect(JSON.stringify(docs)).not.toMatch(/Secret|privado/);
    const [sec] = await two.status(['Secret']);
    expect(sec.autosync?.lastError).toBe('Secret: ENOENT /n4/privado.md');
    expect(Object.keys(sec.autosync?.lastResults ?? {})).toEqual(['Secret']);
  });

  it('P2 #1418: el fichero de estado es privado (0600) y los minutos tienen tope', () => {
    const a = autosync({ onState: (st) => rag.persistAutosyncState(st) });
    return a.runCycle().then(() => {
      expect(fs.statSync(path.join(home, 'autosync-state.json')).mode & 0o777).toBe(0o600);
      expect(() => new RagAutosync(rag, { intervalMin: AUTOSYNC_MAX_INTERVAL_MIN, clock, log: () => {} })).not.toThrow();
      expect(() => new RagAutosync(rag, { intervalMin: AUTOSYNC_MAX_INTERVAL_MIN + 1, clock, log: () => {} })).toThrow(/minutos/);
      expect(AUTOSYNC_MAX_INTERVAL_MIN * 60_000).toBeLessThan(2 ** 31);
    });
  });

  it('onRegistryReload no propaga si enabledDomes() lanza (P2 #1418)', () => {
    let boom = false;
    const target = { enabledDomes: () => { if (boom) throw new Error('registro roto'); return []; }, sync: async () => undefined };
    const logs: string[] = [];
    const a = new RagAutosync(target, { intervalMin: 15, clock, log: (m) => logs.push(m) });
    a.start();
    boom = true;
    expect(() => a.onRegistryReload()).not.toThrow();
    expect(logs.join('\n')).toMatch(/registro roto/);
    a.stop();
  });

  it('envMs: solo números finitos ≥ 0 (P2 #1418)', () => {
    expect(envMs('250')).toBe(250);
    expect(envMs('0')).toBe(0);
    for (const bad of ['abc', 'NaN', '-5', '', undefined, 'Infinity']) expect(envMs(bad)).toBeUndefined();
  });

  it('nunca solapa ciclos: una llamada durante un ciclo en curso no lanza otro en paralelo', async () => {
    let concurrent = 0;
    let max = 0;
    let syncs = 0;
    const target = {
      enabledDomes: () => ['Docs'],
      sync: async () => { syncs++; concurrent++; max = Math.max(max, concurrent); await new Promise(r => setImmediate(r)); concurrent--; },
    };
    const a = new RagAutosync(target, { intervalMin: 15, clock, log: () => {} });
    const first = a.runCycle();
    void a.runCycle();
    await a.whenIdle();
    await first;
    expect(max).toBe(1);
    expect(syncs).toBe(2); // el segundo aviso se atiende al terminar, no a la vez
  });

  it('sin cúpulas habilitadas el ciclo no cuenta como fallo ni como éxito', async () => {
    dome.rag = { enabled: false };
    const a = autosync();
    await a.runCycle();
    expect(a.getState()).toMatchObject({ lastResults: {}, consecutiveFailures: 0 });
    expect(a.getState().lastOk).toBeUndefined();
    expect(embedder.calls).toBe(0);
  });

  it('un registro que habilita una cúpula lanza un ciclo sin esperar al intervalo', async () => {
    dome.rag = { enabled: false };
    const a = autosync();
    a.start();
    dome.rag = { enabled: true, model: 'm1' };
    a.onRegistryReload();
    await a.whenIdle();
    expect(a.getState().lastResults).toEqual({ Docs: 'ok' });
    // caso negativo: una recarga que no habilita nada nuevo no sincroniza
    const before = a.getState().lastRunAt;
    clock.advance(1000);
    a.onRegistryReload();
    await a.whenIdle();
    expect(a.getState().lastRunAt).toBe(before);
    a.stop();
  });

  it('AC-8: sin start() no hay temporizador; stop() cancela el pendiente', () => {
    const a = autosync();
    expect(clock.timers).toBe(0);
    a.start();
    expect(clock.timers).toBe(1);
    a.stop();
    expect(clock.timers).toBe(0);
  });

  it('rechaza un intervalo no positivo', () => {
    expect(() => new RagAutosync(rag, { intervalMin: 0 })).toThrow(/minutos/);
    expect(() => new RagAutosync(rag, { intervalMin: NaN })).toThrow(/minutos/);
  });
});
