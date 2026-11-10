// SE-514 S1: vista de cola única, de solo lectura, sobre las fuentes que ya existen.
// Cada petición dice qué se pide, por qué, qué pasa si no contestas, qué cuesta aplazarla y
// hasta cuándo vale. Lo que la fuente no dice se marca como tal; nunca se inventa.
import assert from 'node:assert/strict';
import { test } from 'node:test';

import {
  CAMPOS, FUENTES, Politica, construirCola, dePrsEnRevision, deBandejaSoul, deRelevoNocturno,
  deAgente, textoCola, type Fuente, type Fuentes,
} from '../../src/attention/index.ts';
import { opA, t } from './comun.ts';

const AHORA = t(0, 10, 5);

/** Una petición completa por fuente, con el contrato normalizado. */
function completa(id: string, extra: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    id,
    que: `Qué se pide en ${id}`,
    porQue: `Por qué ahora en ${id}`,
    siNoContestas: 'Queda en espera; no se decide nada por ti.',
    siAplazas: 'Pierde unos 20 minutos.',
    caduca: t(0, 12, 0),
    desde: t(0, 9, 25),
    nivel: 1,
    ...extra,
  };
}

function todasLasFuentes(): Fuentes {
  const f: Fuentes = {};
  for (const fuente of FUENTES) f[fuente] = [completa(`p-${fuente}`)];
  return f;
}

function congelar<T>(x: T): T {
  if (x !== null && typeof x === 'object') {
    for (const v of Object.values(x)) congelar(v);
    Object.freeze(x);
  }
  return x;
}

test('AC-2: hay siete fuentes, las de la tabla de la spec', () => {
  assert.deepEqual([...FUENTES].sort(), [
    'AVISO_RUN', 'AVISO_SOUL', 'ESPERAN_ALGO', 'PENDIENTE_MANANA', 'PR_REVISION', 'RELEVO_NOCTURNO',
    'TARJETA_APROBACION',
  ]);
  assert.deepEqual([...CAMPOS], ['que', 'porQue', 'siNoContestas', 'siAplazas', 'caduca']);
});

test('AC-2: la cola muestra una petición de cada fuente con las cinco cosas', () => {
  const cola = construirCola(todasLasFuentes(), AHORA, 2);
  assert.equal(cola.peticiones.length, FUENTES.length);
  assert.deepEqual(new Set(cola.peticiones.map((p) => p.fuente)), new Set(FUENTES));
  for (const p of cola.peticiones) {
    assert.deepEqual(p.faltan, [], `${p.fuente} trae todo`);
    assert.ok(p.que && p.porQue && p.siNoContestas && p.siAplazas, p.fuente);
    assert.equal(p.caduca, t(0, 12, 0));
  }
  assert.ok(cola.cobertura.every((c) => c.estado === 'CONECTADA'));
  const txt = textoCola(cola);
  assert.match(txt, /Esperan algo de ti \(7\)/);
  for (const r of ['Por qué ahora:', 'Si no contestas:', 'Si lo aplazas:', 'Vale hasta: hoy 12:00']) {
    assert.equal(txt.split(r).length - 1, 7, `«${r}» en cada tarjeta`);
  }
  assert.doesNotMatch(txt, /La fuente no lo dice/);
});

test('negativo: lo que la fuente no dice se marca y no se inventa', () => {
  const cola = construirCola({ ESPERAN_ALGO: [{ id: 'x', que: 'Confirmar un nombre', porQue: '   ', caduca: 'mañana', nivel: 1 }] }, AHORA, 2);
  const [p] = cola.peticiones;
  assert.deepEqual(p.faltan, ['porQue', 'siNoContestas', 'siAplazas', 'caduca']);
  assert.equal(p.porQue, null);
  assert.equal(p.caduca, null);
  const txt = textoCola(cola);
  assert.equal(txt.split('La fuente no lo dice').length - 1, 4);
});

