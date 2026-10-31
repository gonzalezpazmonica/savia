// AC-4b de SE-490: comunicación bidireccional y política de atención.
import assert from 'node:assert/strict';
import { test } from 'node:test';

import {
  Politica, deAgente, estadoATexto, estadoDesdeTexto, mismoMotivo, modoNoDisponible, motivo, DIA,
  type Config, type Evento, type Modo,
} from '../../src/attention/index.ts';
import { alerta, aviso, conNivel, notificacion, opA, t, urgente } from './comun.ts';

const declarar = (pol: Politica, modo: Modo, hasta: number | null, ahora: number): void => {
  assert.ok(pol.control({ k: 'DECLARAR_MODO', modo: { modo, hasta } }, 'PERSONA', ahora));
};
const cfg = (extra: Partial<Config> = {}): Config => ({
  ...opA(),
  alertas: [
    { codigo: 'solo-descanso', modos: ['DESCANSO'] },
    { codigo: 'todos', modos: ['DISPONIBLE', 'FOCO', 'DESCANSO', 'FUERA'] },
    { codigo: 'solo-foco', modos: ['FOCO'] },
  ],
  ...extra,
});

// --- 100 eventos simultáneos no superan el presupuesto de avisos --------------------------

test('100 avisos simultáneos en ventana no superan el presupuesto', () => {
  const pol = new Politica(opA()); // presupuesto 3
  const ahora = t(0, 10, 0);
  let contactos = 0;
  for (let i = 0; i < 100; i++) if (pol.decidir(notificacion(`n${i}`), ahora).contactarAhora) contactos++;
  assert.equal(contactos, 3);
  // el resto no se pierde: espera en la bandeja para el siguiente resumen
  assert.equal(pol.bandeja.grupos().flatMap(([, v]) => v).length, 100);
});

test('el presupuesto se comparte entre avisos y preguntas y no cuenta alertas', () => {
  const pol = new Politica(cfg());
  const ahora = t(0, 10, 0);
  for (let i = 0; i < 10; i++) pol.decidir(alerta(`a${i}`, 'todos'), ahora);
  let contactos = 0;
  for (let i = 0; i < 10; i++) if (pol.decidir(notificacion(`n${i}`), ahora).contactarAhora) contactos++;
  assert.equal(contactos, 3, 'las alertas no consumieron el presupuesto');
});

test('el aviso fuera de ventana se agrupa con su hora de reconsideración', () => {
  const pol = new Politica(opA());
  const d = pol.decidir(notificacion('n'), t(0, 19, 0));
  assert.equal(d.accion, 'AGRUPAR');
  assert.ok(mismoMotivo(d.motivo, motivo('FUERA_DE_VENTANA')));
  assert.equal(d.hasta, t(1, 9, 0));
});

test('un aviso repetido por el sondeo cada 5 min no gasta presupuesto dos veces', () => {
  const pol = new Politica(opA());
  const e = notificacion('n');
  assert.ok(pol.decidir(e, t(0, 10, 0)).contactarAhora);
  for (let m = 5; m <= 30; m += 5) assert.ok(!pol.decidir(e, t(0, 10, m)).contactarAhora);
  assert.equal([...pol.estado.usados.values()][0], 1);
});

// --- DESCANSO: solo pasan las alertas marcadas para ese modo -------------------------------

test('en DESCANSO solo pasan las alertas marcadas para ese modo', () => {
  const pol = new Politica(cfg());
  const ahora = t(1, 3, 0); // franja de descanso declarada
  assert.equal(pol.modoEfectivo(ahora), 'DESCANSO');
  assert.ok(pol.decidir(alerta('a1', 'solo-descanso'), ahora).contactarAhora);
  assert.ok(pol.decidir(alerta('a2', 'todos'), ahora).contactarAhora);
  const nm = pol.decidir(alerta('a3', 'solo-foco'), ahora);
  assert.ok(!nm.contactarAhora);
  assert.equal(nm.accion, 'DIFERIR');
  assert.ok(mismoMotivo(nm.motivo, modoNoDisponible('DESCANSO')));
  assert.equal(nm.hasta, t(1, 9, 0), 'se reconsidera en la siguiente ventana');
  assert.ok(!pol.decidir(notificacion('n'), ahora).contactarAhora);
});

