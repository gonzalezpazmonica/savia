// SE-514 S0: dominio piloto (tres casos y tres contraejemplos) ejecutado contra la cola y el
// registro de preguntas que ya existen. Los datos viven en `fixtures/piloto-s0.json`, fijados en
// el prerregistro `docs/evidence/SE-514-S0-prerregistro.md`. Si el comportamiento cambia, el
// test falla y el fixture se revisa a propósito, no se ajusta para que pase.
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { test } from 'node:test';

import {
  Politica, Preguntas, construirCola, type Fuentes, type Minuto, type PreguntaAgente,
} from '../../src/attention/index.ts';
import { opA, t } from './comun.ts';

interface Hora { dia: number; hh: number; mm: number }
interface PregFx {
  id: string; agente: string; trabajo: string; clase: 'DECISION' | 'PERMISO';
  que: string; tema?: string; permiso?: string; obligatoria?: boolean; version?: string;
  pregunta_a: Hora; caduca?: Hora;
}
interface CasoFx {
  id: string; tipo: 'caso' | 'contraejemplo';
  preguntas?: PregFx[]; fuentes?: Record<string, string[]>;
  respuesta?: { version: string; valor: string; a: Hora };
  vencer_a?: Hora; repreguntar_caduca?: Hora;
  esperado: Record<string, unknown>;
}
interface HuecoFx { id: string; fuentes: Record<string, string[]>; observado: { peticiones: number; duplicadas: number } }

const FX = JSON.parse(readFileSync(new URL('./fixtures/piloto-s0.json', import.meta.url), 'utf8')) as {
  casos: CasoFx[]; huecos_observados: HuecoFx[];
};

const m = (h: Hora): Minuto => t(h.dia, h.hh, h.mm);
const AG = 'AGENTE_AUTENTICADO' as const;
const PE = 'PERSONA' as const;

function caso(id: string): CasoFx {
  const c = FX.casos.find((x) => x.id === id);
  assert.ok(c, `falta el caso ${id} en el fixture`);
  return c;
}

function entrada(p: PregFx): PreguntaAgente {
  return {
    id: p.id, agente: p.agente, trabajo: p.trabajo, version: p.version ?? 'v1', clase: p.clase,
    ...(p.tema ? { tema: p.tema } : {}), ...(p.permiso ? { permiso: p.permiso } : {}),
    ...(p.obligatoria ? { obligatoria: true } : {}),
    que: p.que, porQue: `Por qué ahora en ${p.id}`,
    siNoContestas: 'El trabajo espera; no se decide nada por ti.', siAplazas: 'Pierde unos 20 minutos.',
    caduca: p.caduca ? m(p.caduca) : t(p.pregunta_a.dia, 13, 0), nivel: 1,
  };
}

function montar(c: CasoFx): Preguntas {
  const pr = new Preguntas(new Politica(opA()));
  for (const p of c.preguntas ?? []) {
    const r = pr.preguntar(entrada(p), m(p.pregunta_a), AG);
    assert.ok(r.ok, `${c.id}/${p.id}: la pregunta no entró (${!r.ok ? r.motivo : ''})`);
  }
  return pr;
}

function fuentes(f: Record<string, string[]>): Fuentes {
  const out: Record<string, unknown[]> = {};
  for (const [fuente, ids] of Object.entries(f)) {
    out[fuente] = ids.map((id) => ({
      id, que: `PR ${id}`, porQue: 'Espera revisión.', siNoContestas: 'Sigue en borrador.',
      siAplazas: 'Nada se fusiona.', caduca: t(0, 18, 0), nivel: 1,
    }));
  }
  return out as Fuentes;
}

test('fixture: tres casos y tres contraejemplos, con ids únicos', () => {
  const ids = FX.casos.map((c) => c.id);
  assert.equal(new Set(ids).size, ids.length);
  assert.equal(FX.casos.filter((c) => c.tipo === 'caso').length, 3);
  assert.equal(FX.casos.filter((c) => c.tipo === 'contraejemplo').length, 3);
});

test('C1 (escena 1): dos agentes, misma decisión, una tarjeta y una respuesta para las dos', () => {
  const c = caso('C1');
  const pr = montar(c);
  const ahora = t(0, 10, 10);
  const vis = pr.visibles(ahora);
  assert.equal(vis.length, c.esperado.tarjetas_visibles);
  const r = pr.responder({ tarjeta: vis[0].id, version: vis[0].version, valor: 'AGENTE-1-PRIMERO' }, ahora, PE);
  assert.ok(r.ok);
  assert.deepEqual([...r.resueltas].sort(), c.esperado.una_respuesta_resuelve);
});

