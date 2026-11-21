// Avisos al escribir (vault_write): nunca bloquean, respetan nivel de confidencialidad y son fail-open.
import { describe, expect, it } from 'vitest';
import { computeWriteWarnings, writeWarningsResult, MAX_NOTES, type NoteSource } from '../../../src/server/write-warnings.js';

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
  it('vecina entrante (backlink): va antes que las de la comunidad aunque estas pesen más', async () => {
    // b enlaza a la escrita y a un grupo denso h0..h5; sin prioridad de backlinks, b quedaría fuera del tope de 5.
    const hubs = Array.from({ length: 6 }, (_, i) => `h${i}`);
    const notes: Record<string, N> = { 'a.md': { content: '# A' }, 'b.md': { content: '# Enlazadora\n[[a]] ' + hubs.map(h => `[[${h}]]`).join(' ') } };
    for (const h of hubs) notes[`${h}.md`] = { content: `# ${h}\n` + hubs.filter(x => x !== h).map(x => `[[${x}]]`).join(' ') };
    const n = (await computeWriteWarnings(source(notes), 'a.md', 'N2')).filter(x => x.code === 'NEIGHBOR_NOTE').map(x => x.target);
    expect(n[0]).toBe('b.md');
    expect(n).toHaveLength(5);
  });
  it('vecina de la misma comunidad sin enlace directo con la escrita', async () => {
    // a-b-c-d forman un grupo denso; e-f otro aparte. d no enlaza con a ni a con d.
    const s = source({
      'a.md': { content: '# A\n[[b]] [[c]]' },
      'b.md': { content: '# B\n[[a]] [[c]] [[d]]' },
      'c.md': { content: '# C\n[[a]] [[b]] [[d]]' },
      'd.md': { content: '# D\n[[b]] [[c]]' },
      'e.md': { content: '# E\n[[f]]' },
      'f.md': { content: '# F\n[[e]]' },
    });
    const n = (await computeWriteWarnings(s, 'a.md', 'N2')).filter(x => x.code === 'NEIGHBOR_NOTE').map(x => x.target);
    expect(n).toContain('d.md');
    expect(n).not.toContain('e.md');
    expect(n).not.toContain('f.md');
  });
  it('conflicto en el que la nota escrita es la segunda fuente (sourceB) también avisa', async () => {
    const s = source({
      'a.md': { content: '# A\n[[z]]', fm: { entity: { id: 'e1' }, owner: 'Ana' } },
      'z.md': { content: '# Z\n[[a]]', fm: { entity: { id: 'e1' }, owner: 'Luis' } },
    });
    for (const p of ['a.md', 'z.md']) {
      const c = (await computeWriteWarnings(s, p, 'N2')).find(x => x.code === 'OPEN_CONFLICT');
      expect(c?.target).toBe(p === 'a.md' ? 'z.md' : 'a.md');
    }
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
    const many = (n: number): Record<string, N> => {
      const o: Record<string, N> = {};
      for (let i = 0; i < n; i++) o[`n${String(i).padStart(4, '0')}.md`] = { content: `# Nota ${i}` };
      return o;
    };
    it(`más de MAX_NOTES (${MAX_NOTES}) notas: warnings_unavailable, nunca un [] engañoso`, async () => {
      const notes = many(MAX_NOTES + 1);
      notes['zzz.md'] = { content: '# Z\n[[no-existe]]' }; // queda la última en orden
      expect(await writeWarningsResult(source(notes), 'zzz.md', 'N2')).toEqual({ warnings_unavailable: true });
      expect(await writeWarningsResult(source(notes), 'n0000.md', 'N2')).toEqual({ warnings_unavailable: true });
    });
    it(`justo MAX_NOTES notas: sí calcula (límite)`, async () => {
      const notes = many(MAX_NOTES - 1);
      notes['zzz.md'] = { content: '# Z\n[[no-existe]]' };
      const r = await writeWarningsResult(source(notes), 'zzz.md', 'N2');
      expect(r).toHaveProperty('warnings');
      expect(codes((r as { warnings: Array<{ code: string }> }).warnings)).toContain('BROKEN_WIKILINK');
    });
    it('la nota escrita no aparece entre las legibles: warnings_unavailable', async () => {
      const s = source({ 'b.md': { content: '# B' } });
      expect(await writeWarningsResult(s, 'a.md', 'N2')).toEqual({ warnings_unavailable: true });
    });
    it('lecturas síncronas lentas (como el almacén real): el plazo corta el cálculo y deja de leer', async () => {
      const notes = many(200);
      let reads = 0;
      const busy = (ms: number) => { const t = Date.now() + ms; while (Date.now() < t) { /* lectura síncrona */ } };
      const base = source(notes);
      const s: NoteSource = { list: base.list, read: async (p) => { reads++; busy(3); return base.read(p); } };
      const t0 = Date.now();
      expect(await writeWarningsResult(s, 'n0000.md', 'N2', { timeoutMs: 60 })).toEqual({ warnings_unavailable: true });
      expect(Date.now() - t0).toBeLessThan(400);
      await new Promise(r => setTimeout(r, 50));
      expect(reads).toBeLessThan(200); // el cálculo se detuvo, no siguió en segundo plano
    });
    it('caso normal: devuelve warnings y no warnings_unavailable', async () => {
      const r = await writeWarningsResult(source({ 'a.md': { content: '# A' } }), 'a.md', 'N2');
      expect(r).toHaveProperty('warnings');
      expect(r).not.toHaveProperty('warnings_unavailable');
    });
  });
});
