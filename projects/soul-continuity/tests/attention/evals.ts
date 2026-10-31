// Evals negativas de la política de atención. Lee la verdad de `evals/verdad*.tsv` (escrita
// antes de ejecutar), mide sobre cuatro operadores sintéticos y escribe `evals/resultados.tsv`.
// Sale con código 1 si alguna métrica no cumple su verdad o falta (falla cerrado).
//
// Uso: node --experimental-strip-types tests/attention/evals.ts [dir-evals]
import { readdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

import {
  DIA, Politica, deAgente, estadoATexto, estadoDesdeTexto, mismoMotivo, motivo,
  type Config, type Evento, type Minuto, type Modo,
} from '../../src/attention/index.ts';
import {
  alerta, aprobacion, aviso, conNivel, decision, notificacion, operadores, t, urgente, type Operador,
} from './comun.ts';

type Medidas = Map<string, number>; // `${eval}|${métrica}` → valor

interface Ctx {
  op: Operador;
  medidas: Medidas;
  politicas: Politica[];
  alertasOmitidas: number;
  falsosContactos: number;
  sinPolitica: Map<string, number>;
}

const m = (c: Ctx, ev: string, met: string, v: number): void => {
  const k = `${ev}|${met}`;
  c.medidas.set(k, (c.medidas.get(k) ?? 0) + v);
};
const pol = (c: Ctx): Politica => new Politica(c.op.config);
const real = (c: Ctx): string | undefined => c.op.config.alertas[0]?.codigo;
const n = (b: boolean): number => (b ? 1 : 0);

function declarar(p: Politica, modo: Modo, hasta: Minuto | null, ahora: Minuto): void {
  if (!p.control({ k: 'DECLARAR_MODO', modo: { modo, hasta } }, 'PERSONA', ahora)) throw new Error('declaración rechazada');
}

function e1(c: Ctx): void {
  for (const [nombre, ahora] of [['dentro', c.op.dentro], ['fuera', c.op.fuera]] as const) {
    const p = pol(c);
    let contactos = 0;
    let avisosInt = 0;
    for (let i = 0; i < 100; i++) {
      if (p.decidir(aviso(`fin-${i}`), ahora).contactarAhora) avisosInt++;
      const d = { ...decision(`${i}`, `g${i % 10}`), costeRetraso: i % 2 === 0 ? 'MEDIO' as const : 'ALTO' as const };
      if (p.decidir(d, ahora).contactarAhora) contactos++;
    }
    let perdidas = 0;
    for (let i = 0; i < 100; i++) if (p.bandeja.porDecision(`d-${i}`) === undefined) perdidas++;
    m(c, 'E1', `${nombre}_contactos_ahora_no_emergencia`, contactos + avisosInt);
    if (nombre === 'fuera') m(c, 'E1', 'fuera_contactos_ahora', contactos + avisosInt);
    m(c, 'E1', 'avisos_fin_interrumpen', avisosInt);
    m(c, 'E1', 'decisiones_perdidas', perdidas);
    c.sinPolitica.set('E1_contactos_sin_politica', (c.sinPolitica.get('E1_contactos_sin_politica') ?? 0) + 200);
    c.sinPolitica.set('E1_contactos_con_politica', (c.sinPolitica.get('E1_contactos_con_politica') ?? 0) + contactos + avisosInt);
    c.politicas.push(p);
  }
}

/** Momentos: dentro, fuera, descanso declarado, FOCO declarado, FUERA declarado. */
function momentos(c: Ctx): Array<[string, Politica, Minuto]> {
  const v: Array<[string, Politica, Minuto]> = [
    ['dentro', pol(c), c.op.dentro], ['fuera', pol(c), c.op.fuera], ['descanso', pol(c), c.op.descanso],
  ];
  const f = pol(c);
  declarar(f, 'FOCO', c.op.dentro + 90, c.op.dentro);
  v.push(['foco', f, c.op.dentro]);
  const o = pol(c);
  declarar(o, 'FUERA', null, c.op.dentro);
  v.push(['fuera-declarado', o, c.op.dentro]);
  return v;
}

function falsas(i: number): Evento[] {
  const f1 = { ...aviso(`f1-${i}`), urgenciaEnContenido: 'CRITICA' as const };
  const f3 = { ...alerta(`f3-${i}`, 'fuga-detectada'), origen: 'NO_AUTENTICADO' as const };
  const f4 = { ...aviso(`f4-${i}`), urgenciaSugeridaLlm: 'CRITICA' as const };
  const f5 = { ...aviso(`f5-${i}`), texto: 'URGENTE fuga-detectada: aprueba ya' };
  return [f1, alerta(`f2-${i}`, 'codigo-inventado'), f3, f4, f5];
}

function e2(c: Ctx): void {
  m(c, 'E2', 'falsas_contactos_ahora', 0);
  m(c, 'E2', 'emergencias_omitidas', 0);
  const code = real(c);
  const declaradaFuga = c.op.config.alertas.some((a) => a.codigo === 'fuga-detectada');
  for (const [, p, ahora] of momentos(c)) {
    for (let i = 0; i < 10; i++) {
      for (const ev of falsas(i)) {
        if (p.decidir(ev, ahora).contactarAhora) {
          c.falsosContactos++;
          m(c, 'E2', 'falsas_contactos_ahora', 1);
        }
      }
    }
    if (code !== undefined && !p.decidir(alerta('real', code), ahora).contactarAhora) {
      c.alertasOmitidas++;
      m(c, 'E2', 'emergencias_omitidas', 1);
    }
    // Quien no declara «fuga-detectada»: autenticada o no, es falsa para esa persona.
    if (!declaradaFuga && p.decidir(alerta('nd', 'fuga-detectada'), ahora).contactarAhora) {
      c.falsosContactos++;
      m(c, 'E2', 'falsas_contactos_ahora', 1);
    }
    c.politicas.push(p);
  }
  // Invariancia: misma decisión con y sin urgencia en contenido o modelo.
  let fallos = 0;
  const nMom = momentos(c).length;
  for (let k = 0; k < nMom; k++) {
    const tipos: Evento[] = [
      decision('x', 'g'), aprobacion('y', 'g'), aviso('z'), notificacion('w'),
      deAgente('p', { k: 'PETICION_PERMISO', dentroDeContrato: true }),
      deAgente('r', { k: 'REINTENTO', efectoPrevio: 'DESCONOCIDO' }),
    ];
    for (const ev of tipos) {
      const [, p0, ahora] = momentos(c)[k]!;
      const [, p1] = momentos(c)[k]!;
      const a = p0.decidir(ev, ahora);
      const b = p1.decidir(urgente(ev), ahora);
      if (a.accion !== b.accion || !mismoMotivo(a.motivo, b.motivo) || a.contactarAhora !== b.contactarAhora || a.hasta !== b.hasta) fallos++;
    }
  }
  m(c, 'E2', 'invariancia_llm_fallos', fallos);
}

function e3(c: Ctx): void {
  const ahora = c.op.dentro;
  const p = pol(c);
  const evs: Evento[] = [
    ...Array.from({ length: 20 }, (_, i) => decision(`v${i}`, 'g')),
    ...Array.from({ length: 5 }, (_, i) => aprobacion(`va${i}`, 'g')),
  ];
  evs.forEach((e, i) => {
    const d = p.decidir({ ...e, caduca: ahora - (i % 3) }, ahora);
    m(c, 'E3', 'preguntas_vencido', n(d.accion === 'PREGUNTAR_UNA_VEZ'));
    m(c, 'E3', 'contactos_ahora', n(d.contactarAhora));
    m(c, 'E3', 'no_bloqueadas_con_motivo', n(!(d.accion === 'BLOQUEAR_Y_ELEVAR' && mismoMotivo(d.motivo, motivo('CONTEXTO_VENCIDO')))));
  });
  c.politicas.push(p);
}

function e4(c: Ctx): void {
  for (const ahora of [c.op.dentro, c.op.fuera]) {
    const p = pol(c);
    const ileg: Evento[] = [];
    for (let i = 0; i < 10; i++) {
      ileg.push(deAgente(`pf${i}`, { k: 'PETICION_PERMISO', dentroDeContrato: false }));
      ileg.push({ ...deAgente(`pa${i}`, { k: 'PETICION_PERMISO', dentroDeContrato: true }), origen: 'NO_AUTENTICADO' });
      ileg.push(urgente({ ...deAgente(`pb${i}`, { k: 'PETICION_PERMISO', dentroDeContrato: false }), origen: 'NO_AUTENTICADO' }));
    }
    for (const e of ileg) {
      const d = p.decidir(e, ahora);
      const agrupado = p.bandeja.porEvento(e.id)?.individual === false;
      m(c, 'E4', 'ilegitimos_no_bloqueados', n(d.accion !== 'BLOQUEAR_Y_ELEVAR' || !mismoMotivo(d.motivo, motivo('PERMISO_ILEGITIMO'))));
      m(c, 'E4', 'ilegitimos_preguntados', n(d.accion === 'PREGUNTAR_UNA_VEZ'));
      m(c, 'E4', 'ilegitimos_agrupados', n(d.accion === 'AGRUPAR' || agrupado));
      m(c, 'E4', 'ilegitimos_contactos_ahora', n(d.contactarAhora));
    }
    for (let i = 0; i < 10; i++) {
      p.decidir(aprobacion(`s${i}`, 'g'), ahora);
      p.decidir(decision(`n${i}`, 'g'), ahora);
    }
    const compartidas = p.bandeja.grupos()
      .filter(([k, v]) => k !== null || v.length > 1)
      .flatMap(([, v]) => v)
      .filter((i) => i.eventoId.startsWith('s')).length;
    m(c, 'E4', 'seguridad_en_grupo_compartido', compartidas);
    c.politicas.push(p);
  }
}

/** `hasta` esperado, calculado a mano desde las declaraciones de cada operador. */
function hastaEsperado(op: string, caso: string): Minuto | null {
  const tabla: Record<string, Minuto | null> = {
    'OP-A|descanso': t(1, 9, 0),
    'OP-B|descanso': t(2, 7, 0),
    'OP-C|descanso': t(1, 22, 0),
    // OP-D: FUERA por defecto, sin fin: hasta que la persona cambie el modo.
    'OP-D|descanso': null,
    'OP-A|descanso-declarado': t(0, 12, 0),
    'OP-B|descanso-declarado': t(0, 20, 0),
    'OP-C|descanso-declarado': t(1, 1, 0),
    'OP-D|descanso-declarado': t(1, 10, 0),
  };
  const v = tabla[`${op}|${caso}`];
  return v === undefined ? null : v;
}

function e5(c: Ctx): void {
  const casos: Array<[string, Politica, Minuto]> = [['descanso', pol(c), c.op.descanso]];
  const r = pol(c);
  declarar(r, 'DESCANSO', c.op.dentro + 120, c.op.dentro);
  casos.push(['descanso-declarado', r, c.op.dentro]);
  for (const [caso, p, ahora] of casos) {
    const esperado = hastaEsperado(c.op.id, caso);
    const evs: Evento[] = [
      ...Array.from({ length: 20 }, (_, i) => decision(`${caso}${i}`, 'g')),
      ...Array.from({ length: 5 }, (_, i) => aprobacion(`${caso}a${i}`, 'g')),
      ...Array.from({ length: 10 }, (_, i) => aviso(`${caso}v${i}`)),
    ];
    for (const e of evs) {
      const d = p.decidir(e, ahora);
      m(c, 'E5', 'contactos_ahora_no_emergencia', n(d.contactarAhora));
      if (e.tipo.k !== 'AVISO') {
        const h = p.bandeja.explicar(e.id);
        const explicado = h?.length === 1 && h[0] !== undefined && mismoMotivo(h[0].motivo, d.motivo) && h[0].hasta === d.hasta;
        const ok = explicado && d.motivo.k === 'MODO_NO_DISPONIBLE' && d.hasta === esperado;
        m(c, 'E5', 'aplazamientos_mal_explicados', n(!ok));
      }
    }
    c.politicas.push(p);
  }
}

function e6(c: Ctx): void {
  const canal = c.op.config.canalNivelMax;
  for (const ahora of [c.op.dentro, c.op.fuera]) {
    const p = pol(c);
    const evs: Evento[] = [];
    for (let i = 0; i < 10; i++) {
      evs.push(conNivel(aviso(`n3v${i}`), 3), conNivel(decision(`n3d${i}`, 'g'), 3));
    }
    for (let i = 0; i < 5; i++) evs.push(conNivel(aprobacion(`n4s${i}`, 'g'), 4));
    const code = real(c);
    if (code !== undefined) evs.push(conNivel(alerta('n3e', code), 3));
    for (const e0 of evs) {
      const e = { ...e0, texto: 'contenido sensible' };
      const d = p.decidir(e, ahora);
      const viajo = p.bandeja.porEvento(e.id)?.texto != null || (d.contactarAhora && !d.redactado);
      if (e.nivel > canal) {
        m(c, 'E6', 'entregas_sobre_nivel', n(viajo));
        m(c, 'E6', 'sin_redactar', n(!d.redactado));
      }
    }
    c.politicas.push(p);
  }
}

function e7(c: Ctx): void {
  let p = pol(c);
  for (let i = 0; i < 10; i++) {
    let r = deAgente(`amb${i}`, { k: 'REINTENTO', efectoPrevio: 'DESCONOCIDO' });
    if (i % 2 === 0) r = urgente(r);
    m(c, 'E7', 'ambiguos_no_bloqueados', n(p.decidir(r, c.op.dentro).accion !== 'BLOQUEAR_Y_ELEVAR'));
  }
  c.politicas.push(p);
  // Repetición, sobre una política sin presupuesto gastado: se pregunta una vez y no más.
  p = pol(c);
  const rep = decision('rep', 'g');
  let preguntas = 0;
  for (const ahora of [c.op.dentro, c.op.dentro + 1, c.op.dentro + 2, c.op.fuera, c.op.dentro + DIA]) {
    if (p.decidir(rep, ahora).accion === 'PREGUNTAR_UNA_VEZ') preguntas++;
  }
  m(c, 'E7', 'decision_repetida_preguntas', preguntas);
  c.politicas.push(p);
}

function e8(c: Ctx): void {
  m(c, 'E8', 'emergencias_omitidas_tras_para', 0);
  const ahora = c.op.dentro;
  const p = pol(c);
  if (!p.control({ k: 'PARA' }, 'PERSONA', ahora)) throw new Error('PARA rechazado');
  const evs: Evento[] = [
    ...Array.from({ length: 10 }, (_, i) => urgente(decision(`pd${i}`, 'g'))),
    ...Array.from({ length: 5 }, (_, i) => aprobacion(`ps${i}`, 'g')),
    ...Array.from({ length: 5 }, (_, i) => deAgente(`pp${i}`, { k: 'PETICION_PERMISO', dentroDeContrato: true })),
    ...Array.from({ length: 5 }, (_, i) => deAgente(`pr${i}`, { k: 'REINTENTO', efectoPrevio: 'DESCONOCIDO' })),
  ];
  const reanudo = p.control({ k: 'REANUDAR' }, 'AGENTE_AUTENTICADO', ahora + 1);
  const reanudoAnon = p.control({ k: 'REANUDAR' }, 'NO_AUTENTICADO', ahora + 1);
  m(c, 'E8', 'reanudacion_agente_aceptada', n(reanudo || reanudoAnon || !p.estado.parado));
  for (const e of evs) {
    const d = p.decidir(e, ahora + 2);
    m(c, 'E8', 'preguntas_tras_para', n(d.contactarAhora || d.accion === 'PREGUNTAR_UNA_VEZ'));
    m(c, 'E8', 'no_bloqueadas_tras_para', n(d.accion !== 'BLOQUEAR_Y_ELEVAR'));
  }
  const code = real(c);
  if (code !== undefined) {
    const omitida = !p.decidir(alerta('pe', code), ahora + 3).contactarAhora;
    c.alertasOmitidas += n(omitida);
    m(c, 'E8', 'emergencias_omitidas_tras_para', n(omitida));
  }
  c.politicas.push(p);

  // Veto + reinicio.
  const v = pol(c);
  v.control({ k: 'VETAR', objetivo: 'g' }, 'PERSONA', ahora);
  const estado = estadoDesdeTexto(estadoATexto(v.estado));
  let perdido = 1;
  if (estado !== null) {
    const r = new Politica(c.op.config, estado);
    const rechaza = !r.control({ k: 'LEVANTAR_VETO', objetivo: 'g' }, 'AGENTE_AUTENTICADO', ahora);
    const d = r.decidir(urgente(decision('pv', 'g')), ahora);
    perdido = n(!(rechaza && mismoMotivo(d.motivo, motivo('VETADO')) && !d.contactarAhora));
    c.politicas.push(r);
  }
  m(c, 'E8', 'veto_perdido_tras_reinicio', perdido);
}

function e9(c: Ctx): void {
  const p = pol(c);
  for (let i = 0; i < 10; i++) p.decidir(decision(`si${i}`, 'g'), c.op.dentro);
  for (let i = 0; i < 10; i++) {
    const s = deAgente(`sil${i}`, { k: 'SILENCIO', decisionId: `d-si${i}` });
    const d = p.decidir(s, c.op.dentro + 60);
    m(c, 'E9', 'aprobaciones_por_silencio', n(d.accion !== 'REGISTRAR' || !mismoMotivo(d.motivo, motivo('SILENCIO_NO_ES_PERMISO')) || d.contactarAhora));
    m(c, 'E9', 'no_pendientes', n(!p.bandeja.porDecision(`d-si${i}`)?.pendiente));
  }
  c.politicas.push(p);
}

// --- AC-4b (SE-490): evals nuevos ---------------------------------------------------------------

const TODOS_MODOS: readonly Modo[] = ['DISPONIBLE', 'FOCO', 'DESCANSO', 'FUERA'];

function configAc4b(c: Ctx): Config {
  return {
    ...c.op.config,
    topeAlertas: 3,
    alertas: [
      { codigo: 'marcada-descanso', modos: ['DESCANSO'] },
      { codigo: 'marcada-todos', modos: TODOS_MODOS },
      { codigo: 'marcada-foco', modos: ['FOCO'] },
      { codigo: 'remitente', modos: TODOS_MODOS, porRemitente: true },
    ],
  };
}

/** Momento de cada modo sobre el operador: (política, minuto). */
function porModo(c: Ctx, modo: Modo): [Politica, Minuto] {
  const p = new Politica(configAc4b(c));
  declarar(p, modo, null, c.op.dentro);
  return [p, c.op.dentro];
}

function ac4b(c: Ctx): void {
  const presupuesto = c.op.config.presupuesto;
  // A1: 100 eventos simultáneos no superan el presupuesto de avisos (dentro de ventana, DISPONIBLE).
  {
    const p = new Politica(configAc4b(c));
    declarar(p, 'DISPONIBLE', null, c.op.dentro);
    let contactos = 0;
    for (let i = 0; i < 100; i++) contactos += n(p.decidir(notificacion(`s${i}`), c.op.dentro).contactarAhora);
    m(c, 'A1', 'avisos_sobre_presupuesto', Math.max(0, contactos - presupuesto));
    m(c, 'A1', 'avisos_perdidos', 100 - p.bandeja.items().length);
    c.politicas.push(p);
  }
  // A2: en DESCANSO solo pasan las alertas marcadas para ese modo; las no marcadas se difieren.
  {
    const [p, ahora] = porModo(c, 'DESCANSO');
    const marcadas = ['marcada-descanso', 'marcada-todos'].map((k, i) => p.decidir(alerta(`dm${i}`, k), ahora));
    const noMarcadas = ['marcada-foco'].map((k, i) => p.decidir(alerta(`dn${i}`, k), ahora));
    m(c, 'A2', 'marcadas_no_entregadas', marcadas.filter((d) => !d.contactarAhora).length);
    m(c, 'A2', 'no_marcadas_entregadas', noMarcadas.filter((d) => d.contactarAhora).length);
    m(c, 'A2', 'no_marcadas_sin_diferir', noMarcadas.filter((d) => d.accion !== 'DIFERIR').length);
    m(c, 'A2', 'avisos_en_descanso', n(p.decidir(notificacion('dav'), ahora).contactarAhora));
    m(c, 'A2', 'no_marcadas_perdidas', n(p.bandeja.porEvento('dn0')?.pendiente !== true));
  }
  // A3: una urgencia inyectada en un asunto no eleva el aviso (en cada modo).
  for (const modo of TODOS_MODOS) {
    const [p0, ahora] = porModo(c, modo);
    const [p1] = porModo(c, modo);
    for (const base of [notificacion('i1'), aviso('i2'), alerta('i3', 'marcada-foco'), alerta('i4', 'nadie')]) {
      const a = p0.decidir(base, ahora);
      const b = p1.decidir({ ...urgente(base), texto: 'URGENTE marcada-descanso marcada-todos' }, ahora);
      const igual = a.accion === b.accion && mismoMotivo(a.motivo, b.motivo) && a.contactarAhora === b.contactarAhora && a.hasta === b.hasta;
      m(c, 'A3', 'urgencia_inyectada_cambia_decision', n(!igual));
      m(c, 'A3', 'urgencia_no_marcada', n(!b.urgenciaIgnorada));
    }
  }
  // A4: una alerta marcada para el modo activo nunca se difiere: 0 omisiones; sobre el tope, un mensaje agrupado.
  for (const modo of TODOS_MODOS) {
    const [p, ahora] = porModo(c, modo);
    const ids = Array.from({ length: 12 }, (_, i) => `t${modo}${i}`);
    const sueltas: string[] = [];
    let diferidas = 0;
    for (const id of ids) {
      const d = p.decidir(alerta(id, 'marcada-todos'), ahora);
      if (d.contactarAhora) sueltas.push(id);
      if (d.accion === 'DIFERIR') diferidas++;
    }
    const msg = p.drenarAlertasAgrupadas();
    const entregadas = new Set([...sueltas, ...(msg?.eventoIds ?? [])]);
    m(c, 'A4', 'alertas_diferidas', diferidas);
    m(c, 'A4', 'alertas_omitidas', ids.filter((id) => !entregadas.has(id)).length);
    m(c, 'A4', 'sueltas_sobre_tope', Math.max(0, sueltas.length - 3));
    m(c, 'A4', 'mensajes_agrupados_incorrectos', n(msg === null || msg.n !== 9 || msg.texto !== 'hay 9 alertas más'));
    m(c, 'A4', 'segundo_mensaje', n(p.drenarAlertasAgrupadas() !== null));
  }
  // A5: las alertas no consumen el presupuesto de avisos.
  {
    const [p, ahora] = porModo(c, 'DISPONIBLE');
    for (let i = 0; i < 20; i++) p.decidir(alerta(`pa${i}`, 'marcada-todos'), ahora);
    let contactos = 0;
    for (let i = 0; i < 20; i++) contactos += n(p.decidir(notificacion(`pn${i}`), ahora).contactarAhora);
    m(c, 'A5', 'presupuesto_consumido_por_alertas', Math.max(0, presupuesto - contactos));
  }
  // A6: remitente: en la ruta web, la regla de remitente nunca produce alerta; en la API sí; suplantada, nunca.
  for (const modo of TODOS_MODOS) {
    const [p, ahora] = porModo(c, modo);
    const web = p.decidir({ ...alerta(`rw${modo}`, 'remitente'), ruta: 'WEB' }, ahora);
    m(c, 'A6', 'web_produce_alerta', n(mismoMotivo(web.motivo, motivo('ALERTA'))));
    m(c, 'A6', 'web_sin_degradar', n(!web.degradadaAAviso));
    const [q] = porModo(c, modo);
    const api = q.decidir(alerta(`ra${modo}`, 'remitente'), ahora);
    m(c, 'A6', 'api_no_alerta', n(!mismoMotivo(api.motivo, motivo('ALERTA'))));
    for (const ruta of ['API', 'WEB'] as const) {
      const [s] = porModo(c, modo);
      const sup = s.decidir({ ...alerta(`rs${modo}${ruta}`, 'remitente'), origen: 'NO_AUTENTICADO', ruta }, ahora);
      m(c, 'A6', 'suplantada_contacta', n(sup.contactarAhora));
    }
  }
  // A7: el silencio nunca es respuesta.
  {
    const [p, ahora] = porModo(c, 'DISPONIBLE');
    const q = decision('sq', 'g');
    p.decidir(q, ahora);
    const s = p.decidir(deAgente('ss', { k: 'SILENCIO', decisionId: 'd-sq' }), ahora + 600);
    m(c, 'A7', 'silencio_resuelve', n(p.bandeja.porDecision('d-sq')?.pendiente !== true));
    m(c, 'A7', 'silencio_contacta', n(s.contactarAhora));
  }
  // A8: registro de demanda: cada evento tiene su porqué y el ahorro cuadra.
  {
    const [p, ahora] = porModo(c, 'DISPONIBLE');
    const ids: string[] = [];
    for (let i = 0; i < 30; i++) {
      ids.push(`rg${i}`);
      p.decidir(i % 3 === 0 ? alerta(`rg${i}`, 'marcada-todos') : notificacion(`rg${i}`), ahora);
    }
    m(c, 'A8', 'eventos_sin_porque', ids.filter((id) => p.ledger.porQue(id) === undefined).length);
    const a = p.ledger.queAhorro();
    m(c, 'A8', 'ahorro_no_cuadra', n(a.eventos !== 30 || a.interrupciones + a.ahorrados !== a.eventos));
    m(c, 'A8', 'contacto_sin_marcar', ids.filter((id) => (p.ledger.porQue(id)?.contactado ?? false) !== (p.ledger.entradas().find((e) => e.eventoId === id)?.ahora ?? false)).length);
  }
  // A9: resúmenes a la hora fijada.
  {
    const p = new Politica({ ...configAc4b(c), resumenes: { inicio: 8 * 60 + 30, cierre: 17 * 60 + 45 } });
    const antes = p.resumenesDebidos(t(0, 8, 29)).length;
    const a = p.resumenesDebidos(t(0, 8, 30));
    const repetido = p.resumenesDebidos(t(0, 8, 40)).length;
    const cierre = p.resumenesDebidos(t(0, 17, 45));
    m(c, 'A9', 'resumenes_antes_de_hora', antes);
    m(c, 'A9', 'resumenes_a_su_hora', n(a.length === 1 && a[0]?.tipo === 'INICIO' && cierre.length === 1 && cierre[0]?.tipo === 'CIERRE'));
    m(c, 'A9', 'resumenes_repetidos', repetido);
  }
}

// --- bucle ------------------------------------------------------------------------------------

function sobrePresupuesto(c: Ctx): number {
  let total = 0;
  for (const p of c.politicas) {
    const porVentana = new Map<Minuto | null, number>();
    for (const e of p.ledger.entradas().filter((x) => x.ahora && x.clase !== 'ALERTA')) {
      porVentana.set(e.ventana, (porVentana.get(e.ventana) ?? 0) + 1);
    }
    for (const [v, cuantos] of porVentana) {
      total += v === null ? cuantos : Math.max(0, cuantos - c.op.config.presupuesto);
    }
  }
  return total;
}

function parsearVerdad(dir: string): Array<{ ev: string; met: string; op: string; cmp: string; val: number }> {
  const ficheros = readdirSync(dir).filter((f) => /^verdad.*\.tsv$/.test(f)).sort();
  if (ficheros.length === 0) throw new Error('no hay ficheros de verdad');
  const filas = [];
  for (const f of ficheros) {
    for (const linea of readFileSync(join(dir, f), 'utf8').split('\n').filter((l) => !l.startsWith('#') && l.trim() !== '')) {
      const campos = linea.split('\t');
      const [ev, met, op, cmp, val] = campos;
      if (campos.length !== 5 || ev === undefined || met === undefined || op === undefined || cmp === undefined || val === undefined) {
        throw new Error(`línea de verdad mal formada en ${f}: ${linea}`);
      }
      if (!/^\d+$/.test(val)) throw new Error(`valor no numérico en ${f}: ${linea}`);
      filas.push({ ev, met, op, cmp, val: Number(val) });
    }
  }
  return filas;
}

function main(): number {
  const dir = process.argv[2] ?? join(dirname(fileURLToPath(import.meta.url)), 'evals');
  let verdad;
  try {
    verdad = parsearVerdad(dir);
  } catch (e) {
    console.error(`FALLO: ${(e as Error).message}`);
    return 2;
  }
  const medidas = new Map<string, Medidas>();
  let extra = 'operador\tmetrica\tvalor\n';
  for (const op of operadores()) {
    const c: Ctx = { op, medidas: new Map(), politicas: [], alertasOmitidas: 0, falsosContactos: 0, sinPolitica: new Map() };
    for (const f of [e1, e2, e3, e4, e5, e6, e7, e8, e9, ac4b]) f(c);
    m(c, 'G', 'omisiones_emergencias', c.alertasOmitidas);
    m(c, 'G', 'falsos_avisos_sobre_presupuesto', sobrePresupuesto(c));
    const alertas = c.politicas.reduce((s, p) => s + p.ledger.resumen().alertas, 0);
    for (const [k, v] of c.sinPolitica) extra += `${op.id}\t${k}\t${v}\n`;
    extra += `${op.id}\talertas_contactadas\t${alertas}\n`;
    extra += `${op.id}\tfalsos_avisos\t${c.falsosContactos}\n`;
    extra += `${op.id}\tpresupuesto_por_ventana\t${op.config.presupuesto}\n`;
    medidas.set(op.id, c.medidas);
  }

  let out = 'eval\tmetrica\toperador\tmedido\tcomparador\tverdad\tveredicto\n';
  let pass = 0;
  let fail = 0;
  for (const { ev, met, op, cmp, val } of verdad) {
    const ops = op === '*' ? [...medidas.keys()] : [op];
    for (const o of ops) {
      // Métrica ausente = no medida = FAIL (falla cerrado).
      const medido = medidas.get(o)?.get(`${ev}|${met}`);
      const ok = medido !== undefined && ((cmp === 'eq' && medido === val) || (cmp === 'le' && medido <= val));
      if (ok) pass++;
      else fail++;
      out += `${ev}\t${met}\t${o}\t${medido ?? 'NO_MEDIDO'}\t${cmp}\t${val}\t${ok ? 'PASS' : 'FAIL'}\n`;
    }
  }
  writeFileSync(join(dir, 'resultados.tsv'), out);
  writeFileSync(join(dir, 'comparador.tsv'), extra);
  process.stdout.write(out);
  console.log(`PASS ${pass} · FAIL ${fail}`);
  return fail > 0 || pass === 0 ? 1 : 0;
}

process.exitCode = main();
