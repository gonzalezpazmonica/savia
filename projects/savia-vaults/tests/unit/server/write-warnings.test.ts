// Avisos al escribir (vault_write): nunca bloquean, respetan nivel de confidencialidad y son fail-open.
import { describe, expect, it } from 'vitest';
import { computeWriteWarnings, writeWarningsResult, type NoteSource } from '../../../src/server/write-warnings.js';

type N = { content: string; fm?: Record<string, unknown> };
function source(notes: Record<string, N>, over: Partial<NoteSource> = {}): NoteSource {
  return {
    list: async () => Object.keys(notes),
    read: async (p: string) => {
      const n = notes[p];
      if (!n) throw new Error('Note not found');
      return { path: p, name: p.replace(/\.md$/, '').split('/').pop()!, frontmatter: n.fm ?? {}, content: n.content };
    },
    ...over,
  };
}
const codes = (w: Array<{ code: string }>) => w.map(x => x.code);

describe('avisos de vault_write', () => {
  it('título duplicado: normalizado sin acentos ni mayúsculas', async () => {
    const s = source({
      'a.md': { content: '# Decisión de Arquitectura\nx [[b]]' },
      'b.md': { content: '# Otra cosa\n[[a]]', fm: { title: 'DECISION de arquitectura ' } },
    });
    const w = await computeWriteWarnings(s, 'a.md', 'N2');
    expect(codes(w)).toContain('DUPLICATE_TITLE');
    expect(w.find(x => x.code === 'DUPLICATE_TITLE')!.target).toBe('b.md');
  });
  it('sin título duplicado: no avisa', async () => {
    const s = source({ 'a.md': { content: '# Uno\n[[b]]' }, 'b.md': { content: '# Dos\n[[a]]' } });
    expect(codes(await computeWriteWarnings(s, 'a.md', 'N2'))).not.toContain('DUPLICATE_TITLE');
  });
  it('wikilink roto: avisa con el destino; enlace válido no avisa', async () => {
    const s = source({ 'a.md': { content: '# A\n[[b]] [[no-existe]]' }, 'b.md': { content: '# B' } });
    const w = await computeWriteWarnings(s, 'a.md', 'N2');
    const broken = w.filter(x => x.code === 'BROKEN_WIKILINK');
    expect(broken.map(x => x.target)).toEqual(['no-existe']);
  });
  it('nota huérfana: sin enlaces entrantes ni salientes; con un enlace saliente no', async () => {
    const s = source({ 'a.md': { content: '# A\nsolo texto' }, 'b.md': { content: '# B' } });
    expect(codes(await computeWriteWarnings(s, 'a.md', 'N2'))).toContain('ORPHAN_NOTE');
    const s2 = source({ 'a.md': { content: '# A\n[[b]]' }, 'b.md': { content: '# B' } });
    expect(codes(await computeWriteWarnings(s2, 'a.md', 'N2'))).not.toContain('ORPHAN_NOTE');
    const s3 = source({ 'a.md': { content: '# A' }, 'b.md': { content: '# B\n[[a]]' } });
    expect(codes(await computeWriteWarnings(s3, 'a.md', 'N2'))).not.toContain('ORPHAN_NOTE');
  });
  it('conflicto abierto que afecta a la nota; sin conflicto no avisa', async () => {
    const s = source({
      'a.md': { content: '# A\n[[b]]', fm: { entity: { id: 'e1' }, owner: 'Ana' } },
      'b.md': { content: '# B\n[[a]]', fm: { entity: { id: 'e1' }, owner: 'Luis' } },
    });
    const w = await computeWriteWarnings(s, 'a.md', 'N2');
    expect(codes(w)).toContain('OPEN_CONFLICT');
    const s2 = source({
      'a.md': { content: '# A\n[[b]]', fm: { entity: { id: 'e1' }, owner: 'Ana' } },
      'b.md': { content: '# B\n[[a]]', fm: { entity: { id: 'e1' }, owner: 'Ana' } },
    });
    expect(codes(await computeWriteWarnings(s2, 'a.md', 'N2'))).not.toContain('OPEN_CONFLICT');
  });
  it('vecinas: enlazadas o de la misma comunidad, máximo 5; sin vecinas no avisa', async () => {
    const notes: Record<string, N> = { 'a.md': { content: '# A\n' + Array.from({ length: 8 }, (_, i) => `[[v${i}]]`).join(' ') } };
    for (let i = 0; i < 8; i++) notes[`v${i}.md`] = { content: `# Vecina ${i}` };
    const w = await computeWriteWarnings(source(notes), 'a.md', 'N2');
    expect(w.filter(x => x.code === 'NEIGHBOR_NOTE')).toHaveLength(5);
    const solo = await computeWriteWarnings(source({ 'a.md': { content: '# A' } }), 'a.md', 'N2');
    expect(codes(solo)).not.toContain('NEIGHBOR_NOTE');
  });
  it('cada aviso tiene code y message en español no vacío', async () => {
    const s = source({ 'a.md': { content: '# A\n[[x]]' }, 'b.md': { content: '# A' } });
    for (const w of await computeWriteWarnings(s, 'a.md', 'N2')) {
      expect(w.code).toMatch(/^[A-Z_]+$/);
      expect(w.message.length).toBeGreaterThan(10);
    }
  });

  describe('confidencialidad', () => {
    const SECRET = 'Proyecto Garceta Reservado';
    it('un duplicado de nivel superior NO revela su título ni su ruta', async () => {
      // Una fuente que filtra (devuelve también la nota N4) no debe traducirse en un aviso.
      const s = source({
        'a.md': { content: `# ${SECRET}\n[[b]]` },
        'b.md': { content: '# B\n[[a]]' },
        'secreta.md': { content: `# ${SECRET}\n[[a]]`, fm: { confidentiality: 'N4', title: SECRET } },
      });
      const w = await computeWriteWarnings(s, 'a.md', 'N2');
      expect(codes(w)).not.toContain('DUPLICATE_TITLE');
      expect(JSON.stringify(w)).not.toContain('secreta');
      expect(JSON.stringify(w)).not.toContain('Garceta');
    });
    it('un conflicto o vecina de nivel superior tampoco se revela; un nivel no válido cuenta como superior', async () => {
      const s = source({
        'a.md': { content: '# A\n[[secreta]] [[rara]]', fm: { entity: { id: 'e1' }, owner: 'Ana' } },
        'secreta.md': { content: '# Secreta Oculta', fm: { confidentiality: 'N3', entity: { id: 'e1' }, owner: 'Luis' } },
        'rara.md': { content: '# Rara Oculta', fm: { confidentiality: 'zzz' } },
      });
      const w = await computeWriteWarnings(s, 'a.md', 'N2');
      expect(JSON.stringify(w)).not.toMatch(/Oculta|Luis/); // ni títulos ni valores de la nota oculta
      expect(codes(w)).not.toContain('OPEN_CONFLICT');
      expect(codes(w)).not.toContain('NEIGHBOR_NOTE');
    });
    it('una nota del mismo nivel o inferior sí se muestra', async () => {
      const s = source({
        'a.md': { content: '# A\n[[b]]' },
        'b.md': { content: '# Visible', fm: { confidentiality: 'N2' } },
      });
      const w = await computeWriteWarnings(s, 'a.md', 'N2');
      expect(w.find(x => x.code === 'NEIGHBOR_NOTE')?.target).toBe('b.md');
    });
  });

  describe('fail-open', () => {
    it('si el cálculo falla devuelve warnings_unavailable y no lanza', async () => {
      const s = source({}, { list: async () => { throw new Error('boom'); } });
      expect(await writeWarningsResult(s, 'a.md', 'N2')).toEqual({ warnings_unavailable: true });
    });
    it('si tarda más del tiempo máximo devuelve warnings_unavailable', async () => {
      const s = source({ 'a.md': { content: '# A' } }, { list: () => new Promise(() => {}) });
      const t0 = Date.now();
      expect(await writeWarningsResult(s, 'a.md', 'N2', { timeoutMs: 50 })).toEqual({ warnings_unavailable: true });
      expect(Date.now() - t0).toBeLessThan(1000);
    });
    it('caso normal: devuelve warnings y no warnings_unavailable', async () => {
      const r = await writeWarningsResult(source({ 'a.md': { content: '# A' } }), 'a.md', 'N2');
      expect(r).toHaveProperty('warnings');
      expect(r).not.toHaveProperty('warnings_unavailable');
    });
  });
});