test('negativo: una fuente sin conectar se dice; no se confunde con «nada pendiente»', () => {
  const cola = construirCola({ AVISO_SOUL: [] }, AHORA, 2);
  const estado = Object.fromEntries(cola.cobertura.map((c) => [c.fuente, c.estado]));
  assert.equal(estado.AVISO_SOUL, 'CONECTADA');
  assert.equal(estado.PR_REVISION, 'SIN_CONECTAR');
  assert.equal(cola.cobertura.filter((c) => c.estado === 'SIN_CONECTAR').length, 6);
  const txt = textoCola(cola);
  assert.match(txt, /Nada pendiente en las fuentes conectadas/);
  assert.match(txt, /Sin datos de: PRs esperando revisión, Tarjeta de aprobación/);
});

test('negativo: una fuente que falla se enseña como fallida, con su motivo', () => {
  const cola = construirCola({ RELEVO_NOCTURNO: { error: 'versión 2 desconocida' } }, AHORA, 2);
  const c = cola.cobertura.find((x) => x.fuente === 'RELEVO_NOCTURNO');
  assert.equal(c?.estado, 'FALLIDA');
  assert.match(textoCola(cola), /No se pudo leer Relevo nocturno: versión 2 desconocida/);
});

test('negativo: entradas ilegibles y fuentes desconocidas se cuentan, no desaparecen', () => {
  const entrada = {
    AVISO_RUN: [null, 'texto', { que: 'sin id' }, { id: '' }, completa('bien')],
    BUZON_NUEVO: [completa('raro')],
  } as unknown as Fuentes;
  const cola = construirCola(entrada, AHORA, 2);
  assert.deepEqual(cola.peticiones.map((p) => p.id), ['bien']);
  assert.equal(cola.descartadas.length, 5);
  assert.deepEqual(cola.descartadas.map((d) => d.motivo), [
    'no es un objeto', 'no es un objeto', 'sin id', 'sin id', 'fuente desconocida',
  ]);
  assert.match(textoCola(cola), /5 entradas no se pudieron leer/);
});

test('negativo: una fuente que no entrega una lista es fallida, no vacía', () => {
  const cola = construirCola({ PENDIENTE_MANANA: 'hoy nada' } as unknown as Fuentes, AHORA, 2);
  assert.equal(cola.cobertura.find((x) => x.fuente === 'PENDIENTE_MANANA')?.estado, 'FALLIDA');
});

test('mismo id en la misma fuente se cuenta una vez; en fuentes distintas no se une', () => {
  const cola = construirCola({
    AVISO_SOUL: [completa('d1'), completa('d1', { que: 'otra versión' })],
    TARJETA_APROBACION: [completa('d1')],
  }, AHORA, 2);
  assert.equal(cola.duplicadas, 1);
  assert.equal(cola.peticiones.length, 2);
  assert.deepEqual(cola.peticiones.map((p) => p.fuente).sort(), ['AVISO_SOUL', 'TARJETA_APROBACION']);
  assert.equal(cola.peticiones.find((p) => p.fuente === 'AVISO_SOUL')?.que, 'Qué se pide en d1');
});

test('negativo: contenido por encima del nivel del canal no se enseña; nivel raro es N4', () => {
  const cola = construirCola({
    ESPERAN_ALGO: [completa('n2', { nivel: 2 }), completa('n3', { nivel: 3 }), completa('raro', { nivel: 'N1' })],
  }, AHORA, 2);
  const por = Object.fromEntries(cola.peticiones.map((p) => [p.id, p]));
  assert.equal(por.n2.redactada, false);
  assert.equal(por.n2.que, 'Qué se pide en n2');
  for (const id of ['n3', 'raro']) {
    assert.equal(por[id].redactada, true, id);
    assert.equal(por[id].que, null);
    assert.equal(por[id].porQue, null);
    assert.equal(por[id].siNoContestas, null);
    assert.equal(por[id].siAplazas, null);
  }
  assert.equal(por.raro.nivel, 4);
  const txt = textoCola(cola);
  assert.doesNotMatch(txt, /Qué se pide en n3|Qué se pide en raro/);
  assert.match(txt, /Contenido de nivel N3: no se enseña en este canal/);
});

test('límite: sin nivel declarado, la petición también es N4', () => {
  const sin = completa('s');
  delete sin.nivel;
  const cola = construirCola({ ESPERAN_ALGO: [sin] }, AHORA, 4);
  assert.equal(cola.peticiones[0].nivel, 4);
  assert.equal(cola.peticiones[0].redactada, false, 'canal N4 sí la enseña');
  assert.equal(construirCola({ ESPERAN_ALGO: [sin] }, AHORA, 3).peticiones[0].redactada, true);
});

