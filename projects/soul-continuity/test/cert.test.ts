import { test } from "node:test";
import assert from "node:assert/strict";
import { X509Certificate, createPublicKey } from "node:crypto";
import { request, createServer } from "node:https";
import type { AddressInfo } from "node:net";
import { mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { ensureInstallCert, makeSelfSigned, spkiPin } from "../src/api/cert.ts";

test("certificado autofirmado válido para las IP de escucha, con clave EC P-256", () => {
  const c = makeSelfSigned(["127.0.0.1", "100.64.0.7"], new Date("2026-10-31T00:00:00Z"));
  const x = new X509Certificate(c.cert);
  assert.ok(x.checkIP("127.0.0.1"));
  assert.ok(x.checkIP("100.64.0.7"));
  assert.equal(x.checkIP("10.0.0.1"), undefined);
  assert.ok(x.verify(x.publicKey), "firma propia correcta");
  assert.equal(x.ca, false);
  assert.equal(createPublicKey(c.key).asymmetricKeyDetails?.namedCurve, "prime256v1");
  assert.match(spkiPin(c.cert), /^sha256\/[A-Za-z0-9+/]{43}=$/);
});

test("TLS real: el cliente que fija el certificado conecta; uno sin él es rechazado", async () => {
  const c = makeSelfSigned(["127.0.0.1"], new Date());
  const srv = createServer({ cert: c.cert, key: c.key, minVersion: "TLSv1.3" }, (_q, r) => r.end("ok"));
  await new Promise<void>((r) => srv.listen(0, "127.0.0.1", () => r()));
  const port = (srv.address() as AddressInfo).port;
  const get = (ca?: string) => new Promise<string>((res, rej) => {
    const q = request({ host: "127.0.0.1", port, path: "/", ca }, (r) => { let b = ""; r.on("data", (d) => { b += d; }); r.on("end", () => res(b)); });
    q.on("error", rej);
    q.end();
  });
  assert.equal(await get(c.cert), "ok");
  await assert.rejects(get(undefined), /self-signed|self signed|unable to verify/i);
  srv.close();
});

test("ensureInstallCert: se genera una vez, se reutiliza y se regenera si cambian las direcciones", () => {
  const d = mkdtempSync(join(tmpdir(), "soul-cert-"));
  const a = ensureInstallCert(d, ["127.0.0.1"]);
  const b = ensureInstallCert(d, ["127.0.0.1"]);
  assert.equal(a.cert, b.cert);
  const c = ensureInstallCert(d, ["127.0.0.1", "100.64.0.9"]);
  assert.notEqual(a.cert, c.cert);
  assert.ok(new X509Certificate(c.cert).checkIP("100.64.0.9"));
});
