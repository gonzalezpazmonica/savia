// SE-514 S2: preguntas de agentes en la cola única. Identificador, caducidad, DEFER sin
// respuesta, agrupación sin mezclar permisos, respuesta ligada a la versión que se enseñó.
// AC-7 (medición con tres agentes y una persona) no se prueba aquí: necesita sesiones reales.
import assert from 'node:assert/strict';
import { test } from 'node:test';

import {
  Politica, Preguntas, construirCola, deBandejaSoul, dePreguntasAgentes, textoCola,
  type PreguntaAgente,
} from '../../src/attention/index.ts';
import { opA, t } from './comun.ts';

const LUNES_9 = t(0, 9, 30);

function nuevo(): { pol: Politica; pr: Preguntas } {
  const pol = new Politica(opA());
  return { pol, pr: new Preguntas(pol) };
}

function dec(id: string, extra: Partial<PreguntaAgente> = {}): PreguntaAgente {
  return {
    id, agente: `ag-${id}`, trabajo: `trab-${id}`, version: 'v1', clase: 'DECISION',
    que: `Qué se pide en ${id}`, porQue: `Por qué ahora en ${id}`,
    siNoContestas: 'El trabajo espera; no se decide nada por ti.', siAplazas: 'Pierde unos 20 minutos.',
    caduca: t(0, 12, 0), nivel: 1, ...extra,
  };
}

function perm(id: string, extra: Partial<PreguntaAgente> = {}): PreguntaAgente {
  return dec(id, { clase: 'PERMISO', permiso: `publicar-${id}`, obligatoria: true, ...extra });
}

const AG = 'AGENTE_AUTENTICADO' as const;
const PE = 'PERSONA' as const;

// ---------------------------------------------------------------------------------------------
// AC-3 — pregunta sin respuesta al vencer: DEFER, ningún efecto, una repregunta por ventana.

test('AC-3: justo antes de vencer sigue abierta; en el minuto de vencer pasa a DEFER; después, idempotente', () => {
  const { pr } = nuevo();
  assert.equal(pr.preguntar(dec('a'), LUNES_9, AG).ok, true);
  assert.deepEqual(pr.vencer(t(0, 11, 59)), []);
  assert.equal(pr.estadoTrabajo('trab-a', t(0, 11, 59)), 'EN_ESPERA');
  assert.deepEqual(pr.vencer(t(0, 12, 0)), ['a']);
  assert.equal(pr.estadoTrabajo('trab-a', t(0, 12, 0)), 'DEFER');
  assert.deepEqual(pr.vencer(t(0, 12, 1)), []);
  assert.equal(pr.estadoTrabajo('trab-a', t(0, 12, 1)), 'DEFER');
});

test('AC-3 negativo: al vencer no se ejecuta nada ni se decide por la persona', () => {
  const { pol, pr } = nuevo();
  pr.preguntar(perm('a'), LUNES_9, AG);
  pr.preguntar(dec('b'), LUNES_9, AG);
  pr.vencer(t(0, 13, 0));
  for (const id of ['a', 'b']) {
    assert.equal(pr.puedeEjecutar(id), false, id);
    assert.equal(pr.respuestaDe(id), null, id);
    const item = pol.bandeja.porDecision(`agente:${id}`);
    assert.equal(item?.pendiente, true, `${id} sigue pendiente: el silencio no es respuesta`);
  }
  assert.equal(pr.estado(t(0, 13, 0)).enEspera, 2);
});

test('AC-3: una pregunta que llega ya vencida se rechaza y no se registra', () => {
  const { pr } = nuevo();
  for (const cad of [t(0, 9, 30), t(0, 9, 0)]) {
    const r = pr.preguntar(dec('a', { caduca: cad }), LUNES_9, AG);
    assert.equal(r.ok, false);
    assert.equal(!r.ok && r.motivo, 'YA_CADUCADA');
  }
  assert.equal(pr.estadoTrabajo('trab-a', LUNES_9), 'LIBRE');
  assert.equal(pr.estado(LUNES_9).abiertas, 0);
});

test('AC-3: se repregunta una sola vez por ventana; el intento rechazado no cambia nada', () => {
  const { pr } = nuevo();
  pr.preguntar(dec('a'), LUNES_9, AG);
  pr.vencer(t(0, 12, 0));
  assert.deepEqual(pr.repreguntar('a', t(0, 13, 0), t(0, 12, 5)), { ok: true, caduca: t(0, 13, 0) });
  assert.equal(pr.estadoTrabajo('trab-a', t(0, 12, 6)), 'EN_ESPERA');
  pr.vencer(t(0, 13, 0));
  const otra = pr.repreguntar('a', t(0, 13, 30), t(0, 13, 5));
  assert.deepEqual(otra, { ok: false, motivo: 'YA_REPREGUNTADA_EN_VENTANA' });
  assert.equal(pr.estadoTrabajo('trab-a', t(0, 13, 6)), 'DEFER');
  // Otra instancia de ventana (la de la tarde): se puede una vez más.
  assert.equal(pr.repreguntar('a', t(0, 16, 0), t(0, 15, 5)).ok, true);
  // Y el día siguiente, también.
  pr.vencer(t(0, 16, 0));
  assert.equal(pr.repreguntar('a', t(1, 11, 0), t(1, 9, 5)).ok, true);
});

