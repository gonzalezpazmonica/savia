/**
 * Formato de estilo de la cara de Savia (SE-538 D2, D3).
 *
 * Un estilo es un JSON con formas y colores, sin código. Es el mismo formato
 * para Sonora y Space. Todo estilo pasa por `validateFaceStyle` antes de
 * pintarse: solo se admiten formas SVG básicas, números finitos, geometría de
 * path y colores que son tokens del tema. Cualquier otra cosa (href, url(),
 * <image>, colores literales, claves desconocidas) se rechaza y la cara cae al
 * estilo por defecto. Así un estilo no puede cargar nada de la red.
 */
import buhita from "./styles/buhita.json";
import circulo from "./styles/circulo.json";

/** Token de color → variable CSS del tema (claro, oscuro o sistema). */
export const FACE_COLOR_TOKENS = {
  ink: "--foreground",
  face: "--surface-solid",
  eye: "--background",
  body: "--secondary-color",
  "body-2": "--accent-color",
  accent: "--primary",
  "accent-strong": "--primary-400",
  muted: "--muted-foreground",
  alert: "--destructive",
} as const;

export type FaceColorToken = keyof typeof FACE_COLOR_TOKENS;
export type FacePart = "base" | "mouth" | "listen" | "think" | "offline";

type Paint = FaceColorToken | "none";

interface ShapeCommon {
  part: FacePart;
  fill?: Paint;
  stroke?: Paint;
  strokeWidth?: number;
  opacity?: number;
  strokeLinecap?: "round" | "butt" | "square";
}

export type FaceShape =
  | (ShapeCommon & { el: "path"; d: string })
  | (ShapeCommon & { el: "circle"; cx: number; cy: number; r: number })
  | (ShapeCommon & { el: "ellipse"; cx: number; cy: number; rx: number; ry: number })
  | (ShapeCommon & {
      el: "rect";
      x: number;
      y: number;
      width: number;
      height: number;
      rx?: number;
    });

export type FaceMouth =
  | { kind: "translateY"; max: number; staticLevel: number }
  | {
      kind: "scaleY";
      max: number;
      originX: number;
      originY: number;
      staticLevel: number;
    };

export interface FaceStyle {
  id: string;
  label: string;
  viewBox: string;
  mouth: FaceMouth;
  shapes: FaceShape[];
}

export type FaceValidation = { ok: true; style: FaceStyle } | { ok: false; error: string };

const COMMON_KEYS = ["el", "part", "fill", "stroke", "strokeWidth", "opacity", "strokeLinecap"];
const GEOMETRY: Record<FaceShape["el"], { numbers: string[]; optional?: string[]; d?: true }> = {
  path: { numbers: [], d: true },
  circle: { numbers: ["cx", "cy", "r"] },
  ellipse: { numbers: ["cx", "cy", "rx", "ry"] },
  rect: { numbers: ["x", "y", "width", "height"], optional: ["rx"] },
};
const PARTS: FacePart[] = ["base", "mouth", "listen", "think", "offline"];
const PATH_DATA = /^[MmLlHhVvCcSsQqTtAaZz0-9.,\s-]+$/;
const VIEWBOX = /^-?\d+(\.\d+)?( -?\d+(\.\d+)?){3}$/;
const STYLE_ID = /^[a-z0-9-]{1,32}$/;
const MAX_SHAPES = 64;

const hasOwn = (o: object, k: string): boolean => Object.prototype.hasOwnProperty.call(o, k);

function isRecord(v: unknown): v is Record<string, unknown> {
  return typeof v === "object" && v !== null && !Array.isArray(v);
}

function isFiniteNumber(v: unknown): v is number {
  return typeof v === "number" && Number.isFinite(v);
}

function isPaint(v: unknown): v is Paint {
  return v === "none" || (typeof v === "string" && hasOwn(FACE_COLOR_TOKENS, v));
}

