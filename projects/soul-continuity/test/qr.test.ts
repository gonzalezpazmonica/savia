import { test } from "node:test";
import assert from "node:assert/strict";
import { inflateSync } from "node:zlib";
import { byteCapacity, encodeQr, formatBits, qrToPng, qrToTerminal, rsEcc, versionBits } from "../src/api/qr.ts";

// ------------------------------------------------------------------ vectores conocidos (ISO 18004 / thonky.com)

test("Reed-Solomon: el ejemplo «HELLO WORLD» 1-M da los 10 codewords de corrección publicados", () => {
  const data = [32, 91, 11, 120, 209, 114, 220, 77, 67, 64, 236, 17, 236, 17, 236, 17];
  assert.deepEqual(rsEcc(data, 10), [196, 35, 39, 119, 235, 215, 231, 226, 93, 23]);
  assert.notDeepEqual(rsEcc([33, ...data.slice(1)], 10), [196, 35, 39, 119, 235, 215, 231, 226, 93, 23], "control: otro dato, otra corrección");
});

test("formato del nivel M: las 8 cadenas de la tabla de la norma", () => {
  const M = ["101010000010010", "101000100100101", "101111001111100", "101101101001011", "100010111111001", "100000011001110", "100111110010111", "100101010100000"];
  M.forEach((s, mask) => assert.equal(formatBits(mask).toString(2).padStart(15, "0"), s, `máscara ${mask}`));
});

test("información de versión: la 7 es 000111110010010100 y todas son múltiplo del generador BCH 0x1F25", () => {
  assert.equal(versionBits(7).toString(2).padStart(18, "0"), "000111110010010100");
  for (let v = 7; v <= 10; v++) {
    let r = versionBits(v);
    for (let i = 17; i >= 12; i--) if ((r >>> i) & 1) r ^= 0x1f25 << (i - 12);
    assert.equal(r, 0, `versión ${v}`);
    assert.equal(versionBits(v) >>> 12, v);
  }
});

test("capacidad en modo byte, nivel M, versiones 1–10 (tabla de la norma)", () => {
  assert.deepEqual([1, 2, 3, 4, 5, 6, 7, 8, 9, 10].map(byteCapacity), [14, 26, 42, 62, 84, 106, 122, 152, 180, 213]);
});

// ------------------------------------------------------------------ decodificador independiente para las pruebas

const ALINEACION: Record<number, number[]> = { 1: [], 2: [6, 18], 3: [6, 22], 4: [6, 26], 5: [6, 30], 6: [6, 34], 7: [6, 22, 38], 8: [6, 24, 42], 9: [6, 26, 46], 10: [6, 28, 50] };
const BLOQUES: Record<number, { ec: number; grupos: [number, number][] }> = {
  1: { ec: 10, grupos: [[1, 16]] }, 2: { ec: 16, grupos: [[1, 28]] }, 3: { ec: 26, grupos: [[1, 44]] }, 4: { ec: 18, grupos: [[2, 32]] },
  5: { ec: 24, grupos: [[2, 43]] }, 6: { ec: 16, grupos: [[4, 27]] }, 7: { ec: 18, grupos: [[4, 31]] }, 8: { ec: 22, grupos: [[2, 38], [2, 39]] },
  9: { ec: 22, grupos: [[3, 36], [2, 37]] }, 10: { ec: 26, grupos: [[4, 43], [1, 44]] },
};

function mul(a: number, b: number) {
  let r = 0;
  while (b) { if (b & 1) r ^= a; a <<= 1; if (a & 0x100) a ^= 0x11d; b >>= 1; }
  return r;
}

