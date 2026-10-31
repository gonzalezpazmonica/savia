// Mutantes del cortafuegos: cada uno quita UNA defensa. La batería tiene que
// matarlos todos (al menos una comprobación falla). Un mutante vivo es una
// defensa que la batería no prueba.
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

const filas: { mutante: string; estado: string; fallidas: number; muertoPor: string[] }[] = [];
const cola = [...lista];
await Promise.all(Array.from({ length: paralelo }, async () => {
  for (let m = cola.shift(); m; m = cola.shift()) {
    const inf = await correr(m);
    // Fail-closed: si la batería no produjo informe, el mutante NO cuenta como muerto.
    const fallos = inf ? inf.comprobaciones.filter((c) => !c.ok).map((c) => c.id) : [];
    filas.push({ mutante: m, estado: !inf ? "SIN_INFORME" : fallos.length ? "MUERTO" : "VIVO", fallidas: fallos.length, muertoPor: fallos.slice(0, 6) });
    console.log(`${m}: ${filas.at(-1)!.estado} (${fallos.length} fallos)`);
  }
}));
// Resumen sobre TODOS los mutantes, con el último informe de cada uno.
filas.length = 0;
for (const m of MUTANTES) {
  let inf: Informe | null = null;
  try { inf = JSON.parse(readFileSync(join(SALIDA, `bateria-${m}.json`), "utf8")); } catch { inf = null; }
  const fallos = inf ? inf.comprobaciones.filter((c) => !c.ok).map((c) => c.id) : [];
  filas.push({ mutante: m, estado: !inf ? "SIN_INFORME" : fallos.length ? "MUERTO" : "VIVO", fallidas: fallos.length, muertoPor: fallos.slice(0, 6) });
}
const muertos = filas.filter((f) => f.estado === "MUERTO").length;
writeFileSync(join(RAIZ, "resultados", "mutantes.json"), JSON.stringify({ muertos, total: filas.length, filas }, null, 2) + "\n");
console.log(`muertos=${muertos}/${filas.length}`);
process.exitCode = muertos === filas.length ? 0 : 1;
