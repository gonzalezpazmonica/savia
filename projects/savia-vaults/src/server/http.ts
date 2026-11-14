// SE-422 — API HTTP de Savia Files (`savia-vaults serve --transport http`): subida reanudable tus 1.0,
// descarga por rangos y lectura, con usuarios y tokens por persona (UserStore + AccessController) y
// los permisos por documento de SE-419. Autorizaciones acotadas (`svt1.…`) para subir o descargar en
// nombre de un usuario sin exponer su token. Sin usuarios no arranca; fuera de loopback exige TLS o
// un proxy con TLS delante (--behind-proxy).
import * as http from 'node:http';
import * as https from 'node:https';
import type { AddressInfo } from 'node:net';
import { createHash } from 'node:crypto';
import { pipeline } from 'node:stream/promises';
import { FilesService, type FilesDomeRef } from '../files/service.js';
import { FilesError } from '../files/types.js';
import { keysHome } from '../files/keys.js';
import { AuthError, type AccessController } from '../auth/controller.js';
import type { UserStore } from '../auth/store.js';
import type { DomeRegistry } from '../registry/domes.js';
import { RateLimiter } from './ratelimit.js';
import { KeyUnavailableError, TokenError, TokenSigner, type ScopedToken } from './grants.js';
import { checkVersion, tusCreate, tusDelete, tusHead, tusOptions, tusPatch, type TusContext } from './tus.js';

export interface FilesHttpOptions {
  domes: DomeRegistry;
  users: UserStore;
  access: AccessController;
  env?: NodeJS.ProcessEnv;
  host: string;
  port: number;
  tls?: { cert: Buffer; key: Buffer };
  /** TLS terminado en un proxy delante: permite escuchar fuera de loopback sin TLS propio. */
  behindProxy?: boolean;
  /** Caducidad de las subidas incompletas (def. 24 h). */
  uploadExpiryMs?: number;
  /** SE-423 AC3: cada cuántos bytes o ms se revalida una transferencia en curso (def. 8 MiB / 30 s). */
  fence?: { bytes: number; ms: number };
  /** Peticiones por minuto y usuario (def. SAVIA_FILES_HTTP_RATE o 600). */
  ratePerMinute?: number;
}

const LOOPBACK = new Set(['127.0.0.1', '::1', 'localhost']);
const TOKEN_CACHE_MS = 60_000;
const ROUTE = /^\/v1\/files\/([A-Za-z0-9][A-Za-z0-9._-]{0,63})\/(uploads|documents|operations)(?:\/([A-Za-z0-9_]{1,64}))?(?:\/(content))?$/;

class HttpError extends Error {
  constructor(readonly status: number, readonly code: string, message: string) { super(message); }
}

const STATUS: Record<string, number> = {
  NOT_FOUND: 404, DISABLED: 404, INVALID_INPUT: 400, TOO_LARGE: 413, LIMIT: 429, LOCKED: 423, POLICY_DENIED: 403,
  SCAN_REQUIRED: 422, UNSUPPORTED: 501, KEY_MISSING: 503, COMMIT_PENDING: 503, IDEMPOTENCY_CONFLICT: 409, CONFLICT: 409,
  CHECKSUM_MISMATCH: 460, EXPIRED: 410, INTEGRITY: 500, UNSAFE_HOME: 500,
};

const FENCE = { bytes: 8 * 1024 * 1024, ms: 30_000 };

/**
 * SE-423 AC3: deja pasar los bytes de una transferencia revalidando al usuario cada `bytes` o
 * `ms`. El trozo que cruza el umbral no sale hasta que la comprobación pasa; si falla, la
 * transferencia se corta con ese error y no sale ni se escribe nada más.
 */
export async function* fenced(source: AsyncIterable<Uint8Array>, check: () => Promise<void>, every: { bytes: number; ms: number }): AsyncGenerator<Uint8Array> {
  let bytes = 0;
  let since = Date.now();
  for await (const chunk of source) {
    bytes += chunk.byteLength;
    if (bytes >= every.bytes || Date.now() - since >= every.ms) {
      await check();
      bytes = 0;
      since = Date.now();
    }
    yield chunk;
  }
}

