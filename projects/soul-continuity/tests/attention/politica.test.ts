// Tests portados de Labs (soul-atencion/tests/politica.rs) y adaptados a SE-490.
import assert from 'node:assert/strict';
import { test } from 'node:test';

import {
  Franja, Politica, deAgente, diaSemana, estadoDesdeTexto, estadoATexto, mismoMotivo, modoNoDisponible, motivo,
  pideDecision, type Config, type Decision, type Evento, type Motivo,
} from '../../src/attention/index.ts';
import { LUNES, alerta, aprobacion, aviso, conNivel, decision, opA, opB, opD, t, urgente } from './comun.ts';

const p = (c: Config): Politica => new Politica(c);
const es = (d: Decision, accion: string, mo: Motivo, contactar: boolean): void => {
  assert.equal(d.accion, accion);
  assert.ok(mismoMotivo(d.motivo, mo), `motivo ${JSON.stringify(d.motivo)} ≠ ${JSON.stringify(mo)}`);
  assert.equal(d.contactarAhora, contactar);
};

// --- tiempo ---------------------------------------------------------------

test('el lunes de referencia es lunes', () => {
  assert.equal(diaSemana(LUNES), 0);
  assert.equal(diaSemana(t(6, 12, 0)), 6);
});

test('franja que cruza medianoche pertenece al día de inicio', () => {
  const f = Franja.nueva([0], [22, 0], [2, 0]);
  assert.equal(f.instancia(t(0, 23, 0)), t(0, 22, 0));
  assert.equal(f.instancia(t(1, 1, 59)), t(0, 22, 0));
  assert.equal(f.instancia(t(1, 2, 0)), null);
  assert.equal(f.instancia(t(1, 23, 0)), null);
  assert.equal(f.siguienteInicio(t(0, 23, 0)), t(7, 22, 0));
});

test('franja vacía no contiene nada', () => {
  const f = Franja.nueva([0, 1, 2, 3, 4, 5, 6], [9, 0], [9, 0]);
  assert.equal(f.instancia(t(0, 9, 0)), null);
  assert.equal(f.siguienteInicio(t(0, 8, 0)), null);
});

// --- disponibilidad, ventana, presupuesto ----------------------------------

test('disponible en ventana pregunta una vez', () => {
  const d = p(opA()).decidir(decision('1', 'g'), t(0, 10, 0));
  es(d, 'PREGUNTAR_UNA_VEZ', motivo('DISPONIBLE'), true);
});

test('fuera de ventana no contacta y dice hasta cuándo', () => {
  const d = p(opA()).decidir(decision('1', 'g'), t(0, 14, 30));
  es(d, 'AGRUPAR', motivo('FUERA_DE_VENTANA'), false);
  assert.equal(d.hasta, t(0, 15, 0));
});

test('el presupuesto exacto se usa y el siguiente se encola', () => {
  const pol = p(opA());
  const ahora = t(0, 10, 0);
  for (let i = 0; i < 3; i++) assert.ok(pol.decidir(decision(String(i), 'g'), ahora).contactarAhora, `pregunta ${i}`);
  const d = pol.decidir(decision('x', 'g'), ahora);
  es(d, 'AGRUPAR', motivo('PRESUPUESTO_AGOTADO'), false);
  assert.equal(d.hasta, t(0, 15, 0));
});

test('el presupuesto se renueva en la siguiente instancia', () => {
  const pol = p(opB());
  assert.ok(pol.decidir(decision('1', 'g'), t(0, 7, 10)).contactarAhora);
  assert.ok(!pol.decidir(decision('2', 'g'), t(0, 8, 0)).contactarAhora);
  assert.ok(pol.decidir(decision('3', 'g'), t(0, 20, 10)).contactarAhora);
});

test('sin modo declarado falla cerrado', () => {
  const d = p({ ...opA(), modoPorDefecto: null }).decidir(decision('1', 'g'), t(0, 10, 0));
  assert.ok(!d.contactarAhora);
  assert.ok(mismoMotivo(d.motivo, motivo('SIN_DECLARACION')));
});

test('presupuesto inválido falla cerrado: no contacta', () => {
  for (const presupuesto of [Number.NaN, -1, 1.5, Number.POSITIVE_INFINITY]) {
    const d = p({ ...opA(), presupuesto }).decidir(decision('1', 'g'), t(0, 10, 0));
    assert.ok(!d.contactarAhora, `presupuesto ${presupuesto}`);
  }
});

