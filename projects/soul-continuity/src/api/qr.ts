/**
 * Codificador QR propio para `soul pair` (SE-490, soul-pair-v2): modo byte, corrección M,
 * versiones 1–10 (hasta 213 bytes, de sobra para el enlace `soul://pair?...`). Sin dependencias.
 *
 * Sigue ISO/IEC 18004: Reed-Solomon sobre GF(256) con 0x11D, información de formato BCH(15,5)
 * con máscara 0x5412, información de versión BCH(18,6) desde la 7, y la máscara de menor
 * penalización. Salidas: texto Unicode de medio bloque con colores fijos (negro sobre blanco,
 * así se lee igual en terminales claros y oscuros) y PNG en escala de grises.
 *
 * El QR de `soul pair` lleva la clave de emparejamiento: quien lo muestre lo trata como secreto.
 */

import { crc32, deflateSync } from "node:zlib";

/** Codewords de corrección por bloque y número de bloques, nivel M, versiones 1–10 (índice = versión). */
const ECC_M = [0, 10, 16, 26, 18, 24, 16, 18, 22, 22, 26];
const BLOCKS_M = [0, 1, 1, 1, 2, 2, 4, 4, 4, 5, 5];
export const QR_MAX_VERSION = 10;
/** Bits del nivel M en la información de formato (ISO 18004: M = 00). */
const ECL_M_BITS = 0;

export type Matriz = boolean[][];

// ---------------------------------------------------------------- Reed-Solomon sobre GF(256)

function gfMul(x: number, y: number): number {
  let z = 0;
  for (let i = 7; i >= 0; i--) {
    z = (z << 1) ^ ((z >>> 7) * 0x11d);
    z ^= ((y >>> i) & 1) * x;
  }
  return z & 0xff;
}

function rsDivisor(degree: number): number[] {
  const r = new Array<number>(degree).fill(0);
  r[degree - 1] = 1;
  let root = 1;
  for (let i = 0; i < degree; i++) {
    for (let j = 0; j < degree; j++) {
      r[j] = gfMul(r[j], root);
      if (j + 1 < degree) r[j] ^= r[j + 1];
    }
    root = gfMul(root, 0x02);
  }
  return r;
}

/** Codewords de corrección de `data`: resto de la división por el polinomio generador. */
export function rsEcc(data: number[], degree: number): number[] {
  const div = rsDivisor(degree);
  const r = new Array<number>(degree).fill(0);
  for (const b of data) {
    const f = b ^ r.shift()!;
    r.push(0);
    for (let i = 0; i < degree; i++) r[i] ^= gfMul(div[i], f);
  }
  return r;
}

// ---------------------------------------------------------------- formato, versión y capacidad

/** 15 bits de formato (corrección M + máscara), ya enmascarados con 0x5412. */
export function formatBits(mask: number): number {
  const d = (ECL_M_BITS << 3) | mask;
  let r = d;
  for (let i = 0; i < 10; i++) r = (r << 1) ^ ((r >>> 9) * 0x537);
  return ((d << 10) | r) ^ 0x5412;
}

/** 18 bits de información de versión (versiones ≥ 7). */
export function versionBits(v: number): number {
  let r = v;
  for (let i = 0; i < 12; i++) r = (r << 1) ^ ((r >>> 11) * 0x1f25);
  return (v << 12) | r;
}

/** Módulos disponibles para datos y corrección en la versión `v`. */
function rawModules(v: number): number {
  let r = (16 * v + 128) * v + 64;
  if (v >= 2) {
    const n = Math.floor(v / 7) + 2;
    r -= (25 * n - 10) * n - 55;
    if (v >= 7) r -= 36;
  }
  return r;
}

