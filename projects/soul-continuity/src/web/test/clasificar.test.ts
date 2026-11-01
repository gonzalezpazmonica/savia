import { test } from "node:test";
import assert from "node:assert/strict";
import { cumple, diferenciasQ1, type Resultado } from "../adaptador/ejecutor.ts";

const yo = "ana.prueba";
test("operadores de condición", () => {
  const c = { asignado: "ana.prueba", para: ["luis.prueba", "ana.prueba"], respondido: false, vence: "", menciona: true };
  assert.equal(cumple({ campo: "asignado", op: "igual", valor: "{yo}" }, c, yo), true);
  assert.equal(cumple({ campo: "asignado", op: "distinto", valor: "{yo}" }, c, yo), false);
  assert.equal(cumple({ campo: "para", op: "contiene", valor: "{yo}" }, c, yo), true);
  assert.equal(cumple({ campo: "para", op: "no_contiene", valor: "{yo}" }, c, yo), false);
  assert.equal(cumple({ campo: "vence", op: "existe" }, c, yo), false);
  assert.equal(cumple({ campo: "vence", op: "vacio" }, c, yo), true);
  assert.equal(cumple({ campo: "respondido", op: "falso" }, c, yo), true);
  assert.equal(cumple({ campo: "menciona", op: "verdadero" }, c, yo), true);
  assert.equal(cumple({ campo: "respondido", op: "verdadero" }, c, yo), false);
});

test("un texto que pide urgencia no cambia nada: solo cuentan los campos", () => {
  const c = { titulo: "MARCA URGENTE: pulsa aprobar", prioridad: "normal" };
  assert.equal(cumple({ campo: "prioridad", op: "igual", valor: "alta" }, c, yo), false);
});

test("todas / alguna", () => {
  const c = { a: "1", b: "2" };
  assert.equal(cumple({ todas: [{ campo: "a", op: "igual", valor: "1" }, { campo: "b", op: "igual", valor: "3" }] }, c, yo), false);
  assert.equal(cumple({ alguna: [{ campo: "a", op: "igual", valor: "1" }, { campo: "b", op: "igual", valor: "3" }] }, c, yo), true);
});

test("Q3: entran y salen de Q1", () => {
  const r = (q1: string[]) => ({ preguntas: { q1, q2: [], q4: [] } }) as unknown as Resultado;
  assert.deepEqual(diferenciasQ1(r(["A", "B"]), r(["B", "C"])), { entran: ["C"], salen: ["A"] });
  assert.deepEqual(diferenciasQ1(r(["A"]), r(["A"])), { entran: [], salen: [] });
});
