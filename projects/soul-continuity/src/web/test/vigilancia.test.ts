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

test("página con estado HTTP de error (503, 404) → ERROR y sin huella (revisión #1443 P2-1 de corrección)", { timeout: 60_000 }, async () => {
  const { createServer } = await import("node:http");
  const { buscarNavegador } = await import("../cortafuegos/perfil.ts");
  const d = mkdtempSync(join(tmpdir(), "soul-vig-"));
  let estado = 503;
  const srv = createServer((_q, r) => { r.writeHead(estado, { "content-type": "text/html" }); r.end("<p>servicio caído</p>"); });
  await new Promise<void>((ok) => srv.listen(0, "127.0.0.1", ok));
  const url = `http://127.0.0.1:${(srv.address() as { port: number }).port}/avisos`;
  try {
    const almacen = new AlmacenHuellas(join(d, "huellas.json"));
    for (const st of [503, 404]) {
      estado = st;
      const res = await vigilarPagina({ vigilada: { id: "p", sitio: "portal", url }, ejecutable: buscarNavegador().ruta, almacen });
      assert.equal(res.estado, "ERROR", `${st}: ${res.estado} ${res.aviso}`);
      assert.match(res.aviso ?? "", new RegExp(`HTTP ${st}`));
      assert.equal(almacen.anterior("p"), null);
    }
    estado = 200;
    const ok = await vigilarPagina({ vigilada: { id: "p", sitio: "portal", url }, ejecutable: buscarNavegador().ruta, almacen });
    assert.equal(ok.estado, "PRIMERA_VISITA");
  } finally { srv.close(); rmSync(d, { recursive: true, force: true }); }
});