const dataCodewords = (v: number) => Math.floor(rawModules(v) / 8) - ECC_M[v] * BLOCKS_M[v];
/** Bytes que caben en modo byte: 4 bits de modo + 8 (v ≤ 9) o 16 bits de longitud. */
export const byteCapacity = (v: number) => Math.floor((dataCodewords(v) * 8 - 4 - (v <= 9 ? 8 : 16)) / 8);

function alignment(v: number): number[] {
  if (v === 1) return [];
  const n = Math.floor(v / 7) + 2;
  const step = Math.ceil((v * 4 + 4) / (n * 2 - 2)) * 2;
  const r = [6];
  for (let p = v * 4 + 10; r.length < n; p -= step) r.splice(1, 0, p);
  return r;
}

// ---------------------------------------------------------------- datos y bloques

/** Codewords de datos en modo byte, con terminador y relleno 0xEC/0x11. */
function encodeData(bytes: Uint8Array, v: number): number[] {
  const bits: number[] = [];
  const put = (val: number, n: number) => { for (let i = n - 1; i >= 0; i--) bits.push((val >>> i) & 1); };
  put(0b0100, 4);
  put(bytes.length, v <= 9 ? 8 : 16);
  for (const b of bytes) put(b, 8);
  put(0, Math.min(4, dataCodewords(v) * 8 - bits.length));
  put(0, (8 - (bits.length % 8)) % 8);
  const out: number[] = [];
  for (let i = 0; i < bits.length; i += 8) out.push(parseInt(bits.slice(i, i + 8).join(""), 2));
  for (let pad = 0xec; out.length < dataCodewords(v); pad ^= 0xec ^ 0x11) out.push(pad);
  return out;
}

/** Reparte en bloques (los cortos primero), añade la corrección de cada uno y entrelaza. */
function interleave(data: number[], v: number): number[] {
  const nb = BLOCKS_M[v], ec = ECC_M[v];
  const total = Math.floor(rawModules(v) / 8);
  const nShort = nb - (total % nb);
  const shortLen = Math.floor(total / nb) - ec;
  const blocks: { d: number[]; e: number[] }[] = [];
  for (let i = 0, k = 0; i < nb; i++) {
    const len = shortLen + (i < nShort ? 0 : 1);
    const d = data.slice(k, k + len);
    k += len;
    blocks.push({ d, e: rsEcc(d, ec) });
  }
  const out: number[] = [];
  for (let i = 0; i <= shortLen; i++) for (const b of blocks) if (i < b.d.length) out.push(b.d[i]);
  for (let i = 0; i < ec; i++) for (const b of blocks) out.push(b.e[i]);
  return out;
}

// ---------------------------------------------------------------- matriz

const MASKS: ((x: number, y: number) => boolean)[] = [
  (x, y) => (x + y) % 2 === 0,
  (_x, y) => y % 2 === 0,
  (x) => x % 3 === 0,
  (x, y) => (x + y) % 3 === 0,
  (x, y) => (Math.floor(x / 3) + Math.floor(y / 2)) % 2 === 0,
  (x, y) => ((x * y) % 2) + ((x * y) % 3) === 0,
  (x, y) => (((x * y) % 2) + ((x * y) % 3)) % 2 === 0,
  (x, y) => (((x + y) % 2) + ((x * y) % 3)) % 2 === 0,
];

/** Recorrido en zigzag de los módulos de datos, desde abajo a la derecha. */
function dataPositions(size: number, fn: Matriz): [number, number][] {
  const r: [number, number][] = [];
  for (let right = size - 1; right >= 1; right -= 2) {
    if (right === 6) right = 5;
    for (let vert = 0; vert < size; vert++) {
      for (let j = 0; j < 2; j++) {
        const x = right - j;
        const y = ((right + 1) & 2) === 0 ? size - 1 - vert : vert;
        if (!fn[y][x]) r.push([x, y]);
      }
    }
  }
  return r;
}

