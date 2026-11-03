// Frontera entre tests sin navegador (test/*.test.ts, `npm run test:unit`) y tests con
// navegador real (test/navegador/, `npm run test:navegador`). El job general de CI ejecuta
// solo los primeros y sin SOUL_NAVEGADOR; si un test que lanza un navegador se cuela ahí,
// buscarNavegador() cae en el Chrome preinstalado del runner, compitiendo por la CPU con
// el resto de ficheros en paralelo (PR #1447: timeout de arranque intermitente).
import { test } from "node:test";
import assert from "node:assert/strict";
import { readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";

const dirTest = import.meta.dirname;
const raiz = join(dirTest, "..", "..", "..", "..", "..");

/** Llamadas que arrancan un navegador real o la batería que lo hace. */
export const LANZA_NAVEGADOR =
  /buscarNavegador\(\s*\)|ejecutarBateria\(|abrirNavegador\(|ejecutarReceta\(|vigilarPagina\(|launchPersistentContext|chromium\.launch/;

export function ficherosQueLanzanNavegador(dir: string): string[] {
  return readdirSync(dir).filter((f) => f.endsWith(".test.ts") && f !== "frontera-navegador.test.ts")
    .filter((f) => LANZA_NAVEGADOR.test(readFileSync(join(dir, f), "utf8")));
}

test("el detector reconoce cada forma de lanzar un navegador y no las llamadas puras", () => {
  for (const s of ["buscarNavegador().ruta", "buscarNavegador( )", "await ejecutarBateria(\"ninguno\")",
    "abrirNavegador({})", "ejecutarReceta({ receta })", "vigilarPagina({ vigilada })",
    "chromium.launchPersistentContext(p, {})", "chromium.launch()"]) {
    assert.ok(LANZA_NAVEGADOR.test(s), s);
  }
  for (const s of ["buscarNavegador({ SOUL_NAVEGADOR: ruta })", "import { vigilarPagina } from", "recetaDeVigilancia({"]) {
    assert.ok(!LANZA_NAVEGADOR.test(s), s);
  }
});

test("ningún test de test/*.test.ts lanza un navegador; esos viven en test/navegador/", () => {
  assert.deepEqual(ficherosQueLanzanNavegador(dirTest), []);
  const nav = ficherosQueLanzanNavegador(join(dirTest, "navegador"));
  for (const f of ["bateria.test.ts", "ejecutor.test.ts", "vigilancia.test.ts"]) assert.ok(nav.includes(f), f);
});

test("scripts: unit no alcanza test/navegador/; navegador en serie; `npm test` ejecuta los dos", () => {
  const { scripts } = JSON.parse(readFileSync(join(dirTest, "..", "package.json"), "utf8")) as { scripts: Record<string, string> };
  assert.match(scripts["test:unit"], /--test test\/\*\.test\.ts$/);
  assert.match(scripts["test:navegador"], /--test-concurrency=1 test\/navegador\/\*\.test\.ts$/);
  assert.equal(scripts.test, "npm run test:unit && npm run test:navegador");
});

test("CI: el job general no corre tests de navegador; el workflow web sí, con SOUL_NAVEGADOR fijado", () => {
  const general = readFileSync(join(raiz, ".github", "workflows", "soul-continuity.yml"), "utf8");
  const web = readFileSync(join(raiz, ".github", "workflows", "soul-continuity-web.yml"), "utf8");
  // En el job general, todo lo del adaptador web es `test:unit`; nunca `npm test` ni `test:navegador` allí.
  const pasosWeb = general.split(/\n\s*- name: /).filter((p) => p.includes("working-directory: projects/soul-continuity/src/web"));
  assert.ok(pasosWeb.some((p) => /run: npm run test:unit\s*$/m.test(p)));
  for (const p of pasosWeb) assert.doesNotMatch(p, /run: npm (test|run test:navegador)\b/, p.split("\n")[0]);
  assert.match(web, /echo "SOUL_NAVEGADOR=\$ruta" >> "\$GITHUB_ENV"/);
  assert.match(web, /run: npm test\s*$/m);
});
