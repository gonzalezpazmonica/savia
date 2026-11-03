// Vigilancia contra un navegador real: sitio inalcanzable y estados HTTP de error.
// La parte pura está en test/vigilancia.test.ts.
import { test } from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { AlmacenHuellas, vigilarPagina } from "../../adaptador/vigilancia.ts";
import { buscarNavegador } from "../../cortafuegos/perfil.ts";
import { Banco } from "../../banco/servidor.ts";

test("sitio inalcanzable → ERROR, no «vuelve a iniciar sesión»; sin huella guardada", { timeout: 60_000 }, async () => {
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

test("página con estado HTTP de error (503, 404) → ERROR y sin huella (revisión #1443 P2-1 de corrección)", { timeout: 60_000 }, async () => {
  const { createServer } = await import("node:http");
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
