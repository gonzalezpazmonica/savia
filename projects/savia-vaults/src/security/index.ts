import * as fs from 'node:fs';
import * as path from 'node:path';
import * as crypto from 'node:crypto';
import * as os from 'node:os';
import type { VaultConfig } from '../types.js';

export class SecurityError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'SecurityError';
  }
}

/** Metadatos de la cúpula que la API de notas nunca lee ni escribe (escribir en `.git/hooks` ejecutaría código). */
const CONTAIN_DENIED = ['.git', '.savia-vault', '.trash'];

export class VaultSecurity {
  private config: VaultConfig;
  private defaultAllowed: Set<string>;
  private defaultDenied: Set<string>;

  constructor(config: VaultConfig) {
    this.config = config;
    this.defaultAllowed = new Set(['.md', '.yaml', '.yml', '.json', '.txt', '.canvas', '.base']);
    this.defaultDenied = new Set(['.git', '.obsidian', 'node_modules', '.savia-vault', '.trash']);
  }

  /**
   * SE-424 H5: única puerta de VaultStorage a disco. Devuelve la ruta absoluta y la relativa (POSIX)
   * de `requested` solo si queda dentro de la raíz REAL de la cúpula, también tras resolver enlaces
   * simbólicos del destino y de cada directorio intermedio. Rechaza (SecurityError, sin tocar disco):
   * vacía, NUL, absoluta (POSIX o unidad), cualquier segmento `..`, cualquier barra invertida
   * (separador en Windows; también UNC), segmentos que al descodificar `%xx` dan `..` o una barra,
   * metadatos internos (`.git`, `.savia-vault`, `.trash` y `deniedPaths`) y la profundidad máxima.
   */
  contain(requested: string): { abs: string; rel: string } {
    if (typeof requested !== 'string' || requested === '' || requested.includes('\0')) {
      throw new SecurityError('PATH_OUTSIDE_DOME: ruta vacía o no válida');
    }
    if (requested.startsWith('/') || /^[a-zA-Z]:/.test(requested)) {
      throw new SecurityError('PATH_OUTSIDE_DOME: ruta absoluta');
    }
    const segments = requested.split('/').filter((s) => s !== '' && s !== '.');
    if (segments.length === 0) throw new SecurityError('PATH_OUTSIDE_DOME: ruta vacía o no válida');
    const denied = new Set([...CONTAIN_DENIED, ...this.config.deniedPaths.map((d) => d.toLowerCase())]);
    for (const seg of segments) {
      let decoded = seg;
      try { decoded = decodeURIComponent(seg); } catch { /* `%` suelto: se compara tal cual */ }
      if (seg === '..' || decoded === '..' || /[\\/]/.test(decoded)) {
        throw new SecurityError('PATH_OUTSIDE_DOME: la ruta sale de la cúpula');
      }
      if (denied.has(seg.toLowerCase()) || denied.has(decoded.toLowerCase())) {
        throw new SecurityError(`PATH_OUTSIDE_DOME: ruta interna no accesible (${seg})`);
      }
    }
    if (segments.length > this.config.maxDepth) {
      throw new SecurityError(`Path exceeds max depth of ${this.config.maxDepth}`);
    }

    // Raíz aún sin crear (la primera escritura la crea): no hay enlaces dentro que resolver todavía.
    const lexicalRoot = path.resolve(this.config.path);
    const realRoot = fs.existsSync(lexicalRoot) ? fs.realpathSync(lexicalRoot) : lexicalRoot;
    const inside = (p: string) => p === realRoot || p.startsWith(realRoot + path.sep);
    const rel = segments.join('/');
    const abs = path.join(realRoot, ...segments);

    // Cada prefijo existente se resuelve: un directorio o fichero enlazado fuera queda fuera.
    let cur = realRoot;
    for (const seg of segments) {
      cur = path.join(cur, seg);
      let st: fs.Stats;
      try { st = fs.lstatSync(cur); } catch { break; } // lo que no existe aún se creará dentro
      if (!st.isSymbolicLink()) continue;
      let target: string;
      try { target = fs.realpathSync(cur); } catch {
        // Enlace roto: escribir lo seguiría y crearía el fichero donde apunte.
        throw new SecurityError('PATH_OUTSIDE_DOME: enlace simbólico roto');
      }
      if (!inside(target)) throw new SecurityError('PATH_OUTSIDE_DOME: enlace simbólico fuera de la cúpula');
    }
    return { abs, rel };
  }

