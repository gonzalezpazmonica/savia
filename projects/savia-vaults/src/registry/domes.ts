import * as fs from 'node:fs';
import * as path from 'node:path';
import { spawnSync } from 'node:child_process';
import { VaultStorage } from '../storage/index.js';
import { SearchEngine } from '../search/index.js';
import { VaultSecurity } from '../security/index.js';
import type { VaultConfig } from '../types.js';
import type { RagDomeConfig } from '../rag/types.js';
import type { FilesDomeConfig } from '../files/types.js';

export type ConfidentialityLevel = 'N1' | 'N2' | 'N3' | 'N4';

export interface DomeInfo {
  name: string;
  path: string;
  description: string;
  confidentiality: ConfidentialityLevel;
  schemaDir?: string;
  /** SE-410: configuración RAG opcional de la cúpula. */
  rag?: RagDomeConfig;
  /** SE-413: Savia Files en la cúpula (desactivado por defecto). */
  files?: FilesDomeConfig;
  active: boolean;
}

interface DomesFile {
  version: number;
  defaultDome: string;
  domes: Record<string, {
    name: string;
    path: string;
    description: string;
    confidentiality: string;
    schemaDir?: string;
    rag?: RagDomeConfig;
    files?: FilesDomeConfig;
  }>;
}

function validFiles(dome: string, files: FilesDomeConfig): FilesDomeConfig {
  if (files.scan !== undefined && !['auto', 'required', 'off'].includes(files.scan)) {
    throw new Error(`Invalid files.scan for dome "${dome}": ${files.scan}. Must be auto, required or off.`);
  }
  if (files.encryption !== undefined && typeof files.encryption !== 'boolean') {
    throw new Error(`Invalid files.encryption for dome "${dome}": ${String(files.encryption)}. Must be true or false.`);
  }
  if (files.maxBytes !== undefined && (!Number.isSafeInteger(files.maxBytes) || files.maxBytes < 1 || files.maxBytes > 10 * 1024 ** 3)) {
    throw new Error(`Invalid files.maxBytes for dome "${dome}": ${String(files.maxBytes)}. Must be an integer between 1 and 10737418240 (10 GiB).`);
  }
  return {
    enabled: files.enabled === true,
    ...(files.scan ? { scan: files.scan } : {}),
    ...(files.encryption !== undefined ? { encryption: files.encryption } : {}),
    ...(files.maxBytes !== undefined ? { maxBytes: files.maxBytes } : {}),
  };
}

function makeConfig(dome: DomeInfo): VaultConfig {
  return {
    name: dome.name,
    path: dome.path,
    allowedExtensions: [],
    deniedPaths: [],
    maxDepth: 10,
    maxFileSize: 10 * 1024 * 1024,
    schemaDir: dome.schemaDir,
    confidentiality: dome.confidentiality,
  };
}

/**
 * True si git versiona el fichero. El registro de cúpulas guarda rutas de la
 * máquina y nombres privados: debe vivir en un fichero local ignorado.
 */
export function isGitTracked(filePath: string): boolean {
  const abs = path.resolve(filePath);
  const r = spawnSync('git', ['ls-files', '--error-unmatch', '--', path.basename(abs)], {
    cwd: path.dirname(abs), stdio: 'ignore',
  });
  return r.status === 0;
}

type Origin = 'base' | 'local';

/** Lee y valida la estructura de un fichero de cúpulas. */
function readDomesFile(filePath: string): DomesFile {
  let raw: string;
  try {
    raw = fs.readFileSync(filePath, 'utf-8');
  } catch {
    throw new Error(`Cannot read domes file: ${filePath}`);
  }
  let data: DomesFile;
  try {
    data = JSON.parse(raw);
  } catch {
    throw new Error(`Invalid JSON in domes file: ${filePath}`);
  }
  if (!data.version || !data.domes || typeof data.domes !== 'object') {
    throw new Error(`Invalid domes file structure in ${filePath}: expected { version, defaultDome, domes }`);
  }
  return data;
}

/**
 * Registro de cúpulas. SE-436 D30-2: además del fichero base (`savia-vaults.domes.json`) lee un registro
 * LOCAL junto a él (`savia-vaults.domes.local.json`, ignorado por git), que es donde escribe Savia Space;
 * se fusionan y, con el mismo nombre, gana el local. `save()` devuelve cada cúpula al fichero de donde salió.
 */