function checkShape(raw: unknown, i: number): string | null {
  if (!isRecord(raw)) return `forma ${i}: no es un objeto`;
  const el = raw.el;
  if (typeof el !== "string" || !hasOwn(GEOMETRY, el)) {
    return `forma ${i}: elemento no permitido (${String(el)})`;
  }
  const geo = GEOMETRY[el as FaceShape["el"]];
  const allowed = new Set([...COMMON_KEYS, ...geo.numbers, ...(geo.optional ?? []), ...(geo.d ? ["d"] : [])]);
  for (const key of Object.keys(raw)) {
    if (!allowed.has(key)) return `forma ${i}: atributo no permitido (${key})`;
  }
  if (!PARTS.includes(raw.part as FacePart)) return `forma ${i}: parte desconocida`;
  for (const key of ["fill", "stroke"]) {
    if (raw[key] !== undefined && !isPaint(raw[key])) {
      return `forma ${i}: ${key} debe ser un token del tema`;
    }
  }
  for (const key of ["strokeWidth", "opacity"]) {
    if (raw[key] !== undefined && !isFiniteNumber(raw[key])) return `forma ${i}: ${key} no numérico`;
  }
  if (raw.strokeLinecap !== undefined && !["round", "butt", "square"].includes(raw.strokeLinecap as string)) {
    return `forma ${i}: strokeLinecap no válido`;
  }
  for (const key of geo.numbers) {
    if (!isFiniteNumber(raw[key])) return `forma ${i}: ${key} no numérico`;
  }
  for (const key of geo.optional ?? []) {
    if (raw[key] !== undefined && !isFiniteNumber(raw[key])) return `forma ${i}: ${key} no numérico`;
  }
  if (geo.d && (typeof raw.d !== "string" || raw.d.length > 2000 || !PATH_DATA.test(raw.d))) {
    return `forma ${i}: d no es geometría de path`;
  }
  return null;
}

function checkMouth(raw: unknown): string | null {
  if (!isRecord(raw)) return "mouth: no es un objeto";
  const keys =
    raw.kind === "translateY"
      ? ["kind", "max", "staticLevel"]
      : raw.kind === "scaleY"
        ? ["kind", "max", "originX", "originY", "staticLevel"]
        : null;
  if (!keys) return "mouth: tipo desconocido";
  for (const key of Object.keys(raw)) if (!keys.includes(key)) return `mouth: clave no permitida (${key})`;
  for (const key of keys.slice(1)) if (!isFiniteNumber(raw[key])) return `mouth: ${key} no numérico`;
  const level = raw.staticLevel as number;
  if (level < 0 || level > 1) return "mouth: staticLevel fuera de 0..1";
  return null;
}

export function validateFaceStyle(raw: unknown): FaceValidation {
  if (!isRecord(raw)) return { ok: false, error: "el estilo no es un objeto" };
  for (const key of Object.keys(raw)) {
    if (!["id", "label", "viewBox", "mouth", "shapes"].includes(key)) {
      return { ok: false, error: `clave no permitida (${key})` };
    }
  }
  if (typeof raw.id !== "string" || !STYLE_ID.test(raw.id)) return { ok: false, error: "id no válido" };
  if (typeof raw.label !== "string" || raw.label.length === 0 || raw.label.length > 40) {
    return { ok: false, error: "label no válido" };
  }
  if (typeof raw.viewBox !== "string" || !VIEWBOX.test(raw.viewBox)) {
    return { ok: false, error: "viewBox no válido" };
  }
  const mouthError = checkMouth(raw.mouth);
  if (mouthError) return { ok: false, error: mouthError };
  if (!Array.isArray(raw.shapes) || raw.shapes.length === 0 || raw.shapes.length > MAX_SHAPES) {
    return { ok: false, error: "shapes vacío o demasiado largo" };
  }
  for (let i = 0; i < raw.shapes.length; i++) {
    const err = checkShape(raw.shapes[i], i);
    if (err) return { ok: false, error: err };
  }
  return { ok: true, style: raw as unknown as FaceStyle };
}

function mustValidate(raw: unknown): FaceStyle {
  const res = validateFaceStyle(raw);
  if (!res.ok) throw new Error(`estilo de cara incluido no válido: ${res.error}`);
  return res.style;
}

export const BUILTIN_FACE_STYLES: Record<string, FaceStyle> = {
  buhita: mustValidate(buhita),
  circulo: mustValidate(circulo),
};

export const DEFAULT_FACE_STYLE_ID = "buhita";

/**
 * Devuelve un estilo pintable. Acepta el id de un estilo incluido o un JSON
 * de estilo; si el id no existe o el JSON no pasa la validación, devuelve el
 * estilo por defecto.
 */
export function resolveFaceStyle(input: unknown): FaceStyle {
  const fallback = BUILTIN_FACE_STYLES[DEFAULT_FACE_STYLE_ID];
  if (typeof input === "string") {
    return hasOwn(BUILTIN_FACE_STYLES, input) ? BUILTIN_FACE_STYLES[input] : fallback;
  }
  const res = validateFaceStyle(input);
  if (!res.ok) {
    console.warn(`[SaviaFace] estilo rechazado: ${res.error}; uso «${fallback.label}»`);
    return fallback;
  }
  return res.style;
}

export function paintVar(paint: Paint | undefined): string | undefined {
  if (paint === undefined) return undefined;
  if (paint === "none") return "none";
  return `var(${FACE_COLOR_TOKENS[paint]})`;
}
