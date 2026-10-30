// SE-481 R1/AC-2/AC-10 — parser canónico de clasificación con cierre seguro.
import { describe, it, expect } from 'vitest';
import * as fs from 'node:fs';
import * as os from 'node:os';
import * as path from 'node:path';
import {
  parseClassification, exceedsDomeLevel, verdictOf, contentOutOfLevel,
  fileClassification, classificationCacheSize, setClassificationCacheMax, type ParsedClassification,
} from '../../../src/storage/note-level.js';

const fm = (body: string) => `---\n${body}\n---\n# Nota\n\ncuerpo\n`;
const kindOf = (raw: string) => parseClassification('n.md', raw);

describe('SE-481 R1 parseClassification', () => {
  it.each([
    ['sin frontmatter', '# Nota\n\ntexto\n', 'ABSENT', undefined],
    ['frontmatter sin la clave', fm('title: x'), 'ABSENT', undefined],
    ['YAML roto sin la clave (heredado)', fm('title: a: b: c'), 'ABSENT', undefined],
    ['YAML roto que menciona la clave', fm('confidentiality: [N4'), 'UNPARSABLE', 'yaml-unparsable'],
    ['YAML roto con la clave en mayúsculas', fm('CONFIDENTIALITY: {N4'), 'UNPARSABLE', 'yaml-unparsable'],
    ['lista', fm('confidentiality: [N2]'), 'INVALID', 'non-string'],
    ['objeto', fm('confidentiality: {level: N2}'), 'INVALID', 'non-string'],
    ['número', fm('confidentiality: 4'), 'INVALID', 'non-string'],
    ['booleano', fm('confidentiality: true'), 'INVALID', 'non-string'],
    ['vacío', fm('confidentiality:'), 'INVALID', 'empty-value'],
    ['nivel desconocido N7', fm('confidentiality: N7'), 'UNKNOWN_LEVEL', 'unknown-level'],
    ['palabra', fm('confidentiality: secreto'), 'UNKNOWN_LEVEL', 'unknown-level'],
    ['anchura cero', fm('confidentiality: N\u200B2'), 'INVALID', 'forbidden-char'],
    ['bidi', fm('confidentiality: \u202EN2'), 'INVALID', 'forbidden-char'],
    ['control', fm('confidentiality: "N2\u0007"'), 'INVALID', 'forbidden-char'],
    ['clave duplicada por mayúsculas', fm('confidentiality: N2\nConfidentiality: N4'), 'INVALID', 'duplicate-key'],
    ['clave con anchura cero', fm('confi\u200Bdentiality: N4'), 'INVALID', 'forbidden-char'],
    ['frontmatter que no es un mapa', fm('- confidentiality: N4'), 'UNPARSABLE', 'yaml-not-map'],
    ['frontmatter sin cerrar con la clave', '---\nconfidentiality: [N4\n# Nota\n', 'UNPARSABLE', 'yaml-unparsable'],
  ])('%s → %s', (_n, raw, kind, diagnostic) => {
    const c = kindOf(raw);
    expect(c.kind).toBe(kind);
    expect(c.diagnostic).toBe(diagnostic);
    expect(c.level).toBeUndefined();
  });

  it.each([
    ['N1', 'N1'], ['n2', 'N2'], [' N3 ', 'N3'], ['N4', 'N4'], ['N4B', 'N4B'], ['N4b', 'N4B'], ['"n4b"', 'N4B'],
  ])('nivel canónico %s → %s', (v, level) => {
    expect(kindOf(fm(`confidentiality: ${v}`))).toEqual({ kind: 'VALID', level });
  });

  it('anchura completa (NFKC) no esconde la clave', () => {
    expect(kindOf(fm('\uFF43\uFF4F\uFF4E\uFF46\uFF49\uFF44\uFF45\uFF4E\uFF54\uFF49\uFF41\uFF4C\uFF49\uFF54\uFF59: N4')).kind).toBe('INVALID');
    expect(kindOf(fm('\uFF43\uFF4F\uFF4E\uFF46\uFF49\uFF44\uFF45\uFF4E\uFF54\uFF49\uFF41\uFF4C\uFF49\uFF54\uFF59: [N4')).kind).toBe('UNPARSABLE');
  });

  it('frontmatter enorme: no se parsea; con la clave, cierra; sin ella, heredado', () => {
    const filler = Array.from({ length: 8_000 }, (_, i) => `k${i}: y`).join('\n') + '\n'; // > 64 KiB, YAML válido
    expect(kindOf(`---\n${filler}confidentiality: N2\n# sin cierre\n`)).toEqual({ kind: 'UNPARSABLE', diagnostic: 'yaml-unparsable' });
    expect(kindOf(`---\n${filler}---\n# cerrado pero enorme, sin clave\n`)).toEqual({ kind: 'ABSENT' });
    expect(kindOf(fm('confidentiality: N2'))).toEqual({ kind: 'VALID', level: 'N2' }); // caso negativo: lo normal se parsea
  });

  it('BOM y CRLF no esconden la clave', () => {
    expect(kindOf('\uFEFF' + fm('confidentiality: [N4')).kind).toBe('UNPARSABLE');
    expect(kindOf('---\r\nconfidentiality: N7\r\n---\r\nx\r\n').kind).toBe('UNKNOWN_LEVEL');
    expect(kindOf('---\r\nconfidentiality: N3\r\n---\r\nx\r\n')).toEqual({ kind: 'VALID', level: 'N3' });
  });

  it('el diagnóstico no contiene texto de la nota', () => {
    const c = kindOf(fm('confidentiality: CANARIO-7781'));
    expect(JSON.stringify(c)).not.toContain('CANARIO');
  });

  it('R2: cuarentena en cualquier cúpula y con cualquier nivel (también sin nivel)', () => {
    const broken = fm('confidentiality: [N4');
    for (const level of ['N1', 'N2', 'N3', 'N4', 'N4B', undefined]) {
      expect(contentOutOfLevel('n.md', broken, level)).toBe(true);
      expect(contentOutOfLevel('n.md', fm('title: x'), level)).toBe(false);
    }
    expect(verdictOf({ kind: 'VALID', level: 'N4' }, 'N2')).toBe('out-of-level');
    expect(verdictOf({ kind: 'VALID', level: 'N4' }, undefined)).toBe('serve');
    expect(verdictOf({ kind: 'VALID', level: 'N4B' }, 'N4')).toBe('out-of-level');
  });

  it('exceedsDomeLevel: un nivel no canónico cierra (antes «no contaba»)', () => {
    expect(exceedsDomeLevel('N7', 'N4')).toBe(true);
    expect(exceedsDomeLevel('secreto', 'N2')).toBe(true);
    expect(exceedsDomeLevel(undefined, 'N2')).toBe(false);
    expect(exceedsDomeLevel('N2', 'N2')).toBe(false);
    expect(exceedsDomeLevel('n4b', 'N4')).toBe(true);
    expect(exceedsDomeLevel('N4', 'N4B')).toBe(false);
  });
});

