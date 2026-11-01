/**
 * AC-6 (SE-490): el documento de transparencia y el modelo de amenazas del canal
 * citan el código que respaldan sus afirmaciones. Este test comprueba que cada cita
 * a este proyecto apunta a un fichero que existe y a líneas que existen, que están
 * los apartados que pide la spec y que cada hueco y cada referencia del anexo citados
 * están definidos (y al revés).
 * Las citas a otras ramas (`[adapters] …`, `[web] …`, `[atencion] …`) no se comprueban aquí.
 * Límites: solo se reconocen citas con línea (`ruta:N`) a ficheros con extensión; una cita
 * sin línea (`package.json`) no se comprueba. El mínimo de 40 citas por documento detecta
 * un colapso del formato, no la pérdida de unas pocas citas.
 */

import { test } from "node:test";
import assert from "node:assert/strict";
import { existsSync, readFileSync } from "node:fs";
import { join, resolve, sep } from "node:path";
import { fileURLToPath } from "node:url";

const PROJECT = resolve(fileURLToPath(new URL("..", import.meta.url)));
const IT_PACK = join(PROJECT, "..", "..", "docs", "soul-continuity-it-pack.md");
const CANAL = join(PROJECT, "docs", "canal-amenazas.md");

interface Cita { file: string; ranges: [number, number][]; at: number }

/** Citas `ruta:N`, `ruta:N-M`, `ruta:N,M` y continuaciones `:N` sobre la última ruta de la misma línea. */
export function citas(md: string): Cita[] {
  const out: Cita[] = [];
  md.split("\n").forEach((line, i) => {
    let last: string | null = null;
    for (const m of line.matchAll(/`([^`]+)`/g)) {
      const span = m[1];
      if (span.startsWith("[")) { last = null; continue; } // otra rama
      const full = /^((?:[\w.-]+\/)*[\w.-]+\.[A-Za-z]\w*):([\d,-]+)$/.exec(span);
      const cont = /^:([\d,-]+)$/.exec(span);
      const file: string | null = full ? full[1] : cont && last ? last : null;
      const spec: string | null = full ? full[2] : cont ? cont[1] : null;
      if (!file || !spec) continue;
      last = file;
      const ranges = spec.split(",").map((p): [number, number] => {
        const [a, b = a] = p.split("-").map((x) => (x === "" ? NaN : Number(x)));
        return [a, b];
      });
      out.push({ file, ranges, at: i + 1 });
    }
  });
  return out;
}

/** Número de líneas del fichero: un salto de línea final no cuenta como línea más. */
function contarLineas(texto: string): number {
  const partes = texto.split("\n");
  return partes.at(-1) === "" ? partes.length - 1 : partes.length;
}

function comprobarCitas(md: string, nombre: string): number {
  const cs = citas(md);
  for (const c of cs) {
    const p = resolve(PROJECT, c.file);
    assert.ok(p.startsWith(PROJECT + sep), `${nombre}:${c.at}: ${c.file} sale del proyecto`);
    assert.ok(existsSync(p), `${nombre}:${c.at}: no existe ${c.file}`);
    const n = contarLineas(readFileSync(p, "utf8"));
    for (const [a, b] of c.ranges) {
      for (const l of [a, b]) assert.ok(Number.isInteger(l) && l >= 1 && l <= n, `${nombre}:${c.at}: ${c.file} no tiene la línea ${l} (tiene ${n})`);
      assert.ok(a <= b, `${nombre}:${c.at}: ${c.file} tiene el rango invertido ${a}-${b}`);
    }
  }
  return cs.length;
}

test("las citas al código del documento de transparencia existen", () => {
  assert.ok(comprobarCitas(readFileSync(IT_PACK, "utf8"), "it-pack") >= 40, "el anexo debe citar el código");
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

test("negativo: la línea siguiente a la última, un rango invertido y una ruta que sale del proyecto se detectan", () => {
  // Recuento independiente de contarLineas: el fichero acaba en salto de línea, así que hay tantas líneas como saltos.
  const texto = readFileSync(join(PROJECT, "src/api/listen.ts"), "utf8");
  assert.ok(texto.endsWith("\n"));
  const n = texto.split("\n").length - 1;
  assert.equal(comprobarCitas(`\`src/api/listen.ts:${n}\``, "x"), 1);
  assert.throws(() => comprobarCitas(`\`src/api/listen.ts:${n + 1}\``, "x"), new RegExp(`no tiene la línea ${n + 1}`));
  assert.throws(() => comprobarCitas("`src/api/listen.ts:10-5`", "x"), /rango invertido 10-5/);
  assert.throws(() => comprobarCitas("`src/../../../package.json:1`", "x"), /sale del proyecto/);
});

