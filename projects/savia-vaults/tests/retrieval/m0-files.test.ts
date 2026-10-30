// SE-489 — M0 con Savia Files: mismos hits que search y ACL del documento (SE-419) en el guard.
import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import * as fs from 'node:fs';
import * as os from 'node:os';
import * as path from 'node:path';
import { FilesService } from '../../src/files/service.js';
import { RagService, type RagDomeRef } from '../../src/rag/service.js';
import { HashEmbedder } from '../../src/rag/embedder.js';
import { Journal } from '../../src/files/journal.js';
import { runRoute } from '../../src/retrieval/runner.js';
import type { Principal } from '../../src/files/policy.js';
import type { ResolvedRagConfig } from '../../src/rag/types.js';

const b64 = (s: string) => Buffer.from(s).toString('base64');

describe('SE-489 M0 con Savia Files', () => {
  let root: string;
  let who: Principal | undefined;
  let rag: RagService;
  let files: FilesService;

  beforeEach(() => {
    root = fs.mkdtempSync(path.join(os.tmpdir(), 'savia-se489-files-'));
    const env = { SAVIA_FILES_HOME: path.join(root, 'files'), SAVIA_FILES_KEYS_HOME: path.join(root, 'keys'), SAVIA_RAG_HOME: path.join(root, 'rag'), HOME: root, PATH: process.env.PATH };
    fs.mkdirSync(path.join(root, 'D'));
    fs.writeFileSync(path.join(root, 'D', 'nota.md'), '# Nota\n\nNota con alcaudón común.\n');
    const domes: RagDomeRef[] = [{ name: 'D', path: path.join(root, 'D'), confidentiality: 'N2', rag: { enabled: true, model: 'h' }, files: { enabled: true } }];
    who = undefined;
    const authorize = async () => who;
    const emb = new HashEmbedder(64, { chunkChars: 1200, overlap: 180 } as ResolvedRagConfig, 'h');
    rag = new RagService({ domes: () => domes, home: env.SAVIA_RAG_HOME, env, embedderFactory: () => emb, authorize });
    files = new FilesService({
      domes: () => domes.map((d) => ({ name: d.name, confidentiality: d.confidentiality, files: d.files })),
      env, scanMode: 'off', authorize, onChange: () => undefined,
      onEncrypted: (d) => rag.sealIndex(d), resealIndex: (d) => rag.resealIndex(d),
    });
  });
  afterEach(() => { Journal.closeAll(); fs.rmSync(root, { recursive: true, force: true }); });

  it('los hits de ficheros son los mismos y llevan revisión y localizador; la ACL los oculta', async () => {
    const put = await files.put({ dome: 'D', name: 'informe.txt', contentBase64: b64('informe del alcaudón común reservado') });
    const id = put.documentId;
    await rag.sync('D');
    const base = await rag.search({ queries: ['alcaudón común'], domes: ['D'], mode: 'bm25' });
    const out = await runRoute(rag, { route: 'M0', query: 'alcaudón común', domes: ['D'], mode: 'bm25' });
    expect(out.result.hits).toEqual(base.results[0].hits);
    const fileEv = out.result.evidence.find(e => e.document === `files/${id}`)!;
    expect(fileEv).toBeDefined();
    expect(fileEv.revision).toBe(base.results[0].hits.find(h => h.source)!.source!.revisionId);
    expect(fileEv.locator).toMatch(/^lines:/);

    await files.policy({ dome: 'D', id, readers: ['ana'] });
    who = { username: 'luis', role: 'reader' };
    const hidden = await runRoute(rag, { route: 'M0', query: 'alcaudón común', domes: ['D'], mode: 'bm25' });
    expect(hidden.result.hits.some(h => h.source)).toBe(false);
    expect(JSON.stringify(hidden.result)).not.toContain(id);
    who = { username: 'ana', role: 'reader' };
    const shown = await runRoute(rag, { route: 'M0', query: 'alcaudón común', domes: ['D'], mode: 'bm25' });
    expect(shown.result.hits.some(h => h.source?.documentId === id)).toBe(true);
  });
});