test('AC-3 negativo: repreguntar exige DEFER, pregunta conocida y un plazo futuro y finito', () => {
  const { pr } = nuevo();
  pr.preguntar(dec('a'), LUNES_9, AG);
  assert.deepEqual(pr.repreguntar('a', t(0, 13, 0), LUNES_9), { ok: false, motivo: 'NO_ESTA_EN_DEFER' });
  assert.deepEqual(pr.repreguntar('zz', t(0, 13, 0), LUNES_9), { ok: false, motivo: 'DESCONOCIDA' });
  pr.vencer(t(0, 12, 0));
  for (const mala of [t(0, 12, 5), t(0, 11, 0), Number.NaN, Infinity, '13:00', null, undefined]) {
    assert.deepEqual(pr.repreguntar('a', mala, t(0, 12, 5)), { ok: false, motivo: 'CADUCA_INVALIDA' }, String(mala));
  }
  // Los rechazos no gastan la repregunta de la ventana.
  assert.equal(pr.repreguntar('a', t(0, 13, 0), t(0, 12, 5)).ok, true);
});

test('AC-3: entrada ilegible o sin autenticar se rechaza sin registrar nada (fail-closed)', () => {
  const { pr } = nuevo();
  const malas: unknown[] = [
    null, undefined, 'pregunta', 42, [], {}, dec('a', { id: '  ' }), dec('a', { caduca: Number.NaN }),
    dec('a', { caduca: Infinity }), { ...dec('a'), clase: 'OTRA' }, { ...dec('a'), que: '' },
    { ...dec('a'), siNoContestas: undefined }, { ...dec('a'), version: 3 },
    { ...dec('a'), clase: 'PERMISO' }, { ...dec('a'), tema: '   ' },
  ];
  for (const x of malas) {
    const r = pr.preguntar(x, LUNES_9, AG);
    assert.equal(r.ok, false, JSON.stringify(x));
    assert.equal(!r.ok && r.motivo, 'ENTRADA_INVALIDA', JSON.stringify(x));
  }
  for (const origen of ['DESCONOCIDO', 'NO_AUTENTICADO'] as const) {
    const r = pr.preguntar(dec('a'), LUNES_9, origen);
    assert.equal(!r.ok && r.motivo, 'ORIGEN_NO_AUTENTICADO');
  }
  assert.equal(pr.estado(LUNES_9).abiertas, 0);
  assert.equal(pr.estadoTrabajo('trab-a', LUNES_9), 'LIBRE');
});

test('preguntar es idempotente por id y versión; reutilizar un id para otra cosa se rechaza', () => {
  const { pr } = nuevo();
  assert.equal(pr.preguntar(dec('a'), LUNES_9, AG).ok && pr.preguntar(dec('a'), LUNES_9, AG).ok, true);
  const otra = pr.preguntar(dec('a'), LUNES_9, AG);
  assert.equal(otra.ok && otra.nueva, false);
  assert.equal(pr.estado(LUNES_9).abiertas, 1);
  const otroTrabajo = pr.preguntar(dec('a', { trabajo: 'otro', version: 'v2' }), LUNES_9, AG);
  assert.equal(!otroTrabajo.ok && otroTrabajo.motivo, 'ID_REUTILIZADO');
  const otraClase = pr.preguntar(perm('a', { trabajo: 'trab-a', agente: 'ag-a' }), LUNES_9, AG);
  assert.equal(!otraClase.ok && otraClase.motivo, 'ID_REUTILIZADO');
});

// ---------------------------------------------------------------------------------------------
// AC-4 — dos permisos distintos nunca como una sola respuesta.

test('AC-4: dos permisos distintos del mismo trabajo son dos tarjetas y una respuesta no abre el otro', () => {
  const { pr } = nuevo();
  pr.preguntar(perm('a', { trabajo: 'informe' }), LUNES_9, AG);
  pr.preguntar(perm('b', { trabajo: 'informe' }), LUNES_9, AG);
  const v = pr.visibles(LUNES_9);
  assert.equal(v.length, 2);
  assert.ok(v.every((x) => x.preguntas.length === 1));
  const ta = v.find((x) => x.preguntas[0] === 'a')!;
  const r = pr.responder({ tarjeta: ta.id, version: ta.version, valor: 'CONCEDER' }, LUNES_9, PE);
  assert.equal(r.ok && r.resueltas.length, 1);
  assert.equal(pr.puedeEjecutar('a'), true);
  assert.equal(pr.puedeEjecutar('b'), false);
  assert.equal(pr.estadoTrabajo('informe', LUNES_9), 'EN_ESPERA');
});