describe('SE-481 R3 caché de clasificación', () => {
  it('la clave incluye ctime/tamaño: reescribir con el mismo mtime se detecta', () => {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'savia-cls-'));
    try {
      const f = path.join(dir, 'a.md');
      fs.writeFileSync(f, fm('confidentiality: N2'));
      const t = new Date(Date.now() - 60_000);
      fs.utimesSync(f, t, t);
      expect(fileClassification(f, 'a.md')).toEqual({ kind: 'VALID', level: 'N2' });
      fs.writeFileSync(f, fm('confidentiality: N9'));
      fs.utimesSync(f, t, t); // mismo mtime; cambian ctime y tamaño
      expect(fileClassification(f, 'a.md')?.kind).toBe('UNKNOWN_LEVEL');
      fs.unlinkSync(f);
      expect(fileClassification(f, 'a.md')).toBeUndefined();
    } finally { fs.rmSync(dir, { recursive: true, force: true }); }
  });

  it('la caché está acotada: expulsa la entrada más antigua al llegar al tope', () => {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'savia-cls-bound-'));
    setClassificationCacheMax(3);
    try {
      for (let i = 0; i < 10; i++) {
        const f = path.join(dir, `n${i}.md`);
        fs.writeFileSync(f, fm(i === 0 ? 'confidentiality: N7' : 'title: x'));
        fileClassification(f, `n${i}.md`);
        expect(classificationCacheSize()).toBe(Math.min(i + 1, 3));
      }
      // la primera se expulsó; al volver a pedirla se relee y sigue en cuarentena
      expect(fileClassification(path.join(dir, 'n0.md'), 'n0.md')?.kind).toBe('UNKNOWN_LEVEL');
      expect(classificationCacheSize()).toBe(3);
    } finally {
      setClassificationCacheMax(20_000);
      fs.rmSync(dir, { recursive: true, force: true });
    }
  });
});

