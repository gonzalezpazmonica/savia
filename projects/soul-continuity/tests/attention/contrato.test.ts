// Puente con el contrato real (src/contract): vocabulario y degradación de la ruta web.
import assert from 'node:assert/strict';
import { test } from 'node:test';

import { LEVELS, SENDER_AUTH, ROUTES, type Level } from '../../src/contract/claims.ts';
import {
  Politica, nivelDeContrato, origenDeContrato, rutaDeContrato, type Evento,
} from '../../src/attention/index.ts';
import { alerta, opA, t } from './comun.ts';

test('cada nivel del contrato tiene su equivalente numérico', () => {
  assert.deepEqual(LEVELS.map(nivelDeContrato), [1, 2, 3, 4]);
});

test('un nivel fuera del contrato no se traduce a un nivel válido', () => {
  assert.equal(nivelDeContrato('N9' as Level), undefined);
});

test('solo tenant y dkim_dmarc fuera de la web autentican', () => {
  for (const route of ROUTES) {
    for (const auth of SENDER_AUTH) {
      const esperado = route !== 'web' && (auth === 'tenant' || auth === 'dkim_dmarc');
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

test('de extremo a extremo: remitente autenticado alerta en DESCANSO; sin autenticar o por web no', () => {
  const pol = new Politica(opA());
  const ev = (auth: string, route: 'api' | 'web'): Evento => ({
    ...alerta('e', 'fuga-detectada'),
    origen: origenDeContrato(auth, route),
    ruta: rutaDeContrato(route),
  });
  const noche = t(1, 3, 0);
  assert.ok(pol.decidir(ev('tenant', 'api'), noche).contactarAhora);
  assert.ok(!pol.decidir(ev('unauthenticated', 'api'), noche).contactarAhora);
  assert.ok(!pol.decidir(ev('tenant', 'web'), noche).contactarAhora);
});