test('AC-4: el mismo permiso pedido por dos agentes tampoco se une, ni con un tema igual', () => {
  const { pr } = nuevo();
  pr.preguntar(perm('a', { permiso: 'publicar', tema: 'x' }), LUNES_9, AG);
  pr.preguntar(perm('b', { permiso: 'publicar', tema: 'x' }), LUNES_9, AG);
  pr.preguntar(dec('c', { tema: 'x' }), LUNES_9, AG);
  const v = pr.visibles(LUNES_9);
  assert.equal(v.length, 3);
  assert.deepEqual(v.map((x) => x.preguntas.length), [1, 1, 1]);
});

test('AC-4: dos decisiones sobre lo mismo se unen en una tarjeta y una respuesta cierra las dos', () => {
  const { pr } = nuevo();
  pr.preguntar(dec('a', { tema: 'Mismo fichero', que: 'Qué hago con el fichero' }), LUNES_9, AG);
  pr.preguntar(dec('b', { tema: ' mismo FICHERO ', que: 'qué  hago con el fichero' }), LUNES_9, AG);
  pr.preguntar(dec('c', { tema: 'otro nombre' }), LUNES_9, AG);
  const v = pr.visibles(LUNES_9);
  assert.equal(v.length, 2);
  const unida = v.find((x) => x.preguntas.length === 2)!;
  assert.deepEqual([...unida.preguntas], ['a', 'b']);
  assert.match(unida.que ?? '', /\+1 más/);
  const r = pr.responder({ tarjeta: unida.id, version: unida.version, valor: 'primero el agente a' }, LUNES_9, PE);
  assert.deepEqual(r.ok && [...r.resueltas], ['a', 'b']);
  assert.equal(pr.respuestaDe('a'), 'primero el agente a');
  assert.equal(pr.respuestaDe('b'), 'primero el agente a');
  assert.equal(pr.respuestaDe('c'), null);
  assert.equal(pr.estadoTrabajo('trab-c', LUNES_9), 'EN_ESPERA');
});

test('AC-4: unir no gasta otro aviso; preguntas distintas sí', () => {
  const unidas = nuevo();
  for (const id of ['a', 'b', 'c']) unidas.pr.preguntar(dec(id, { tema: 'igual', que: 'misma' }), LUNES_9, AG);
  const gastadoUnidas = [...unidas.pol.estado.usados.values()].reduce((s, n) => s + n, 0);
  assert.equal(gastadoUnidas, 1);
  const sueltas = nuevo();
  for (const id of ['a', 'b', 'c']) sueltas.pr.preguntar(dec(id, { tema: `tema ${id}` }), LUNES_9, AG);
  const gastadoSueltas = [...sueltas.pol.estado.usados.values()].reduce((s, n) => s + n, 0);
  assert.equal(gastadoSueltas, 3);
});

test('AC-4 negativo: un permiso solo se concede o se deniega; cualquier otro valor se rechaza sin efecto', () => {
  const { pr } = nuevo();
  pr.preguntar(perm('a'), LUNES_9, AG);
  const ta = pr.visibles(LUNES_9)[0]!;
  for (const valor of ['SI', 'conceder', 'quizá', 'CONCEDER Y DENEGAR', '  ']) {
    const r = pr.responder({ tarjeta: ta.id, version: ta.version, valor }, LUNES_9, PE);
    assert.equal(r.ok, false, valor);
    assert.equal(!r.ok && r.motivo, valor.trim() === '' ? 'ENTRADA_INVALIDA' : 'VALOR_INVALIDO', valor);
  }
  assert.equal(pr.puedeEjecutar('a'), false);
  const den = pr.responder({ tarjeta: ta.id, version: ta.version, valor: 'DENEGAR' }, LUNES_9, PE);
  assert.equal(den.ok, true);
  assert.equal(pr.puedeEjecutar('a'), false, 'denegar no autoriza el efecto');
});

// ---------------------------------------------------------------------------------------------
// AC-5 — respuesta a tarjeta caducada o de versión cambiada: rechazada y vuelta a enseñar.

