// Mutantes del cortafuegos: cada uno quita UNA defensa. La batería tiene que
// matarlos todos: falla al menos una comprobación de SU defensa
// (bench/mapa-mutantes.ts). Un mutante vivo es una defensa que la batería no prueba.
//
// Uso: node --experimental-strip-types bench/mutantes.ts [--paralelo 1] [--solo a,b]
// En paralelo, varios Chrome a la vez llegaron a colgar la batería: por defecto, en serie
// y con un tiempo máximo por mutante. El resumen reúne los informes de todas las tandas.

import { spawn } from "node:child_process";
import { mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { MUTANTES } from "../cortafuegos/decision.ts";
import type { Informe } from "./bateria.ts";
import { clasificarMutante } from "./mapa-mutantes.ts";

const RAIZ = join(dirname(fileURLToPath(import.meta.url)), "..");
const SALIDA = join(RAIZ, "resultados", "mutantes");
mkdirSync(SALIDA, { recursive: true });

const arg = (n: string) => { const i = process.argv.indexOf(n); return i > 0 ? process.argv[i + 1] : undefined; };
const paralelo = Number(arg("--paralelo") ?? 1);
const MAX_MS = 9 * 60_000;
const lista = arg("--solo")?.split(",") ?? [...MUTANTES];

function correr(m: string): Promise<Informe | null> {
  rmSync(join(SALIDA, `bateria-${m}.json`), { force: true });
  return new Promise((ok) => {
    const p = spawn(process.execPath, ["--experimental-strip-types", "--no-warnings", join(RAIZ, "bench", "bateria.ts"),
      "--mutante", m, "--salida", SALIDA], { stdio: "ignore" });
    const reloj = setTimeout(() => p.kill("SIGKILL"), MAX_MS);
    p.on("close", () => {
      clearTimeout(reloj);
      try { ok(JSON.parse(readFileSync(join(SALIDA, `bateria-${m}.json`), "utf8"))); } catch { ok(null); }
    });
  });
}

// Fail-closed: sin informe, o sin fallar ninguna comprobación de SU defensa, el mutante NO cuenta como muerto.
function fila(m: string, inf: Informe | null) {
  const fallos = inf ? inf.comprobaciones.filter((c) => !c.ok).map((c) => c.id) : null;
  const c = clasificarMutante(m, fallos);
  return { mutante: m, estado: c.estado, fallidas: fallos?.length ?? 0, ajenos: c.ajenos, muertoPor: c.muertoPor.slice(0, 6) };
}

const filas: ReturnType<typeof fila>[] = [];
const cola = [...lista];
await Promise.all(Array.from({ length: paralelo }, async () => {
  for (let m = cola.shift(); m; m = cola.shift()) {
    filas.push(fila(m, await correr(m)));
    console.log(`${m}: ${filas.at(-1)!.estado} (${filas.at(-1)!.fallidas} fallos, ${filas.at(-1)!.ajenos} ajenos)`);
  }
}));
// Resumen sobre TODOS los mutantes, con el último informe de cada uno.
filas.length = 0;
for (const m of MUTANTES) {
  let inf: Informe | null = null;
  try { inf = JSON.parse(readFileSync(join(SALIDA, `bateria-${m}.json`), "utf8")); } catch { inf = null; }
  filas.push(fila(m, inf));
}
const muertos = filas.filter((f) => f.estado === "MUERTO").length;
writeFileSync(join(RAIZ, "resultados", "mutantes.json"), JSON.stringify({ muertos, total: filas.length, filas }, null, 2) + "\n");
console.log(`muertos=${muertos}/${filas.length}`);
process.exitCode = muertos === filas.length ? 0 : 1;
