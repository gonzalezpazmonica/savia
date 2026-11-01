/**
 * AC-6 (SE-490): el documento de transparencia y el modelo de amenazas del canal
 * citan el código que respaldan sus afirmaciones. Este test comprueba que cada cita
 * a este proyecto apunta a un fichero que existe y a líneas que existen, que están
 * los apartados que pide la spec y que cada hueco citado está en su lista.
 * Con las partes ya integradas, el documento de transparencia no cita otras ramas: todas sus
 * citas se resuelven contra este árbol.
 */

import { test } from "node:test";
import assert from "node:assert/strict";
import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { fileURLToPath } from "node:url";

const PROJECT = fileURLToPath(new URL("..", import.meta.url));
const IT_PACK = join(PROJECT, "..", "..", "docs", "soul-continuity-it-pack.md");
const CANAL = join(PROJECT, "docs", "canal-amenazas.md");

interface Cita { file: string; lines: number[]; at: number }

/** Citas `ruta:N`, `ruta:N-M`, `ruta:N,M` y continuaciones `:N` sobre la última ruta de la misma línea. */
export function citas(md: string): Cita[] {
  const out: Cita[] = [];
  md.split("\n").forEach((line, i) => {
    let last: string | null = null;
    for (const m of line.matchAll(/`([^`]+)`/g)) {
      const span = m[1];
      if (span.startsWith("[")) { last = null; continue; } // otra rama
      const full = /^((?:src|test|bench|bin)\/[\w./-]+?):([\d,-]+)$/.exec(span);
      const cont = /^:([\d,-]+)$/.exec(span);
      const file: string | null = full ? full[1] : cont && last ? last : null;
      const spec: string | null = full ? full[2] : cont ? cont[1] : null;
      if (!file || !spec) continue;
      last = file;
      const lines = spec.split(",").flatMap((p) => p.split("-")).filter(Boolean).map(Number);
      out.push({ file, lines, at: i + 1 });
    }
  });
  return out;
}

function comprobarCitas(md: string, nombre: string): number {
  const cs = citas(md);
  for (const c of cs) {
    const p = join(PROJECT, c.file);
    assert.ok(existsSync(p), `${nombre}:${c.at}: no existe ${c.file}`);
    const n = readFileSync(p, "utf8").split("\n").length;
    for (const l of c.lines) assert.ok(Number.isInteger(l) && l >= 1 && l <= n, `${nombre}:${c.at}: ${c.file} no tiene la línea ${l} (tiene ${n})`);
  }
  return cs.length;
}

test("las citas al código del documento de transparencia existen", () => {
  assert.ok(comprobarCitas(readFileSync(IT_PACK, "utf8"), "it-pack") >= 40, "el anexo debe citar el código");
});

test("el documento de transparencia describe el código integrado: ninguna cita a otra rama", () => {
  const md = readFileSync(IT_PACK, "utf8");
  assert.doesNotMatch(md, /`\[(adapters|web|atencion)\] /, "una cita a otra rama no se comprueba contra el código");
});

test("los huecos H-1…H-5 y H-11 constan como cerrados y cada cierre cita su prueba en el anexo", () => {
  const md = readFileSync(IT_PACK, "utf8");
  for (const h of ["H-1", "H-2", "H-3", "H-4", "H-5", "H-11"]) assert.match(md, new RegExp(`^\\| ${h} \\| Cerrado`, "m"), h);
  for (const a of ["A32", "A33", "A34", "A35", "A36", "A39", "A40", "A41", "A42", "A43", "A44", "A45"]) assert.match(md, new RegExp(`^- \\*\\*${a}\\*\\* `, "m"), a);
});

test("las citas al código del modelo de amenazas del canal existen", () => {
  assert.ok(comprobarCitas(readFileSync(CANAL, "utf8"), "canal-amenazas") >= 40);
});

test("negativo: una cita a una línea que no existe o a un fichero ausente se detecta", () => {
  assert.throws(() => comprobarCitas("`src/api/listen.ts:99999`", "x"), /no tiene la línea 99999/);
  assert.throws(() => comprobarCitas("`src/api/no-existe.ts:1`", "x"), /no existe/);
  assert.throws(() => comprobarCitas("`src/api/listen.ts:1` y `:99999`", "x"), /no tiene la línea 99999/);
  // Las citas a otras ramas no se resuelven contra este árbol.
  assert.equal(comprobarCitas("`[web] src/web/no-existe.ts:1` y `:5`", "x"), 0);
});

test("el documento de transparencia cubre lo que pide la spec y lista los huecos", () => {
  const md = readFileSync(IT_PACK, "utf8");
  const titulos = md.split("\n").filter((l) => l.startsWith("## ")).join("\n");
  for (const t of [/Qué lee/, /permisos/, /Qué guarda.*cuánto tiempo.*borra/, /escucha en la red.*nunca sale/, /desinstala/, /adaptador web/, /Huecos conocidos/, /Anexo/]) {
    assert.match(titulos, t, `falta el apartado ${t}`);
  }
  assert.match(md, /canal-amenazas\.md/, "debe remitir al modelo de amenazas del canal");
  assert.doesNotMatch(md, /\/home\/|C:\\Users\\[A-Za-z]/, "sin rutas personales");
});

test("cada hueco citado en el modelo de amenazas está definido en su lista, y cada uno definido se cita", () => {
  const md = readFileSync(CANAL, "utf8");
  const [cuerpo, lista] = md.split("## Lista de huecos");
  assert.ok(lista, "falta la lista de huecos");
  const definidos = new Set([...lista.matchAll(/^\| (P[12]-\d+) \|/gm)].map((m) => m[1]));
  const citados = new Set([...cuerpo.matchAll(/\*\*(P[12]-\d+)\*\*/g)].map((m) => m[1]));
  assert.ok(definidos.size >= 5);
  for (const c of citados) assert.ok(definidos.has(c), `${c} se cita pero no está en la lista`);
  for (const d of definidos) assert.ok(citados.has(d), `${d} está en la lista pero no se justifica en el texto`);
  for (const t of [/direcciones configuradas/, /TLS/, /Emparejamiento/, /Revocación/, /Móvil perdido/, /Reenvío.*fuerza bruta/, /VPN cae.*dirección cambia/, /proveedor de la VPN/]) {
    assert.match(cuerpo, new RegExp(`^## .*${t.source}`, "m"), `falta el apartado ${t}`);
  }
});