test('AC-5: justo antes del vencimiento se acepta; en el vencimiento y después se rechaza y se vuelve a enseñar', () => {
  for (const [ahora, ok] of [[t(0, 11, 59), true], [t(0, 12, 0), false], [t(0, 12, 1), false], [t(1, 9, 0), false]] as const) {
    const { pr } = nuevo();
    pr.preguntar(perm('a'), LUNES_9, AG);
    const ta = pr.visibles(LUNES_9)[0]!;
    const r = pr.responder({ tarjeta: ta.id, version: ta.version, valor: 'CONCEDER' }, ahora, PE);
    assert.equal(r.ok, ok, `ahora=${ahora}`);
    assert.equal(pr.puedeEjecutar('a'), ok, `ahora=${ahora}`);
    if (!r.ok) {
      assert.equal(r.motivo, 'CADUCADA');
      assert.equal(r.volverAEnsenar?.estado, 'DEFER');
      assert.deepEqual([...(r.volverAEnsenar?.preguntas ?? [])], ['a']);
      assert.match(r.texto, /caducó/);
      assert.equal(pr.estadoTrabajo('trab-a', ahora), 'DEFER');
    }
  }
});

test('AC-5: la respuesta a una versión anterior se rechaza y se enseña la actual', () => {
  const { pr } = nuevo();
  pr.preguntar(perm('a'), LUNES_9, AG);
  const v1 = pr.visibles(LUNES_9)[0]!;
  const cambio = pr.preguntar(perm('a', { version: 'v2', que: 'Publicar el informe con los datos nuevos' }), t(0, 10, 0), AG);
  assert.equal(cambio.ok && cambio.nueva, false);
  const r = pr.responder({ tarjeta: v1.id, version: v1.version, valor: 'CONCEDER' }, t(0, 10, 5), PE);
  assert.equal(r.ok, false);
  assert.equal(!r.ok && r.motivo, 'VERSION_CAMBIADA');
  assert.match(!r.ok ? (r.volverAEnsenar?.que ?? '') : '', /datos nuevos/);
  assert.equal(pr.puedeEjecutar('a'), false);
  const v2 = pr.visibles(t(0, 10, 5))[0]!;
  assert.notEqual(v2.version, v1.version);
  assert.equal(pr.responder({ tarjeta: v2.id, version: v2.version, valor: 'CONCEDER' }, t(0, 10, 6), PE).ok, true);
  assert.equal(pr.puedeEjecutar('a'), true);
});

test('AC-5: cambiar la versión de una pregunta ya concedida anula la concesión', () => {
  const { pr } = nuevo();
  pr.preguntar(perm('a'), LUNES_9, AG);
  const ta = pr.visibles(LUNES_9)[0]!;
  pr.responder({ tarjeta: ta.id, version: ta.version, valor: 'CONCEDER' }, LUNES_9, PE);
  assert.equal(pr.puedeEjecutar('a'), true);
  pr.preguntar(perm('a', { version: 'v2', caduca: t(0, 14, 0) }), t(0, 10, 0), AG);
  assert.equal(pr.puedeEjecutar('a'), false);
  assert.equal(pr.respuestaDe('a'), null);
  assert.equal(pr.visibles(t(0, 10, 0)).length, 1);
});

test('AC-5: si se une otra pregunta a la tarjeta, la respuesta a la versión vista se rechaza', () => {
  const { pr } = nuevo();
  pr.preguntar(dec('a', { tema: 'x', que: 'misma' }), LUNES_9, AG);
  const vista = pr.visibles(LUNES_9)[0]!;
  pr.preguntar(dec('b', { tema: 'x', que: 'misma' }), t(0, 9, 40), AG);
  const r = pr.responder({ tarjeta: vista.id, version: vista.version, valor: 'sí' }, t(0, 9, 45), PE);
  assert.equal(!r.ok && r.motivo, 'VERSION_CAMBIADA');
  assert.equal(pr.respuestaDe('a'), null);
  assert.equal(pr.respuestaDe('b'), null);
});

test('AC-5: lo ilegible, lo que no es de la persona, lo desconocido y lo ya respondido se rechaza', () => {
  const { pr } = nuevo();
  pr.preguntar(perm('a'), LUNES_9, AG);
  const ta = pr.visibles(LUNES_9)[0]!;
  const buena = { tarjeta: ta.id, version: ta.version, valor: 'CONCEDER' };
  for (const x of [null, undefined, 'sí', 3, [], {}, { ...buena, tarjeta: 5 }, { ...buena, version: '' }, { ...buena, valor: undefined }]) {
    const r = pr.responder(x, LUNES_9, PE);
    assert.equal(!r.ok && r.motivo, 'ENTRADA_INVALIDA', JSON.stringify(x));
  }
  for (const origen of [AG, 'DESCONOCIDO', 'NO_AUTENTICADO'] as const) {
    const r = pr.responder(buena, LUNES_9, origen);
    assert.equal(!r.ok && r.motivo, 'ORIGEN_NO_VALIDO', origen);
  }
  assert.equal(pr.puedeEjecutar('a'), false, 'un agente no se autoriza a sí mismo');
  const des = pr.responder({ ...buena, tarjeta: 'p:no-existe' }, LUNES_9, PE);
  assert.equal(!des.ok && des.motivo, 'DESCONOCIDA');
  assert.equal(pr.responder(buena, LUNES_9, PE).ok, true);
  const otra = pr.responder({ ...buena, valor: 'DENEGAR' }, LUNES_9, PE);
  assert.equal(!otra.ok && otra.motivo, 'YA_RESPONDIDA');
  assert.equal(pr.respuestaDe('a'), 'CONCEDER', 'la segunda respuesta no cambia la primera');
});

