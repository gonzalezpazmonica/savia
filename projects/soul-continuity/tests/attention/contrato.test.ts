// Puente con el contrato real (src/contract): vocabulario y degradación de la ruta web.
import assert from 'node:assert/strict';
import { test } from 'node:test';

import { LEVELS, SENDER_AUTH, ROUTES, type Level } from '../../src/contract/claims.ts';
import {
  Politica, deAgente, mismoMotivo, motivo, nivelDeContrato, origenDeContrato, rutaDeContrato, type Evento,
} from '../../src/attention/index.ts';
import { alerta, aprobacion, aviso, decision, notificacion, opA, t } from './comun.ts';

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

test('solo tenant y dkim_dmarc fuera de la web autentican; en la web, nada', () => {
  const esperado: Record<string, Record<string, string>> = {
    tenant: { web: 'NO_AUTENTICADO', otra: 'AGENTE_AUTENTICADO' },
    dkim_dmarc: { web: 'NO_AUTENTICADO', otra: 'AGENTE_AUTENTICADO' },
    unauthenticated: { web: 'NO_AUTENTICADO', otra: 'NO_AUTENTICADO' },
    unknown: { web: 'DESCONOCIDO', otra: 'DESCONOCIDO' },
  };
  assert.deepEqual(Object.keys(esperado).sort(), [...SENDER_AUTH].sort(), 'la tabla cubre todo el contrato');
  for (const route of ROUTES) {
    for (const auth of SENDER_AUTH) {
      assert.equal(origenDeContrato(auth, route), esperado[auth]![route === 'web' ? 'web' : 'otra'], `${route}/${auth}`);
    }
  }
});

test('valores ausentes o desconocidos no autentican (fail-closed)', () => {
  for (const v of [null, undefined, '', 'Tenant', 'internal']) {
    assert.equal(origenDeContrato(v, 'api'), 'NO_AUTENTICADO');
  }
});

test('la ruta web se traduce a WEB y las rutas del contrato con identidad, a API', () => {
  assert.equal(rutaDeContrato('web'), 'WEB');
  for (const r of ['graph', 'api', 'local'] as const) assert.equal(rutaDeContrato(r), 'API');
  assert.deepEqual(ROUTES.filter((r) => rutaDeContrato(r) === 'API').sort(), ['api', 'graph', 'local'], 'la tabla cubre el contrato');
});

test('una ruta desconocida es WEB y no autentica (fail-closed)', () => {
  for (const r of ['WEB', 'Api', 'smtp', '', null, undefined]) {
    assert.equal(rutaDeContrato(r), 'WEB', String(r));
    assert.equal(origenDeContrato('tenant', r), 'NO_AUTENTICADO', String(r));
  }
});

test('por la web, un permiso, decisión o reintento con código de regla no se degrada a aviso', () => {
  const casos: Array<[Evento, string, string]> = [
    [deAgente('p', { k: 'PETICION_PERMISO', dentroDeContrato: false }), 'BLOQUEAR_Y_ELEVAR', 'PERMISO_ILEGITIMO'],
    [deAgente('p2', { k: 'PETICION_PERMISO', dentroDeContrato: true }), 'BLOQUEAR_Y_ELEVAR', 'PERMISO_ILEGITIMO'],
    [decision('d', 'g'), 'REGISTRAR', 'ORIGEN_NO_AUTENTICADO'],
    [aprobacion('s', 'g'), 'REGISTRAR', 'ORIGEN_NO_AUTENTICADO'],
    [deAgente('r', { k: 'REINTENTO', efectoPrevio: 'DESCONOCIDO' }), 'REGISTRAR', 'ORIGEN_NO_AUTENTICADO'],
  ];
  for (const [base, accion, mot] of casos) {
    const ev: Evento = { ...base, codigoAlerta: 'fuga-detectada', origen: 'DESCONOCIDO', ruta: 'WEB' };
    const pol = new Politica(opA());
    const d = pol.decidir(ev, t(0, 10, 0));
    assert.equal(d.accion, accion, base.id);
    assert.ok(mismoMotivo(d.motivo, motivo(mot as never)), base.id);
    assert.ok(!d.contactarAhora && !d.degradadaAAviso, base.id);
    assert.equal(pol.estado.usados.size, 0, `${base.id} no gasta presupuesto`);
  }
});

test('la ruta web nunca autentica: `unknown` es desconocido y el resto, sin autenticar', () => {
  assert.equal(origenDeContrato('unknown', 'web'), 'DESCONOCIDO');
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

// La web solo puede avisar por una regla de alerta; nada de lo que llega por ella pide una
// decisión, un permiso o una aprobación a la persona, ni gasta presupuesto (revisión de #1441).
const pideAlgo = (id: string): Array<[string, Evento]> => [
  ['DECISION', decision(id, 'g')],
  ['APROBACION_SEGURIDAD', aprobacion(`${id}a`, 'g')],
  ['PETICION_PERMISO', deAgente(`${id}p`, { k: 'PETICION_PERMISO', dentroDeContrato: true })],
  ['REINTENTO', deAgente(`${id}r`, { k: 'REINTENTO', efectoPrevio: 'DESCONOCIDO' })],
  ['NOTIFICACION', notificacion(`${id}n`)],
  ['AVISO', aviso(`${id}v`)],
];

for (const [como, origen] of [['por el puente', origenDeContrato('unknown', 'web')], ['con origen declarado', 'AGENTE_AUTENTICADO']] as const) {
  test(`por la web, ${como}, nada pide decisión ni gasta presupuesto`, () => {
    for (const [tipo, base] of pideAlgo('w')) {
      const pol = new Politica(opA());
      const d = pol.decidir({ ...base, origen, ruta: 'WEB' }, t(0, 10, 0));
      assert.ok(!d.contactarAhora, tipo);
      assert.equal(pol.estado.usados.size, 0, `${tipo}: presupuesto`);
      if (tipo === 'PETICION_PERMISO') {
        assert.equal(d.accion, 'BLOQUEAR_Y_ELEVAR', tipo);
        assert.ok(mismoMotivo(d.motivo, motivo('PERMISO_ILEGITIMO')), tipo);
      } else {
        assert.equal(d.accion, 'REGISTRAR', tipo);
        assert.ok(mismoMotivo(d.motivo, motivo('ORIGEN_NO_AUTENTICADO')), tipo);
      }
    }
  });
}

test('control: la web y lo desconocido no detienen ni vetan', () => {
  for (const origen of [origenDeContrato('unknown', 'web'), origenDeContrato('unknown', 'graph'), 'NO_AUTENTICADO'] as const) {
    const pol = new Politica(opA());
    assert.ok(!pol.control({ k: 'PARA' }, origen, t(0, 10, 0)), `${origen}: PARA`);
    assert.ok(!pol.control({ k: 'VETAR', objetivo: 'g' }, origen, t(0, 10, 0)), `${origen}: VETAR`);
    assert.ok(!pol.estado.parado && pol.estado.vetos.size === 0, origen);
  }
});

test('por API, un remitente desconocido (sin cabeceras) no alerta', () => {
  const d = new Politica(opA()).decidir(porPuente('e5', 'unknown', 'api'), t(1, 3, 0));
  assert.equal(d.accion, 'REGISTRAR');
  assert.ok(mismoMotivo(d.motivo, motivo('ORIGEN_NO_AUTENTICADO')));
  assert.ok(!d.contactarAhora && !d.degradadaAAviso);
});