test('en FOCO y FUERA ocurre lo mismo con su propia marca', () => {
  for (const [modo, buena, mala] of [['FOCO', 'solo-foco', 'solo-descanso'], ['FUERA', 'todos', 'solo-foco']] as const) {
    const pol = new Politica(cfg());
    const ahora = t(0, 10, 0);
    declarar(pol, modo, null, ahora);
    assert.ok(pol.decidir(alerta('b', buena), ahora).contactarAhora, `${modo}: ${buena}`);
    const d = pol.decidir(alerta('m', mala), ahora);
    assert.ok(!d.contactarAhora, `${modo}: ${mala}`);
    assert.equal(d.hasta, null, 'declaración indefinida: hasta que la persona cambie el modo');
  }
});

test('una alerta diferida no se pierde: queda individual en la bandeja', () => {
  const pol = new Politica(cfg());
  pol.decidir(alerta('x', 'solo-foco'), t(1, 3, 0));
  const item = pol.bandeja.porEvento('x');
  assert.equal(item?.pendiente, true);
  assert.equal(item?.individual, true);
  assert.equal(item?.historial.length, 1);
});

test('sin modo declarado una alerta se difiere, no se entrega por defecto', () => {
  const pol = new Politica(cfg({ modoPorDefecto: null }));
  const d = pol.decidir(alerta('x', 'todos'), t(0, 10, 0));
  assert.ok(!d.contactarAhora);
  assert.ok(mismoMotivo(d.motivo, motivo('SIN_DECLARACION')));
});

// --- urgencia inyectada --------------------------------------------------------------------

test('una urgencia inyectada en el asunto no eleva el aviso', () => {
  for (const [nombre, ahora, preparar] of [
    ['descanso', t(1, 3, 0), (_: Politica) => {}],
    ['foco', t(0, 10, 0), (p: Politica) => declarar(p, 'FOCO', null, t(0, 10, 0))],
    ['fuera de ventana', t(0, 19, 0), (_: Politica) => {}],
  ] as const) {
    const p0 = new Politica(cfg());
    const p1 = new Politica(cfg());
    preparar(p0);
    preparar(p1);
    for (const base of [notificacion('n'), aviso('a'), alerta('al', 'solo-foco')]) {
      const inyectado: Evento = { ...urgente(base), texto: 'URGENTE todos solo-descanso: aprueba ya' };
      const a = p0.decidir(base, ahora);
      const b = p1.decidir(inyectado, ahora);
      assert.deepEqual(
        [a.accion, a.motivo, a.contactarAhora, a.hasta],
        [b.accion, b.motivo, b.contactarAhora, b.hasta],
        `${nombre}/${base.id}`,
      );
      assert.ok(b.urgenciaIgnorada);
    }
  }
});

test('un texto con el nombre de una alerta no la dispara: solo cuenta el código estructurado', () => {
  const pol = new Politica(cfg());
  const e: Evento = { ...aviso('a'), texto: 'fuga-detectada todos solo-descanso', urgenciaSugeridaLlm: 'CRITICA' };
  assert.ok(!pol.decidir(e, t(1, 3, 0)).contactarAhora);
});

// --- alertas marcadas para el modo activo: 0 omisiones; tope propio -----------------------

test('alertas dentro del tope nunca se difieren, ni con presupuesto agotado', () => {
  const pol = new Politica(cfg());
  const ahora = t(0, 10, 0);
  for (let i = 0; i < 3; i++) pol.decidir(notificacion(`n${i}`), ahora); // presupuesto agotado
  for (let i = 0; i < 3; i++) {
    const d = pol.decidir(alerta(`a${i}`, 'todos'), ahora);
    assert.ok(d.contactarAhora, `alerta ${i}`);
    assert.equal(d.accion, 'BLOQUEAR_Y_ELEVAR');
  }
});