test('AC-5: lo que supera el nivel del canal no se enseña ni al volver a enseñarlo', () => {
  const { pr } = nuevo();
  pr.preguntar(perm('a', { nivel: 3, que: 'dato secreto del cliente' }), LUNES_9, AG);
  const v = pr.visibles(LUNES_9)[0]!;
  assert.equal(v.redactada, true);
  assert.equal(v.que, null);
  pr.preguntar(perm('a', { nivel: 3, version: 'v2', que: 'otro dato secreto' }), t(0, 10, 0), AG);
  const r = pr.responder({ tarjeta: v.id, version: v.version, valor: 'CONCEDER' }, t(0, 10, 5), PE);
  assert.equal(!r.ok && r.volverAEnsenar?.que, null);
  assert.doesNotMatch(JSON.stringify(r), /secreto/);
});

// ---------------------------------------------------------------------------------------------
// AC-6 — una autorización obligatoria no se pierde en modo descanso.

test('AC-6: en descanso no se enseña ni se contacta; al salir aparece, vencida, y el trabajo esperó', () => {
  const { pol, pr } = nuevo();
  const noche = t(0, 23, 30);
  const r = pr.preguntar(perm('pub', { trabajo: 'informe', caduca: t(1, 6, 0) }), noche, AG);
  assert.equal(r.ok && r.decision?.contactarAhora, false);
  assert.equal(pol.modoEfectivo(noche), 'DESCANSO');
  assert.deepEqual(pr.visibles(noche), []);
  assert.deepEqual(pr.visibles(t(1, 3, 0)), []);
  const dormida = pr.estado(t(1, 3, 0));
  assert.equal(dormida.ocultasPorModo, 1);
  assert.equal(dormida.obligatorias, 1);
  assert.deepEqual([...dormida.trabajosEnEspera], ['informe']);
  // Al salir del descanso (08:00) el plazo ya venció: aparece, en espera, sin efecto ejecutado.
  const manana = t(1, 8, 0);
  const v = pr.visibles(manana);
  assert.equal(v.length, 1);
  assert.equal(v[0]!.obligatoria, true);
  assert.equal(v[0]!.estado, 'DEFER');
  assert.equal(pr.estadoTrabajo('informe', manana), 'DEFER');
  assert.equal(pr.puedeEjecutar('pub'), false);
  assert.equal(pol.bandeja.porDecision('agente:pub')?.pendiente, true);
  const cola = construirCola({ ESPERAN_ALGO: dePreguntasAgentes(pr, manana) }, manana, 2);
  assert.equal(cola.peticiones.length, 1);
  assert.equal(cola.peticiones[0]!.critica, true);
  assert.equal(cola.peticiones[0]!.caducada, true);
  assert.match(textoCola(cola), /sigue en espera; no se ejecutó nada/);
});

test('AC-6: una obligatoria que no ha vencido aparece al salir del descanso y se puede conceder', () => {
  const { pr } = nuevo();
  pr.preguntar(perm('pub', { caduca: t(1, 12, 0) }), t(0, 23, 30), AG);
  assert.deepEqual(pr.visibles(t(1, 6, 59)), []);
  const v = pr.visibles(t(1, 7, 0));
  assert.equal(v.length, 1);
  assert.equal(v[0]!.estado, 'ABIERTA');
  assert.equal(pr.responder({ tarjeta: v[0]!.id, version: v[0]!.version, valor: 'CONCEDER' }, t(1, 7, 5), PE).ok, true);
  assert.equal(pr.puedeEjecutar('pub'), true);
});