test("las citas a ficheros fuera de src/test/bench/bin también se comprueban", () => {
  assert.equal(comprobarCitas("`package.json:1`", "x"), 1);
  assert.throws(() => comprobarCitas("`README.md:99999`", "x"), /no tiene la línea 99999/);
  assert.throws(() => comprobarCitas("`docs/no-existe.md:1`", "x"), /no existe/);
  // Una dirección con puerto no es una cita.
  assert.equal(comprobarCitas("`192.0.2.77:8787`", "x"), 0);
});

test("el documento de transparencia cubre lo que pide la spec y lista los huecos", () => {
  const md = readFileSync(IT_PACK, "utf8");
  for (const t of [/Qué lee/, /permisos/, /Qué guarda.*cuánto tiempo.*borra/, /escucha en la red.*nunca sale/, /desinstala/, /adaptador web/, /Huecos conocidos/, /Anexo/]) {
    assert.match(md, new RegExp(`^## .*${t.source}`, "m"), `falta el apartado ${t}`);
  }
  assert.match(md, /canal-amenazas\.md/, "debe remitir al modelo de amenazas del canal");
});

test("ninguno de los dos documentos lleva rutas personales", () => {
  for (const [nombre, f] of [["it-pack", IT_PACK], ["canal-amenazas", CANAL]]) {
    assert.doesNotMatch(readFileSync(f, "utf8"), /\/home\/|C:\\Users\\[A-Za-z]/, `${nombre}: sin rutas personales`);
  }
});

/** Huecos `H-n` de la tabla del it-pack: los citados en el texto están definidos y la numeración es contigua. */
export function problemasHuecosItPack(md: string): string[] {
  const [cuerpo, resto = ""] = md.split(/^## Huecos conocidos/m);
  const [tabla, anexo = ""] = resto.split(/^## Anexo/m);
  const definidos = [...tabla.matchAll(/^\| (H-\d+) \|/gm)].map((m) => m[1]);
  const citados = new Set([...(cuerpo + anexo).matchAll(/\bH-\d+\b/g)].map((m) => m[0]));
  const out: string[] = [];
  if (definidos.length === 0) out.push("falta la tabla de huecos");
  definidos.forEach((d, i) => { if (d !== `H-${i + 1}`) out.push(`numeración no contigua: ${d} en la posición ${i + 1}`); });
  for (const c of citados) if (!definidos.includes(c)) out.push(`${c} se cita pero no está en la tabla`);
  return out;
}

/** Referencias `[An]` del texto frente a las definiciones `**An**` del anexo, en ambos sentidos. */
export function problemasAnexo(md: string): string[] {
  const [cuerpo, anexo = ""] = md.split(/^## Anexo/m);
  const definidas = new Set([...anexo.matchAll(/^- \*\*(A\d+)\*\*/gm)].map((m) => m[1]));
  const citadas = new Set([...cuerpo.matchAll(/\[(A\d+(?:,\s*A\d+)*)\]/g)].flatMap((m) => m[1].split(/,\s*/)));
  const out: string[] = [];
  if (definidas.size === 0) out.push("falta el anexo");
  for (const c of citadas) if (!definidas.has(c)) out.push(`[${c}] se cita pero no está en el anexo`);
  for (const d of definidas) if (!citadas.has(d)) out.push(`${d} está en el anexo pero no se cita`);
  return out;
}

test("cada hueco H-n citado en el documento de transparencia está en su tabla", () => {
  assert.deepEqual(problemasHuecosItPack(readFileSync(IT_PACK, "utf8")), []);
});

test("cada referencia [An] del documento de transparencia está en el anexo, y cada una del anexo se cita", () => {
  assert.deepEqual(problemasAnexo(readFileSync(IT_PACK, "utf8")), []);
});

test("negativo: hueco sin definir, numeración con saltos y referencia del anexo huérfana se detectan", () => {
  const md = readFileSync(IT_PACK, "utf8");
  assert.ok(problemasHuecosItPack(md.replace("Ver H-3 y H-4", "Ver H-3 y H-42")).some((p) => p.includes("H-42 se cita")));
  assert.ok(problemasHuecosItPack(md.replace("| H-2 |", "| H-20 |")).some((p) => p.includes("no contigua")));
  assert.ok(problemasAnexo(md.replace("[A25]", "[A99]")).some((p) => p.includes("[A99] se cita")));
  assert.ok(problemasAnexo(md.replace("[A25]", "")).some((p) => p.includes("A25 está en el anexo pero no se cita")));
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
