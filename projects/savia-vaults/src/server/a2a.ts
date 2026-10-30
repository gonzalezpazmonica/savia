import { AUTOSYNC_FAILING_ALERT, AUTOSYNC_FAIL_THRESHOLD } from '../rag/autosync.js';
import * as http from 'node:http';
import { createHash, timingSafeEqual } from 'node:crypto';
import * as fs from 'node:fs';
import * as path from 'node:path';
import { NoteNotFoundError, VaultStorage } from '../storage/index.js';
import { resolveRagConfig } from '../rag/policy.js';
import { SearchEngine } from '../search/index.js';
import { RateLimiter } from './ratelimit.js';
import { DomeRegistry } from '../registry/domes.js';
import type { DomeInfo } from '../registry/domes.js';
import type { VaultConfig } from '../types.js';
import type { AccessController, AuthAction } from '../auth/controller.js';

/** SE-424 H2: sin token, A2A solo sirve lo que ya es de lectura amplia (N1/N2) y solo en loopback. */
const LOOPBACK = new Set(['127.0.0.1', '::1', 'localhost']);
const PUBLIC_LEVELS = new Set(['N1', 'N2']);

export interface A2AOptions {
  /** Orígenes de navegador permitidos (CORS). Sin ellos, toda petición con `Origin` se rechaza. */
  corsOrigins?: string[];
  /** SE-423: con fichero de usuarios, cada petición se autoriza como en MCP y HTTP (token personal). */
  access?: AccessController;
}

/** Comparación en tiempo constante (sobre SHA-256 para igualar longitudes). */
function sameToken(given: string, expected: string): boolean {
  const a = createHash('sha256').update(given).digest();
  const b = createHash('sha256').update(expected).digest();
  return timingSafeEqual(a, b) && given.length === expected.length;
}

export class A2AServer {
  private config: VaultConfig;
  private storage: VaultStorage;
  private search: SearchEngine;
  private limiter: RateLimiter;
  private startTime: number;
  private domeReg?: DomeRegistry;
  private domeSearches = new Map<string, SearchEngine>();
  private domeStorages = new Map<string, VaultStorage>();
  private corsOrigins: Set<string>;
  private access?: AccessController;
  private server?: http.Server;
  /** SE-480 R2: lo llama refreshRegistry() tras una recarga (el autosync se entera de cúpulas nuevas). */
  onRegistryReload?: () => void;
  /** SE-480 R2: sincronizador activo del servicio; su estado (sin textos de error) sale en /health. */
  autosync?: { getState(): { lastRunAt?: string; lastOk?: boolean; consecutiveFailures: number } };

  constructor(config: VaultConfig, domeReg?: DomeRegistry, options: A2AOptions = {}) {
    this.corsOrigins = new Set(options.corsOrigins ?? []);
    this.access = options.access;
    this.config = config;
    this.storage = new VaultStorage(config);
    this.search = new SearchEngine(config);
    this.limiter = new RateLimiter(100);
    this.startTime = Date.now();
    this.domeReg = domeReg;
    this.initVault();
  }

  /** SE-480 R1: cada petición vuelve a leer el registro si cambió; las cachés por cúpula se descartan. */
  refreshRegistry(): boolean {
    if (!this.domeReg?.reloadIfChanged()) return false;
    this.domeSearches.clear();
    this.domeStorages.clear();
    this.onRegistryReload?.();
    return true;
  }

  /** Cupulas activas configurables (SE-310 S0-H): el registry si existe, si no la vault unica. */
  listDomes(): DomeInfo[] {
    this.refreshRegistry();
    if (this.domeReg) {
      return this.domeReg.listActive();
    }
    return [{ name: this.config.name, path: this.config.path, description: '', confidentiality: 'N2', active: true }];
  }

  private domeSearch(name: string): SearchEngine | undefined {
    const dome = this.domeReg?.get(name);
    if (!dome) return undefined;
    let se = this.domeSearches.get(name);
    if (!se) {
      const cfg: VaultConfig = {
        name: dome.name,
        path: dome.path,
        allowedExtensions: [],
        deniedPaths: [],
        maxDepth: 10,
        maxFileSize: this.config.maxFileSize,
        confidentiality: dome.confidentiality, // SE-420
      };
      se = new SearchEngine(cfg);
      this.domeSearches.set(name, se);
    }
    return se;
  }