test('AC-6: foco y fuera también retrasan; al declarar disponible vuelve todo, obligatorias primero', () => {
  const { pol, pr } = nuevo();
  pr.preguntar(dec('d', { caduca: t(0, 17, 0) }), LUNES_9, AG);
  pr.preguntar(perm('p', { caduca: t(0, 17, 30) }), LUNES_9, AG);
  assert.equal(pol.control({ k: 'DECLARAR_MODO', modo: { modo: 'FOCO', hasta: null } }, PE, LUNES_9), true);
  assert.deepEqual(pr.visibles(t(0, 10, 0)), []);
  assert.equal(pr.estado(t(0, 10, 0)).ocultasPorModo, 2);
  pol.control({ k: 'DECLARAR_MODO', modo: { modo: 'DISPONIBLE', hasta: null } }, PE, t(0, 11, 0));
  assert.deepEqual(pr.visibles(t(0, 11, 0)).map((x) => x.preguntas[0]), ['p', 'd']);
  assert.equal(pr.estado(t(0, 11, 0)).ocultasPorModo, 0);
});

test('AC-6: sin modo declarado no hay disponibilidad implícita: no se enseña, tampoco se pierde', () => {
  const pol = new Politica({ ...opA(), modoPorDefecto: null });
  const pr = new Preguntas(pol);
  pr.preguntar(perm('p'), LUNES_9, AG);
  assert.deepEqual(pr.visibles(LUNES_9), []);
  assert.equal(pr.estado(LUNES_9).ocultasPorModo, 1);
});

// ---------------------------------------------------------------------------------------------
// AC-8 — contestar y consultar el estado con todos los agentes ocupados.

test('AC-8: con tres agentes ocupados la persona consulta el estado y contesta sin esperar a ninguno', () => {
  const { pr } = nuevo();
  // Los agentes ya preguntaron y siguen ocupados: nada de lo que sigue les llama ni les espera.
  pr.preguntar(dec('a', { tema: 'fichero', que: 'misma' }), LUNES_9, AG);
  pr.preguntar(dec('b', { tema: 'fichero', que: 'misma' }), t(0, 9, 31), AG);
  pr.preguntar(perm('c', { trabajo: 'informe' }), t(0, 9, 32), AG);
  const ahora = t(0, 10, 5);
  const est = pr.estado(ahora);
  assert.equal(est.abiertas, 2);
  assert.equal(est.obligatorias, 1);
  assert.deepEqual([...est.trabajosEnEspera], ['informe', 'trab-a', 'trab-b']);
  assert.equal(est.masAntiguaMin, 35);
  const v = pr.visibles(ahora);
  assert.equal(v.length, 2);
  for (const tj of v) {
    const valor = tj.clase === 'PERMISO' ? 'DENEGAR' : 'primero a';
    assert.equal(pr.responder({ tarjeta: tj.id, version: tj.version, valor }, ahora, PE).ok, true);
  }
  const despues = pr.estado(t(0, 10, 6));
  assert.equal(despues.abiertas, 0);
  assert.equal(despues.masAntiguaMin, null);
  assert.deepEqual([...despues.trabajosEnEspera], []);
  assert.equal(pr.estadoTrabajo('informe', t(0, 10, 6)), 'LIBRE');
});

// ---------------------------------------------------------------------------------------------
// Cola única: las preguntas de agentes entran por un solo sitio.

test('cola: la pregunta de un agente sale con las cinco cosas y no se duplica con la fuente de Soul', () => {
  const { pol, pr } = nuevo();
  pr.preguntar(dec('a', { que: 'Dos agentes van a editar el mismo fichero. ¿Quién va primero?' }), LUNES_9, AG);
  const ahora = t(0, 10, 5);
  const cola = construirCola({
    ESPERAN_ALGO: dePreguntasAgentes(pr, ahora),
    AVISO_SOUL: deBandejaSoul(pol.bandeja.items(), 2),
  }, ahora, 2);
  assert.equal(cola.peticiones.length, 1, 'una sola vez, no también como aviso de Soul');
  const p = cola.peticiones[0]!;
  assert.equal(p.fuente, 'ESPERAN_ALGO');
  assert.deepEqual(p.faltan, []);
  assert.equal(p.caduca, t(0, 12, 0));
  assert.match(p.que ?? '', /mismo fichero/);
});

test('cola: una decisión de Soul que no es de un agente sigue saliendo por Soul', () => {
  const { pol, pr } = nuevo();
  pol.decidir({ ...{
    id: 'soul-1', origen: 'AGENTE_AUTENTICADO', tipo: { k: 'DECISION', decisionId: 'soul-1' }, ruta: 'API',
    objetivo: null, plazo: null, costeRetraso: 'MEDIO', nivel: 1, caduca: null, codigoAlerta: null,
    urgenciaEnContenido: 'NORMAL', urgenciaSugeridaLlm: null, texto: 'Decisión de Soul',
  } }, LUNES_9);
  pr.preguntar(dec('a'), LUNES_9, AG);
  const soul = deBandejaSoul(pol.bandeja.items(), 2) as Array<{ id: string }>;
  assert.deepEqual(soul.map((x) => x.id), ['soul-1']);
});