/** `Content-Disposition` sin inyección: ASCII escapado + filename* (RFC 6266 / 5987). */
export function contentDisposition(name: string): string {
  const ascii = name.replace(/[^\x20-\x7e]/g, '_').replace(/["\\;]/g, '_');
  return `attachment; filename="${ascii}"; filename*=UTF-8''${encodeURIComponent(name).replace(/['()*]/g, (c) => `%${c.charCodeAt(0).toString(16).toUpperCase()}`)}`;
}

/** `Range: bytes=a-b | a- | -n` (un solo rango). undefined ⇒ servir entero; null ⇒ 416. */
export function parseRange(header: string | undefined, size: number): { start: number; end: number } | undefined | null {
  if (!header) return undefined;
  const m = /^bytes=(\d*)-(\d*)$/.exec(header.trim());
  if (!m || (m[1] === '' && m[2] === '')) return undefined; // formato no soportado (p. ej. varios rangos): entero
  if (size === 0) return null;
  if (m[1] === '') {
    const n = Number(m[2]);
    return n === 0 ? null : { start: Math.max(0, size - n), end: size - 1 };
  }
  const start = Number(m[1]);
  const end = m[2] === '' ? size - 1 : Math.min(Number(m[2]), size - 1);
  return start >= size || end < start ? null : { start, end };
}

export class FilesHttpServer {
  private server?: http.Server;
  private readonly env: NodeJS.ProcessEnv;
  private readonly limiter: RateLimiter;
  private readonly grants: TokenSigner;
  private readonly tokenCache = new Map<string, { username: string; credentialId: string; until: number }>();

  constructor(private readonly o: FilesHttpOptions) {
    this.env = o.env ?? process.env;
    const rate = Number(this.env.SAVIA_FILES_HTTP_RATE);
    this.limiter = new RateLimiter(o.ratePerMinute ?? (Number.isFinite(rate) && rate > 0 ? rate : 600));
    this.grants = new TokenSigner(keysHome(this.env));
  }

  /** Condiciones de arranque (también las comprueba `start`). */
  static assertStartable(o: { users: UserStore; host: string; tls?: unknown; behindProxy?: boolean }): void {
    o.users.reloadIfChanged();
    if (!o.users.exists() || !o.users.listUsers().length) {
      throw new Error('La API HTTP necesita usuarios: crea al menos uno con `savia-vaults user create <nombre>` y dale permisos sobre las cúpulas.');
    }
    if (!LOOPBACK.has(o.host) && !o.tls && !o.behindProxy) {
      throw new Error(`Escuchar en ${o.host} sin cifrar expondría tokens y ficheros: usa --tls-cert/--tls-key o, si hay un proxy con TLS delante, --behind-proxy.`);
    }
  }

  async start(): Promise<{ url: string }> {
    FilesHttpServer.assertStartable(this.o);
    const handler = (req: http.IncomingMessage, res: http.ServerResponse) => { void this.handle(req, res); };
    const server = this.o.tls ? https.createServer({ cert: this.o.tls.cert, key: this.o.tls.key }, handler) : http.createServer(handler);
    server.requestTimeout = 0; // una subida larga no se corta por duración total…
    server.headersTimeout = 30_000;
    server.timeout = 120_000; // …pero sí por inactividad
    server.keepAliveTimeout = 5_000;
    this.server = server;
    await new Promise<void>((resolve, reject) => { server.once('error', reject); server.listen(this.o.port, this.o.host, resolve); });
    const addr = server.address() as AddressInfo;
    const host = addr.family === 'IPv6' ? `[${addr.address}]` : addr.address;
    return { url: `${this.o.tls ? 'https' : 'http'}://${host}:${addr.port}` };
  }

  async stop(): Promise<void> {
    const s = this.server;
    this.server = undefined;
    if (!s) return;
    s.closeAllConnections?.();
    await new Promise<void>((resolve) => s.close(() => resolve()));
  }

  private domes(): FilesDomeRef[] {
    return this.o.domes.listActive().map((d) => ({ name: d.name, confidentiality: d.confidentiality, files: d.files }));
  }

  /** Servicio con la identidad de la petición: cada acción se autoriza como ese usuario (y SE-419). */
  private service(username: string, credentialId?: string): FilesService {
    return new FilesService({
      domes: () => this.domes(), env: this.env,
      // SE-423: cada acción revalida la credencial (revocada o caducada ⇒ 401) y su alcance.
      authorize: (dome, action, tool) => this.o.access.authorizeUser({ username, credentialId, dome, action, tool }),
      subjects: this.o.access.subjects,
    });
  }

  private bearer(req: http.IncomingMessage, url: URL): string | undefined {
    const h = req.headers.authorization;
    if (h?.startsWith('Bearer ')) return h.slice(7).trim();
    return url.searchParams.get('token') ?? undefined; // enlaces de descarga para navegadores
  }

  /** Usuario de la petición: token personal (bcrypt, con caché corta) o autorización acotada. */
  /** El fichero de usuarios cambió: se recarga y la caché de tokens deja de valer. */
  private recheckUsers(): void {
    if (this.o.users.reloadIfChanged()) this.tokenCache.clear();
  }

  private authenticate(req: http.IncomingMessage, url: URL): { username: string; credentialId?: string; grant?: ScopedToken } {
    this.recheckUsers();
    const value = this.bearer(req, url);
    if (!value) throw new HttpError(401, 'unauthorized', 'falta Authorization: Bearer <token>');
    if (TokenSigner.looksLike(value)) {
      const grant = this.grants.verify(value);
      if (!this.o.users.getUser(grant.sub)) throw new HttpError(401, 'unauthorized', 'el usuario de la autorización ya no existe');
      // SE-423 AC3: la autorización vale lo que la credencial que la emitió.
      if (grant.cid && !this.o.users.activeCredential(grant.sub, grant.cid)) throw new HttpError(401, 'unauthorized', 'la credencial que emitió esta autorización está revocada o caducada');
      return { username: grant.sub, ...(grant.cid ? { credentialId: grant.cid } : {}), grant };
    }
    const key = createHash('sha256').update(value).digest('hex');
    const hit = this.tokenCache.get(key);
    if (hit && hit.until > Date.now() && this.o.users.activeCredential(hit.username, hit.credentialId)) {
      return { username: hit.username, credentialId: hit.credentialId };
    }
    const found = this.o.users.validateCredential(value);
    if (!found) throw new HttpError(401, 'unauthorized', 'token no válido o caducado');
    // La caché nunca dura más que la credencial.
    const until = Math.min(Date.now() + TOKEN_CACHE_MS, Date.parse(found.credential.expiresAt));
    this.tokenCache.set(key, { username: found.user.username, credentialId: found.credential.id, until });
    return { username: found.user.username, credentialId: found.credential.id };
  }

  private json(res: http.ServerResponse, status: number, body: unknown): void {
    res.statusCode = status;
    res.setHeader('Content-Type', 'application/json; charset=utf-8');
    res.setHeader('Cache-Control', 'no-store');
    res.end(JSON.stringify(body));
  }

  private fail(res: http.ServerResponse, e: unknown): void {
    let status = 500;
    let code = 'INTERNAL';
    let message = 'error interno';
    if (e instanceof HttpError) ({ status, code, message } = e);
    else if (e instanceof TokenError) { status = 401; code = 'unauthorized'; message = e.message; }
    else if (e instanceof KeyUnavailableError) { status = 503; code = 'KEY_UNAVAILABLE'; message = 'la clave de firma de autorizaciones no está disponible; ver el registro del servidor'; }
    else if (e instanceof AuthError) { status = e.code === 'unauthorized' ? 401 : e.code === 'forbidden' ? 403 : 404; code = e.code; message = e.message; }
    else if (e instanceof FilesError) { status = STATUS[e.code] ?? 500; code = e.code; message = e.message.replace(/^[A-Z_]+: /, ''); }
    if (res.headersSent) { res.destroy(); return; }
    if (code === 'COMMIT_PENDING') res.setHeader('Retry-After', '5');
    if (req400(res)) res.setHeader('Tus-Resumable', '1.0.0');
    this.json(res, status, { error: { code, message } });
  }

  private async handle(req: http.IncomingMessage, res: http.ServerResponse): Promise<void> {
    res.setHeader('X-Content-Type-Options', 'nosniff');
    try {
      const url = new URL(req.url ?? '/', 'http://savia.invalid');
      if (url.pathname === '/v1/health') return this.json(res, 200, { ok: true });
      const m = ROUTE.exec(url.pathname);
      if (!m) throw new HttpError(404, 'NOT_FOUND', 'ruta desconocida');
      const [, dome, kind, id, content] = m;
      const method = req.method ?? 'GET';
      if (kind === 'uploads' && method === 'OPTIONS' && !id) {
        const d = this.domes().find((x) => x.name === dome);
        return tusOptions(res, Math.min(new FilesService({ domes: () => this.domes(), env: this.env }).limits.maxBytes, d?.files?.maxBytes ?? Infinity));
      }
      const who = this.authenticate(req, url);
      if (!this.limiter.allow(who.username)) throw new HttpError(429, 'LIMIT', 'demasiadas peticiones; espera un momento');
      const svc = this.service(who.username, who.credentialId);
      const g = who.grant;
      if (g && g.dome !== dome) throw new HttpError(403, 'forbidden', 'la autorización es de otra cúpula');
      if (kind === 'uploads') {
        if (g && g.kind !== 'upload') throw new HttpError(403, 'forbidden', 'esta autorización no sirve para subir');
        if (method !== 'GET' && !checkVersion(req, res)) return; // GET de estado no es tus
        const ctx: TusContext = {
          svc, dome, username: who.username, grant: g, maxBytes: svc.limits.maxBytes, expiresInMs: this.o.uploadExpiryMs,
          base: `/v1/files/${dome}/uploads`,
          fence: (src) => fenced(src, async () => {
            this.recheckUsers();
            if (id) await svc.uploadInfo({ dome, uploadId: id, owner: who.username }); // vuelve a autorizar escritura
          }, this.o.fence ?? FENCE),
        };
        if (!id && method === 'POST') {
          if (g) {
            ctx.beforeCreate = async () => {
              if (!(await svc.consumeGrant({ dome, jti: g.jti }))) throw new HttpError(401, 'unauthorized', 'esta autorización ya se usó');
            };
          }
          return await tusCreate(req, res, ctx);
        }
        if (!id) throw new HttpError(405, 'METHOD', 'método no permitido');
        if (g) {
          const info = await svc.uploadInfo({ dome, uploadId: id, owner: who.username });
          if (info.meta.grant !== g.jti) throw new HttpError(403, 'forbidden', 'la subida no es de esta autorización');
        }
        if (method === 'HEAD') return await tusHead(res, ctx, id);
        if (method === 'PATCH') return await tusPatch(req, res, ctx, id);
        if (method === 'DELETE') return await tusDelete(res, ctx, id);
        if (method === 'GET') {
          const info = await svc.uploadInfo({ dome, uploadId: id, owner: who.username });
          return this.json(res, 200, {
            uploadId: id, status: info.status, offset: info.offset, length: info.length, expiresAt: new Date(info.expiresAt).toISOString(),
            ...(info.documentId ? { documentId: info.documentId } : {}), ...(info.operationId ? { operationId: info.operationId } : {}),
            ...(info.errorCode ? { errorCode: info.errorCode } : {}),
          });
        }
        throw new HttpError(405, 'METHOD', 'método no permitido');
      }
      if (method !== 'GET' && method !== 'HEAD') throw new HttpError(405, 'METHOD', 'método no permitido');
      if (g && (g.kind !== 'download' || kind !== 'documents' || !content || g.documentId !== id)) {
        throw new HttpError(403, 'forbidden', 'esta autorización no sirve para esto');
      }
      if (kind === 'operations') {
        if (!id) throw new HttpError(404, 'NOT_FOUND', 'falta el operationId');
        return this.json(res, 200, await svc.operation({ dome, operationId: id }));
      }
      if (!id) return this.json(res, 200, await svc.list({ dome, tag: url.searchParams.get('tag') ?? undefined }));
      if (!content) return this.json(res, 200, await svc.get({ dome, id }));
      const revision = g?.revisionId ?? url.searchParams.get('revision') ?? undefined;
      return await this.content(req, res, svc, dome, id, revision);
    } catch (e) {
      this.fail(res, e);
    }
  }

  /** Descarga con ETag (revisionId), If-None-Match, Range/If-Range y cabeceras seguras. */
  private async content(req: http.IncomingMessage, res: http.ServerResponse, svc: FilesService, dome: string, id: string, revisionId?: string): Promise<void> {
    const doc = await svc.get({ dome, id });
    const rev = doc.revisions.find((r) => r.id === (revisionId ?? doc.currentRevision));
    if (!rev) throw new FilesError('NOT_FOUND', `revisión ${String(revisionId).slice(0, 40)} no existe`);
    const etag = `"${rev.id}"`;
    res.setHeader('ETag', etag);
    res.setHeader('Accept-Ranges', 'bytes');
    res.setHeader('Cache-Control', 'private, no-cache');
    if (req.headers['if-none-match'] === etag) { res.statusCode = 304; res.end(); return; }
    const ifRange = req.headers['if-range'];
    const range = ifRange && ifRange !== etag ? undefined : parseRange(req.headers.range, rev.size);
    if (range === null) {
      res.statusCode = 416;
      res.setHeader('Content-Range', `bytes */${rev.size}`);
      res.end();
      return;
    }
    const r = await svc.openRead({ dome, id, revisionId: rev.id, ...(range ? { range } : {}) });
    res.statusCode = range ? 206 : 200;
    if (range) res.setHeader('Content-Range', `bytes ${range.start}-${range.end}/${rev.size}`);
    res.setHeader('Content-Length', String(range ? range.end - range.start + 1 : rev.size));
    res.setHeader('Content-Type', rev.mime);
    res.setHeader('Content-Disposition', contentDisposition(doc.name));
    res.setHeader('Content-Security-Policy', 'sandbox');
    if (req.method === 'HEAD') { r.stream.destroy(); res.end(); return; }
    // SE-423 AC3: revocar la credencial, perder el permiso o cambiar la política del documento corta la descarga.
    const check = async () => { this.recheckUsers(); await svc.get({ dome, id }); };
    try {
      await pipeline(fenced(r.stream, check, this.o.fence ?? FENCE), res);
    } catch {
      res.destroy(); // a mitad: el cliente ve una respuesta truncada, nunca un fichero «completo» erróneo
    }
  }
}

/** Las respuestas de error de rutas tus también llevan Tus-Resumable. */
function req400(res: http.ServerResponse): boolean {
  return res.req?.url?.includes('/uploads') ?? false;
}