test('C2 (escena 3): permiso obligatorio en descanso no suena, el trabajo espera y aparece en la ventana', () => {
  const c = caso('C2');
  const pr = montar(c);
  const noche = t(0, 23, 31);
  const e = c.esperado as { visibles_en_descanso: number; puede_ejecutar_en_descanso: boolean;
    estado_trabajo_en_descanso: string; visible_en: Hora; puede_ejecutar_al_verla: boolean };
  assert.equal(pr.visibles(noche).length, e.visibles_en_descanso);
  assert.equal(pr.puedeEjecutar('c2-a'), e.puede_ejecutar_en_descanso);
  assert.equal(pr.estadoTrabajo('trab-publicar', noche), e.estado_trabajo_en_descanso);
  const manana = pr.visibles(m(e.visible_en));
  assert.equal(manana.length, 1);
  assert.deepEqual(manana[0].preguntas, ['c2-a']);
  assert.equal(manana[0].obligatoria, true);
  assert.equal(pr.puedeEjecutar('c2-a'), e.puede_ejecutar_al_verla);
});

test('C3 (escena 5): respuesta a una versión anterior, rechazada y se enseña la actual', () => {
  const c = caso('C3');
  const pr = montar(c);
  const tarjeta = pr.visibles(t(0, 10, 1))[0];
  const resp = c.respuesta!;
  const r = pr.responder({ tarjeta: tarjeta.id, version: resp.version, valor: resp.valor }, m(resp.a), PE);
  assert.equal(r.ok, c.esperado.ok);
  assert.ok(!r.ok);
  assert.equal(r.motivo, c.esperado.motivo);
  assert.equal(r.volverAEnsenar?.version, c.esperado.vuelve_a_ensenar_version);
  assert.equal(pr.puedeEjecutar('c3-a'), false);
});

test('X1 (AC-4): dos permisos distintos con el mismo tema no se unen', () => {
  const c = caso('X1');
  const pr = montar(c);
  const ahora = t(0, 10, 5);
  const vis = pr.visibles(ahora);
  assert.equal(vis.length, c.esperado.tarjetas_visibles);
  const primera = vis.find((v) => v.preguntas.includes('x1-a'))!;
  const r = pr.responder({ tarjeta: primera.id, version: primera.version, valor: 'CONCEDER' }, ahora, PE);
  assert.ok(r.ok);
  assert.deepEqual([...r.resueltas], c.esperado.una_respuesta_resuelve);
  assert.equal(pr.puedeEjecutar('x1-b'), false);
});

test('X2: la misma PR re-emitida por la misma fuente es una sola petición', () => {
  const c = caso('X2');
  const cola = construirCola(fuentes(c.fuentes!), t(0, 10, 0), 2);
  assert.equal(cola.peticiones.length, c.esperado.peticiones);
  assert.equal(cola.duplicadas, c.esperado.duplicadas);
});

test('X3 (AC-3): permiso sin respuesta al vencer queda en DEFER, sin efecto y con una sola repregunta', () => {
  const c = caso('X3');
  const pr = montar(c);
  const vence = m(c.vencer_a!);
  pr.vencer(vence);
  assert.equal(pr.estadoTrabajo('trab-x3', vence), c.esperado.estado_trabajo);
  assert.equal(pr.puedeEjecutar('x3-a'), c.esperado.puede_ejecutar);
  const nueva = m(c.repreguntar_caduca!);
  const intentos = [pr.repreguntar('x3-a', nueva, vence + 1).ok];
  pr.vencer(nueva);
  intentos.push(pr.repreguntar('x3-a', nueva + 30, nueva + 1).ok);
  assert.deepEqual(intentos, c.esperado.repreguntas_en_ventana);
  assert.equal(pr.puedeEjecutar('x3-a'), false);
});

test('H1 (hueco observado): la misma PR por dos fuentes cuenta dos veces hoy', () => {
  for (const h of FX.huecos_observados) {
    const cola = construirCola(fuentes(h.fuentes), t(0, 10, 0), 2);
    assert.equal(cola.peticiones.length, h.observado.peticiones, h.id);
    assert.equal(cola.duplicadas, h.observado.duplicadas, h.id);
  }
});