test('una respuesta registrada resuelve el elemento de la bandeja de la política', () => {
  const { pol, pr } = nuevo();
  pr.preguntar(dec('a'), LUNES_9, AG);
  assert.equal(pol.bandeja.porDecision('agente:a')?.pendiente, true);
  const ta = pr.visibles(LUNES_9)[0]!;
  pr.responder({ tarjeta: ta.id, version: ta.version, valor: 'adelante' }, LUNES_9, PE);
  assert.equal(pol.bandeja.porDecision('agente:a')?.pendiente, false);
});

// ---------------------------------------------------------------------------------------------
// Correcciones tras la revisión independiente de la PR #1534.

test('revisión P1: con el sistema en PARA no entra ninguna pregunta, ni nueva ni unida', () => {
  const { pol, pr } = nuevo();
  pr.preguntar(dec('a', { tema: 'x', que: 'misma' }), LUNES_9, AG);
  pol.control({ k: 'PARA' }, PE, LUNES_9);
  for (const p of [perm('b'), dec('c'), dec('d', { tema: 'x', que: 'misma' })]) {
    const r = pr.preguntar(p, t(0, 9, 31), AG);
    assert.equal(!r.ok && r.motivo, 'BLOQUEADA', p.id);
  }
  assert.equal(pr.estadoTrabajo('trab-b', t(0, 9, 31)), 'LIBRE');
  assert.equal(pol.bandeja.porDecision('agente:b'), undefined);
});

test('revisión P1: un trabajo vetado no puede preguntar; reanudar o levantar el veto lo permite', () => {
  const { pol, pr } = nuevo();
  pol.control({ k: 'VETAR', objetivo: 'trab-a' }, PE, LUNES_9);
  const r = pr.preguntar(perm('a'), LUNES_9, AG);
  assert.equal(!r.ok && r.motivo, 'BLOQUEADA');
  assert.equal(pr.preguntar(perm('z', { trabajo: 'otro' }), LUNES_9, AG).ok, true);
  pol.control({ k: 'LEVANTAR_VETO', objetivo: 'trab-a' }, PE, LUNES_9);
  assert.equal(pr.preguntar(perm('a'), LUNES_9, AG).ok, true);
});

test('revisión P1: PARA o veto posterior a la concesión impiden ejecutar el efecto', () => {
  const { pol, pr } = nuevo();
  pr.preguntar(perm('a'), LUNES_9, AG);
  const ta = pr.visibles(LUNES_9)[0]!;
  pr.responder({ tarjeta: ta.id, version: ta.version, valor: 'CONCEDER' }, LUNES_9, PE);
  assert.equal(pr.puedeEjecutar('a'), true);
  pol.control({ k: 'PARA' }, PE, t(0, 9, 40));
  assert.equal(pr.puedeEjecutar('a'), false);
  pol.control({ k: 'REANUDAR' }, PE, t(0, 9, 41));
  assert.equal(pr.puedeEjecutar('a'), true);
  pol.control({ k: 'VETAR', objetivo: 'trab-a' }, PE, t(0, 9, 42));
  assert.equal(pr.puedeEjecutar('a'), false);
});

test('revisión P1: repreguntar no salta PARA ni veto', () => {
  const { pol, pr } = nuevo();
  pr.preguntar(dec('a'), LUNES_9, AG);
  pr.vencer(t(0, 12, 0));
  pol.control({ k: 'PARA' }, PE, t(0, 12, 1));
  const r = pr.repreguntar('a', t(0, 15, 0), t(0, 12, 2));
  assert.equal(!r.ok && r.motivo, 'BLOQUEADA');
  assert.equal(pr.estadoTrabajo('trab-a', t(0, 12, 2)), 'DEFER');
});

test('revisión P1: otro agente no se pega a una tarjeta con un texto distinto aunque el tema coincida', () => {
  const { pol, pr } = nuevo();
  pr.preguntar(dec('a', { tema: 'x', que: '¿Renombro el fichero?' }), LUNES_9, AG);
  pr.preguntar(dec('b', { tema: 'x', que: '¿Borro la rama X?', obligatoria: true }), LUNES_9, AG);
  pr.preguntar(dec('c', { tema: 'x', que: '¿Borro la rama Y?' }), LUNES_9, AG);
  const v = pr.visibles(LUNES_9);
  assert.equal(v.length, 3, 'cada texto distinto es su tarjeta');
  assert.ok(v.every((x) => x.preguntas.length === 1));
  const ta = v.find((x) => x.preguntas[0] === 'a')!;
  pr.responder({ tarjeta: ta.id, version: ta.version, valor: 'sí' }, LUNES_9, PE);
  assert.equal(pr.respuestaDe('b'), null, 'la respuesta a otra pregunta no resuelve la de b');
  assert.equal(pr.respuestaDe('c'), null);
  // Cada una pasó por la política y gastó su propio aviso.
  assert.equal([...pol.estado.usados.values()].reduce((s, n) => s + n, 0), 3);
});

