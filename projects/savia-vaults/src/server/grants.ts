// SE-422 — autorizaciones acotadas de la API HTTP de ficheros: permiten que un tercero (un
// navegador, curl, otra persona) suba un fichero o descargue uno sin conocer el token del usuario.
// HMAC-SHA256 con clave propia (`<keys home>/_http/token.key`, 0600); formato
// `svt1.<payload b64url>.<mac b64url>`. El servidor revalida al usuario en cada uso y consume el
// `jti` de las subidas (un solo uso).
import * as fs from 'node:fs';
import * as path from 'node:path';
import { createHmac, randomBytes, timingSafeEqual } from 'node:crypto';
import { ensureSafeHome, writeAtomic } from '../rag/store.js';

export interface ScopedTokenInput {
  kind: 'upload' | 'download';
  dome: string;
  /** Usuario en cuyo nombre actúa. */
  sub: string;
  /** SE-423: credencial que la emitió; revocarla (o que caduque) invalida la autorización. */
  cid?: string;
  maxBytes?: number;
  name?: string;
  tags?: string[];
  confidentiality?: string;
  replaces?: string;
  documentId?: string;
  revisionId?: string;
}

export interface ScopedToken extends ScopedTokenInput { exp: number; jti: string }

export class TokenError extends Error {
  readonly code = 'unauthorized';
  constructor(message: string) {
    super(message);
    this.name = 'TokenError';
  }
}

/** SE-528 S3: la clave de firma no se puede usar; quien firma o verifica falla cerrado. */
export class KeyUnavailableError extends Error {
  readonly code = 'key_unavailable';
  constructor(readonly sysCode: string, message: string) {
    super(message);
    this.name = 'KeyUnavailableError';
  }
}

const KEY_BYTES = 32;
const PREFIX = 'svt1';
const MAX_CHARS = 4096;

export class TokenSigner {
  private readonly dir: string;

  constructor(keysHome: string) {
    this.dir = path.join(keysHome, '_http');
  }

  static looksLike(value: string): boolean {
    return typeof value === 'string' && value.startsWith(`${PREFIX}.`);
  }

  private get keyPath(): string { return path.join(this.dir, 'token.key'); }

  /**
   * SE-528 S3: la clave solo se crea si no existe (ENOENT). Cualquier otro fallo de lectura o una
   * longitud inválida falla cerrado: se registra con el código del sistema y la clave no se toca.
   */
  private key(): Buffer {
    let k: Buffer;
    try {
      k = fs.readFileSync(this.keyPath);
    } catch (e) {
      const sysCode = (e as NodeJS.ErrnoException | undefined)?.code;
      if (sysCode === 'ENOENT') return this.create();
      throw this.unavailable(typeof sysCode === 'string' && sysCode ? sysCode : 'UNKNOWN', 'no se puede leer');
    }
    if (k.length !== KEY_BYTES) throw this.unavailable('EINVAL', `longitud inválida (${k.length} bytes, se esperan ${KEY_BYTES})`);
    return k;
  }

  private unavailable(sysCode: string, what: string): KeyUnavailableError {
    const err = new KeyUnavailableError(sysCode, `${what} la clave de firma de autorizaciones (${sysCode}); `
      + 'no se regenera sola: si la persona decide regenerarla, todo lo emitido deja de valer');
    console.error(`SECURITY: ${err.message} [${this.keyPath}]`);
    return err;
  }

  /**
   * Primera creación: se escribe completa en un temporal y se enlaza con link(), que falla si la
   * clave ya existe; así nunca se pisa una clave creada a la vez por otro proceso.
   */
  private create(): Buffer {
    this.prepareDir();
    const k = randomBytes(KEY_BYTES);
    const tmp = `${this.keyPath}.new-${process.pid}-${randomBytes(4).toString('hex')}`;
    try {
      fs.writeFileSync(tmp, k, { mode: 0o600, flag: 'wx' });
      fs.chmodSync(tmp, 0o600);
      fs.linkSync(tmp, this.keyPath);
    } catch (e) {
      const sysCode = (e as NodeJS.ErrnoException | undefined)?.code;
      if (sysCode === 'EEXIST') return this.key();
      throw this.unavailable(typeof sysCode === 'string' && sysCode ? sysCode : 'UNKNOWN', 'no se puede crear');
    } finally {
      fs.rmSync(tmp, { force: true });
    }
    return k;
  }

  private prepareDir(): void {
    ensureSafeHome(path.dirname(this.dir));
    fs.mkdirSync(this.dir, { recursive: true, mode: 0o700 });
    fs.chmodSync(this.dir, 0o700);
  }

  /** Clave nueva por decisión explícita de la persona: todo lo emitido deja de valer. */
  rotate(): Buffer {
    this.prepareDir();
    const k = randomBytes(KEY_BYTES);
    writeAtomic(this.keyPath, k);
    fs.chmodSync(this.keyPath, 0o600);
    return k;
  }

  sign(input: ScopedTokenInput, ttlMs: number): string {
    const payload: ScopedToken = { ...input, exp: Date.now() + ttlMs, jti: randomBytes(16).toString('hex') };
    const body = Buffer.from(JSON.stringify(payload)).toString('base64url');
    const mac = createHmac('sha256', this.key()).update(`${PREFIX}.${body}`).digest('base64url');
    return `${PREFIX}.${body}.${mac}`;
  }

  verify(value: string): ScopedToken {
    if (typeof value !== 'string' || value.length > MAX_CHARS) throw new TokenError('token no válido');
    const parts = value.split('.');
    if (parts.length !== 3 || parts[0] !== PREFIX || !parts[1] || !parts[2]) throw new TokenError('token no válido');
    const expected = createHmac('sha256', this.key()).update(`${PREFIX}.${parts[1]}`).digest();
    const got = Buffer.from(parts[2], 'base64url');
    if (got.length !== expected.length || !timingSafeEqual(got, expected)) throw new TokenError('token no válido: firma incorrecta');
    let p: ScopedToken;
    try {
      p = JSON.parse(Buffer.from(parts[1], 'base64url').toString('utf-8')) as ScopedToken;
    } catch {
      throw new TokenError('token no válido');
    }
    if (!p || (p.kind !== 'upload' && p.kind !== 'download') || typeof p.dome !== 'string' || typeof p.sub !== 'string'
      || typeof p.exp !== 'number' || typeof p.jti !== 'string') throw new TokenError('token no válido');
    if (p.exp <= Date.now()) throw new TokenError('token caducado');
    return p;
  }
}