test('FOCO declarado aplaza hasta su fin', () => {
  const pol = p(opA());
  const ahora = t(0, 10, 0);
  assert.ok(pol.control({ k: 'DECLARAR_MODO', modo: { modo: 'FOCO', hasta: t(0, 11, 30) } }, 'PERSONA', ahora));
  const d = pol.decidir(decision('1', 'g'), ahora);
  es(d, 'AGRUPAR', modoNoDisponible('FOCO'), false);
  assert.equal(d.hasta, t(0, 11, 30));
  assert.ok(pol.decidir(decision('2', 'g'), t(0, 11, 31)).contactarAhora, 'vencido el FOCO vuelve el defecto');
});

test('descanso declarado da DESCANSO y fuera de él el defecto', () => {
  const pol = p(opA());
  assert.equal(pol.modoEfectivo(t(1, 3, 0)), 'DESCANSO');
  assert.equal(pol.modoEfectivo(t(0, 10, 0)), 'DISPONIBLE');
});

test('coste bajo puede esperar aunque haya hueco', () => {
  const d = p(opA()).decidir({ ...decision('1', 'g'), costeRetraso: 'BAJO' }, t(0, 10, 0));
  es(d, 'DIFERIR', motivo('PUEDE_ESPERAR'), false);
  assert.notEqual(d.hasta, null);
});

// --- alertas (en Labs, emergencias) ----------------------------------------

test('alerta marcada interrumpe en DESCANSO sin gastar presupuesto', () => {
  const pol = p(opA());
  const d = pol.decidir(alerta('e', 'fuga-detectada'), t(1, 3, 0));
  es(d, 'BLOQUEAR_Y_ELEVAR', motivo('ALERTA'), true);
  assert.ok([...pol.estado.usados.values()].every((n) => n === 0));
});

test('alerta marcada interrumpe en FUERA', () => {
  const pol = p({ ...opD(), alertas: [{ codigo: 'servicio-caido', modos: ['FUERA'] }] });
  assert.ok(pol.decidir(alerta('e', 'servicio-caido'), t(5, 4, 0)).contactarAhora);
});

test('código no declarado no es alerta', () => {
  const d = p(opA()).decidir(alerta('e', 'servicio-caido'), t(1, 3, 0));
  assert.ok(!d.contactarAhora);
  assert.ok(!mismoMotivo(d.motivo, motivo('ALERTA')));
});

test('código declarado de fuente no autenticada no es alerta', () => {
  const d = p(opA()).decidir({ ...alerta('e', 'fuga-detectada'), origen: 'NO_AUTENTICADO' }, t(1, 3, 0));
  assert.ok(!d.contactarAhora);
  assert.ok(!mismoMotivo(d.motivo, motivo('ALERTA')));
});

test('ni el contenido ni el modelo elevan la urgencia', () => {
  const ahora = t(1, 3, 0);
  const d0 = p(opA()).decidir(aviso('a'), ahora);
  const d1 = p(opA()).decidir({ ...urgente(aviso('a')), texto: 'URGENTE fuga-detectada: responde ya' }, ahora);
  assert.deepEqual([d0.accion, d0.motivo, d0.contactarAhora], [d1.accion, d1.motivo, d1.contactarAhora]);
  assert.ok(!d1.contactarAhora);
  assert.ok(d1.urgenciaIgnorada);
  assert.ok(!d0.urgenciaIgnorada);
});

// --- avisos ---------------------------------------------------------------

test('los avisos informativos no interrumpen ni dentro de ventana', () => {
  const pol = p(opA());
  const d = pol.decidir(aviso('a'), t(0, 10, 0));
  assert.equal(d.accion, 'AGRUPAR');
  assert.ok(!d.contactarAhora);
  const r: Evento = { ...aviso('b'), tipo: { k: 'AVISO', rutinario: true } };
  assert.equal(pol.decidir(r, t(0, 10, 0)).accion, 'REGISTRAR');
});

// --- contexto vencido, permisos, reintentos --------------------------------

