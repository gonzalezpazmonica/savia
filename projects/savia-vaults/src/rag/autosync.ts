import { RagError } from './types.js';

/**
 * SE-480 R2 — sincronizador autónomo del servicio: sync incremental de las cúpulas con rag.enabled:true,
 * al arrancar (tras un retardo), cada N minutos y cuando el registro habilita una cúpula. Usa el lock del
 * indexador (si el cron lo tiene, el ciclo se salta) y nunca solapa dos ciclos en el mismo proceso.
 */

export const AUTOSYNC_FAIL_THRESHOLD = 3;
export const AUTOSYNC_FAILING_ALERT = 'autosync-failing';
export const AUTOSYNC_START_DELAY_MS = 30_000;

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
    if (!Number.isFinite(o.intervalMin) || o.intervalMin <= 0) throw new Error(`--rag-autosync exige minutos > 0 (recibido ${o.intervalMin})`);
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
    const now = new Set(this.target.enabledDomes());
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
  }
}
