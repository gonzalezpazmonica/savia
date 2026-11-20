// E2E tests: SaviaVaults MCP server protocol compliance
// Copyright (c) 2026 Savia. MIT License.

import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import * as fs from 'node:fs';
import * as path from 'node:path';
import * as os from 'node:os';
import { MCPVaultServer } from '../../src/server/mcp.js';
import type { VaultConfig } from '../../src/types.js';

describe('SaviaVaults E2E — MCP Protocol', () => {
  let config: VaultConfig;
  let vaultPath: string;

  beforeEach(async () => {
    vaultPath = fs.mkdtempSync(path.join(os.tmpdir(), 'savia-vault-e2e-'));
    config = {
      name: 'e2e-vault',
      path: vaultPath,
      allowedExtensions: [],
      deniedPaths: [],
      maxDepth: 10,
      maxFileSize: 1024 * 1024,
    };

    // Pre-populate with test notes
    fs.mkdirSync(path.join(vaultPath, 'docs'), { recursive: true });
    fs.writeFileSync(path.join(vaultPath, 'README.md'), [
      '---',
      'title: Vault Overview',
      'tags: [overview, getting-started]',
      '---',
      '',
      '# SaviaVaults',
      'A context dome server for AI agents.',
    ].join('\n'));

    fs.writeFileSync(path.join(vaultPath, 'docs', 'api.md'), [
      '---',
      'title: API Reference',
      'tags: [api, reference, technical]',
      '---',
      '',
      '# API Reference',
      'MCP tools: vault_read, vault_write, vault_search, vault_list.',
    ].join('\n'));

    fs.writeFileSync(path.join(vaultPath, 'INDEX.md'), '# e2e-vault\n\n');
    fs.writeFileSync(path.join(vaultPath, 'MAP.md'), '# e2e-vault — Routing Map\n\n');
    fs.mkdirSync(path.join(vaultPath, '.git'), { recursive: true });
  });

  afterEach(() => {
    if (fs.existsSync(vaultPath)) {
      fs.rmSync(vaultPath, { recursive: true, force: true });
    }
  });

  it('server can be constructed without error', () => {
    const server = new MCPVaultServer(config);
    expect(server).toBeDefined();
  });

  it('vault contains expected notes after setup', () => {
    expect(fs.existsSync(path.join(vaultPath, 'README.md'))).toBe(true);
    expect(fs.existsSync(path.join(vaultPath, 'docs', 'api.md'))).toBe(true);
  });

  it('directory structure matches expected layout', () => {
    const entries = fs.readdirSync(vaultPath, { withFileTypes: true });
    const files = entries.filter((e) => e.isFile()).map((e) => e.name);
    const dirs = entries.filter((e) => e.isDirectory()).map((e) => e.name);

    expect(files).toContain('README.md');
    expect(files).toContain('INDEX.md');
    expect(files).toContain('MAP.md');
    expect(dirs).toContain('docs');
    expect(dirs).toContain('.git');
  });

  it('security blocks traversal attacks', async () => {
    const { VaultSecurity: VS } = await import('../../src/security/index.js');
    const security = new VS(config);

    expect(() => security.contain('../../../etc/passwd')).toThrow();
    expect(() => security.contain('.git/config')).toThrow();
  });
});