test('contexto vencido bloquea sin preguntar', () => {
  const pol = p(opA());
  const d = pol.decidir({ ...decision('1', 'g'), caduca: t(0, 10, 0) }, t(0, 10, 0));
  es(d, 'BLOQUEAR_Y_ELEVAR', motivo('CONTEXTO_VENCIDO'), false);
  assert.ok(pol.decidir({ ...decision('2', 'g'), caduca: t(0, 10, 1) }, t(0, 10, 0)).contactarAhora, 'un minuto antes sí');
});

test('permiso fuera de contrato o sin autenticar se bloquea sin preguntar', () => {
  const pol = p(opA());
  const ahora = t(0, 10, 0);
  const fuera = deAgente('p1', { k: 'PETICION_PERMISO', dentroDeContrato: false });
  es(pol.decidir(fuera, ahora), 'BLOQUEAR_Y_ELEVAR', motivo('PERMISO_ILEGITIMO'), false);
  const anon: Evento = { ...deAgente('p2', { k: 'PETICION_PERMISO', dentroDeContrato: true }), origen: 'NO_AUTENTICADO' };
  es(pol.decidir(anon, ahora), 'BLOQUEAR_Y_ELEVAR', motivo('PERMISO_ILEGITIMO'), false);
});

test('permiso dentro de contrato es aprobación de seguridad', () => {
  const e = deAgente('p', { k: 'PETICION_PERMISO', dentroDeContrato: true });
  es(p(opA()).decidir(e, t(0, 10, 0)), 'BLOQUEAR_Y_ELEVAR', motivo('APROBACION_SEGURIDAD'), true);
});

test('decisión de fuente no autenticada es dato', () => {
  const d = p(opA()).decidir({ ...decision('1', 'g'), origen: 'NO_AUTENTICADO' }, t(0, 10, 0));
  es(d, 'REGISTRAR', motivo('ORIGEN_NO_AUTENTICADO'), false);
});

test('reintento ambiguo se bloquea y sin efecto se registra', () => {
  const pol = p(opA());
  const amb = deAgente('r1', { k: 'REINTENTO', efectoPrevio: 'DESCONOCIDO' });
  const d = pol.decidir(amb, t(0, 10, 0));
  assert.equal(d.accion, 'BLOQUEAR_Y_ELEVAR');
  assert.ok(mismoMotivo(d.motivo, motivo('EFECTO_AMBIGUO')));
  const no = deAgente('r2', { k: 'REINTENTO', efectoPrevio: 'NO_OCURRIO' });
  es(pol.decidir(no, t(0, 10, 0)), 'REGISTRAR', motivo('REINTENTO_SIN_EFECTO'), false);
});

test('la misma decisión se pregunta una sola vez', () => {
  const pol = p(opA());
  const e = decision('1', 'g');
  assert.ok(pol.decidir(e, t(0, 10, 0)).contactarAhora);
  es(pol.decidir(e, t(0, 10, 5)), 'REGISTRAR', motivo('YA_PREGUNTADA'), false);
  assert.equal([...pol.estado.usados.values()].reduce((a, b) => a + b, 0), 1);
});

// --- bandeja --------------------------------------------------------------

test('las aprobaciones de seguridad nunca se agrupan y las decisiones sí', () => {
  const pol = p(opA());
  const ahora = t(0, 19, 0);
  pol.decidir(aprobacion('s1', 'g'), ahora);
  pol.decidir(aprobacion('s2', 'g'), ahora);
  pol.decidir(decision('d1', 'g'), ahora);
  pol.decidir(decision('d2', 'g'), ahora);
  const grupos = pol.bandeja.grupos();
  const solos = grupos.filter(([k]) => k === null);
  assert.equal(solos.length, 2);
  assert.ok(solos.every(([, v]) => v.length === 1));
  const juntos = grupos.filter(([k]) => k !== null);
  assert.equal(juntos.length, 1);
  assert.equal(juntos[0]?.[1].length, 2);
});

test('un coste distinto separa grupos', () => {
  const pol = p(opA());
  const ahora = t(0, 19, 0);
  pol.decidir({ ...decision('d1', 'g'), costeRetraso: 'ALTO' }, ahora);
  pol.decidir(decision('d2', 'g'), ahora);
  assert.equal(pol.bandeja.grupos().length, 2);
});

