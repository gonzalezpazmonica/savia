import * as fs from 'node:fs';
import * as path from 'node:path';
import * as crypto from 'node:crypto';
import { simpleGit } from 'simple-git';
import YAML from 'yaml';
import type { VaultConfig, Note, Receipt, VaultStats, CommitEntry, Frontmatter } from '../types.js';
import { signContent } from '../security/index.js';
import { fileClassification, fileOutOfLevel, isMarkdown, parseClassification, verdictOf } from './note-level.js';

export class VaultStorage {
  private config: VaultConfig;

  constructor(config: VaultConfig) {
    this.config = config;
  }

  async init(): Promise<void> {
    const vp = this.config.path;
    fs.mkdirSync(vp, { recursive: true });

    if (!fs.existsSync(path.join(vp, 'INDEX.md'))) {
      fs.writeFileSync(path.join(vp, 'INDEX.md'), `# ${this.config.name}\n\nVault index.\n`);
    }

    if (!fs.existsSync(path.join(vp, 'MAP.md'))) {
      fs.writeFileSync(path.join(vp, 'MAP.md'), `# ${this.config.name} — Routing Map\n\n`);
    }

    const git = simpleGit(vp);
    const isRepo = await git.checkIsRepo().catch(() => false);
    if (!isRepo) {
      await git.init();
      await git.addConfig('user.name', 'savia-vaults');
      await git.addConfig('user.email', 'vaults@localhost');
      await git.add('.');
      await git.commit('Initial commit: vault created');
    }
  }

  /** SE-420: nota con nivel mayor que la cúpula (solo si la configuración trae el nivel). */
  private outOfLevel(notePath: string): boolean {
    return fileOutOfLevel(path.join(this.config.path, notePath), notePath, this.config.confidentiality);
  }

  async read(notePath: string): Promise<Note> {
    const fullPath = path.join(this.config.path, notePath);
    if (!fs.existsSync(fullPath) || this.outOfLevel(notePath)) throw new Error('Note not found');

    const raw = fs.readFileSync(fullPath, 'utf-8');
    const { frontmatter, content } = this.parseFrontmatter(raw);
    const stat = fs.statSync(fullPath);
    const ext = path.extname(notePath);

    return {
      path: notePath,
      name: path.basename(notePath, ext),
      frontmatter,
      tags: this.extractTags(frontmatter, content),
      content,
      created: stat.birthtime.toISOString(),
      modified: stat.mtime.toISOString(),
    };
  }

  async write(notePath: string, content: string, message?: string): Promise<Receipt> {
    const fullPath = path.join(this.config.path, notePath);
    // SE-420: ni se escribe una nota de nivel superior a la cúpula ni se pisa una que ya lo esté.
    if (isMarkdown(notePath)) {
      // SE-481 R2: una clasificación explícita no interpretable se rechaza antes de persistir.
      const cls = parseClassification(notePath, content);
      const verdict = verdictOf(cls, this.config.confidentiality);
      if (verdict === 'quarantine') {
        throw new Error(`INVALID_CLASSIFICATION: el frontmatter declara \`confidentiality\` pero no es un nivel válido (${cls.diagnostic}); usa N1, N2, N3, N4 o N4b`);
      }
      if (verdict === 'out-of-level') {
        throw new Error(`POLICY_DENIED: la nota declara un nivel superior al de la cúpula (${this.config.confidentiality})`);
      }
    }
    if (this.outOfLevel(notePath)) throw new Error('POLICY_DENIED: en esa ruta hay una nota de nivel superior al de la cúpula');
    const dir = path.dirname(fullPath);
    fs.mkdirSync(dir, { recursive: true });
    fs.writeFileSync(fullPath, content);

    const hash = crypto.createHash('sha256').update(content).digest('hex');
    const signature = signContent(content);

    const git = simpleGit(this.config.path);
    try {
      await git.add(notePath);
      await git.commit(message || `Write ${notePath}`);
    } catch {
      // git operations may fail in some environments; non-fatal
    }

    return {
      vault: this.config.name,
      path: notePath,
      contentHash: hash,
      signature,
      timestamp: new Date().toISOString(),
    };
  }

  async delete(notePath: string, soft = true): Promise<void> {
    const fullPath = path.join(this.config.path, notePath);
    if (!fs.existsSync(fullPath)) return;

    if (soft) {
      const trashDir = path.join(this.config.path, '.trash');
      fs.mkdirSync(trashDir, { recursive: true });
      const ts = Date.now();
      const base = path.basename(notePath);
      const dest = path.join(trashDir, `${base}.${ts}`);
      fs.renameSync(fullPath, dest);
    } else {
      fs.unlinkSync(fullPath);
    }

    const git = simpleGit(this.config.path);
    try {
      if (soft) {
        const trashDir = path.join(this.config.path, '.trash');
        await git.add(trashDir);
        await git.add(notePath);
        await git.commit(`Delete ${notePath} (soft)`);
      } else {
        await git.rm(notePath);
        await git.commit(`Delete ${notePath} (hard)`);
      }
    } catch {
      // git operations may fail in some environments
    }
  }

