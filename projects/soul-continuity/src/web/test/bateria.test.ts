// Integración: la batería AC-4e completa contra el cortafuegos real y el
// navegador instalado. Sin navegador falla (no se descarga ninguno).
import { test } from "node:test";
import assert from "node:assert/strict";
import { ejecutarBateria } from "../bench/bateria.ts";

test("batería AC-4e: 0 fallos con el cortafuegos real", { timeout: 600_000 }, async () => {
  const inf = await ejecutarBateria("ninguno");
  const fallos = inf.comprobaciones.filter((c) => !c.ok).map((c) => `${c.id} ${c.detalle}`);
  assert.deepEqual(fallos, []);
  assert.ok(inf.comprobaciones.length >= 300, `solo ${inf.comprobaciones.length} comprobaciones`);
});
