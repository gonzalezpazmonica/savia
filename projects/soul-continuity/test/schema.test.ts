import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { validar } from "../src/api/schema.ts";

const OPENAPI = JSON.parse(readFileSync(new URL("../src/contract/openapi.json", import.meta.url), "utf8"));
const S = (n: string) => OPENAPI.components.schemas[n];

test("validar: TextoInerte exige inerte:true y no admite propiedades de más", () => {
  const ok = { texto: "x", inerte: true, origen: "tercero" };
  assert.deepEqual(validar(OPENAPI, S("TextoInerte"), ok), []);
  assert.ok(validar(OPENAPI, S("TextoInerte"), { ...ok, inerte: false }).length);
  assert.ok(validar(OPENAPI, S("TextoInerte"), { ...ok, extra: 1 }).length);
});

test("validar: fail-closed ante palabras clave desconocidas y oneOf ambiguo", () => {
  assert.ok(validar(OPENAPI, { type: "string", foo: 1 }, "a").length);
  assert.ok(validar(OPENAPI, { oneOf: [{ type: "string" }, { type: "string" }] }, "a").length);
  assert.ok(validar(OPENAPI, S("Atencion"), { modo: "FOCO", hasta: "mañana", vuelve_a: "DISPONIBLE" }).length);
});