export class DomeRegistry {
  private filePath: string;
  private domes: Map<string, DomeInfo> = new Map();
  private origin: Map<string, Origin> = new Map();
  private localDefault: string = '';
  public defaultDome: string = '';
  /** SE-480: huella (mtime:size:ino) de base y local en la última carga, intentada o fallida. */
  private loadedKey = '';
  private loadedAt = 0;
  private lastCheck = 0;
  private loadError: string | undefined;
  /** SE-480: como mucho una comprobación de `stat` por este intervalo (ms); 0 desactiva el límite. */
  public reloadMinIntervalMs: number = Number(process.env.SAVIA_VAULTS_RELOAD_MS ?? 1000);

  constructor(filePath: string = 'savia-vaults.domes.json') {
    this.filePath = filePath;
  }

  private statKey(): string {
    const part = (f: string): string => {
      try {
        const st = fs.statSync(f);
        return `${st.mtimeMs}:${st.size}:${st.ino}`;
      } catch {
        return 'missing';
      }
    };
    return `${part(this.filePath)}|${part(this.getLocalFilePath())}`;
  }

  /**
   * SE-480 R1: recarga el registro si base o local cambiaron en disco. Si el nuevo contenido no parsea o no
   * valida, conserva el último registro válido y deja el error en `getState().error`. true si hubo recarga.
   */
  reloadIfChanged(): boolean {
    const now = Date.now();
    if (this.reloadMinIntervalMs > 0 && now - this.lastCheck < this.reloadMinIntervalMs) return false;
    this.lastCheck = now;
    const key = this.statKey();
    if (key === this.loadedKey) return false;
    const previous = this.loadError;
    try {
      this.load();
    } catch (e) {
      this.loadedKey = key;
      this.loadError = e instanceof Error ? e.message : String(e);
      if (this.loadError !== previous) console.error(`[registry] recarga rechazada, se conserva el último registro válido: ${this.loadError}`);
      return false;
    }
    return true;
  }

  /** SE-480: frescura del registro para `vault_rag_status` y `vault_health`. */
  getState(): { file: string; loadedAt: string | null; mtime: string | null; error?: string } {
    let mtime: string | null = null;
    try { mtime = fs.statSync(this.filePath).mtime.toISOString(); } catch { /* sin fichero base */ }
    return {
      file: this.getFilePath(),
      loadedAt: this.loadedAt ? new Date(this.loadedAt).toISOString() : null,
      mtime,
      ...(this.loadError ? { error: this.loadError } : {}),
    };
  }

  getFilePath(): string {
    return path.resolve(this.filePath);
  }

  /** Registro local: el base con `.local` antes de la extensión. */
  getLocalFilePath(): string {
    const abs = this.getFilePath();
    const ext = path.extname(abs);
    return abs.slice(0, abs.length - ext.length) + '.local' + ext;
  }

  load(): void {
    const localPath = this.getLocalFilePath();
    const hasBase = fs.existsSync(this.filePath);
    const hasLocal = fs.existsSync(localPath);
    if (!hasBase && !hasLocal) {
      throw new Error(`Domes file not found: ${this.filePath}. Create one with 'savia-vaults dome create <name>' or use --path for single-dome mode.`);
    }

    const key = this.statKey();
    const base = hasBase ? readDomesFile(this.filePath) : null;
    const loc = hasLocal ? readDomesFile(localPath) : null;

    const domes = new Map<string, DomeInfo>();
    const origins = new Map<string, Origin>();

    const sources: Array<[DomesFile | null, string, Origin]> = [[base, this.filePath, 'base'], [loc, localPath, 'local']];
    for (const [data, file, origin] of sources) {
      if (!data) continue;
      for (const [name, dome] of Object.entries(data.domes)) {
        // SE-310: resolver relativo al directorio del fichero de domes, NO al cwd
        // (el CLI puede correr desde cualquier cwd; la cupula vive junto al registry).
        const resolvedPath = path.resolve(path.dirname(file), dome.path);
        const active = fs.existsSync(resolvedPath) && fs.statSync(resolvedPath).isDirectory();

        if (!active) {
          console.warn(`Dome "${name}" path not found: ${resolvedPath} — marked inactive`);
        }

        const level = dome.confidentiality?.toUpperCase() || 'N2';
        if (!['N1', 'N2', 'N3', 'N4'].includes(level)) {
          throw new Error(`Invalid confidentiality level for dome "${name}": ${dome.confidentiality}. Must be N1, N2, N3, or N4.`);
        }

        domes.set(name, {
          name: dome.name || name,
          path: resolvedPath,
          description: dome.description || '',
          confidentiality: level as ConfidentialityLevel,
          schemaDir: dome.schemaDir,
          ...(dome.rag && typeof dome.rag === 'object' ? { rag: dome.rag } : {}),
          ...(dome.files && typeof dome.files === 'object' ? { files: validFiles(name, dome.files) } : {}),
          active,
        });
        origins.set(name, origin);
      }
    }
    // SE-480: se aplica solo si todo validó; un fichero a medias no deja el registro vacío.
    this.defaultDome = loc?.defaultDome || base?.defaultDome || '';
    this.localDefault = loc?.defaultDome || '';
    this.domes = domes;
    this.origin = origins;
    this.loadedKey = key;
    this.loadedAt = Date.now();
    this.loadError = undefined;
  }

