import { Server } from '@modelcontextprotocol/sdk/server/index.js';
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js';
import {
  CallToolRequestSchema,
  ListToolsRequestSchema,
} from '@modelcontextprotocol/sdk/types.js';
import { VaultStorage } from '../storage/index.js';
import { SearchEngine } from '../search/index.js';
import { VaultSecurity } from '../security/index.js';
import { Introspector } from '../knowledge/introspector.js';
import { KnowledgeGraph } from '../knowledge/graph.js';
import { QueryEngine } from '../knowledge/query.js';
import { QualityEngine } from '../knowledge/quality.js';
import type { VaultConfig } from '../types.js';
import { DomeRegistry, VaultInstance } from '../registry/domes.js';
import { UserStore, AccessController, AuthError, AuditLogger, UserQuotaStore } from '../auth/index.js';
import type { AuthAction } from '../auth/index.js';
import * as fs from 'node:fs';
import * as path from 'node:path';

const AUTH_TOKEN_ENV = 'SAVIA_AUTH_TOKEN';

function readAuthToken(): string | undefined {
  return process.env[AUTH_TOKEN_ENV] || undefined;
}

export class MCPVaultServer {
  private config: VaultConfig;
  private storage: VaultStorage;
  private search: SearchEngine;
  private security: VaultSecurity;

  private domeRegistry: DomeRegistry | undefined;
  private userStore: UserStore | undefined;
  private accessController: AccessController | undefined;
  private auditLogger: AuditLogger | undefined;
  private quotaStore: UserQuotaStore | undefined;
  private instances: Map<string, VaultInstance> = new Map();

  constructor(config: VaultConfig, domeRegistry?: DomeRegistry, userStore?: UserStore) {
    this.config = config;
    this.storage = new VaultStorage(config);
    this.search = new SearchEngine(config);
    this.security = new VaultSecurity(config);

    if (domeRegistry) {
      this.domeRegistry = domeRegistry;
      const us = userStore || new UserStore();
      this.userStore = us;
      try { us.load(); } catch {}

      const al = new AuditLogger();
      const qs = new UserQuotaStore();
      try { qs.load(); } catch {}
      qs.startAutoPersist();

      this.auditLogger = al;
      this.quotaStore = qs;

      this.accessController = new AccessController(us, domeRegistry, al, qs);

      for (const dome of domeRegistry.listActive()) {
        this.instances.set(dome.name, new VaultInstance(dome));
      }
    }

    if (!domeRegistry) {
      this.initVault();
    }
  }

  private getInstance(vaultName?: string): VaultInstance {
    if (!this.domeRegistry) {
      return { config: this.config, dome: { name: this.config.name, path: this.config.path, description: '', confidentiality: 'N2', active: true }, storage: this.storage, search: this.search, security: this.security };
    }
    const name = vaultName || this.domeRegistry.getDefaultName();
    const inst = this.instances.get(name);
    if (!inst) throw new Error(`Dome "${name}" not found. Available: ${[...this.instances.keys()].join(', ')}`);
    return inst;
  }

  private getDomeName(vaultName?: string): string {
    if (!this.domeRegistry) return this.config.name;
    return vaultName || this.domeRegistry.getDefaultName();
  }