  resolve(relativePath: string): string {
    const root = path.resolve(this.config.path);
    const normalized = path.normalize(relativePath.replace(/[\\/]+/g, path.sep));
    const resolved = path.resolve(root, normalized);
    const relative = path.relative(root, resolved);

    if (relative === '..' || relative.startsWith(`..${path.sep}`) || path.isAbsolute(relative)) {
      throw new SecurityError('Path traversal blocked');
    }

    if (normalized === '..' || normalized.startsWith(`..${path.sep}`)) {
      throw new SecurityError('Path traversal blocked');
    }

    return resolved;
  }

  checkDenied(absPath: string): void {
    const parts = absPath.split(/[\\/]+/);
    const custom = new Set(this.config.deniedPaths.map(d => d.toLowerCase()));

    for (const part of parts) {
      if (this.defaultDenied.has(part.toLowerCase())) {
        throw new SecurityError(`Access denied: ${part}`);
      }
      if (custom.has(part.toLowerCase())) {
        throw new SecurityError(`Access denied: ${part}`);
      }
    }
  }

  checkSymlink(absPath: string): void {
    try {
      const lstat = fs.lstatSync(absPath);
      if (lstat.isSymbolicLink()) {
        const target = fs.realpathSync(absPath);
        // Raíz real y con separador: `/vault-otra` no empieza por `/vault` (SE-424 H5).
        const resolved = fs.realpathSync(path.resolve(this.config.path));
        if (target !== resolved && !target.startsWith(resolved + path.sep)) {
          throw new SecurityError('Symlink points outside vault boundary');
        }
      }
    } catch (e: unknown) {
      if (e instanceof SecurityError) throw e;
    }
  }

  checkExtension(absPath: string): void {
    const ext = path.extname(absPath).toLowerCase();
    const allowed = this.config.allowedExtensions.length > 0
      ? new Set(this.config.allowedExtensions.map(e => e.toLowerCase()))
      : this.defaultAllowed;

    if (!allowed.has(ext)) {
      throw new SecurityError(`Extension not allowed: ${ext}`);
    }
  }

  checkDepth(relativePath: string): void {
    const parts = relativePath.split(/[\\/]+/).filter(p => p !== '' && p !== '.');
    if (parts.length > this.config.maxDepth) {
      throw new SecurityError(`Path exceeds max depth of ${this.config.maxDepth}`);
    }
  }

  guardRead(relativePath: string): string {
    const { abs: absPath, rel } = this.contain(relativePath);
    this.checkDenied(rel);

    if (fs.existsSync(absPath)) {
      this.checkSymlink(absPath);
      this.checkExtension(absPath);
      const stat = fs.statSync(absPath);
      if (stat.size > this.config.maxFileSize) {
        throw new SecurityError(`File exceeds max size of ${this.config.maxFileSize}`);
      }
    }

    return absPath;
  }

  guardWrite(relativePath: string): string {
    const { abs: absPath, rel } = this.contain(relativePath);
    this.checkDenied(rel);

    const dir = path.dirname(absPath);
    if (!fs.existsSync(dir)) {
      fs.mkdirSync(dir, { recursive: true });
    }

    return absPath;
  }
}


// Ed25519 signing
const KEY_DIR = `${os.homedir()}/.savia-vaults/keys`;

function ensureKeys(): { publicKey: crypto.KeyObject; privateKey: crypto.KeyObject } {
  fs.mkdirSync(KEY_DIR, { recursive: true });
  const pubPath = path.join(KEY_DIR, 'ed25519-public.pem');
  const privPath = path.join(KEY_DIR, 'ed25519-private.pem');

  if (!fs.existsSync(pubPath) || !fs.existsSync(privPath)) {
    const { publicKey, privateKey } = crypto.generateKeyPairSync('ed25519');
    fs.writeFileSync(pubPath, publicKey.export({ type: 'spki', format: 'pem' }));
    fs.writeFileSync(privPath, privateKey.export({ type: 'pkcs8', format: 'pem' }));
  }

  return {
    publicKey: crypto.createPublicKey(fs.readFileSync(pubPath)),
    privateKey: crypto.createPrivateKey(fs.readFileSync(privPath)),
  };
}

export function signContent(content: string): string {
  const { privateKey } = ensureKeys();
  const buf = crypto.sign(null, Buffer.from(content), privateKey);
  return buf.toString('hex');
}

export function verifySignature(content: string, signature: string): boolean {
  try {
    const { publicKey } = ensureKeys();
    return crypto.verify(null, Buffer.from(content), publicKey, Buffer.from(signature, 'hex'));
  } catch {
    return false;
  }
}