/** Lee el QR como lo haría un lector: formato, desenmascarado, bloques, síndromes y datos. */
function decodificar(m: boolean[][]): { modo: number; texto: string; mascara: number; sindromesCero: boolean } {
  const size = m.length, v = (size - 17) / 4;
  assert.ok(Number.isInteger(v) && v >= 1 && v <= 10);
  // Patrones de posición en las tres esquinas.
  for (const [ox, oy] of [[0, 0], [size - 7, 0], [0, size - 7]]) {
    for (let y = 0; y < 7; y++) for (let x = 0; x < 7; x++) {
      const d = Math.max(Math.abs(x - 3), Math.abs(y - 3));
      assert.equal(m[oy + y][ox + x], d !== 2, `buscador en ${ox},${oy}`);
    }
  }
  for (let i = 8; i < size - 8; i++) { assert.equal(m[6][i], i % 2 === 0); assert.equal(m[i][6], i % 2 === 0); }
  // Formato (las dos copias deben coincidir).
  let f1 = 0, f2 = 0;
  const a1: [number, number][] = [[8, 0], [8, 1], [8, 2], [8, 3], [8, 4], [8, 5], [8, 7], [8, 8], [7, 8], [5, 8], [4, 8], [3, 8], [2, 8], [1, 8], [0, 8]];
  a1.forEach(([x, y], i) => { if (m[y][x]) f1 |= 1 << i; });
  for (let i = 0; i < 8; i++) if (m[8][size - 1 - i]) f2 |= 1 << i;
  for (let i = 8; i < 15; i++) if (m[size - 15 + i][8]) f2 |= 1 << i;
  assert.equal(f1, f2, "las dos copias del formato coinciden");
  const fd = (f1 ^ 0x5412) >>> 10;
  assert.equal(fd >>> 3, 0, "nivel M");
  const mascara = fd & 7;
  // Módulos de función, calculados aquí por separado.
  const fn = Array.from({ length: size }, () => new Array<boolean>(size).fill(false));
  const marca = (x0: number, y0: number, w: number, h: number) => { for (let y = y0; y < y0 + h; y++) for (let x = x0; x < x0 + w; x++) if (x >= 0 && y >= 0 && x < size && y < size) fn[y][x] = true; };
  marca(0, 0, 9, 9); marca(size - 8, 0, 8, 9); marca(0, size - 8, 9, 8);
  marca(6, 0, 1, size); marca(0, 6, size, 1);
  const al = ALINEACION[v];
  const ult = al[al.length - 1];
  for (const y of al) for (const x of al) if (!((x === 6 && y === 6) || (x === ult && y === 6) || (x === 6 && y === ult))) marca(x - 2, y - 2, 5, 5);
  if (v >= 7) { marca(size - 11, 0, 3, 6); marca(0, size - 11, 6, 3); }
  // Zigzag y desenmascarado.
  const masc = [(x: number, y: number) => (x + y) % 2 === 0, (_: number, y: number) => y % 2 === 0, (x: number) => x % 3 === 0, (x: number, y: number) => (x + y) % 3 === 0,
    (x: number, y: number) => (Math.floor(y / 2) + Math.floor(x / 3)) % 2 === 0, (x: number, y: number) => ((x * y) % 2) + ((x * y) % 3) === 0,
    (x: number, y: number) => (((x * y) % 2) + ((x * y) % 3)) % 2 === 0, (x: number, y: number) => (((x + y) % 2) + ((x * y) % 3)) % 2 === 0][mascara];
  const bits: number[] = [];
  let arriba = true;
  for (let col = size - 1; col > 0; col -= 2) {
    if (col === 6) col--;
    for (let k = 0; k < size; k++) {
      const y = arriba ? size - 1 - k : k;
      for (const x of [col, col - 1]) if (!fn[y][x]) bits.push((m[y][x] !== masc(x, y)) ? 1 : 0);
    }
    arriba = !arriba;
  }
  const cw: number[] = [];
  for (let i = 0; i + 8 <= bits.length; i += 8) cw.push(parseInt(bits.slice(i, i + 8).join(""), 2));
  // Desentrelazado y síndromes.
  const { ec, grupos } = BLOQUES[v];
  const lens = grupos.flatMap(([n, l]) => new Array<number>(n).fill(l));
  const bloques = lens.map(() => [] as number[]);
  let k = 0;
  for (let i = 0; i < Math.max(...lens); i++) lens.forEach((l, b) => { if (i < l) bloques[b].push(cw[k++]); });
  for (let i = 0; i < ec; i++) bloques.forEach((b) => b.push(cw[k++]));
  let sindromesCero = true;
  for (const b of bloques) {
    let alfa = 1;
    for (let i = 0; i < ec; i++) {
      let s = 0;
      for (const c of b) s = mul(s, alfa) ^ c;
      if (s !== 0) sindromesCero = false;
      alfa = mul(alfa, 2);
    }
  }
  const datos = bloques.flatMap((b, i) => b.slice(0, lens[i]));
  const db = datos.flatMap((c) => [7, 6, 5, 4, 3, 2, 1, 0].map((s) => (c >>> s) & 1));
  const leer = (p: number, n: number) => parseInt(db.slice(p, p + n).join(""), 2);
  const modo = leer(0, 4);
  const nl = v <= 9 ? 8 : 16, len = Math.min(leer(4, nl), datos.length);
  const out = new Uint8Array(len);
  for (let i = 0; i < len; i++) out[i] = leer(4 + nl + i * 8, 8);
  return { modo, texto: new TextDecoder().decode(out), mascara, sindromesCero };
}