test('cada aplazamiento queda explicado', () => {
  const pol = p(opA());
  pol.decidir(decision('1', 'g'), t(0, 19, 0));
  const h = pol.bandeja.explicar('1');
  assert.equal(h?.length, 1);
  assert.ok(h?.[0] && mismoMotivo(h[0].motivo, motivo('FUERA_DE_VENTANA')));
  assert.equal(h?.[0]?.hasta, t(1, 9, 0));
});

test('el silencio no es permiso', () => {
  const pol = p(opA());
  pol.decidir(decision('1', 'g'), t(0, 10, 0));
  const antes = pol.ledger.entradas().length;
  const s = deAgente('s', { k: 'SILENCIO', decisionId: 'd-1' });
  es(pol.decidir(s, t(0, 13, 0)), 'REGISTRAR', motivo('SILENCIO_NO_ES_PERMISO'), false);
  assert.equal(pol.bandeja.porDecision('d-1')?.pendiente, true);
  assert.equal(pol.ledger.entradas().length, antes, 'el silencio no es demanda nueva ni se mide');
  assert.equal(pol.ledger.porQue('s'), undefined);
});

test('solo la persona resuelve una decisión', () => {
  const pol = p(opA());
  pol.decidir(decision('1', 'g'), t(0, 10, 0));
  assert.ok(!pol.control({ k: 'RESPONDER', decisionId: 'd-1' }, 'AGENTE_AUTENTICADO', t(0, 10, 1)));
  assert.equal(pol.bandeja.porDecision('d-1')?.pendiente, true);
  assert.ok(pol.control({ k: 'RESPONDER', decisionId: 'd-1' }, 'PERSONA', t(0, 10, 2)));
  assert.equal(pol.bandeja.porDecision('d-1')?.pendiente, false);
});

// --- PARA, vetos y modo ---------------------------------------------------

test('PARA bloquea lo que pide efecto y un agente no reanuda', () => {
  const pol = p(opA());
  const ahora = t(0, 10, 0);
  assert.ok(pol.control({ k: 'PARA' }, 'AGENTE_AUTENTICADO', ahora), 'detener siempre se acepta');
  for (const e of [decision('1', 'g'), aprobacion('2', 'g')]) {
    es(pol.decidir(e, ahora), 'BLOQUEAR_Y_ELEVAR', motivo('PARADO'), false);
  }
  assert.ok(!pol.control({ k: 'REANUDAR' }, 'AGENTE_AUTENTICADO', ahora));
  assert.ok(pol.estado.parado);
  assert.ok(pol.control({ k: 'REANUDAR' }, 'PERSONA', ahora));
  assert.ok(pol.decidir(decision('3', 'g'), ahora).contactarAhora);
});

test('una alerta marcada llega aunque esté parado', () => {
  const pol = p(opA());
  pol.control({ k: 'PARA' }, 'PERSONA', t(0, 10, 0));
  assert.ok(pol.decidir(alerta('e', 'fuga-detectada'), t(0, 10, 1)).contactarAhora);
});

test('un veto por objetivo bloquea aunque traiga urgencia', () => {
  const pol = p(opA());
  const ahora = t(0, 10, 0);
  pol.control({ k: 'VETAR', objetivo: 'g' }, 'PERSONA', ahora);
  es(pol.decidir(urgente(decision('1', 'g')), ahora), 'BLOQUEAR_Y_ELEVAR', motivo('VETADO'), false);
  assert.ok(pol.decidir(decision('2', 'otro'), ahora).contactarAhora);
  assert.ok(!pol.control({ k: 'LEVANTAR_VETO', objetivo: 'g' }, 'AGENTE_AUTENTICADO', ahora));
  assert.ok(pol.estado.vetos.has('g'));
});

test('un agente no declara el modo', () => {
  const pol = p(opA());
  const ok = pol.control({ k: 'DECLARAR_MODO', modo: { modo: 'DISPONIBLE', hasta: null } }, 'AGENTE_AUTENTICADO', t(1, 3, 0));
  assert.ok(!ok);
  assert.equal(pol.modoEfectivo(t(1, 3, 0)), 'DESCANSO');
});