  private async authorize(dome: string, action: AuthAction, tool?: string): Promise<void> {
    if (!this.accessController) return;
    if (!this.accessController.isActive) return;
    const token = readAuthToken();
    await this.accessController.authorize({ authToken: token, dome, action, tool });
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

  async start(): Promise<void> {
    const server = new Server(
      { name: 'savia-vaults', version: '0.3.0' },
      { capabilities: { tools: {} } }
    );

    server.setRequestHandler(ListToolsRequestSchema, async () => ({
      tools: [
        {
          name: 'vault_read',
          description: 'Read a note by path. Returns content with frontmatter and tags.',
          inputSchema: {
            type: 'object',
            properties: {
              vault: { type: 'string', description: 'Dome name (default: configured default)' },
              path: { type: 'string', description: 'Relative path to the note' },
            },
            required: ['path'],
          },
        },
        {
          name: 'vault_write',
          description: 'Create or update a note. Git-committed with content hash.',
          inputSchema: {
            type: 'object',
            properties: {
              vault: { type: 'string', description: 'Dome name (default: configured default)' },
              path: { type: 'string', description: 'Relative path for the note' },
              content: { type: 'string', description: 'Markdown content to write' },
              message: { type: 'string', description: 'Optional commit message' },
            },
            required: ['path', 'content'],
          },
        },
        {
          name: 'vault_search',
          description: 'Full-text search across vault notes with BM25 ranking.',
          inputSchema: {
            type: 'object',
            properties: {
              vault: { type: 'string', description: 'Dome name (default: configured default)' },
              query: { type: 'string', description: 'Search query' },
              maxResults: { type: 'number', description: 'Max results (default 10)' },
              pathPrefix: { type: 'string', description: 'Filter by path prefix' },
            },
            required: ['query'],
          },
        },
        {
          name: 'vault_list',
          description: 'List all notes in a vault as a directory tree.',
          inputSchema: {
            type: 'object',
            properties: {
              vault: { type: 'string', description: 'Dome name (default: configured default)' },
              path: { type: 'string', description: 'Optional subdirectory to list' },
            },
          },
        },
        {
          name: 'vault_stats',
          description: 'Vault statistics: note count, total size, commits.',
          inputSchema: {
            type: 'object',
            properties: {
              vault: { type: 'string', description: 'Dome name (default: configured default)' },
            },
          },
        },
        {
          name: 'vault_index',
          description: 'Rebuild the search index.',
          inputSchema: {
            type: 'object',
            properties: {
              vault: { type: 'string', description: 'Dome name (default: configured default)' },
            },
          },
        },
        {
          name: 'vault_diff',
          description: 'Show git diff for a note.',
          inputSchema: {
            type: 'object',
            properties: {
              vault: { type: 'string', description: 'Dome name (default: configured default)' },
              path: { type: 'string' },
            },
            required: ['path'],
          },
        },
        {
          name: 'vault_log',
          description: 'Show git history for a note.',
          inputSchema: {
            type: 'object',
            properties: {
              vault: { type: 'string', description: 'Dome name (default: configured default)' },
              path: { type: 'string' },
              maxCount: { type: 'number', description: 'Max entries (default 20)' },
            },
            required: ['path'],
          },
        },
        {
          name: 'vault_tags',
          description: 'List all tags with occurrence counts.',
          inputSchema: {
            type: 'object',
            properties: {
              vault: { type: 'string', description: 'Dome name (default: configured default)' },
            },
          },
        },
        {
          name: 'vault_domes',
          description: 'List registered domes with name, description, confidentiality, and note count.',
          inputSchema: { type: 'object', properties: {} },
        },
        { name: 'vault_introspect', description: 'Discover entity types, coverage, and available properties.', inputSchema: { type: 'object', properties: { vault: { type: 'string' }, entity: { type: 'string' } } } },
        { name: 'vault_graph', description: 'Query knowledge graph: traverse, search, or get stats.', inputSchema: { type: 'object', properties: { vault: { type: 'string' }, action: { type: 'string' }, id: { type: 'string' }, depth: { type: 'number' }, query: { type: 'string' } }, required: ['action'] } },
        { name: 'vault_query', description: 'Deterministic dotted-notation query for entities.', inputSchema: { type: 'object', properties: { vault: { type: 'string' }, expression: { type: 'string' } }, required: ['expression'] } },
        { name: 'vault_health', description: 'Quality report: coverage, provenance, conflicts, freshness.', inputSchema: { type: 'object', properties: { vault: { type: 'string' } } } },
        {
          name: 'vault_wikilink_health',
          description: 'Report wikiLink health: total links, valid links, broken links, and most-linked entities.',
          inputSchema: {
            type: 'object',
            properties: {
              vault: { type: 'string', description: 'Dome name (optional, uses default if not specified)' },
            },
          },
        },
      ],
    }));

    server.setRequestHandler(CallToolRequestSchema, async (request) => {
      const name = request.params.name;
      const args = (request.params.arguments || {}) as Record<string, unknown>;
      try {
        switch (name) {
          case 'vault_domes': {
            if (!this.domeRegistry) {
              return { content: [{ type: 'text', text: JSON.stringify([{ name: this.config.name, description: '', confidentiality: 'N2', noteCount: 0 }], null, 2) }] };
            }
            const domes = this.domeRegistry.listActive();
            const result = await Promise.all(domes.map(async (d) => {
              const inst = this.instances.get(d.name);
              let noteCount = 0;
              if (inst) {
                try { const files = await inst.storage.list(); noteCount = files.length; } catch {}
              }
              return { name: d.name, path: '', description: d.description, confidentiality: d.confidentiality, noteCount };
            }));
            return { content: [{ type: 'text', text: JSON.stringify(result, null, 2) }] };
          }

          case 'vault_read': {
            const inst = this.getInstance(args.vault as string | undefined);
            const dome = this.getDomeName(args.vault as string | undefined);
            try { await this.authorize(dome, 'read', 'vault_read'); } catch (e) { if (e instanceof AuthError) return { content: [{ type: 'text', text: `Error: ${e.message}` }], isError: true }; throw e; }
            const note = await inst.storage.read(args.path as string);

            // Resolve wikilink backlinks
            let backlinks: Array<{ source: string; context: string }> | undefined;
            let outgoingLinks: string[] | undefined;
            try {
              const { resolveBacklinks, extractWikiLinks } = await import('../knowledge/wikilink-validator.js');
              const allNotes = await inst.storage.list();
              const allContents: Array<{ path: string; content: string }> = [];
              for (const notePath of allNotes.slice(0, 200)) {
                try {
                  const n = await inst.storage.read(notePath);
                  allContents.push({ path: n.path, content: n.content });
                } catch {}
              }
              backlinks = resolveBacklinks(note.path, allContents);
              outgoingLinks = extractWikiLinks(note.content).map(l => l.target);
            } catch { /* backlinks are optional */ }

            return { content: [{ type: 'text', text: JSON.stringify({ path: note.path, name: note.name, frontmatter: note.frontmatter, tags: note.tags, content: note.content, ...(backlinks?.length ? { backlinks } : {}), ...(outgoingLinks?.length ? { outgoing_links: outgoingLinks } : {}) }, null, 2) }] };
          }

          case 'vault_write': {
            const inst = this.getInstance(args.vault as string | undefined);
            const dome = this.getDomeName(args.vault as string | undefined);
            try { await this.authorize(dome, 'write', 'vault_write'); } catch (e) { if (e instanceof AuthError) return { content: [{ type: 'text', text: `Error: ${e.message}` }], isError: true }; throw e; }
            const receipt = await inst.storage.write(args.path as string, args.content as string, args.message as string);
            return { content: [{ type: 'text', text: JSON.stringify(receipt, null, 2) }] };
          }

          case 'vault_search': {
            const inst = this.getInstance(args.vault as string | undefined);
            const dome = this.getDomeName(args.vault as string | undefined);
            try { await this.authorize(dome, 'read', 'vault_search'); } catch (e) { if (e instanceof AuthError) return { content: [{ type: 'text', text: `Error: ${e.message}` }], isError: true }; throw e; }
            inst.search.buildIndex();
            const results = inst.search.search({
              query: args.query as string,
              maxResults: (args.maxResults as number) || 10,
              pathPrefix: args.pathPrefix as string | undefined,
            });
            return { content: [{ type: 'text', text: JSON.stringify(results, null, 2) }] };
          }

          case 'vault_list': {
            const inst = this.getInstance(args.vault as string | undefined);
            const dome = this.getDomeName(args.vault as string | undefined);
            try { await this.authorize(dome, 'read', 'vault_list'); } catch (e) { if (e instanceof AuthError) return { content: [{ type: 'text', text: `Error: ${e.message}` }], isError: true }; throw e; }
            const files = await inst.storage.list();
            const prefix = args.path as string | undefined;
            const filtered = prefix ? files.filter(f => f.startsWith(prefix)) : files;
            return { content: [{ type: 'text', text: JSON.stringify(filtered, null, 2) }] };
          }

          case 'vault_stats': {
            const inst = this.getInstance(args.vault as string | undefined);
            const dome = this.getDomeName(args.vault as string | undefined);
            try { await this.authorize(dome, 'read', 'vault_stats'); } catch (e) { if (e instanceof AuthError) return { content: [{ type: 'text', text: `Error: ${e.message}` }], isError: true }; throw e; }
            const stats = await inst.storage.stats();
            return { content: [{ type: 'text', text: JSON.stringify(stats, null, 2) }] };
          }

          case 'vault_index': {
            const inst = this.getInstance(args.vault as string | undefined);
            const dome = this.getDomeName(args.vault as string | undefined);
            try { await this.authorize(dome, 'write', 'vault_index'); } catch (e) { if (e instanceof AuthError) return { content: [{ type: 'text', text: `Error: ${e.message}` }], isError: true }; throw e; }
            inst.search.buildIndex();
            const tags = inst.search.getTags();
            return { content: [{ type: 'text', text: `Index rebuilt. ${tags.size} unique tags indexed.` }] };
          }

          case 'vault_diff': {
            const inst = this.getInstance(args.vault as string | undefined);
            const dome = this.getDomeName(args.vault as string | undefined);
            try { await this.authorize(dome, 'read', 'vault_diff'); } catch (e) { if (e instanceof AuthError) return { content: [{ type: 'text', text: `Error: ${e.message}` }], isError: true }; throw e; }
            const diff = await inst.storage.diff(args.path as string);
            return { content: [{ type: 'text', text: diff || '(no changes)' }] };
          }

          case 'vault_log': {
            const inst = this.getInstance(args.vault as string | undefined);
            const dome = this.getDomeName(args.vault as string | undefined);
            try { await this.authorize(dome, 'read', 'vault_log'); } catch (e) { if (e instanceof AuthError) return { content: [{ type: 'text', text: `Error: ${e.message}` }], isError: true }; throw e; }
            const log = await inst.storage.log(args.path as string, (args.maxCount as number) || 20);
            return { content: [{ type: 'text', text: JSON.stringify(log, null, 2) }] };
          }

          case 'vault_tags': {
            const inst = this.getInstance(args.vault as string | undefined);
            const dome = this.getDomeName(args.vault as string | undefined);
            try { await this.authorize(dome, 'read', 'vault_tags'); } catch (e) { if (e instanceof AuthError) return { content: [{ type: 'text', text: `Error: ${e.message}` }], isError: true }; throw e; }
            inst.search.buildIndex();
            const tags = inst.search.getTags();
            return { content: [{ type: 'text', text: JSON.stringify([...tags.entries()], null, 2) }] };
          }

          case 'vault_introspect': {
            const inst = this.getInstance(args.vault as string | undefined);
            const dome = this.getDomeName(args.vault as string | undefined);
            try { await this.authorize(dome, 'read', 'vault_introspect'); } catch (e) { if (e instanceof AuthError) return { content: [{ type: 'text', text: `Error: ${e.message}` }], isError: true }; throw e; }
            if (!inst.config.schemaDir) return { content: [{ type: 'text', text: 'No schema configured.' }], isError: true };
            const introspector = new Introspector(inst.config);
            if (args.entity) {
              const entity = await introspector.introspectEntity(args.entity as string);
              return { content: [{ type: 'text', text: JSON.stringify(entity, null, 2) }] };
            }
            const vault = await introspector.introspectVault();
            return { content: [{ type: 'text', text: JSON.stringify(vault, null, 2) }] };
          }

          case 'vault_graph': {
            const inst = this.getInstance(args.vault as string | undefined);
            const dome = this.getDomeName(args.vault as string | undefined);
            try { await this.authorize(dome, 'read', 'vault_graph'); } catch (e) { if (e instanceof AuthError) return { content: [{ type: 'text', text: `Error: ${e.message}` }], isError: true }; throw e; }
            if (!inst.config.schemaDir) return { content: [{ type: 'text', text: 'No schema configured.' }], isError: true };
            const graph = new KnowledgeGraph(inst.config);
            await graph.build();
            const action = args.action as string;
            if (action === 'traverse') {
              const result = graph.traverse(args.id as string, (args.depth as number) || 3);
              return { content: [{ type: 'text', text: JSON.stringify(result, null, 2) }] };
            } else if (action === 'search') {
              const nodes = graph.searchNodes(args.query as string);
              return { content: [{ type: 'text', text: JSON.stringify(nodes.map(n => ({ id: n.id, type: n.type, path: n.path, outgoing: n.outgoing.length, incoming: n.incoming.length })), null, 2) }] };
            } else {
              const stats = graph.getStats();
              return { content: [{ type: 'text', text: JSON.stringify(stats, null, 2) }] };
            }
          }

          case 'vault_query': {
            const inst = this.getInstance(args.vault as string | undefined);
            const dome = this.getDomeName(args.vault as string | undefined);
            try { await this.authorize(dome, 'read', 'vault_query'); } catch (e) { if (e instanceof AuthError) return { content: [{ type: 'text', text: `Error: ${e.message}` }], isError: true }; throw e; }
            if (!inst.config.schemaDir) return { content: [{ type: 'text', text: 'No schema configured.' }], isError: true };
            const queryEngine = new QueryEngine(inst.config);
            await queryEngine.ensureLoaded();
            const result = await queryEngine.query(args.expression as string);
            return { content: [{ type: 'text', text: result.outputMarkdown }] };
          }

          case 'vault_wikilink_health': {
            const inst = this.getInstance(args.vault as string | undefined);
            const dome = this.getDomeName(args.vault as string | undefined);
            try { await this.authorize(dome, 'read', 'vault_wikilink_health'); } catch (e) { if (e instanceof AuthError) return { content: [{ type: 'text', text: `Error: ${e.message}` }], isError: true }; throw e; }
            try {
              const { computeWikiLinkHealth, buildEntityIndex } = await import('../knowledge/wikilink-validator.js');
              const allNotes = await inst.storage.list();
              const notes: Array<{ path: string; content: string; frontmatter: Record<string, unknown> }> = [];
              for (const notePath of allNotes.slice(0, 500)) {
                try {
                  const n = await inst.storage.read(notePath);
                  notes.push({ path: n.path, content: n.content, frontmatter: n.frontmatter });
                } catch {}
              }
              const entityIndex = buildEntityIndex(notes);
              const health = computeWikiLinkHealth(notes, entityIndex);
              return { content: [{ type: 'text', text: JSON.stringify(health, null, 2) }] };
            } catch (e) {
              return { content: [{ type: 'text', text: JSON.stringify({ error: String(e) }) }], isError: true };
            }
          }

          case 'vault_health': {
            const inst = this.getInstance(args.vault as string | undefined);
            const dome = this.getDomeName(args.vault as string | undefined);
            try { await this.authorize(dome, 'read', 'vault_health'); } catch (e) { if (e instanceof AuthError) return { content: [{ type: 'text', text: `Error: ${e.message}` }], isError: true }; throw e; }
            if (!inst.config.schemaDir) return { content: [{ type: 'text', text: 'No schema configured.' }], isError: true };
            const quality = new QualityEngine(inst.config);
            const indicators = await quality.assess();
            return { content: [{ type: 'text', text: quality.formatReport(indicators) }] };
          }

          default:
            return { content: [{ type: 'text', text: `Unknown tool: ${name}` }], isError: true };
        }
      } catch (e: unknown) {
        if (e instanceof AuthError) {
          return { content: [{ type: 'text', text: `Error: ${e.message}` }], isError: true };
        }
        const msg = e instanceof Error ? e.message : String(e);
        return { content: [{ type: 'text', text: `Error: ${msg}` }], isError: true };
      }
    });

    const transport = new StdioServerTransport();
    await server.connect(transport);
  }
}
