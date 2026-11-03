// SE-489 M2 — las dependencias del reranker son opcionales: su ausencia no rompe la compilación
// ni la ruta; el reranker deja de existir y M2 cae a M0 (fail-open en calidad).
import { describe, expect, it } from 'vitest';
import * as crypto from 'node:crypto';
import * as fs from 'node:fs';
import * as os from 'node:os';
import * as path from 'node:path';
import { createRequire } from 'node:module';
import { ORT_MODULE, RerankDepsError, TOKENIZERS_MODULE, loadRerankDeps, type ModuleImporter } from '../../src/retrieval/rerank/optional-deps.js';
import { RerankError, loadOnnxCrossEncoder } from '../../src/retrieval/rerank/cross-encoder.js';

const notFound = (name: string) => Object.assign(new Error(`Cannot find package '${name}'`), { code: 'ERR_MODULE_NOT_FOUND' });
const fakeOrt = { Tensor: class {}, InferenceSession: { create: async () => ({}) } };
const fakeTok = { Tokenizer: class {} };

/** Importador que simula una instalación con solo los módulos indicados. */
const only = (mods: Record<string, unknown>): ModuleImporter => async name => {
  if (name in mods) return mods[name];
  throw notFound(name);
};

describe('SE-489 M2 dependencias opcionales del reranker', () => {
  it('sin onnxruntime-node instalado: error propio, sin detalle de la librería', async () => {
    const err = await loadRerankDeps(only({ [TOKENIZERS_MODULE]: fakeTok })).catch(e => e);
    expect(err).toBeInstanceOf(RerankDepsError);
    expect(err.message).toBe('dependencia opcional del reranker no instalada');
    expect(err.message).not.toMatch(/Cannot find/);
  });

  it('sin @huggingface/tokenizers instalado: mismo error', async () => {
    await expect(loadRerankDeps(only({ [ORT_MODULE]: fakeOrt }))).rejects.toThrow(/no instalada/);
  });

  it('módulo presente pero con otra forma: no se acepta', async () => {
    await expect(loadRerankDeps(only({ [ORT_MODULE]: { Tensor: class {} }, [TOKENIZERS_MODULE]: fakeTok }))).rejects.toThrow(/API no reconocida/);
    await expect(loadRerankDeps(only({ [ORT_MODULE]: fakeOrt, [TOKENIZERS_MODULE]: { Tokenizer: 'no' } }))).rejects.toThrow(/API no reconocida/);
    await expect(loadRerankDeps(only({ [ORT_MODULE]: null, [TOKENIZERS_MODULE]: fakeTok }))).rejects.toThrow(/API no reconocida/);
  });

  it('con ambas dependencias con la forma esperada: las devuelve', async () => {
    const deps = await loadRerankDeps(only({ [ORT_MODULE]: fakeOrt, [TOKENIZERS_MODULE]: fakeTok }));
    expect(deps.ort).toBe(fakeOrt);
    expect(deps.tokenizers).toBe(fakeTok);
  });

  it('el cargador del modelo, con digests correctos y sin dependencias, falla con RerankError', async () => {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'savia-m2-deps-'));
    try {
      fs.writeFileSync(path.join(dir, 'model.onnx'), 'modelo');
      fs.writeFileSync(path.join(dir, 'tokenizer.json'), '{}');
      const h = (s: string) => crypto.createHash('sha256').update(s).digest('hex');
      const cfg = { modelDir: dir, topN: 20, maxMs: 1000, modelSha256: h('modelo'), tokenizerSha256: h('{}') };
      const err = await loadOnnxCrossEncoder(cfg, only({})).catch(e => e);
      expect(err).toBeInstanceOf(RerankError);
      expect(err.message).toBe('dependencia opcional del reranker no instalada');
    } finally {
      fs.rmSync(dir, { recursive: true, force: true });
    }
  });
});

// Con los paquetes reales instalados (la CI los instala), su API cumple la forma declarada.
const installed = (() => {
  const req = createRequire(import.meta.url);
  try { req.resolve(ORT_MODULE); req.resolve(TOKENIZERS_MODULE); return true; } catch { return false; }
})();
describe.skipIf(!installed)('SE-489 M2 dependencias reales', () => {
  it('onnxruntime-node y @huggingface/tokenizers cumplen la forma declarada', async () => {
    const deps = await loadRerankDeps();
    expect(typeof deps.ort.InferenceSession.create).toBe('function');
    expect(typeof deps.tokenizers.Tokenizer).toBe('function');
  });
});