test('el estado sobrevive a un reinicio', () => {
  const pol = p(opA());
  const ahora = t(0, 10, 0);
  pol.control({ k: 'VETAR', objetivo: 'g' }, 'PERSONA', ahora);
  pol.control({ k: 'PARA' }, 'PERSONA', ahora);
  pol.control({ k: 'DECLARAR_MODO', modo: { modo: 'FOCO', hasta: t(0, 12, 0) } }, 'PERSONA', ahora);
  pol.decidir(decision('x', 'h'), ahora);
  const restaurado = estadoDesdeTexto(estadoATexto(pol.estado));
  assert.notEqual(restaurado, null);
  assert.deepEqual(restaurado, pol.estado);
  const nueva = new Politica(opA(), restaurado!);
  nueva.control({ k: 'REANUDAR' }, 'PERSONA', ahora);
  const d = nueva.decidir(decision('1', 'g'), t(0, 12, 30));
  assert.ok(mismoMotivo(d.motivo, motivo('VETADO')));
});

test('un estado ilegible falla cerrado', () => {
  assert.equal(estadoDesdeTexto('parado=quizá\n'), null);
  assert.equal(estadoDesdeTexto('basura'), null);
  assert.equal(estadoDesdeTexto(''), null, 'sin versión no se acepta');
  const cab = 'soul-atencion-estado v2\n';
  assert.equal(estadoDesdeTexto(`${cab}parado=0\nclave_rara=1\n`), null, 'clave desconocida');
  assert.equal(estadoDesdeTexto(cab), null, 'sin la línea parado no se sabe si estaba parado');
  assert.equal(estadoDesdeTexto(`${cab}parado=0\nmodo=INVENTADO,-\n`), null, 'modo desconocido');
  assert.equal(estadoDesdeTexto(`${cab}parado=0\nusado=1,-3\n`), null, 'contador negativo');
  assert.notEqual(estadoDesdeTexto(`${cab}parado=0\n`), null);
});

test('un estado con líneas repetidas falla cerrado (no se levanta un PARA en silencio)', () => {
  const cab = 'soul-atencion-estado v2\nparado=1\n';
  for (const extra of [
    'parado=0', 'modo=FOCO,-\nmodo=DISPONIBLE,-', 'usado=10,1\nusado=10,0', 'usado=10,1\nusado=010,0', 'alerta_usada=10,1\nalerta_usada=10,0',
    'resumen_inicio=5\nresumen_inicio=1', 'resumen_cierre=5\nresumen_cierre=5', 'veto=g\nveto=g', 'preguntada=a\npreguntada=a',
  ]) {
    assert.equal(estadoDesdeTexto(`${cab}${extra}\n`), null, extra);
  }
  // Claves distintas del mismo tipo sí conviven.
  const ok = estadoDesdeTexto(`${cab}usado=10,1\nusado=20,2\nveto=g\nveto=h\npreguntada=a\npreguntada=b\n`);
  assert.ok(ok?.parado);
  assert.equal(ok?.usados.size, 2);
  assert.equal(ok?.vetos.size, 2);
});

// --- niveles y ledger -----------------------------------------------------

test('el contenido por encima del canal se redacta', () => {
  const pol = p(opA());
  const e = { ...conNivel(aviso('a'), 3), texto: 'contenido N3' };
  assert.ok(pol.decidir(e, t(0, 10, 0)).redactado);
  assert.equal(pol.bandeja.porEvento('a')?.texto, null);
  const f = { ...conNivel(aviso('b'), 2), texto: 'ok' };
  assert.ok(!pol.decidir(f, t(0, 10, 0)).redactado);
  assert.equal(pol.bandeja.porEvento('b')?.texto, 'ok');
});

test('el ledger cuenta lo que pide el sistema', () => {
  const pol = p(opA());
  pol.decidir(decision('1', 'g'), t(0, 10, 0));
  pol.decidir(decision('2', 'g'), t(0, 19, 0));
  pol.decidir(aviso('a'), t(0, 10, 0));
  pol.decidir(alerta('e', 'fuga-detectada'), t(1, 3, 0));
  pol.control({ k: 'PARA' }, 'PERSONA', t(1, 3, 1));
  const r = pol.ledger.resumen();
  assert.deepEqual(
    [r.preguntas, r.avisos, r.alertas, r.contactosAhora, r.contactosAhoraFueraDeVentana, r.encolados],
    [2, 1, 1, 2, 1, 2],
  );
  assert.equal(pol.ledger.entradas().length, 4);
});

test('pideDecision distingue lo que exige respuesta', () => {
  assert.ok(pideDecision(decision('1', 'g')));
  assert.ok(!pideDecision(aviso('a')));
  assert.ok(!pideDecision(deAgente('n', { k: 'NOTIFICACION' })));
});