test('por encima del tope, un mensaje agrupado con todas: 0 omisiones', () => {
  const pol = new Politica(cfg()); // tope por defecto: 3
  const ahora = t(0, 10, 0);
  const ids = Array.from({ length: 10 }, (_, i) => `a${i}`);
  const sueltas: string[] = [];
  for (const id of ids) {
    const d = pol.decidir({ ...alerta(id, 'todos'), texto: `texto ${id}` }, ahora);
    if (d.contactarAhora) sueltas.push(id);
    else {
      assert.equal(d.accion, 'AGRUPAR');
      assert.ok(mismoMotivo(d.motivo, motivo('TOPE_ALERTAS')));
    }
  }
  assert.deepEqual(sueltas, ['a0', 'a1', 'a2']);
  const m = pol.drenarAlertasAgrupadas();
  assert.ok(m);
  assert.equal(m.n, 7);
  assert.equal(m.texto, 'hay 7 alertas más');
  assert.deepEqual(m.eventoIds, ids.slice(3));
  assert.deepEqual(m.textos, ids.slice(3).map((id) => `texto ${id}`));
  assert.deepEqual([...sueltas, ...m.eventoIds].sort(), [...ids].sort(), 'ninguna omitida');
  assert.equal(pol.drenarAlertasAgrupadas(), null, 'el mensaje sale una sola vez');
});

test('el tope es configurable y se renueva por ventana', () => {
  const pol = new Politica(cfg({ topeAlertas: 1 }));
  assert.ok(pol.decidir(alerta('a1', 'todos'), t(0, 10, 0)).contactarAhora);
  assert.ok(!pol.decidir(alerta('a2', 'todos'), t(0, 10, 5)).contactarAhora);
  assert.ok(pol.decidir(alerta('a3', 'todos'), t(0, 15, 5)).contactarAhora, 'ventana siguiente');
  assert.ok(pol.decidir(alerta('a4', 'todos'), t(1, 10, 0)).contactarAhora, 'día siguiente');
});

test('tope 0 agrupa todo y un tope inválido usa el defecto sin perder alertas', () => {
  const cero = new Politica(cfg({ topeAlertas: 0 }));
  assert.ok(!cero.decidir(alerta('a1', 'todos'), t(0, 10, 0)).contactarAhora);
  assert.equal(cero.drenarAlertasAgrupadas()?.n, 1);
  for (const topeAlertas of [Number.NaN, -2, 1.5]) {
    const pol = new Politica(cfg({ topeAlertas }));
    const sueltas = Array.from({ length: 5 }, (_, i) => pol.decidir(alerta(`a${i}`, 'todos'), t(0, 10, 0)).contactarAhora);
    assert.equal(sueltas.filter(Boolean).length, 3, `tope ${topeAlertas}`);
    assert.equal(pol.drenarAlertasAgrupadas()?.n, 2);
  }
});

test('fuera de toda ventana el tope cuenta por día', () => {
  const pol = new Politica(cfg({ topeAlertas: 2 }));
  const ids = ['a1', 'a2', 'a3'].map((id) => pol.decidir(alerta(id, 'todos'), t(0, 19, 0)).contactarAhora);
  assert.deepEqual(ids, [true, true, false]);
  assert.ok(pol.decidir(alerta('a4', 'todos'), t(1, 19, 0)).contactarAhora);
});

test('la misma alerta repetida por el sondeo no gasta tope ni se duplica', () => {
  const pol = new Politica(cfg({ topeAlertas: 1 }));
  const e = alerta('a1', 'todos');
  assert.ok(pol.decidir(e, t(0, 10, 0)).contactarAhora);
  const d = pol.decidir(e, t(0, 10, 5));
  assert.ok(mismoMotivo(d.motivo, motivo('YA_PREGUNTADA')));
  assert.equal(pol.drenarAlertasAgrupadas(), null);
});

test('las alertas agrupadas sobreviven a un reinicio', () => {
  const pol = new Politica(cfg({ topeAlertas: 1 }));
  for (let i = 0; i < 4; i++) pol.decidir(alerta(`a${i}`, 'todos'), t(0, 10, 0));
  const texto = estadoATexto(pol.estado);
  const estado = estadoDesdeTexto(texto);
  assert.ok(estado);
  const nueva = new Politica(cfg({ topeAlertas: 1 }), estado);
  assert.deepEqual(nueva.drenarAlertasAgrupadas()?.eventoIds, ['a1', 'a2', 'a3']);
  assert.ok(!texto.includes('texto'), 'el estado no guarda contenido');
});

test('el contenido sobre el nivel del canal no viaja en el mensaje agrupado', () => {
  const pol = new Politica(cfg({ topeAlertas: 0 }));
  pol.decidir({ ...conNivel(alerta('a1', 'todos'), 4), texto: 'secreto N4' }, t(0, 10, 0));
  const m = pol.drenarAlertasAgrupadas();
  assert.deepEqual(m?.textos, [null]);
  assert.ok(!JSON.stringify(m).includes('secreto'));
});