test('orden: lo crítico primero, luego lo que caduca antes; lo caducado al final y marcado', () => {
  const cola = construirCola({
    ESPERAN_ALGO: [
      completa('tarde', { caduca: t(0, 18, 0), nivel: 1 }),
      completa('pronto', { caduca: t(0, 11, 0), nivel: 1 }),
      completa('vencida', { caduca: t(0, 10, 5), nivel: 1 }),
      completa('sin-plazo', { caduca: null, nivel: 1 }),
    ],
    AVISO_SOUL: [completa('critica', { critica: true, caduca: t(1, 9, 0), nivel: 1 })],
    AVISO_RUN: [completa('texto-critico', { critica: 'true', caduca: t(0, 17, 0), nivel: 1 })],
  }, AHORA, 2);
  assert.deepEqual(cola.peticiones.map((p) => p.id), ['critica', 'pronto', 'texto-critico', 'tarde', 'sin-plazo', 'vencida']);
  assert.equal(cola.peticiones.at(-1)?.caducada, true, 'caduca == ahora ya no vale');
  assert.equal(cola.peticiones.find((p) => p.id === 'texto-critico')?.critica, false, 'solo `true` es crítico');
  const txt = textoCola(cola);
  assert.match(txt, /Caducadas \(1\)/);
  assert.match(txt, /Esperan algo de ti \(5\)/);
  assert.match(txt, /Vale hasta: mañana 09:00/);
});

test('solo lectura: no cambia la entrada y no hay forma de contestar desde la vista', async () => {
  const entrada = congelar(todasLasFuentes());
  const antes = JSON.stringify(entrada);
  const cola = construirCola(entrada, AHORA, 2);
  assert.equal(JSON.stringify(entrada), antes);
  assert.ok(Object.isFrozen(cola) && Object.isFrozen(cola.peticiones) && Object.isFrozen(cola.peticiones[0]));
  const mod = await import('../../src/attention/cola.ts');
  assert.deepEqual(Object.keys(mod).filter((k) => /respond|contest|aprob|resolver/i.test(k)), []);
});

// Adaptadores de las fuentes que ya tienen código en este repo.

test('Soul (SE-490): las decisiones pendientes de la bandeja entran con sus cinco cosas', () => {
  const pol = new Politica(opA());
  const ev = (id: string, coste: 'BAJO' | 'ALTO') => ({
    ...deAgente(id, { k: 'DECISION' as const, decisionId: `d-${id}` }),
    costeRetraso: coste, plazo: t(0, 12, 0), texto: `¿Sigo con ${id}?`,
  });
  pol.decidir(ev('baja', 'BAJO'), AHORA); // puede esperar: se difiere
  pol.decidir({ ...deAgente('aviso', { k: 'AVISO', rutinario: false }), texto: 'informa' }, AHORA);
  pol.decidir({ ...deAgente('secreto', { k: 'APROBACION_SEGURIDAD', decisionId: 'd-s' }), nivel: 4, texto: 'N4' }, AHORA);
  const items = deBandejaSoul(pol.bandeja.items(), 2);
  assert.ok(Array.isArray(items));
  const cola = construirCola({ AVISO_SOUL: items }, AHORA, 2);
  assert.deepEqual(cola.peticiones.map((p) => p.id).sort(), ['d-baja', 'd-s'], 'el aviso informativo no pide respuesta');
  const baja = cola.peticiones.find((p) => p.id === 'd-baja')!;
  assert.deepEqual(baja.faltan, []);
  assert.equal(baja.que, '¿Sigo con baja?');
  assert.match(baja.porQue!, /puede esperar/i);
  assert.match(baja.siNoContestas!, /no se decide nada por ti/);
  assert.match(baja.siAplazas!, /cuesta poco/);
  assert.equal(baja.caduca, t(0, 12, 0));
  const seg = cola.peticiones.find((p) => p.id === 'd-s')!;
  assert.equal(seg.critica, true, 'una aprobación de seguridad va sola y primero');
  assert.equal(seg.redactada, true, 'la bandeja ya la redactó: no sale el texto');
  assert.equal(cola.peticiones[0].id, 'd-s');
});