function drawFormat(m: Matriz, fn: Matriz, mask: number) {
  const size = m.length, b = formatBits(mask);
  const bit = (i: number) => ((b >>> i) & 1) === 1;
  const set = (x: number, y: number, d: boolean) => { m[y][x] = d; fn[y][x] = true; };
  for (let i = 0; i <= 5; i++) set(8, i, bit(i));
  set(8, 7, bit(6)); set(8, 8, bit(7)); set(7, 8, bit(8));
  for (let i = 9; i < 15; i++) set(14 - i, 8, bit(i));
  for (let i = 0; i < 8; i++) set(size - 1 - i, 8, bit(i));
  for (let i = 8; i < 15; i++) set(8, size - 15 + i, bit(i));
  set(8, size - 8, true);
}

/** Patrones de función: buscadores con separador, temporización, alineación, formato y versión. */
function base(v: number): { size: number; m: Matriz; fn: Matriz } {
  const size = v * 4 + 17;
  const m: Matriz = Array.from({ length: size }, () => new Array<boolean>(size).fill(false));
  const fn: Matriz = Array.from({ length: size }, () => new Array<boolean>(size).fill(false));
  const set = (x: number, y: number, d: boolean) => { m[y][x] = d; fn[y][x] = true; };
  for (let i = 0; i < size; i++) { set(6, i, i % 2 === 0); set(i, 6, i % 2 === 0); }
  for (const [cx, cy] of [[3, 3], [size - 4, 3], [3, size - 4]]) {
    for (let dy = -4; dy <= 4; dy++) for (let dx = -4; dx <= 4; dx++) {
      const x = cx + dx, y = cy + dy;
      if (x < 0 || y < 0 || x >= size || y >= size) continue;
      const d = Math.max(Math.abs(dx), Math.abs(dy));
      set(x, y, d !== 2 && d !== 4);
    }
  }
  const al = alignment(v), last = al[al.length - 1];
  for (const ay of al) for (const ax of al) {
    if ((ax === 6 && ay === 6) || (ax === 6 && ay === last) || (ax === last && ay === 6)) continue;
    for (let dy = -2; dy <= 2; dy++) for (let dx = -2; dx <= 2; dx++) set(ax + dx, ay + dy, Math.max(Math.abs(dx), Math.abs(dy)) !== 1);
  }
  drawFormat(m, fn, 0);
  if (v >= 7) {
    const b = versionBits(v);
    for (let i = 0; i < 18; i++) {
      const d = ((b >>> i) & 1) === 1, a = size - 11 + (i % 3), c = Math.floor(i / 3);
      set(a, c, d); set(c, a, d);
    }
  }
  return { size, m, fn };
}

/** Penalización de ISO 18004 (rachas, bloques 2×2, falsos buscadores y equilibrio de oscuros). */
function penalty(m: Matriz): number {
  const size = m.length;
  let p = 0;
  const linea = (get: (i: number) => boolean) => {
    let run = 1;
    for (let i = 1; i <= size; i++) {
      if (i < size && get(i) === get(i - 1)) { run++; continue; }
      if (run >= 5) p += 3 + run - 5;
      run = 1;
    }
    // 1011101 con cuatro claros a un lado; fuera de la matriz cuenta como claro.
    const at = (i: number) => i >= 0 && i < size && get(i);
    for (let i = -4; i < size; i++) {
      if (at(i) && !at(i + 1) && at(i + 2) && at(i + 3) && at(i + 4) && !at(i + 5) && at(i + 6)) {
        if ([1, 2, 3, 4].every((k) => !at(i - k)) || [7, 8, 9, 10].every((k) => !at(i + k))) p += 40;
      }
    }
  };
  for (let y = 0; y < size; y++) linea((x) => m[y][x]);
  for (let x = 0; x < size; x++) linea((y) => m[y][x]);
  for (let y = 0; y < size - 1; y++) for (let x = 0; x < size - 1; x++) {
    const c = m[y][x];
    if (c === m[y][x + 1] && c === m[y + 1][x] && c === m[y + 1][x + 1]) p += 3;
  }
  let dark = 0;
  for (const row of m) for (const c of row) if (c) dark++;
  const total = size * size;
  return p + (Math.ceil(Math.abs(dark * 20 - total * 10) / total) - 1) * 10;
}