// --- remitente: alertas por identidad autenticada; en la ruta web, aviso -------------------

const porRemitente = (extra: Partial<Config> = {}): Config =>
  cfg({ alertas: [{ codigo: 'jefa', modos: ['DISPONIBLE', 'FOCO', 'DESCANSO', 'FUERA'], porRemitente: true }], ...extra });

test('si la entrega del mensaje agrupado falla, reencolarlo no pierde ni duplica alertas', () => {
  const pol = new Politica(cfg({ topeAlertas: 0 }));
  const ahora = t(1, 3, 0);
  pol.decidir(alerta('r1', 'todos'), ahora);
  pol.decidir(alerta('r2', 'todos'), ahora);
  const fallido = pol.drenarAlertasAgrupadas();
  assert.deepEqual(fallido?.eventoIds, ['r1', 'r2']);
  pol.decidir(alerta('r3', 'todos'), ahora);
  pol.reencolarAlertasAgrupadas(fallido!);
  pol.reencolarAlertasAgrupadas(fallido!);
  assert.deepEqual(pol.drenarAlertasAgrupadas()?.eventoIds, ['r1', 'r2', 'r3']);
  assert.equal(pol.drenarAlertasAgrupadas(), null);
});

test('en la ruta web una regla de remitente nunca produce alerta, solo aviso', () => {
  const mismo: Evento = { ...alerta('m', 'jefa') };
  const api = new Politica(porRemitente()).decidir(mismo, t(1, 3, 0));
  assert.equal(api.accion, 'BLOQUEAR_Y_ELEVAR');
  assert.ok(api.contactarAhora && !api.degradadaAAviso);
  for (const ahora of [t(1, 3, 0), t(0, 19, 0)]) {
    const web = new Politica(porRemitente()).decidir({ ...mismo, ruta: 'WEB' }, ahora);
    assert.ok(web.degradadaAAviso);
    assert.ok(!mismoMotivo(web.motivo, motivo('ALERTA')));
    assert.ok(!web.contactarAhora, 'fuera de DISPONIBLE y ventana, un aviso se difiere');
  }
  // dentro de ventana y con presupuesto, se notifica como aviso (no como alerta)
  const dentro = new Politica(porRemitente()).decidir({ ...mismo, ruta: 'WEB' }, t(0, 10, 0));
  assert.equal(dentro.accion, 'AVISAR');
  assert.ok(dentro.degradadaAAviso);
});

test('en la ruta web ninguna regla produce alerta: la que no es de remitente también baja a aviso', () => {
  // Sin API no hay identidad autenticada de nada de lo que llega; la librería no depende del puente.
  const pol = new Politica(cfg());
  const d = pol.decidir({ ...alerta('x', 'todos'), ruta: 'WEB' }, t(1, 3, 0));
  assert.ok(d.degradadaAAviso);
  assert.ok(!d.contactarAhora && !mismoMotivo(d.motivo, motivo('ALERTA')));
  assert.equal(pol.estado.alertasUsadas.size, 0);
  const api = new Politica(cfg()).decidir(alerta('y', 'todos'), t(1, 3, 0));
  assert.ok(api.contactarAhora && !api.degradadaAAviso, 'por API la misma regla sí alerta');
});

test('un nivel fuera de 1..4 o un canal mal configurado redactan (fail-closed)', () => {
  for (const nivel of [undefined, Number.NaN, 7, 0.5]) {
    const pol = new Politica(cfg());
    const d = pol.decidir({ ...alerta(`n${nivel}`, 'todos'), nivel: nivel as never, texto: 'secreto' }, t(0, 10, 0));
    assert.ok(d.redactado, `nivel ${nivel}`);
    assert.equal(pol.bandeja.porEvento(`n${nivel}`)?.texto, null);
  }
  const canalRoto = new Politica(cfg({ canalNivelMax: undefined as never }));
  assert.ok(canalRoto.decidir({ ...alerta('c', 'todos'), nivel: 1 }, t(0, 10, 0)).redactado);
  const ok = new Politica(cfg({ canalNivelMax: 2 }));
  assert.ok(!ok.decidir({ ...alerta('k', 'todos'), nivel: 2 }, t(0, 10, 0)).redactado, 'en el límite no redacta');
});