test('Soul: una decisión ya contestada no aparece', () => {
  const pol = new Politica(opA());
  pol.decidir({ ...deAgente('x', { k: 'DECISION', decisionId: 'd-x' }), costeRetraso: 'BAJO' }, AHORA);
  pol.control({ k: 'RESPONDER', decisionId: 'd-x' }, 'PERSONA', AHORA);
  assert.deepEqual(deBandejaSoul(pol.bandeja.items(), 2), []);
});

const aMinuto = (iso: string): number | null => {
  const ms = Date.parse(iso);
  return Number.isNaN(ms) ? null : Math.floor(ms / 60_000);
};

test('relevo nocturno (SE-471): cada decisión del digest entra; el digest raro falla visible', () => {
  const digest = {
    version: 1,
    ventana: { desde: '2026-11-02T22:00:00Z', hasta: '2026-11-03T06:00:00Z' },
    decisiones: [
      { categoria: 'fallo', etiqueta: 'FALLO', run: 'informe', siguiente: 'reintentar', pr_url: null },
      { categoria: 'parcial', etiqueta: 'PARCIAL', run: 'migracion', siguiente: null, pr_url: null },
      { categoria: 'nueva', etiqueta: '?', run: 'otro', siguiente: null, pr_url: null },
    ],
  };
  const entradas = deRelevoNocturno(digest, aMinuto, 2);
  const cola = construirCola({ RELEVO_NOCTURNO: entradas }, AHORA, 2);
  assert.equal(cola.peticiones.length, 3);
  const fallo = cola.peticiones.find((p) => p.id === 'informe')!;
  assert.match(fallo.que!, /informe/);
  assert.match(fallo.porQue!, /fallo/);
  assert.match(fallo.siNoContestas!, /queda como está/);
  assert.deepEqual(fallo.faltan, ['siAplazas', 'caduca'], 'el digest no lo dice');
  assert.equal(fallo.desde, aMinuto('2026-11-03T06:00:00Z'));
  assert.ok(cola.peticiones.find((p) => p.id === 'otro')!.faltan.includes('porQue'), 'categoría nueva: no se inventa');

  for (const malo of [null, { version: 2, decisiones: [] }, { version: 1 }]) {
    const r = deRelevoNocturno(malo, aMinuto, 2);
    assert.ok(!Array.isArray(r) && typeof r.error === 'string', JSON.stringify(malo));
    assert.equal(construirCola({ RELEVO_NOCTURNO: r }, AHORA, 2).cobertura.find((c) => c.fuente === 'RELEVO_NOCTURNO')?.estado, 'FALLIDA');
  }
});

test('PRs (SE-458): las abiertas sin aprobar entran; las aprobadas no; sin número se descarta', () => {
  const prs = [
    { number: 12, title: 'feat: algo', isDraft: true, createdAt: '2026-11-03T08:00:00Z', reviewDecision: '' },
    { number: 13, title: 'fix: otra', isDraft: false, createdAt: '2026-11-03T07:00:00Z', reviewDecision: 'CHANGES_REQUESTED' },
    { number: 14, title: 'ya vale', isDraft: false, createdAt: '2026-11-03T07:00:00Z', reviewDecision: 'APPROVED' },
    { title: 'sin número' },
  ];
  const r = dePrsEnRevision(prs, aMinuto, 1);
  assert.ok(Array.isArray(r));
  const cola = construirCola({ PR_REVISION: r }, AHORA, 2);
  assert.deepEqual(cola.peticiones.map((p) => p.id), ['13', '12'], 'la más antigua primero');
  assert.equal(cola.descartadas.length, 1);
  const p13 = cola.peticiones[0];
  assert.match(p13.que!, /#13/);
  assert.match(p13.porQue!, /cambios/);
  assert.match(p13.siNoContestas!, /nada se fusiona sin tu revisión/);
  assert.deepEqual(p13.faltan, ['siAplazas', 'caduca']);
  assert.ok(!Array.isArray(dePrsEnRevision({ no: 'lista' }, aMinuto, 1)));
});

test('la cobertura sigue el orden de la tabla de la spec', () => {
  const cola = construirCola({}, AHORA, 2);
  assert.deepEqual(cola.cobertura.map((c) => c.fuente), FUENTES as readonly Fuente[]);
  assert.match(textoCola(cola), /Ninguna fuente conectada/);
});
