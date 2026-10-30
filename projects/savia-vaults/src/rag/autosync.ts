import * as fs from 'node:fs';
import * as path from 'node:path';
import { RagError } from './types.js';

/**
 * SE-480 R2 — sincronizador autónomo del servicio: sync incremental de las cúpulas con rag.enabled:true,
 * al arrancar (tras un retardo), cada N minutos y cuando el registro habilita una cúpula. Usa el lock del
 * indexador (si el cron lo tiene, el ciclo se salta) y nunca solapa dos ciclos en el mismo proceso.
 */

export const AUTOSYNC_FAIL_THRESHOLD = 3;
export const AUTOSYNC_FAILING_ALERT = 'autosync-failing';
export const AUTOSYNC_START_DELAY_MS = 30_000;
const STATE_FILE = 'autosync-state.json';
/** Un estado persistido más viejo que esto × intervalMin ya no describe un sincronizador vivo. */
export const AUTOSYNC_STALE_FACTOR = 3;
/** Tope de minutos: setTimeout usa un entero de 32 bits en ms (2^31-1); por encima dispara al instante. */
export const AUTOSYNC_MAX_INTERVAL_MIN = Math.floor((2 ** 31 - 1) / 60_000);

/** Escribe el estado del ciclo en el rag-home (atómico) para que `status` de cualquier proceso lo vea. */
export function writeAutosyncState(home: string, state: AutosyncState): void {
  fs.mkdirSync(home, { recursive: true, mode: 0o700 });
  const f = path.join(home, STATE_FILE);
  const tmp = `${f}.${process.pid}.tmp`;
  fs.writeFileSync(tmp, JSON.stringify(state), { mode: 0o600 });
  fs.renameSync(tmp, f);
}

/**
 * Lee el estado persistido; ausente, ilegible, con forma inesperada o caducado → undefined.
 * Caducado: `lastRunAt` más viejo que AUTOSYNC_STALE_FACTOR × intervalMin (servicio parado o desinstalado):
 * ni alerta de fallo ni falso verde de un sincronizador que ya no corre.
 */
export function readAutosyncState(home: string, nowMs: number = Date.now()): AutosyncState | undefined {
  try {
    const s = JSON.parse(fs.readFileSync(path.join(home, STATE_FILE), 'utf8')) as AutosyncState;
    if (typeof s?.consecutiveFailures !== 'number' || !Number.isFinite(s.consecutiveFailures)) return undefined;
    const last = Date.parse(s.lastRunAt ?? '');
    if (!Number.isFinite(last) || !(s.intervalMin > 0)) return undefined;
    if (nowMs - last > AUTOSYNC_STALE_FACTOR * s.intervalMin * 60_000) return undefined;
    return s;
  } catch {
    return undefined;
  }
}

export interface AutosyncState {
  intervalMin: number;
  running: boolean;
  lastRunAt?: string;
  lastOk?: boolean;
  lastError?: string;
  consecutiveFailures: number;
  /** Resultado por cúpula del último ciclo: `ok`, `skipped:LOCKED` o `error:<mensaje>`. */
  lastResults: Record<string, string>;
}

export interface AutosyncClock {
  now(): number;
  setTimeout(fn: () => void, ms: number): unknown;
  clearTimeout(handle: unknown): void;
}

export const realClock: AutosyncClock = {
  now: () => Date.now(),
  setTimeout: (fn, ms) => {
    const t = setTimeout(fn, ms);
    t.unref?.();
    return t;
  },
  clearTimeout: (h) => clearTimeout(h as NodeJS.Timeout),
};

/** Lo mínimo que el sincronizador necesita de RagService (facilita probarlo con un doble). */
export interface AutosyncTarget {
  enabledDomes(): string[];
  sync(name: string): Promise<unknown>;
}

export interface AutosyncOptions {
  intervalMin: number;
  clock?: AutosyncClock;
  startDelayMs?: number;
  /** Se invoca al empezar cada ciclo para que el registro se relea aunque nadie haga peticiones. */
  refresh?: () => void;
  log?: (msg: string) => void;
  /** Se invoca al terminar cada ciclo con el estado resultante (persistencia para otros procesos). */
  onState?: (state: AutosyncState) => void;
}

export class RagAutosync {
  private readonly clock: AutosyncClock;
  private readonly log: (msg: string) => void;
  private readonly state: AutosyncState;
  private timer: unknown;
  private current: Promise<void> | undefined;
  private rerun = false;
  private stopped = true;
  private known = new Set<string>();
  private refreshing = false;

