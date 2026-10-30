// SE-485 R1 (N1) — los backlinks resuelven [[destino]] a destino.md con la misma resolución
// de enlaces: nombre sin extensión, ruta relativa, entidad y alias.
import { describe, it, expect } from 'vitest';
import { resolveBacklinks, resolveWikiTarget } from '../../../src/knowledge/wikilink-validator.js';

const notes = [
  { path: 'docs/destino.md', content: '# Destino', frontmatter: { entity: { id: 'ent-destino' }, aliases: ['Apodo'] } },
  { path: 'a.md', content: 'por nombre [[destino]]' },
  { path: 'b.md', content: 'por ruta [[docs/destino]] y [[docs/destino.md|texto]]' },
  { path: 'c.md', content: 'por alias [[Apodo]]' },
  { path: 'd.md', content: 'por entidad [[ent-destino#sección]]' },
  { path: 'e.md', content: 'otro destino [[otro]] y [[destino-largo]]' },
  { path: 'otro.md', content: 'enlaza a [[destino]]' },
];
const target = { path: 'docs/destino.md', entityId: 'ent-destino', aliases: ['Apodo'] };

describe('SE-485 R1 backlinks por nombre', () => {
  it('[[nombre]], ruta, alias y entidad resuelven a la nota', () => {
    const b = resolveBacklinks(target, notes);
    expect(b.map(x => x.source).sort()).toEqual(['a.md', 'b.md', 'c.md', 'd.md', 'otro.md']);
  });

  it('negativo: un enlace a otro destino o a un prefijo del nombre no cuenta', () => {
    const b = resolveBacklinks(target, notes);
    expect(b.map(x => x.source)).not.toContain('e.md');
  });

  it('con dos notas del mismo nombre, [[nombre]] resuelve a la de ruta más corta', () => {
    const dup = [{ path: 'x/n.md', content: '' }, { path: 'n.md', content: '' }, { path: 'l.md', content: '[[n]]' }];
    expect(resolveWikiTarget('n', dup)).toBe('n.md');
    expect(resolveBacklinks({ path: 'n.md' }, dup).map(x => x.source)).toEqual(['l.md']);
    expect(resolveBacklinks({ path: 'x/n.md' }, dup)).toEqual([]);
  });

  it('compat: destino como cadena sigue funcionando', () => {
    const b = resolveBacklinks('SE-291', [{ path: 'a.md', content: 'Ver [[SE-291]]' }]);
    expect(b).toHaveLength(1);
  });

  it('el contexto sale del enlace que resolvió, no del primero del texto', () => {
    const b = resolveBacklinks({ path: 'docs/destino.md' }, [{ path: 'z.md', content: `${'x'.repeat(400)} [[otro]] ${'y'.repeat(400)} [[destino]] fin` }]);
    expect(b[0].context).toContain('[[destino]]');
  });
});
