import * as fs from 'node:fs';
import * as path from 'node:path';
import { VaultStorage } from '../storage/index.js';
import { SearchEngine } from '../search/index.js';
import { VaultSecurity } from '../security/index.js';
import type { VaultConfig } from '../types.js';

export type ConfidentialityLevel = 'N1' | 'N2' | 'N3' | 'N4';

export interface DomeInfo {
  name: string;
  path: string;
  description: string;
  confidentiality: ConfidentialityLevel;
  schemaDir?: string;
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
  }>;
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
  };
}

export class DomeRegistry {
  private filePath: string;
  private domes: Map<string, DomeInfo> = new Map();
  public defaultDome: string = '';

  constructor(filePath: string = 'savia-vaults.domes.json') {
    this.filePath = filePath;
  }

  load(): void {
    if (!fs.existsSync(this.filePath)) {
      throw new Error(`Domes file not found: ${this.filePath}. Create one with 'savia-vaults dome create <name>' or use --path for single-dome mode.`);
    }

    let raw: string;
    try {
      raw = fs.readFileSync(this.filePath, 'utf-8');
    } catch {
      throw new Error(`Cannot read domes file: ${this.filePath}`);
    }

    let data: DomesFile;
    try {
      data = JSON.parse(raw);
    } catch {
      throw new Error(`Invalid JSON in domes file: ${this.filePath}`);
    }

    if (!data.version || !data.domes || typeof data.domes !== 'object') {
      throw new Error(`Invalid domes file structure in ${this.filePath}: expected { version, defaultDome, domes }`);
    }

    this.defaultDome = data.defaultDome || '';
    this.domes.clear();

    for (const [name, dome] of Object.entries(data.domes)) {
      // SE-310: resolver relativo al directorio del fichero de domes, NO al cwd
      // (el CLI puede correr desde cualquier cwd; la cupula vive junto al registry).
      const resolvedPath = path.resolve(path.dirname(this.filePath), dome.path);
      const active = fs.existsSync(resolvedPath) && fs.statSync(resolvedPath).isDirectory();

      if (!active) {
        console.warn(`Dome "${name}" path not found: ${resolvedPath} — marked inactive`);
      }

      const level = dome.confidentiality?.toUpperCase() || 'N2';
      if (!['N1', 'N2', 'N3', 'N4'].includes(level)) {
        throw new Error(`Invalid confidentiality level for dome "${name}": ${dome.confidentiality}. Must be N1, N2, N3, or N4.`);
      }

      this.domes.set(name, {
        name: dome.name || name,
        path: resolvedPath,
        description: dome.description || '',
        confidentiality: level as ConfidentialityLevel,
        schemaDir: dome.schemaDir,
        active,
      });
    }
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
  }

  remove(name: string): void {
    if (!this.domes.has(name)) {
      throw new Error(`Dome "${name}" not found`);
    }
    if (name === this.defaultDome) {
      throw new Error(`Cannot remove default dome "${name}". Change defaultDome first.`);
    }
    this.domes.delete(name);
  }

  save(): void {
    const domes: Record<string, unknown> = {};
    for (const [name, dome] of this.domes) {
      domes[name] = {
        name: dome.name,
        path: dome.path,
        description: dome.description,
        confidentiality: dome.confidentiality,
        schemaDir: dome.schemaDir,
      };
    }

    const data: DomesFile = {
      version: 1,
      defaultDome: this.defaultDome,
      domes: domes as DomesFile['domes'],
    };

    fs.writeFileSync(this.filePath, JSON.stringify(data, null, 2) + '\n');
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