  constructor(private readonly target: AutosyncTarget, private readonly o: AutosyncOptions) {
    if (!Number.isFinite(o.intervalMin) || o.intervalMin <= 0 || o.intervalMin > AUTOSYNC_MAX_INTERVAL_MIN) {
      throw new Error(`--rag-autosync exige minutos > 0 y ≤ ${AUTOSYNC_MAX_INTERVAL_MIN} (recibido ${o.intervalMin})`);
    }
    this.clock = o.clock ?? realClock;
    this.log = o.log ?? ((m) => console.error(m));
    this.state = { intervalMin: o.intervalMin, running: false, consecutiveFailures: 0, lastResults: {} };
  }

  getState(): AutosyncState {
    return { ...this.state, lastResults: { ...this.state.lastResults } };
  }

  start(): void {
    if (!this.stopped) return;
    this.stopped = false;
    this.known = new Set(this.target.enabledDomes());
    this.schedule(this.o.startDelayMs ?? AUTOSYNC_START_DELAY_MS);
    this.log(`[autosync] activo: primer ciclo en ${(this.o.startDelayMs ?? AUTOSYNC_START_DELAY_MS) / 1000}s, luego cada ${this.o.intervalMin} min`);
  }

  stop(): void {
    this.stopped = true;
    this.rerun = false;
    if (this.timer !== undefined) this.clock.clearTimeout(this.timer);
    this.timer = undefined;
  }

  /** Resuelve cuando no hay ciclo en curso (los tests lo esperan tras avanzar el reloj). */
  async whenIdle(): Promise<void> {
    while (this.current) await this.current;
  }

  /** El registro cambió: si habilita una cúpula que no estaba habilitada, lanza un ciclo ya. */
  onRegistryReload(): void {
    if (this.stopped || this.refreshing) return;
    let now: Set<string>;
    try {
      now = new Set(this.target.enabledDomes());
    } catch (e) {
      this.log(`[autosync] registro recargado pero ilegible para RAG: ${e instanceof Error ? e.message : String(e)}`);
      return;
    }
    const added = [...now].some(n => !this.known.has(n));
    this.known = now;
    if (added) void this.runCycle();
  }

  private schedule(ms: number): void {
    if (this.stopped) return;
    this.timer = this.clock.setTimeout(() => {
      this.timer = undefined;
      void this.runCycle().finally(() => this.schedule(this.o.intervalMin * 60_000));
    }, ms);
  }

  /** Un ciclo. Si ya hay uno en curso no lanza otro: pide una repetición al terminar. */
  runCycle(): Promise<void> {
    if (this.current) {
      this.rerun = true;
      return this.current;
    }
    this.current = this.cycle().finally(() => {
      this.current = undefined;
      if (this.rerun) {
        this.rerun = false;
        void this.runCycle();
      }
    });
    return this.current;
  }

  private async cycle(): Promise<void> {
    this.state.running = true;
    const results: Record<string, string> = {};
    let firstError: string | undefined;
    let ran = 0;
    try {
      this.refreshing = true;
      try { this.o.refresh?.(); } finally { this.refreshing = false; }
      const enabled = this.target.enabledDomes();
      this.known = new Set(enabled);
      for (const name of enabled) {
        try {
          await this.target.sync(name);
          results[name] = 'ok';
          ran++;
        } catch (e) {
          if (e instanceof RagError && (e.code === 'LOCKED' || e.code === 'UNKNOWN_DOME')) {
            // UNKNOWN_DOME: la cúpula salió del registro entre listarla y sincronizarla.
            results[name] = `skipped:${e.code}`;
            continue;
          }
          const msg = e instanceof Error ? e.message : String(e);
          results[name] = `error:${msg}`;
          firstError ??= `${name}: ${msg}`;
          this.log(`[autosync] ${name}: ${msg}`);
        }
      }
    } catch (e) {
      // enabledDomes() falló (registro en mal estado): cuenta como fallo del ciclo.
      firstError = e instanceof Error ? e.message : String(e);
      this.log(`[autosync] ciclo abortado: ${firstError}`);
    }
    this.state.running = false;
    this.state.lastRunAt = new Date(this.clock.now()).toISOString();
    this.state.lastResults = results;
    if (firstError) {
      this.state.lastOk = false;
      this.state.lastError = firstError;
      this.state.consecutiveFailures++;
    } else if (ran > 0) {
      this.state.lastOk = true;
      this.state.lastError = undefined;
      this.state.consecutiveFailures = 0;
    }
    // Solo cúpulas bloqueadas o ninguna habilitada: ni éxito ni fallo, los contadores no se tocan.
    try { this.o.onState?.(this.getState()); } catch (e) { this.log(`[autosync] no se pudo persistir el estado: ${e instanceof Error ? e.message : String(e)}`); }
  }
}