  list(): DomeInfo[] {
    return [...this.domes.values()];
  }

  listActive(): DomeInfo[] {
    return this.list().filter(d => d.active);
  }

  get(name: string): DomeInfo | undefined {
    return this.domes.get(name);
  }

  getDefaultName(): string {
    if (!this.defaultDome) {
      const active = this.listActive();
      if (active.length > 0) return active[0].name;
      throw new Error('No active domes configured');
    }
    return this.defaultDome;
  }

  add(dome: DomeInfo): void {
    if (this.domes.has(dome.name)) {
      throw new Error(`Dome "${dome.name}" already exists`);
    }
    const resolvedPath = path.resolve(dome.path);
    dome.path = resolvedPath;
    dome.active = fs.existsSync(resolvedPath) && fs.statSync(resolvedPath).isDirectory();
    this.domes.set(dome.name, { ...dome });
    this.origin.set(dome.name, 'base');
  }

  remove(name: string): void {
    if (!this.domes.has(name)) {
      throw new Error(`Dome "${name}" not found`);
    }
    if (name === this.defaultDome) {
      throw new Error(`Cannot remove default dome "${name}". Change defaultDome first.`);
    }
    this.domes.delete(name);
    this.origin.delete(name);
  }

  save(): void {
    const byOrigin: Record<Origin, Record<string, unknown>> = { base: {}, local: {} };
    for (const [name, dome] of this.domes) {
      byOrigin[this.origin.get(name) ?? 'base'][name] = {
        name: dome.name,
        path: dome.path,
        description: dome.description,
        confidentiality: dome.confidentiality,
        schemaDir: dome.schemaDir,
        ...(dome.rag ? { rag: dome.rag } : {}),
        ...(dome.files ? { files: dome.files } : {}),
      };
    }

    const write = (file: string, defaultDome: string, domes: Record<string, unknown>) => {
      const data: DomesFile = { version: 1, defaultDome, domes: domes as DomesFile['domes'] };
      fs.writeFileSync(file, JSON.stringify(data, null, 2) + '\n');
    };
    // El base se escribe siempre que exista o tenga cúpulas; el local solo si existe o tiene cúpulas.
    const baseDefault = this.defaultDome === this.localDefault && this.localDefault ? '' : this.defaultDome;
    if (fs.existsSync(this.filePath) || Object.keys(byOrigin.base).length > 0 || !fs.existsSync(this.getLocalFilePath())) {
      write(this.filePath, baseDefault, byOrigin.base);
    }
    if (fs.existsSync(this.getLocalFilePath()) || Object.keys(byOrigin.local).length > 0) {
      write(this.getLocalFilePath(), this.localDefault, byOrigin.local);
    }
    this.loadedKey = this.statKey();
  }

  setDefault(name: string): void {
    if (!this.domes.has(name)) {
      throw new Error(`Dome "${name}" not found`);
    }
    this.defaultDome = name;
    this.save();
  }
}

export class VaultInstance {
  public readonly dome: DomeInfo;
  public readonly storage: VaultStorage;
  public readonly search: SearchEngine;
  public readonly security: VaultSecurity;
  public readonly config: VaultConfig;

  constructor(dome: DomeInfo) {
    this.dome = dome;
    const config = makeConfig(dome);
    this.config = config;
    this.storage = new VaultStorage(config);
    this.search = new SearchEngine(config);
    this.security = new VaultSecurity(config);
  }
}
