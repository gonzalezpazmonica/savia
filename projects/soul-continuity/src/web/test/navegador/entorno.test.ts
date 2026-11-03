// En CI, los tests de navegador solo valen con el navegador fijado (el Chromium de
// Playwright que instala soul-continuity-web.yml). Sin SOUL_NAVEGADOR, buscarNavegador()
// usaría el Chrome preinstalado del runner, de versión y arranque no controlados.
import { test } from "node:test";
import assert from "node:assert/strict";

export function navegadorFijadoEnCI(entorno: NodeJS.ProcessEnv): string | null {
  if (!entorno.CI) return null;
  return entorno.SOUL_NAVEGADOR ? null : "en CI hace falta SOUL_NAVEGADOR (Chromium de Playwright); ver soul-continuity-web.yml";
}

test("la regla: en CI sin SOUL_NAVEGADOR es un error; fuera de CI o con la ruta fijada, no", () => {
  assert.match(navegadorFijadoEnCI({ CI: "true" }) ?? "", /SOUL_NAVEGADOR/);
  assert.match(navegadorFijadoEnCI({ CI: "true", SOUL_NAVEGADOR: "" }) ?? "", /SOUL_NAVEGADOR/);
  assert.equal(navegadorFijadoEnCI({ CI: "true", SOUL_NAVEGADOR: "/tmp/chrome" }), null);
  assert.equal(navegadorFijadoEnCI({}), null);
});

test("este proceso: si es CI, el navegador está fijado", () => {
  assert.equal(navegadorFijadoEnCI(process.env), null);
});
