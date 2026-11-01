// Valida una receta contra la grabación (HAR) del propio operador y, si pasa y
// se pide, emite el recibo local que activa una receta experimental.
//
// Uso: node --experimental-strip-types adaptador/cli-grabacion.ts \
//        --receta <receta.json> --har <grabacion.har> [--var clave=valor ...] \
//        [--emitir-recibo] [--validaciones <dir>]
// Salida: el informe enmascarado en JSON. Código 0 si pasa, 1 si no, 2 si el uso es incorrecto.

import { readFileSync } from "node:fs";
import { dirValidacionesPorDefecto, guardarRecibo } from "./activacion.ts";
import { validarGrabacion } from "./grabacion.ts";
import { directorioDatos } from "../cortafuegos/perfil.ts";
import { cargarReceta } from "../receta/validar.ts";

function uso(): number {
  console.error("uso: cli-grabacion.ts --receta <receta.json> --har <grabacion.har> [--var k=v ...] [--emitir-recibo] [--validaciones <dir>]");
  return 2;
}

function main(argv: string[]): number {
  // El valor de una opción nunca es otra opción: `--receta --har x` es uso incorrecto.
  const valor = (n: string) => { const i = argv.indexOf(n); const v = i >= 0 ? argv[i + 1] : undefined; return v && !v.startsWith("--") ? v : undefined; };
  const receta = valor("--receta"), har = valor("--har");
  if (!receta || !har) return uso();
  const variables: Record<string, string> = {};
  argv.forEach((a, i) => {
    if (a !== "--var") return;
    const [k, ...v] = (argv[i + 1] ?? "").split("=");
    variables[k] = v.join("=");
  });
  let r;
  let datos: unknown;
  try {
    r = cargarReceta(receta, { variables });
    datos = JSON.parse(readFileSync(har, "utf8"));
  } catch (e) {
    console.error(`no se puede validar: ${(e as Error).message}`);
    return 1;
  }
  const inf = validarGrabacion(r, datos);
  console.log(JSON.stringify(inf, null, 2));
  if (!inf.pasa) return 1;
  if (argv.includes("--emitir-recibo")) {
    if (argv.includes("--validaciones") && !valor("--validaciones")) return uso();
    const dir = valor("--validaciones") ?? dirValidacionesPorDefecto(directorioDatos());
    try {
      const ruta = guardarRecibo(dir, r, { peticiones: inf.peticiones, permitidas: inf.permitidas,
        operaciones_lectura: inf.operaciones.filter((o) => o.clase === "lectura").length });
      console.error(`recibo: ${ruta}`);
    } catch (e) {
      console.error(`la receta pasa, pero no se pudo guardar el recibo en ${dir}: ${(e as Error).message}`);
      return 1;
    }
  }
  return 0;
}

process.exitCode = main(process.argv.slice(2));