// ------------------------------------------------------------------ codificador completo

const ENLACE = "soul://pair?v=2&h=100.64.0.1&p=8443&k=soulpk_7Kq2MdX9QxF4pZr8TbW1nVc3LhJ6sY_2aIow1&f=20e27497e834bc56";

test("el QR del enlace de emparejamiento se lee de vuelta con un decodificador independiente (varias versiones)", () => {
  const casos = [["SOUL", 1], [ENLACE, 6], [ENLACE.replace("100.64.0.1", "[fd7a:115c:a1e0::1]"), 7], ["x".repeat(213), 10]] as const;
  for (const [texto, version] of casos) {
    const q = encodeQr(texto);
    assert.equal(q.version, version, texto.slice(0, 20));
    assert.equal(q.modules.length, version * 4 + 17);
    const d = decodificar(q.modules);
    assert.equal(d.modo, 0b0100, "modo byte");
    assert.equal(d.texto, texto);
    assert.equal(d.mascara, q.mask);
    assert.equal(d.sindromesCero, true, "la corrección de errores cuadra");
  }
});

test("control: un módulo de datos cambiado rompe los síndromes, y un texto que no cabe da error", () => {
  const q = encodeQr(ENLACE);
  const m = q.modules.map((r) => [...r]);
  const s = m.length;
  m[s - 1][s - 1] = !m[s - 1][s - 1];
  assert.equal(decodificar(m).sindromesCero, false);
  assert.throws(() => encodeQr("x".repeat(214)), /no caben/);
});

test("terminal: medios bloques con negro sobre blanco fijo y zona de silencio de 4 módulos", () => {
  const q = encodeQr(ENLACE);
  const t = qrToTerminal(q.modules);
  const lines = t.split("\n");
  const n = q.modules.length + 8;
  assert.equal(lines.length, Math.ceil(n / 2));
  for (const l of lines) {
    assert.ok(l.startsWith("\x1b[30;47m") && l.endsWith("\x1b[0m"));
    const cuerpo = l.slice(8, -4);
    assert.equal([...cuerpo].length, n);
    assert.match(cuerpo, /^[ █▀▄]+$/);
  }
  // Se reconstruye la matriz desde el texto: ▀ es oscuro arriba, ▄ oscuro abajo.
  const filas: boolean[][] = [];
  for (const l of lines) {
    const cs = [...l.slice(8, -4)];
    filas.push(cs.map((c) => c === "█" || c === "▀"), cs.map((c) => c === "█" || c === "▄"));
  }
  const size = q.modules.length;
  for (let y = 0; y < size; y++) assert.deepEqual(filas[y + 4].slice(4, 4 + size), q.modules[y], `fila ${y}`);
  assert.match(lines[0].slice(8, -4), /^ +$/, "la primera fila es zona de silencio");
  assert.match(lines[2].slice(8, -4), /^ {4}█/, "el buscador empieza tras 4 módulos claros");
});

test("PNG: firma, cabecera y píxeles que corresponden a los módulos", () => {
  const q = encodeQr(ENLACE);
  const scale = 4, size = q.modules.length, px = (size + 8) * scale;
  const png = qrToPng(q.modules, scale);
  assert.deepEqual([...png.subarray(0, 8)], [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
  assert.equal(png.subarray(12, 16).toString("ascii"), "IHDR");
  assert.equal(png.readUInt32BE(16), px);
  assert.equal(png.readUInt32BE(20), px);
  const idat = png.indexOf("IDAT");
  const raw = inflateSync(png.subarray(idat + 4, idat + 4 + png.readUInt32BE(idat - 4)));
  assert.equal(raw.length, (px + 1) * px);
  const pixel = (mx: number, my: number) => raw[((my + 4) * scale + 1) * (px + 1) + 1 + (mx + 4) * scale + 1];
  for (let y = 0; y < size; y++) for (let x = 0; x < size; x++) assert.equal(pixel(x, y), q.modules[y][x] ? 0 : 255);
  assert.equal(raw[1], 255, "zona de silencio blanca");
});
