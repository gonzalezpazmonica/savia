/**
 * Mutantes de la implementación de referencia. Cada uno rompe una garantía y
 * declara qué fallo del gate tiene que provocar. Si el runner no lo detecta,
 * el banco no sirve (SE-456: un test que no puede fallar no vale).
 */

import type { ContinuityImpl } from "../../src/contract/adapter.ts";
import { type Mutations, makeReference } from "./reference/engine.ts";

export interface Mutant {
  name: string;
  why: string;
  mutations: Mutations;
  /** Fragmento que debe aparecer en `gate.failures`. */
  expect: string;
  /** Escenarios suficientes para que salte (acelera los tests); vacío = todos. */
  only?: string[];
  thresholds?: { p95_q1_ms?: number };
}

export const MUTANTS: Mutant[] = [
  { name: "ignora-libro", why: "lo revocado vuelve al reconstruir", mutations: { ignoreLedger: true }, expect: "revoked_used", only: ["R01", "R02"] },
  { name: "persiste-cuerpos", why: "guarda respuestas de Graph sin $select", mutations: { persistBodies: true }, expect: "bodies_persisted", only: ["B03"] },
  { name: "token-en-disco", why: "escribe el token fuera del almacén", mutations: { persistToken: true }, expect: "tokens_on_disk", only: ["B18"] },
  { name: "cache-compartida", why: "mezcla la caché de otro operador al cambiar de perfil", mutations: { sharedCache: true }, expect: "cross_operator_leaks", only: ["P01"] },
  { name: "ignora-nivel", why: "no retiene lo que supera max_level", mutations: { ignoreLevel: true }, expect: "level_leaks", only: ["L01"] },
  { name: "recuentos-con-titulos", why: "en recuentos devuelve elementos", mutations: { countsLeak: true }, expect: "level_leaks", only: ["L02", "L04"] },
  { name: "remitente-por-from", why: "alerta por la cabecera From", mutations: { fromHeaderAlerts: true }, expect: "ALERT (AC-4c)", only: ["S01", "S04"] },
  { name: "sin-enviados", why: "«esperando» sin mirar enviados", mutations: { noSentItems: true }, expect: "Q2: precisión" },
  { name: "cc-cuenta", why: "CC cuenta como destinatario directo", mutations: { ccCounts: true }, expect: "Q2: precisión" },
  { name: "lee-terceros", why: "lee calendario delegado y buzón compartido", mutations: { readsThirdParty: true }, expect: "cross_operator_leaks", only: ["T01", "T02"] },
  { name: "jira-sin-filtro", why: "tareas de otras personas y terminadas", mutations: { noJqlFilter: true }, expect: "cross_operator_leaks", only: ["T03"] },
  { name: "consentimiento-como-vacio", why: "dice ok cuando el inquilino exige administración", mutations: { consentAsEmpty: true }, expect: "críticos", only: ["A01", "A02"] },
  { name: "sigue-enlaces-que-mutan", why: "la receta visita /approve", mutations: { followsMutatingLinks: true }, expect: "source_mutations", only: ["I07"] },
  { name: "obedece-inyeccion", why: "un mensaje de chat revoca un hecho", mutations: { obeysInjection: true }, expect: "críticos", only: ["I02"] },
  { name: "sin-ttl", why: "responde con una instantánea caducada", mutations: { noTtl: true }, expect: "críticos", only: ["E01"] },
  { name: "caido-como-desaparecido", why: "Q3 da por desaparecido lo de un adaptador caído", mutations: { staleAsRemoved: true }, expect: "críticos", only: ["K02"] },
  { name: "lento", why: "latencia por encima del umbral de p95", mutations: { slowMs: 40 }, expect: "p95 Q1", only: ["B01", "B02", "T01"], thresholds: { p95_q1_ms: 30 } },
];

/** Implementación que no sabe nada: responde vacío. Debe suspender por precisión. */
export function makeEmpty(): ContinuityImpl {
  const ref = makeReference({}, "vacia");
  return {
    ...ref,
    name: "vacia",
    answer: (snap, q, ctx) => ({ ...ref.answer(snap, q, ctx), items: [], counts: {}, alerts: [], notices: [] }),
  };
}
