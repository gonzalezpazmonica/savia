// Puente con el contrato real (src/contract): vocabulario y degradación de la ruta web.
import assert from 'node:assert/strict';
import { test } from 'node:test';

import { LEVELS, SENDER_AUTH, ROUTES, type Level } from '../../src/contract/claims.ts';
import {
  Politica, mismoMotivo, motivo, nivelDeContrato, origenDeContrato, rutaDeContrato, type Evento,
} from '../../src/attention/index.ts';
import { alerta, opA, t } from './comun.ts';

test('cada nivel del contrato tiene su equivalente numérico', () => {
  assert.deepEqual(LEVELS.map(nivelDeContrato), [1, 2, 3, 4]);
});

test('un nivel fuera del contrato se trata como el más confidencial (fail-closed)', () => {
  for (const v of ['N9', 'n4', '', null, undefined]) {
    assert.equal(nivelDeContrato(v as Level), 4, String(v));
  }
});

test('un nivel desconocido llega redactado al canal, en la bandeja y en las alertas agrupadas', () => {
  const pol = new Politica({ ...opA(), topeAlertas: 0 });
  const ev: Evento = { ...alerta('n', 'fuga-detectada'), nivel: nivelDeContrato('N9' as Level), texto: 'secreto' };
  const d = pol.decidir(ev, t(0, 10, 0));
  assert.ok(d.redactado);
  assert.equal(pol.bandeja.porEvento('n')?.texto, null);
  assert.ok(!JSON.stringify(pol.drenarAlertasAgrupadas()).includes('secreto'));
});

test('fuera de la web solo tenant y dkim_dmarc autentican; en la web, solo unknown', () => {
  for (const route of ROUTES) {
    for (const auth of SENDER_AUTH) {
      const esperado = route === 'web' ? auth === 'unknown' : auth === 'tenant' || auth === 'dkim_dmarc';
      assert.equal(origenDeContrato(auth, route) === 'AGENTE_AUTENTICADO', esperado, `${route}/${auth}`);
    }
  }
});

test('valores ausentes o desconocidos no autentican (fail-closed)', () => {
  for (const v of [null, undefined, '', 'Tenant', 'internal']) {
    assert.equal(origenDeContrato(v, 'api'), 'NO_AUTENTICADO');
  }
});

test('la ruta web se traduce a WEB y el resto a API', () => {
  assert.equal(rutaDeContrato('web'), 'WEB');
  for (const r of ['graph', 'api', 'local'] as const) assert.equal(rutaDeContrato(r), 'API');
});

test('la ruta web solo acepta el remitente `unknown` que fija el contrato', () => {
  assert.equal(origenDeContrato('unknown', 'web'), 'AGENTE_AUTENTICADO');
  for (const v of ['tenant', 'dkim_dmarc', 'unauthenticated', null, undefined, '']) {
    assert.equal(origenDeContrato(v, 'web'), 'NO_AUTENTICADO', String(v));
  }
});

// De extremo a extremo: cada caso con su propia política y su id, para que ninguna
// aserción pase por YA_PREGUNTADA.
const porPuente = (id: string, auth: string, route: 'api' | 'web'): Evento => ({
  ...alerta(id, 'fuga-detectada'),
  origen: origenDeContrato(auth, route),
  ruta: rutaDeContrato(route),
});

test('de extremo a extremo: remitente autenticado por API alerta en DESCANSO', () => {
  const d = new Politica(opA()).decidir(porPuente('e1', 'tenant', 'api'), t(1, 3, 0));
  assert.equal(d.accion, 'BLOQUEAR_Y_ELEVAR');
  assert.ok(mismoMotivo(d.motivo, motivo('ALERTA')));
  assert.ok(d.contactarAhora && !d.degradadaAAviso);
});

test('de extremo a extremo: remitente sin autenticar por API se registra y no alerta', () => {
  const d = new Politica(opA()).decidir(porPuente('e2', 'unauthenticated', 'api'), t(1, 3, 0));
  assert.equal(d.accion, 'REGISTRAR');
  assert.ok(mismoMotivo(d.motivo, motivo('ORIGEN_NO_AUTENTICADO')));
  assert.ok(!d.contactarAhora);
});

test('de extremo a extremo: por web la alerta baja a aviso (diferido de noche, avisado en ventana)', () => {
  const noche = new Politica(opA()).decidir(porPuente('e3', 'unknown', 'web'), t(1, 3, 0));
  assert.ok(noche.degradadaAAviso);
  assert.equal(noche.accion, 'AGRUPAR');
  assert.ok(!noche.contactarAhora);
  const ventana = new Politica(opA()).decidir(porPuente('e4', 'unknown', 'web'), t(0, 10, 0));
  assert.ok(ventana.degradadaAAviso);
  assert.equal(ventana.accion, 'AVISAR');
  assert.ok(mismoMotivo(ventana.motivo, motivo('DISPONIBLE')));
});