  private domeStorage(name: string): VaultStorage | undefined {
    const dome = this.domeReg?.get(name);
    if (!dome) return undefined;
    let st = this.domeStorages.get(name);
    if (!st) {
      const cfg: VaultConfig = {
        name: dome.name,
        path: dome.path,
        allowedExtensions: [],
        deniedPaths: [],
        maxDepth: 10,
        maxFileSize: this.config.maxFileSize,
        confidentiality: dome.confidentiality, // SE-420
      };
      st = new VaultStorage(cfg);
      this.domeStorages.set(name, st);
    }
    return st;
  }

  /** Escribe una nota en UNA cupula concreta (S0-H alimenta). Fallback a la vault de config. */
  async writeDome(dome: string, notePath: string, content: string): Promise<{ vault: string; path: string } | undefined> {
    this.refreshRegistry();
    const st = this.domeStorage(dome);
    if (!st) return undefined;
    const note = await st.write(notePath, content);
    return { vault: dome, path: note.path };
  }

  /** Lee una nota de UNA cupula concreta (S0-H consume). Fallback a la vault de config. */
  async readDome(dome: string, notePath: string): Promise<{ path: string; name: string; frontmatter: unknown; tags: string[]; content: string } | undefined> {
    this.refreshRegistry();
    const st = this.domeStorage(dome);
    if (!st) return undefined;
    const note = await st.read(notePath);
    return { path: note.path, name: note.name, frontmatter: note.frontmatter, tags: note.tags, content: note.content };
  }

  /** Nivel de una cúpula del registro, o de la vault única de configuración (por defecto N2). */
  private levelOf(dome?: string): string {
    const level = dome ? this.domeReg?.get(dome)?.confidentiality : (this.config.confidentiality ?? 'N2');
    return (level ?? '').toUpperCase();
  }

  /** Busca en UNA cupula (`dome`) o en todas las activas; devuelve resultados fusionados. */
  searchAll(query: { query: string; maxResults?: number; includeStale?: boolean }, dome?: string, allow: (dome: string) => boolean = () => true): { path: string; score: number; snippet: string; dome: string; exactMatch?: boolean; warnings?: string[] }[] {
    this.refreshRegistry();
    const max = query.maxResults || 20;
    const engines: { name: string; se: SearchEngine }[] = [];
    if (dome) {
      const se = this.domeSearch(dome);
      if (se) engines.push({ name: dome, se });
    } else if (this.domeReg) {
      for (const d of this.domeReg.listActive()) {
        if (!allow(d.name)) continue;
        const se = this.domeSearch(d.name);
        if (se) engines.push({ name: d.name, se });
      }
    } else {
      engines.push({ name: this.config.name, se: this.search });
    }

    const merged: { path: string; score: number; snippet: string; dome: string; exactMatch?: boolean; warnings?: string[] }[] = [];
    for (const { name, se } of engines) {
      se.buildIndex();
      const excludeStatuses = resolveRagConfig(this.domeReg?.get(name)?.rag).excludeStatuses;
      for (const r of se.search({ query: query.query, maxResults: max, includeStale: query.includeStale, excludeStatuses })) {
        merged.push({
          path: r.path, score: r.score, snippet: r.snippet, dome: name,
          ...(r.exactMatch !== undefined ? { exactMatch: r.exactMatch } : {}),
          ...(r.warnings ? { warnings: r.warnings } : {}),
        });
      }
    }
    merged.sort((a, b) => Number(!!b.exactMatch) - Number(!!a.exactMatch) || b.score - a.score);
    return merged.slice(0, max);
  }

  private initVault(): void {
    const vp = this.config.path;
    fs.mkdirSync(vp, { recursive: true });
    if (!fs.existsSync(path.join(vp, 'INDEX.md'))) {
      fs.writeFileSync(path.join(vp, 'INDEX.md'), `# ${this.config.name}\n\n`);
    }
    if (!fs.existsSync(path.join(vp, 'MAP.md'))) {
      fs.writeFileSync(path.join(vp, 'MAP.md'), `# ${this.config.name} — Routing Map\n\n`);
    }
  }