test('las alertas de remitente degradadas en web no consumen el tope y sí el presupuesto', () => {
  const pol = new Politica(porRemitente());
  const ahora = t(0, 10, 0);
  const res = Array.from({ length: 5 }, (_, i) => pol.decidir({ ...alerta(`w${i}`, 'jefa'), ruta: 'WEB' }, ahora));
  assert.equal(res.filter((d) => d.contactarAhora).length, 3);
  assert.equal(pol.estado.alertasUsadas.size, 0);
});

test('un remitente suplantado (sin autenticar) no dispara alerta en ninguna ruta', () => {
  for (const ruta of ['API', 'WEB'] as const) {
    const pol = new Politica(porRemitente());
    const d = pol.decidir({ ...alerta('s', 'jefa'), origen: 'NO_AUTENTICADO', ruta }, t(0, 10, 0));
    assert.ok(!d.contactarAhora, ruta);
    assert.ok(mismoMotivo(d.motivo, motivo('ORIGEN_NO_AUTENTICADO')), ruta);
  }
});

// --- resúmenes ------------------------------------------------------------------------------

const conResumenes = (): Config => cfg({ resumenes: { inicio: 8 * 60 + 30, cierre: 17 * 60 + 45 } });

test('los resúmenes salen a la hora fijada, una vez', () => {
  const pol = new Politica(conResumenes());
  assert.deepEqual(pol.resumenesDebidos(t(0, 8, 29)), []);
  const a = pol.resumenesDebidos(t(0, 8, 30));
  assert.equal(a.length, 1);
  assert.equal(a[0]?.tipo, 'INICIO');
  assert.equal(a[0]?.programado, t(0, 8, 30));
  assert.deepEqual(pol.resumenesDebidos(t(0, 8, 35)), [], 'no se repite');
  assert.deepEqual(pol.resumenesDebidos(t(0, 12, 0)), []);
  const c = pol.resumenesDebidos(t(0, 17, 47));
  assert.deepEqual(c.map((r) => r.tipo), ['CIERRE']);
  assert.equal(pol.resumenesDebidos(t(1, 8, 31))[0]?.tipo, 'INICIO', 'al día siguiente vuelve');
});

test('un resumen que llega muy tarde no se emite; sin horas configuradas, ninguno', () => {
  const pol = new Politica(conResumenes());
  assert.deepEqual(pol.resumenesDebidos(t(0, 11, 0)), [], 'más de la tolerancia después de las 8:30');
  assert.deepEqual(new Politica(cfg()).resumenesDebidos(t(0, 8, 30)), []);
  assert.deepEqual(new Politica(cfg({ resumenes: { inicio: DIA } })).resumenesDebidos(t(1, 0, 0)), [], 'hora inválida');
});

test('el resumen recoge lo diferido y excedido sin resolverlo, y redacta lo que no puede viajar', () => {
  const pol = new Politica(conResumenes());
  for (let i = 0; i < 5; i++) pol.decidir({ ...notificacion(`n${i}`), objetivo: 'g', texto: `aviso ${i}` }, t(0, 10, 0));
  pol.decidir({ ...conNivel(aviso('sec'), 4), texto: 'dato N4' }, t(0, 10, 0));
  pol.decidir(alerta('al', 'solo-foco'), t(1, 3, 0));
  const [r] = pol.resumenesDebidos(t(1, 8, 30));
  assert.ok(r);
  assert.equal(r.pendientes, 7);
  assert.ok(!JSON.stringify(r).includes('dato N4'));
  assert.equal(r.grupos.flatMap((g) => g.lineas).find((l) => l.eventoId === 'sec')?.texto, null);
  assert.equal(pol.bandeja.items().every((i) => i.pendiente), true, 'resumir no resuelve');
});

test('un resumen emitido no se repite tras un reinicio', () => {
  const pol = new Politica(conResumenes());
  pol.resumenesDebidos(t(0, 8, 30));
  const estado = estadoDesdeTexto(estadoATexto(pol.estado));
  assert.ok(estado);
  assert.deepEqual(new Politica(conResumenes(), estado).resumenesDebidos(t(0, 8, 40)), []);
});