/** QR de `text` (UTF-8, modo byte, corrección M) con la versión mínima y la máscara de menor penalización. */
export function encodeQr(text: string): { version: number; mask: number; modules: Matriz } {
  const bytes = new TextEncoder().encode(text);
  let v = 1;
  while (v <= QR_MAX_VERSION && byteCapacity(v) < bytes.length) v++;
  if (v > QR_MAX_VERSION) throw new Error(`QR: ${bytes.length} bytes no caben en la versión ${QR_MAX_VERSION}-M`);
  const cw = interleave(encodeData(bytes, v), v);
  let mejor: { mask: number; modules: Matriz; p: number } | null = null;
  for (let mask = 0; mask < 8; mask++) {
    const { size, m, fn } = base(v);
    dataPositions(size, fn).forEach(([x, y], i) => {
      const d = i < cw.length * 8 && ((cw[i >>> 3] >>> (7 - (i & 7))) & 1) === 1;
      m[y][x] = d !== MASKS[mask](x, y);
    });
    drawFormat(m, fn, mask);
    const p = penalty(m);
    if (!mejor || p < mejor.p) mejor = { mask, modules: m, p };
  }
  return { version: v, mask: mejor!.mask, modules: mejor!.modules };
}

// ---------------------------------------------------------------- salidas

const QUIET = 4;

/**
 * Medios bloques: cada carácter son dos filas de módulos. Colores ANSI fijos (negro sobre fondo
 * blanco) y zona de silencio de 4 módulos, para que se lea con cualquier tema de terminal.
 */
export function qrToTerminal(m: Matriz): string {
  const size = m.length, n = size + QUIET * 2;
  const dark = (x: number, y: number) => x >= QUIET && y >= QUIET && x < size + QUIET && y < size + QUIET && m[y - QUIET][x - QUIET];
  const lines: string[] = [];
  for (let y = 0; y < n; y += 2) {
    let s = "\x1b[30;47m";
    for (let x = 0; x < n; x++) {
      const a = dark(x, y), b = dark(x, y + 1);
      s += a && b ? "█" : a ? "▀" : b ? "▄" : " ";
    }
    lines.push(s + "\x1b[0m");
  }
  return lines.join("\n");
}

function chunk(type: string, data: Buffer): Buffer {
  const len = Buffer.alloc(4);
  len.writeUInt32BE(data.length);
  const td = Buffer.concat([Buffer.from(type, "ascii"), data]);
  const crc = Buffer.alloc(4);
  crc.writeUInt32BE(crc32(td));
  return Buffer.concat([len, td, crc]);
}

/** PNG en escala de grises de 8 bits, `scale` píxeles por módulo y zona de silencio de 4 módulos. */
export function qrToPng(m: Matriz, scale = 8): Buffer {
  const size = m.length, px = (size + QUIET * 2) * scale;
  const raw = Buffer.alloc((px + 1) * px, 0xff);
  for (let y = 0; y < px; y++) {
    raw[y * (px + 1)] = 0;
    const my = Math.floor(y / scale) - QUIET;
    for (let x = 0; x < px; x++) {
      const mx = Math.floor(x / scale) - QUIET;
      if (my >= 0 && mx >= 0 && my < size && mx < size && m[my][mx]) raw[y * (px + 1) + 1 + x] = 0;
    }
  }
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(px, 0);
  ihdr.writeUInt32BE(px, 4);
  ihdr[8] = 8;
  return Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    chunk("IHDR", ihdr), chunk("IDAT", deflateSync(raw)), chunk("IEND", Buffer.alloc(0)),
  ]);
}