// AC-10 — fuzz determinista (semilla fija): una clave `confidentiality` con valor no canónico
// nunca da ABSENT (ni VALID).
function mulberry32(seed: number): () => number {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6D2B79F5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

const INVISIBLE = ['\u200B', '\u200C', '\u200D', '\u2060', '\uFEFF', '\u202E', '\u2066', '\u00AD', '\u0007', '\u061C'];
const UNKNOWN = ['N0', 'N5', 'N7', 'N', 'N44', 'NN2', 'N4c', 'N4BB', 'secreto', 'public', 'interno', 'L2', 'n-2', 'N 2', 'Ｎ２', 'Н2', 'N₂', 'top secret'];
const NON_STRING = ['[N2]', '[N4, N2]', '{level: N2}', '4', '2.5', 'true', 'false', '~', 'null', '- N2', '!!binary aGVsbG8=', '2026-10-30'];
const BROKEN = ['[N4', '{N2', '"N2', "'N3", 'N2: x: y', '[N2, {', '*alias', '|-\n  N2\n x: [', '@N2', '`N2`', '>=1 N2', '"N2\\', '{a: [}'];

function fuzzCases(seed: number, n: number): { raw: string; label: string }[] {
  const r = mulberry32(seed);
  const pick = <T>(xs: T[]): T => xs[Math.floor(r() * xs.length)];
  const cases: { raw: string; label: string }[] = [];
  for (let i = 0; i < n; i++) {
    const family = pick(['unknown', 'non-string', 'broken', 'invisible', 'invisible-key']);
    let value: string;
    let key = pick(['confidentiality', 'Confidentiality', 'CONFIDENTIALITY', 'confidentiality ']);
    switch (family) {
      case 'unknown': value = pick(UNKNOWN); break;
      case 'non-string': value = pick(NON_STRING); break;
      case 'broken': value = pick(BROKEN); break;
      case 'invisible': {
        const lvl = pick(['N1', 'N2', 'N3', 'N4', 'N4B']);
        const at = Math.floor(r() * (lvl.length + 1));
        value = lvl.slice(0, at) + pick(INVISIBLE) + lvl.slice(at);
        break;
      }
      default: {
        value = pick(['N4', 'N3']);
        const at = 1 + Math.floor(r() * (key.trim().length - 1));
        key = key.slice(0, at) + pick(INVISIBLE.slice(0, 5)) + key.slice(at);
      }
    }
    const before = Array.from({ length: Math.floor(r() * 3) }, (_, j) => pick([`title: Nota ${i}`, `tags: [a, b${j}]`, 'status: active', 'title: roto: sí: no', 'x: [']));
    const after = Array.from({ length: Math.floor(r() * 3) }, () => pick(['modified: 2026-01-01', 'owner: alguien', 'note: "texto"', 'y: {']));
    const nl = r() < 0.2 ? '\r\n' : '\n';
    const lines = [...before, `${key}: ${value}`, ...after].join(nl);
    const bom = r() < 0.1 ? '\uFEFF' : '';
    const closed = r() < 0.9;
    const raw = `${bom}---${nl}${lines}${nl}${closed ? `---${nl}` : ''}# Nota ${i}${nl}${nl}texto${nl}`;
    cases.push({ raw, label: `${family}:${JSON.stringify(key)}=${JSON.stringify(value)}` });
  }
  return cases;
}

describe('SE-481 AC-10 fuzz de frontmatter', () => {
  const cases = fuzzCases(0x5E481, 400);

  it('genera ≥200 casos deterministas con todas las familias', () => {
    expect(cases.length).toBeGreaterThanOrEqual(200);
    expect(fuzzCases(0x5E481, 400).map(c => c.raw)).toEqual(cases.map(c => c.raw));
    for (const f of ['unknown', 'non-string', 'broken', 'invisible', 'invisible-key']) {
      expect(cases.some(c => c.label.startsWith(`${f}:`))).toBe(true);
    }
  });

  it('nunca ABSENT ni VALID con clave `confidentiality` y valor no canónico', () => {
    const bad: string[] = [];
    for (const c of cases) {
      let res: ParsedClassification;
      try { res = parseClassification('f.md', c.raw); } catch (e) { bad.push(`${c.label} → throw ${String(e)}`); continue; }
      if (res.kind === 'ABSENT' || res.kind === 'VALID') bad.push(`${c.label} → ${res.kind}`);
      else if (!res.diagnostic) bad.push(`${c.label} → sin diagnóstico`);
    }
    expect(bad).toEqual([]);
  });
});