  async start(port: number, host = '127.0.0.1', authToken?: string): Promise<{ url: string }> {
    // SE-424 H2 + SE-423 D2: fuera de loopback, solo con usuarios (tokens personales). El secreto
    // compartido SAVIA_VAULTS_TOKEN queda obsoleto: se acepta solo en loopback, con aviso.
    const loopback = LOOPBACK.has(host);
    if (!loopback && !this.access?.isActive) {
      throw new Error(`A2A fuera de loopback (${host}) exige usuarios (savia-vaults user create); SAVIA_VAULTS_TOKEN solo vale en 127.0.0.1`);
    }
    const shared = loopback ? authToken : undefined;
    // Como en MCP (SE-424 H3): si arrancó con usuarios, perder el fichero no lo abre al modo público.
    const startedWithUsers = !!this.access?.isActive;
    if (authToken) {
      console.warn(`AVISO: SAVIA_VAULTS_TOKEN está obsoleto (SE-423)${loopback ? '' : ' y se ignora fuera de loopback'}; usa tokens personales: savia-vaults user create / token-create`);
    }
    const server = http.createServer(async (req, res) => {
      res.setHeader('Content-Type', 'application/json');

      // Un navegador envía Origin: solo se aceptan orígenes permitidos (ni lectura ni escritura cruzada).
      const origin = req.headers.origin;
      if (origin !== undefined) {
        if (!this.corsOrigins.has(origin)) {
          res.writeHead(403);
          res.end(JSON.stringify({ error: 'Origin not allowed' }));
          return;
        }
        res.setHeader('Access-Control-Allow-Origin', origin);
        res.setHeader('Vary', 'Origin');
        if (req.method === 'OPTIONS') {
          res.setHeader('Access-Control-Allow-Methods', 'GET, POST');
          res.setHeader('Access-Control-Allow-Headers', 'Authorization, Content-Type');
          res.writeHead(204);
          res.end();
          return;
        }
      }

      const clientIp = req.socket.remoteAddress || 'unknown';
      if (!this.limiter.allow(clientIp)) {
        res.writeHead(429);
        res.end(JSON.stringify({ error: 'Rate limit exceeded' }));
        return;
      }
      this.refreshRegistry();

      // Modo de la petición: secreto compartido (solo loopback), usuario (token personal) o público.
      const bearer = (req.headers.authorization ?? '').startsWith('Bearer ') ? (req.headers.authorization as string).slice(7).trim() : '';
      if (startedWithUsers) this.access!.reloadUsers();
      const usersMode = !!this.access?.isActive;
      if (startedWithUsers && !usersMode) {
        res.writeHead(401);
        res.end(JSON.stringify({ error: 'Unauthorized' }));
        return;
      }
      let mode: 'shared' | 'user' | 'public' = 'public';
      if (shared && bearer && sameToken(bearer, shared)) {
        mode = 'shared';
      } else if (usersMode) {
        try {
          this.access!.identify(bearer);
          mode = 'user';
        } catch {
          res.writeHead(401);
          res.end(JSON.stringify({ error: 'Unauthorized' }));
          return;
        }
      } else if (shared) {
        res.writeHead(401);
        res.end(JSON.stringify({ error: 'Unauthorized' }));
        return;
      }
      // Sin secreto ni usuarios: solo N1/N2 (niveles desconocidos: no). Con usuarios: AccessController.
      const allowed = async (dome: string | undefined, action: AuthAction): Promise<boolean> => {
        if (mode === 'shared') return true;
        if (mode === 'public') return PUBLIC_LEVELS.has(this.levelOf(dome));
        if (!dome) return false;
        try {
          await this.access!.authorize({ authToken: bearer, dome, action, tool: 'a2a' });
          return true;
        } catch { return false; }
      };
      const denied = async (dome: string | undefined, action: AuthAction): Promise<boolean> => {
        if (await allowed(dome, action)) return false;
        if (mode === 'user') {
          res.writeHead(dome ? 403 : 400);
          res.end(JSON.stringify({ error: dome ? `Sin permiso en la cúpula ${dome}` : 'Indica la cúpula (dome)' }));
        } else {
          res.writeHead(404);
          res.end(JSON.stringify({ error: `Not found in dome ${dome || this.config.name}` }));
        }
        return true;
      };

      try {
        const url = new URL(req.url || '/', `http://${host}:${port}`);
        const p = url.pathname;

        if (p === '/health') {
          res.writeHead(200);
          res.end(JSON.stringify({
            status: 'ok',
            uptime: Math.floor((Date.now() - this.startTime) / 1000),
            vault: this.config.name,
            domes: this.domeReg ? this.domeReg.listActive().length : 1,
            ...(this.autosync ? { autosync: (({ lastRunAt, lastOk, consecutiveFailures }) => ({ lastRunAt, lastOk, consecutiveFailures, ...(consecutiveFailures >= AUTOSYNC_FAIL_THRESHOLD ? { alert: AUTOSYNC_FAILING_ALERT } : {}) }))(this.autosync.getState()) } : {}),
          }));
        } else if (p === '/domes') {
          const list = this.listDomes();
          const ok = await Promise.all(list.map((d) => allowed(this.domeReg ? d.name : undefined, 'read')));
          const domes = list.filter((_, i) => ok[i])
            .map(({ name, description, confidentiality, active }) => ({ name, description, confidentiality, active }));
          res.writeHead(200);
          res.end(JSON.stringify({ domes }));
        } else if (p === '/search') {
          const q = url.searchParams.get('q') || '';
          const max = parseInt(url.searchParams.get('maxResults') || '10', 10);
          const dome = url.searchParams.get('dome') || undefined;
          if (dome && await denied(dome, 'read')) return;
          if (!dome && !this.domeReg && await denied(undefined, 'read')) return;
          // Sin cúpula: solo las que esta petición puede leer.
          const ok = new Set<string>();
          for (const d of this.domeReg?.listActive() ?? []) if (await allowed(d.name, 'read')) ok.add(d.name);
          const stale = url.searchParams.get('includeStale');
          const includeStale = stale === null ? undefined : stale === 'true';
          const results = this.searchAll({ query: q, maxResults: max, includeStale }, dome, (d) => ok.has(d));
          res.writeHead(200);
          res.end(JSON.stringify({ results }));
        } else if (p.startsWith('/context/')) {
          const parts = p.replace('/context/', '').split('/');
          const dome = url.searchParams.get('dome') || undefined;
          const notePath = parts.slice(1).join('/');
          if (await denied(dome, 'read')) return;
          // Ausente, fuera de nivel y en cuarentena: la misma respuesta (SE-485 R3, sin oráculo de existencia).
          let note: Awaited<ReturnType<A2AServer['readDome']>> | undefined;
          try {
            note = dome ? await this.readDome(dome, notePath) : await this.storage.read(notePath);
          } catch (e) {
            if (!(e instanceof NoteNotFoundError)) throw e;
          }
          if (!note) { res.writeHead(404); res.end(JSON.stringify({ error: `Not found in dome ${dome || this.config.name}` })); return; }
          res.writeHead(200);
          res.end(JSON.stringify(note));
        } else if (p === '/stats') {
          // SE-485 R2: por cúpula y autorizado como el resto; solo recuentos de lo visible
          // (sin outOfLevel, quarantined ni commits: revelarían existencia de lo oculto).
          const dome = url.searchParams.get('dome') || undefined;
          if (await denied(dome, 'read')) return;
          const st = dome ? this.domeStorage(dome) : this.storage;
          if (!st) { res.writeHead(404); res.end(JSON.stringify({ error: `Not found in dome ${dome}` })); return; }
          const { name, noteCount, totalSize } = await st.stats();
          res.writeHead(200);
          res.end(JSON.stringify({ name, noteCount, totalSize }));
        } else if (p === '/share' && req.method === 'POST') {
          let body = '';
          req.on('data', chunk => body += chunk);
          req.on('end', async () => {
            try {
              const { path: notePath, content, dome } = JSON.parse(body);
              if (await denied(dome || undefined, 'write')) return;
              const receipt = dome
                ? await this.writeDome(dome, notePath, content)
                : await this.storage.write(notePath, content);
              res.writeHead(receipt ? 200 : 404);
              res.end(JSON.stringify(receipt ?? { error: `Dome not found: ${dome}` }));
            } catch {
              res.writeHead(400);
              res.end(JSON.stringify({ error: 'Invalid request' }));
            }
          });
          return;
        } else {
          res.writeHead(404);
          res.end(JSON.stringify({ error: 'Not found' }));
        }
      } catch (e: unknown) {
        // El detalle (rutas absolutas, errores de E/S) queda en el log local, no en la respuesta.
        // JSON.stringify escapa CR/LF: un cliente no puede fabricar líneas falsas en el log.
        const detail = e instanceof Error ? e.message : String(e);
        console.error(`A2A ${req.method} ${JSON.stringify(req.url)}: ${JSON.stringify(detail)}`);
        res.writeHead(500);
        res.end(JSON.stringify({ error: 'Internal error' }));
      }
    });

    this.server = server;
    await new Promise<void>((resolve, reject) => { server.once('error', reject); server.listen(port, host, resolve); });
    const addr = server.address();
    const bound = typeof addr === 'object' && addr ? addr.port : port;
    if (host === '0.0.0.0') {
      console.warn('WARNING: Server bound to 0.0.0.0 — accessible from network.');
    }
    const shown = host.includes(':') ? `[${host}]` : host;
    console.error(`A2A server listening on http://${shown}:${bound}`);
    return { url: `http://${shown}:${bound}` };
  }

  async stop(): Promise<void> {
    const server = this.server;
    this.server = undefined;
    if (!server) return;
    server.closeAllConnections?.();
    await new Promise<void>((resolve) => server.close(() => resolve()));
  }
}
