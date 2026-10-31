// Vigilancia sin receta: solo «esta página cambió», con el enlace. Parte pura.
import { test } from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { AlmacenHuellas, huellaTexto, recetaDeVigilancia, VigilanciaInvalida, vigilarPagina } from "../adaptador/vigilancia.ts";

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

test("sitio inalcanzable → ERROR, no «vuelve a iniciar sesión»; sin huella guardada", { timeout: 60_000 }, async () => {
  const { buscarNavegador } = await import("../cortafuegos/perfil.ts");
  const { Banco } = await import("../banco/servidor.ts");
  const d = mkdtempSync(join(tmpdir(), "soul-vig-"));
  const b = await new Banco().arrancar();
  const url = `${b.origen("aprobaciones")}/aprobaciones`;
  await b.parar();
  try {
    const almacen = new AlmacenHuellas(join(d, "huellas.json"));
    const res = await vigilarPagina({ vigilada: { id: "p", sitio: "aprobaciones", url }, ejecutable: buscarNavegador().ruta, almacen });
    assert.equal(res.estado, "ERROR", `${res.estado} ${res.aviso}`);
    assert.doesNotMatch(res.aviso ?? "", /iniciar sesión/);
    assert.equal(almacen.anterior("p"), null);
  } finally { rmSync(d, { recursive: true, force: true }); }
});