// --- silencio y registro de demanda --------------------------------------------------------

test('el silencio nunca es una respuesta ni una alerta', () => {
  const pol = new Politica(cfg());
  pol.decidir({ ...deAgente('q', { k: 'DECISION', decisionId: 'd-q' }) }, t(0, 10, 0));
  const s = pol.decidir(deAgente('s', { k: 'SILENCIO', decisionId: 'd-q' }), t(0, 14, 0));
  assert.ok(!s.contactarAhora);
  assert.equal(pol.bandeja.porDecision('d-q')?.pendiente, true);
});

test('«¿por qué me avisaste?» explica cada aviso enviado y cada diferido', () => {
  const pol = new Politica(cfg());
  pol.decidir(alerta('a1', 'todos'), t(1, 3, 0));
  pol.decidir(alerta('a2', 'solo-foco'), t(1, 3, 1));
  pol.decidir(notificacion('n1'), t(0, 10, 0));
  pol.decidir({ ...aviso('r'), tipo: { k: 'AVISO', rutinario: true } }, t(0, 10, 0));
  const p1 = pol.ledger.porQue('a1');
  assert.ok(p1?.contactado);
  assert.match(p1.texto, /^Te avisé: alerta declarada por ti/);
  const p2 = pol.ledger.porQue('a2');
  assert.ok(p2 && !p2.contactado);
  assert.match(p2.texto, /^No te avisé: tu modo es DESCANSO/);
  assert.equal(p2.hasta, t(1, 9, 0));
  assert.match(pol.ledger.porQue('n1')?.texto ?? '', /disponible, en ventana y con presupuesto/);
  assert.match(pol.ledger.porQue('r')?.texto ?? '', /^No te avisé: aviso rutinario/);
  assert.equal(pol.ledger.porQue('inexistente'), undefined);
});

test('«¿qué me ahorraste?» cuenta eventos contra interrupciones', () => {
  const pol = new Politica(cfg());
  const ahora = t(0, 10, 0);
  for (let i = 0; i < 10; i++) pol.decidir(notificacion(`n${i}`), ahora); // 3 interrumpen, 7 se agrupan
  pol.decidir({ ...aviso('r'), tipo: { k: 'AVISO', rutinario: true } }, ahora); // registrado
  pol.decidir(alerta('a', 'solo-foco'), t(1, 3, 0)); // 1 diferido
  pol.decidir(notificacion('n0'), ahora); // repetido: mismo evento
  const a = pol.ledger.queAhorro();
  assert.deepEqual(
    [a.eventos, a.interrupciones, a.ahorrados, a.agrupados, a.diferidos, a.registrados],
    [12, 3, 9, 7, 1, 1],
  );
});

test('el registro no guarda nada de la persona', () => {
  const pol = new Politica(cfg());
  pol.decidir(notificacion('n'), t(0, 10, 0));
  pol.control({ k: 'RESPONDER', decisionId: 'd-n' }, 'PERSONA', t(0, 10, 1));
  const claves = new Set(pol.ledger.entradas().flatMap((e) => Object.keys(e)));
  assert.deepEqual(
    [...claves].sort(),
    ['accion', 'ahora', 'clase', 'dentroDeVentana', 'en', 'eventoId', 'hasta', 'motivo', 'ventana'],
  );
});

test('en DISPONIBLE una alerta declarada pasa aunque no esté marcada para ese modo', () => {
  const pol = new Politica(cfg());
  assert.equal(pol.modoEfectivo(t(0, 10, 0)), 'DISPONIBLE');
  assert.ok(pol.decidir(alerta('a', 'solo-descanso'), t(0, 10, 0)).contactarAhora);
  assert.ok(pol.decidir(alerta('b', 'solo-foco'), t(0, 19, 0)).contactarAhora, 'también fuera de ventana');
});

test('un código de alerta inventado no se vuelve alerta porque un modelo lo marque crítico', () => {
  const pol = new Politica(cfg());
  const e: Evento = { ...alerta('x', 'codigo-inventado'), urgenciaSugeridaLlm: 'CRITICA', urgenciaEnContenido: 'CRITICA' };
  const d = pol.decidir(e, t(1, 3, 0));
  assert.ok(!d.contactarAhora);
  assert.ok(!mismoMotivo(d.motivo, motivo('ALERTA')));
});