test('revisión P1: una decisión obligatoria no se une aunque el tema y el texto coincidan', () => {
  const { pr } = nuevo();
  pr.preguntar(dec('a', { tema: 'x', que: 'misma' }), LUNES_9, AG);
  pr.preguntar(dec('b', { tema: 'x', que: 'misma', obligatoria: true }), LUNES_9, AG);
  assert.deepEqual(pr.visibles(LUNES_9).map((x) => x.preguntas.length), [1, 1]);
});

test('revisión P1: subir la versión de una pregunta en DEFER cuenta como la repregunta de la ventana', () => {
  const { pr } = nuevo();
  pr.preguntar(dec('a'), LUNES_9, AG);
  pr.vencer(t(0, 12, 0));
  const v2 = pr.preguntar(dec('a', { version: 'v2', caduca: t(0, 13, 0) }), t(0, 12, 1), AG);
  assert.equal(v2.ok, true);
  pr.vencer(t(0, 13, 0));
  const v3 = pr.preguntar(dec('a', { version: 'v3', caduca: t(0, 14, 0) }), t(0, 13, 1), AG);
  assert.equal(!v3.ok && v3.motivo, 'YA_REPREGUNTADA_EN_VENTANA');
  assert.equal(pr.estadoTrabajo('trab-a', t(0, 13, 1)), 'DEFER');
  assert.equal(pr.repreguntar('a', t(0, 15, 0), t(0, 13, 2)).ok, false, 'la ventana ya está gastada');
});

test('revisión P1: subir la versión de una pregunta denegada no insiste sin límite', () => {
  const { pr } = nuevo();
  pr.preguntar(perm('a'), LUNES_9, AG);
  const ta = pr.visibles(LUNES_9)[0]!;
  pr.responder({ tarjeta: ta.id, version: ta.version, valor: 'DENEGAR' }, LUNES_9, PE);
  assert.equal(pr.preguntar(perm('a', { version: 'v2' }), t(0, 9, 40), AG).ok, true);
  const ta2 = pr.visibles(t(0, 9, 40))[0]!;
  pr.responder({ tarjeta: ta2.id, version: ta2.version, valor: 'DENEGAR' }, t(0, 9, 41), PE);
  const otra = pr.preguntar(perm('a', { version: 'v3' }), t(0, 9, 45), AG);
  assert.equal(!otra.ok && otra.motivo, 'YA_REPREGUNTADA_EN_VENTANA');
  assert.equal(pr.visibles(t(0, 9, 45)).length, 0);
});

test('revisión P2: el motivo del rechazo dice la causa real', () => {
  const { pol, pr } = nuevo();
  const vencida = pr.preguntar(perm('a', { caduca: LUNES_9 }), LUNES_9, AG);
  assert.equal(!vencida.ok && vencida.motivo, 'YA_CADUCADA');
  pol.control({ k: 'PARA' }, PE, LUNES_9);
  const parada = pr.preguntar(perm('b'), LUNES_9, AG);
  assert.equal(!parada.ok && parada.motivo, 'BLOQUEADA');
  assert.match(!parada.ok ? parada.detalle : '', /PARADO/);
});

test('revisión P2: cambiar el tema al subir la versión es reutilizar el identificador', () => {
  const { pr } = nuevo();
  pr.preguntar(dec('a', { tema: 'x' }), LUNES_9, AG);
  const r = pr.preguntar(dec('a', { tema: 'y', version: 'v2' }), t(0, 9, 40), AG);
  assert.equal(!r.ok && r.motivo, 'ID_REUTILIZADO');
});

test('revisión P2: la persona no pregunta y un tema con # se rechaza', () => {
  const { pr } = nuevo();
  const p = pr.preguntar(dec('a'), LUNES_9, PE);
  assert.equal(!p.ok && p.motivo, 'ORIGEN_NO_AUTENTICADO');
  const h = pr.preguntar(dec('b', { tema: 'x#vencida' }), LUNES_9, AG);
  assert.equal(!h.ok && h.motivo, 'ENTRADA_INVALIDA');
});

test('revisión: dos permisos no obligatorios con el mismo tema y el mismo texto tampoco se unen', () => {
  const { pr } = nuevo();
  for (const id of ['a', 'b']) pr.preguntar(perm(id, { obligatoria: false, tema: 'x', que: 'misma' }), LUNES_9, AG);
  assert.deepEqual(pr.visibles(LUNES_9).map((x) => x.preguntas.length), [1, 1]);
});
