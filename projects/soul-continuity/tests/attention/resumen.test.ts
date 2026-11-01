// Revisión independiente de la PR #1441: una alerta sobre el tope sale una sola vez, sea por el
// mensaje «hay N alertas más» o por el resumen, y una regla de alerta no salta el tipo del evento.
import assert from 'node:assert/strict';
import { test } from 'node:test';

import { Politica, deAgente, mismoMotivo, motivo, type Config, type Evento } from '../../src/attention/index.ts';
import { alerta, opA, t } from './comun.ts';

const cfg = (extra: Partial<Config> = {}): Config => ({
  ...opA(),
  alertas: [{ codigo: 'todos', modos: ['DISPONIBLE', 'FOCO', 'DESCANSO', 'FUERA'] }],
  resumenes: { inicio: 8 * 60 + 30, cierre: 17 * 60 + 45 },
  ...extra,
});

const lineas = (pol: Politica, ahora: number): string[] =>
  pol.resumenesDebidos(ahora).flatMap((r) => r.grupos.flatMap((g) => g.lineas.map((l) => l.eventoId)));

test('una alerta drenada en «hay N alertas más» no vuelve en el resumen', () => {
  const pol = new Politica(cfg({ topeAlertas: 1 }));
  pol.decidir(alerta('a0', 'todos'), t(0, 10, 0));
  pol.decidir(alerta('a1', 'todos'), t(0, 10, 0));
  assert.deepEqual(pol.drenarAlertasAgrupadas()?.eventoIds, ['a1']);
  assert.deepEqual(lineas(pol, t(0, 17, 45)), [], 'a1 ya se entregó en el mensaje agrupado');
});

test('sin drenar, la alerta sobre el tope sale en el resumen y ya no en el mensaje agrupado', () => {
  const pol = new Politica(cfg({ topeAlertas: 1 }));
  pol.decidir(alerta('a0', 'todos'), t(0, 10, 0));
  pol.decidir(alerta('a1', 'todos'), t(0, 10, 0));
  pol.decidir(alerta('a2', 'todos'), t(0, 10, 0));
  assert.deepEqual(lineas(pol, t(0, 17, 45)), ['a1', 'a2']);
  assert.equal(pol.drenarAlertasAgrupadas(), null, 'el resumen ya las entregó');
});

test('un mensaje agrupado que no se entregó vuelve a estar pendiente para el resumen', () => {
  const pol = new Politica(cfg({ topeAlertas: 0 }));
  pol.decidir(alerta('r1', 'todos'), t(0, 10, 0));
  const fallido = pol.drenarAlertasAgrupadas();
  assert.ok(fallido);
  pol.reencolarAlertasAgrupadas(fallido);
  assert.equal(pol.bandeja.porEvento('r1')?.pendiente, true);
  assert.deepEqual(lineas(pol, t(0, 17, 45)), ['r1']);
  assert.equal(pol.drenarAlertasAgrupadas(), null, 'tras el resumen no se repite');
});

test('una alerta drenada y otra nueva: el resumen lleva solo la nueva', () => {
  const pol = new Politica(cfg({ topeAlertas: 0 }));
  pol.decidir(alerta('x1', 'todos'), t(0, 10, 0));
  pol.drenarAlertasAgrupadas();
  pol.decidir(alerta('x2', 'todos'), t(0, 11, 0));
  assert.deepEqual(lineas(pol, t(0, 17, 45)), ['x2']);
});

test('un permiso fuera de contrato con código de alerta de un agente autenticado se bloquea', () => {
  const pol = new Politica(cfg());
  const ev: Evento = { ...deAgente('p', { k: 'PETICION_PERMISO', dentroDeContrato: false }), codigoAlerta: 'todos' };
  const d = pol.decidir(ev, t(0, 10, 0));
  assert.equal(d.accion, 'BLOQUEAR_Y_ELEVAR');
  assert.ok(mismoMotivo(d.motivo, motivo('PERMISO_ILEGITIMO')));
  assert.ok(!mismoMotivo(d.motivo, motivo('ALERTA')));
});

test('una decisión con código de alerta se pregunta una vez y se puede responder', () => {
  const pol = new Politica(cfg());
  const ev: Evento = { ...deAgente('q', { k: 'DECISION', decisionId: 'd-q' }), codigoAlerta: 'todos' };
  const d = pol.decidir(ev, t(0, 10, 0));
  assert.equal(d.accion, 'PREGUNTAR_UNA_VEZ');
  assert.ok(mismoMotivo(pol.decidir({ ...ev, id: 'q2' }, t(0, 10, 5)).motivo, motivo('YA_PREGUNTADA')));
  assert.ok(pol.control({ k: 'RESPONDER', decisionId: 'd-q' }, 'PERSONA', t(0, 11, 0)));
});

test('un aviso con código de alerta de un agente autenticado sigue siendo alerta', () => {
  const pol = new Politica(cfg());
  const d = pol.decidir(alerta('a', 'todos'), t(0, 10, 0));
  assert.ok(mismoMotivo(d.motivo, motivo('ALERTA')));
  assert.ok(d.contactarAhora);
});