// --- revisión de #1441: alertas vetadas o vencidas, control, franjas y estado ---------------

test('una alerta de un objetivo vetado se registra y llega al levantar el veto', () => {
  const pol = p(opA());
  const ahora = t(0, 10, 0);
  assert.ok(pol.control({ k: 'VETAR', objetivo: 'g' }, 'PERSONA', ahora));
  const ev: Evento = { ...alerta('av', 'fuga-detectada'), objetivo: 'g' };
  es(pol.decidir(ev, ahora), 'REGISTRAR', motivo('VETADO'), false);
  assert.equal(pol.bandeja.porEvento('av'), undefined);
  assert.ok(pol.control({ k: 'LEVANTAR_VETO', objetivo: 'g' }, 'PERSONA', ahora));
  es(pol.decidir(ev, ahora + 1), 'BLOQUEAR_Y_ELEVAR', motivo('ALERTA'), true);
  es(p(opA()).decidir({ ...ev, objetivo: 'otro' }, ahora), 'BLOQUEAR_Y_ELEVAR', motivo('ALERTA'), true);
});

test('una alerta con el contexto vencido se registra; un minuto antes, llega', () => {
  const ahora = t(0, 10, 0);
  es(p(opA()).decidir({ ...alerta('ac', 'fuga-detectada'), caduca: ahora }, ahora), 'REGISTRAR', motivo('CONTEXTO_VENCIDO'), false);
  es(p(opA()).decidir({ ...alerta('ad', 'fuga-detectada'), caduca: ahora + 1 }, ahora), 'BLOQUEAR_Y_ELEVAR', motivo('ALERTA'), true);
});

test('un agente autenticado puede detener y vetar; un veto vacío no se acepta', () => {
  const pol = p(opA());
  assert.ok(pol.control({ k: 'VETAR', objetivo: 'g' }, 'AGENTE_AUTENTICADO', t(0, 10, 0)));
  assert.ok(!pol.control({ k: 'VETAR', objetivo: '' }, 'PERSONA', t(0, 10, 0)));
  assert.deepEqual([...pol.estado.vetos], ['g']);
});

test('una franja con horas fuera de rango no contiene ningún minuto ni tiene inicio', () => {
  const todos = [0, 1, 2, 3, 4, 5, 6];
  for (const [i, f] of [[[24, 0], [9, 0]], [[9, 0], [9, 60]], [[-1, 0], [9, 0]], [[9.5, 0], [12, 0]], [[9, 0], [25, 0]]] as const) {
    const fr = Franja.nueva(todos, i, f);
    for (let m = 0; m < 2 * 1440; m += 30) assert.equal(fr.instancia(LUNES + m), null, `${i}-${f}`);
    assert.equal(fr.siguienteInicio(LUNES), null, `${i}-${f}`);
  }
  const limite = Franja.nueva(todos, [23, 59], [0, 0]);
  assert.equal(limite.instancia(LUNES + 23 * 60 + 59), LUNES + 23 * 60 + 59, '23:59 es válida');
});

test('una franja que cruza la medianoche contiene la madrugada del primer día', () => {
  const fr = Franja.nueva([0, 1, 2, 3, 4, 5, 6], [22, 0], [2, 0]);
  assert.equal(fr.instancia(60), -120);
  assert.equal(fr.instancia(3 * 60), null);
});

test('un estado con vetos, ids vacíos o alertas agrupadas duplicadas falla cerrado', () => {
  const cab = 'soul-atencion-estado v2\nparado=0\n';
  assert.equal(estadoDesdeTexto(`${cab}veto=\n`), null, 'veto vacío');
  assert.equal(estadoDesdeTexto(`${cab}preguntada=\n`), null, 'preguntada vacía');
  assert.equal(estadoDesdeTexto(`${cab}excedida=\n`), null, 'excedida vacía');
  assert.equal(estadoDesdeTexto(`${cab}excedida=a\nexcedida=a\n`), null, 'excedida duplicada');
  assert.equal(estadoDesdeTexto(`${cab}excedida=a%\nexcedida=a%25\n`), null, 'excedida duplicada tras decodificar');
  assert.deepEqual(estadoDesdeTexto(`${cab}excedida=a\nexcedida=b\n`)?.excedidas, ['a', 'b']);
});