  async list(): Promise<string[]> {
    return this.listAll().filter((f) => !this.outOfLevel(f));
  }

  private listAll(): string[] {
    const results: string[] = [];
    this.walkDir(this.config.path, '', results);
    return results;
  }

  private walkDir(base: string, relative: string, results: string[]): void {
    const full = path.join(base, relative);
    if (!fs.existsSync(full)) return;

    const entries = fs.readdirSync(full, { withFileTypes: true });
    for (const e of entries) {
      const relPath = relative ? path.join(relative, e.name) : e.name;
      if (e.isDirectory()) {
        if (['.git', '.trash', '.savia-vault'].includes(e.name)) continue;
        this.walkDir(base, relPath, results);
      } else if (e.isFile()) {
        if (e.name === 'INDEX.md' || e.name === 'MAP.md') continue;
        // Vault APIs use POSIX separators so the same note has one stable ID
        // on Windows and POSIX hosts.
        results.push(relPath.split(path.sep).join('/'));
      }
    }
  }

  async stats(): Promise<VaultStats> {
    const all = this.listAll();
    const files = all.filter((f) => !this.outOfLevel(f));
    let totalSize = 0;
    for (const f of files) {
      try {
        totalSize += fs.statSync(path.join(this.config.path, f)).size;
      } catch {}
    }

    let commitCount = 0;
    try {
      const git = simpleGit(this.config.path);
      const log = await git.log({ maxCount: 1000 });
      commitCount = log.total;
    } catch {}

    const quarantined = this.quarantine().total;
    return {
      name: this.config.name,
      noteCount: files.length,
      totalSize,
      commitCount,
      ...(this.config.confidentiality ? { outOfLevel: all.length - files.length - quarantined } : {}),
      ...(quarantined ? { quarantined } : {}),
    };
  }

  /**
   * SE-481 R2: notas en cuarentena (clasificación explícita no interpretable).
   * Las rutas solo deben salir por la CLI local (`dome quarantine`); MCP muestra `byCode`.
   */
  quarantine(): { total: number; byCode: Record<string, number>; notes: { path: string; code: string }[] } {
    const byCode: Record<string, number> = {};
    const notes: { path: string; code: string }[] = [];
    for (const f of this.listAll()) {
      const cls = fileClassification(path.join(this.config.path, f), f);
      if (!cls || verdictOf(cls, undefined) !== 'quarantine') continue;
      byCode[cls.diagnostic!] = (byCode[cls.diagnostic!] ?? 0) + 1;
      notes.push({ path: f, code: cls.diagnostic! });
    }
    return { total: notes.length, byCode, notes };
  }

  async diff(notePath: string): Promise<string> {
    if (this.outOfLevel(notePath)) throw new Error('Note not found');
    const git = simpleGit(this.config.path);
    try {
      const d = await git.diff([notePath]);
      return d || '';
    } catch {
      return '';
    }
  }

  async log(notePath: string, maxCount = 20): Promise<CommitEntry[]> {
    if (this.outOfLevel(notePath)) throw new Error('Note not found');
    const git = simpleGit(this.config.path);
    try {
      const history = await git.log({ file: notePath, maxCount });
      return history.all.map((e: { hash: string; date: string; message: string }) => ({
        hash: e.hash,
        date: e.date,
        message: e.message,
      }));
    } catch {
      return [];
    }
  }

  private parseFrontmatter(raw: string): { frontmatter: Frontmatter; content: string } {
    const match = raw.match(/^---\r?\n([\s\S]*?)\r?\n---\r?\n?([\s\S]*)$/);
    if (!match) return { frontmatter: {}, content: raw };

    try {
      const frontmatter = YAML.parse(match[1]) || {};
      const content = match[2].trim();
      return { frontmatter, content };
    } catch {
      return { frontmatter: {}, content: raw };
    }
  }

  private extractTags(frontmatter: Frontmatter, content: string): string[] {
    const tags = new Set<string>();

    if (Array.isArray(frontmatter.tags)) {
      for (const t of frontmatter.tags) tags.add(String(t).toLowerCase());
    }

    const inlineTags = content.match(/#([\w-]+)/g);
    if (inlineTags) {
      for (const t of inlineTags) {
        tags.add(t.slice(1).toLowerCase());
      }
    }

    return [...tags].sort();
  }
}
