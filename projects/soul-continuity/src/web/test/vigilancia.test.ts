// Vigilancia sin receta: solo «esta página cambió», con el enlace. Parte pura;
// lo que lanza un navegador está en test/navegador/vigilancia.test.ts.
import { test } from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { AlmacenHuellas, clasificarSalida, huellaTexto, recetaDeVigilancia, VigilanciaInvalida } from "../adaptador/vigilancia.ts";

test("la receta sintetizada solo admite esa URL exacta, sin JS, POST, WebSocket ni acciones", () => {
  const r = recetaDeVigilancia({ id: "portal", sitio: "Portal", url: "https://intra.example/avisos?vista=lista" });
  assert.equal(r.origen, "https://intra.example");
  assert.deepEqual(r.urls, ["/avisos?vista=lista"]);
  assert.deepEqual([r.javascript, r.post_lectura.length, r.websocket.urls.length, r.acciones.length, r.renovacion_sesion.length],
    [false, 0, 0, 0, 0]);
});

test("URL de vigilancia inválida: acción, credenciales, comodín, fragmento, esquema", () => {
  for (const url of ["https://intra.example/approve?id=1", "https://u:p@intra.example/a", "https://intra.example/a*",
    "https://intra.example/a#x", "file:///etc/passwd", "javascript:alert(1)", "no es url"]) {
    assert.throws(() => recetaDeVigilancia({ id: "x", sitio: "X", url }), VigilanciaInvalida, url);
  }
});

test("huella: normaliza espacios; cambia si cambia el texto", () => {
  assert.equal(huellaTexto(" a\n\n b  "), huellaTexto("a b"));
  assert.notEqual(huellaTexto("a b"), huellaTexto("a c"));
});

test("almacén: guarda solo huella, URL y fecha; nunca el texto", () => {
  const d = mkdtempSync(join(tmpdir(), "soul-vig-"));
  try {
    const a = new AlmacenHuellas(join(d, "huellas.json"));
    assert.equal(a.anterior("p"), null);
    a.guardar("p", "https://intra.example/a", huellaTexto("texto secreto de la página"));
    assert.equal(a.anterior("p"), huellaTexto("texto secreto de la página"));
    const crudo = readFileSync(join(d, "huellas.json"), "utf8");
    assert.ok(!crudo.includes("secreto"));
    assert.deepEqual(Object.keys(JSON.parse(crudo).p).sort(), ["huella", "url", "visto_en"]);
  } finally { rmSync(d, { recursive: true, force: true }); }
});
test("almacén ilegible: falla en vez de tratar todo como primera visita (revisión #1443 P2-3)", async () => {
  const { writeFileSync } = await import("node:fs");
  const { HuellasIlegibles } = await import("../adaptador/vigilancia.ts");
  const d = mkdtempSync(join(tmpdir(), "soul-vig-"));
  try {
    for (const crudo of ["{no json", "[]", "null"]) {
      const f = join(d, "huellas.json");
      writeFileSync(f, crudo);
      const a = new AlmacenHuellas(f);
      assert.throws(() => a.anterior("p"), HuellasIlegibles, crudo);
      assert.throws(() => a.guardar("p", "https://intra.example/a", "h"), HuellasIlegibles, crudo);
      assert.equal(readFileSync(f, "utf8"), crudo, "no se sobrescribe");
    }
  } finally { rmSync(d, { recursive: true, force: true }); }
});

test("salida de la URL vigilada: el login es sesión caducada; otra redirección no (revisión #1443, P2-2 de corrección)", () => {
  const v = { id: "p", sitio: "intranet", url: "https://intra.example/avisos" };
  const fw = (urls: string[], sesionCaducada = false) => ({ sesionCaducada,
    registro: urls.map((url) => ({ t: 0, tipo: "redireccion" as const, url, permitida: false, motivo: "redireccion_fuera" as const })) });
  assert.equal(clasificarSalida(v, fw([]), ""), null);
  assert.equal(clasificarSalida(v, fw([]), "https://intra.example/avisos"), null);
  assert.equal(clasificarSalida(v, fw(["https://intra.example/avisos/"]), ""), "REDIRIGIDA");
  assert.equal(clasificarSalida(v, fw([]), "https://intra.example/portada"), "REDIRIGIDA");
  // «authors» no es «auth»: la palabra tiene que ir entera.
  assert.equal(clasificarSalida(v, fw(["https://intra.example/authors"]), ""), "REDIRIGIDA");
  assert.equal(clasificarSalida(v, fw(["https://intra.example/login?vuelta=%2Favisos"]), ""), "SESION_CADUCADA");
  assert.equal(clasificarSalida(v, fw(["https://login.idp.example/oauth2/authorize"]), ""), "SESION_CADUCADA");
  assert.equal(clasificarSalida(v, fw([], true), ""), "SESION_CADUCADA");
});
