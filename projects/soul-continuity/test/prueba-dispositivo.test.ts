/**
 * AC-4b (SE-490): la guía de prueba en dispositivo real (`docs/prueba-dispositivo.md`)
 * cubre los cuatro bloques que solo se comprueban en un teléfono, cada paso tiene
 * su casilla OK/FALLO, las órdenes de Soul que pide existen en la CLI y el texto
 * no lleva datos de ninguna instalación concreta (rutas personales ni IP).
 * Límite: los textos de la app que cita la guía viven en otro repositorio y no se comprueban aquí.
 */

import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const PROJECT = resolve(fileURLToPath(new URL("..", import.meta.url)));
const GUIA = join(PROJECT, "docs", "prueba-dispositivo.md");
const CLI = join(PROJECT, "src", "cli", "cli.ts");

/** Órdenes que la ayuda de la CLI declara (primera palabra de cada alternativa). */
function ordenesCli(src: string): Set<string> {
  const ayuda = /const HELP = `([\s\S]*?)`;/.exec(src)?.[1] ?? "";
  const out = new Set<string>();
  for (const linea of ayuda.split("\n").slice(1)) {
    const izq = linea.trim().split(/\s{2,}/)[0] ?? "";
    for (const alt of izq.split("|")) {
      const w = alt.trim().split(/\s+/)[0];
      if (/^[a-z][a-z0-9-]*$/.test(w)) out.add(w);
    }
  }
  return out;
}

/** Problemas de la guía; vacío si está bien. */
export function problemasGuia(md: string, ordenes: Set<string>): string[] {
  const out: string[] = [];
  for (const t of [/Consulta cada 5 minutos/, /Tras reiniciar/, /Pantalla bloqueada.*recuentos/, /Desemparejar.*token/, /Cómo anotar los resultados/]) {
    if (!new RegExp(`^## .*${t.source}`, "m").test(md)) out.push(`falta el apartado ${t.source}`);
  }
  if (!/^### .*Doze con cable/m.test(md)) out.push("falta Doze con cable");
  if (!/^### .*Doze sin cable/m.test(md)) out.push("falta Doze sin cable");
  if (!/deviceidle force-idle/.test(md)) out.push("falta cómo forzar Doze con adb");

  // Cada fila de paso (`| 1a.1 | … |`) termina con dos celdas: OK y FALLO, o «—» si es una medida.
  const filas = [...md.matchAll(/^\| (\d+[a-z]?\.\d+) \|.*$/gm)];
  if (filas.length < 15) out.push(`solo ${filas.length} pasos con resultado esperado`);
  for (const f of filas) {
    const celdas = f[0].split(/(?<!\\)\|/).slice(1, -1).map((c) => c.trim());
    const [ok, fallo] = celdas.slice(-2);
    const casillas = ok === "[ ]" && fallo === "[ ]";
    const medida = ok === "—" && fallo === "—";
    if (celdas.length !== 4 || !(casillas || medida)) out.push(`${f[1]}: sin casillas OK/FALLO`);
    if (!new RegExp(`\\b${f[1].replace(".", "\\.")} `).test(md.split(/^## Cómo anotar/m)[1] ?? "")) out.push(`${f[1]}: no está en la plantilla de resultados`);
  }

  for (const m of md.matchAll(/node bin\/soul\.mjs ([a-z][a-z0-9-]*)/g)) {
    if (!ordenes.has(m[1])) out.push(`la orden «${m[1]}» no existe en la CLI`);
  }

  if (/\/home\/|\/Users\/|C:\\Users\\/.test(md)) out.push("ruta personal");
  if (/\b\d{1,3}(?:\.\d{1,3}){3}\b/.test(md)) out.push("dirección IPv4");
  if (/\b(?:100\.(?:6[4-9]|[7-9]\d|1[01]\d|12[0-7])|10|192\.168)\.\d/.test(md)) out.push("dirección privada");
  return out;
}

const guia = readFileSync(GUIA, "utf8");
const ordenes = ordenesCli(readFileSync(CLI, "utf8"));

test("la ayuda de la CLI declara las órdenes que usa la guía", () => {
  for (const o of ["status", "serve", "pair", "unpair", "devices"]) assert.ok(ordenes.has(o), `falta ${o} en la ayuda`);
});

test("la guía de prueba en dispositivo cubre AC-4b, tiene casillas y no lleva datos de una instalación", () => {
  assert.deepEqual(problemasGuia(guia, ordenes), []);
});

test("negativo: apartado ausente, paso sin casilla, orden inventada, IP y ruta personal se detectan", () => {
  const p = (md: string) => problemasGuia(md, ordenes);
  assert.ok(p(guia.replace("## 2. Tras reiniciar el teléfono", "## 2. Otra cosa")).some((x) => x.includes("Tras reiniciar")));
  assert.ok(p(guia.replace(/^(\| 2a\.1 \|.*)\| \[ \] \| \[ \] \|$/m, "$1| | |")).some((x) => x.startsWith("2a.1: sin casillas")));
  assert.ok(p(guia.replace("2a.1 OK|FALLO", "")).some((x) => x.startsWith("2a.1: no está en la plantilla")));
  assert.ok(p(guia.replace("node bin/soul.mjs devices", "node bin/soul.mjs forget")).some((x) => x.includes("«forget»")));
  assert.ok(p(`${guia}\nservidor en 192.0.2.7`).includes("dirección IPv4"));
  assert.ok(p(`${guia}\n/home/alguien/x`).includes("ruta personal"));
  assert.ok(p(guia.replace("deviceidle force-idle", "deviceidle algo")).includes("falta cómo forzar Doze con adb"));
});
