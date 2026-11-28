import { describe, it, expect } from "vitest";
import {
  BUILTIN_FACE_STYLES,
  DEFAULT_FACE_STYLE_ID,
  resolveFaceStyle,
  validateFaceStyle,
} from "./faceStyle";
import buhita from "./styles/buhita.json";

function clone<T>(v: T): T {
  return JSON.parse(JSON.stringify(v)) as T;
}

describe("validateFaceStyle", () => {
  it("acepta los dos estilos incluidos", () => {
    expect(Object.keys(BUILTIN_FACE_STYLES).sort()).toEqual(["buhita", "circulo"]);
    for (const style of Object.values(BUILTIN_FACE_STYLES)) {
      expect(validateFaceStyle(style).ok).toBe(true);
    }
  });

  it("rechaza un atributo con url() externa", () => {
    const bad = clone(buhita) as Record<string, unknown>;
    (bad.shapes as Array<Record<string, unknown>>)[0].fill =
      "url(https://example.com/x.svg#g)";
    const res = validateFaceStyle(bad);
    expect(res.ok).toBe(false);
  });

  it("rechaza un elemento image con href externo", () => {
    const bad = clone(buhita) as Record<string, unknown>;
    (bad.shapes as Array<Record<string, unknown>>).push({
      el: "image",
      href: "https://example.com/cara.png",
      part: "base",
    });
    expect(validateFaceStyle(bad).ok).toBe(false);
  });

  it("rechaza un atributo href aunque el elemento sea válido", () => {
    const bad = clone(buhita) as Record<string, unknown>;
    (bad.shapes as Array<Record<string, unknown>>)[0].href = "//cdn.example.com/a";
    expect(validateFaceStyle(bad).ok).toBe(false);
  });

  it("rechaza un color literal que no es un token del tema", () => {
    const bad = clone(buhita) as Record<string, unknown>;
    (bad.shapes as Array<Record<string, unknown>>)[0].fill = "#ff0000";
    expect(validateFaceStyle(bad).ok).toBe(false);
  });

  it("rechaza un path con algo que no es geometría", () => {
    const bad = clone(buhita) as Record<string, unknown>;
    (bad.shapes as Array<Record<string, unknown>>)[0].d = "M0 0 url(http://x)";
    expect(validateFaceStyle(bad).ok).toBe(false);
  });
});

describe("resolveFaceStyle", () => {
  it("un estilo con URL externa cae al estilo por defecto", () => {
    const bad = clone(buhita) as Record<string, unknown>;
    bad.id = "maliciosa";
    (bad.shapes as Array<Record<string, unknown>>)[0].stroke =
      "url(http://evil.example/p)";
    const style = resolveFaceStyle(bad);
    expect(style.id).toBe(DEFAULT_FACE_STYLE_ID);
  });

  it("un id conocido resuelve a su estilo", () => {
    expect(resolveFaceStyle("circulo").id).toBe("circulo");
  });

  it("un id desconocido cae al estilo por defecto", () => {
    expect(resolveFaceStyle("otro").id).toBe(DEFAULT_FACE_STYLE_ID);
  });
});
