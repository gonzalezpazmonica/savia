import { test } from "node:test";
import assert from "node:assert/strict";
import { X509Certificate, createPublicKey } from "node:crypto";
import { request, createServer } from "node:https";
import type { AddressInfo } from "node:net";
import { mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { ensureInstallCert, identidadServidor, makeSelfSigned, spkiPin } from "../src/api/cert.ts";

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

// Validación activa (CA fijada + identidad por SAN IP) contra un servidor real en 127.0.0.1 y ::1.
// Falla sin `identidadServidor` en Node 22.23.2/22.23.3: allí `tls.checkServerIdentity` rechaza ::1
// aunque el certificado lo lleve como SAN IP (ERR_TLS_CERT_ALTNAME_INVALID, «is not cert's CN»).
async function servirEn(cert: { cert: string; key: string }, host: string) {
  const srv = createServer({ cert: cert.cert, key: cert.key, minVersion: "TLSv1.3" }, (_q, r) => r.end("ok"));
  await new Promise<void>((r) => srv.listen({ port: 0, host, ipv6Only: host.includes(":") }, () => r()));
  return { srv, port: (srv.address() as AddressInfo).port };
}
const pedir = (host: string, port: number, ca: string) => new Promise<string>((res, rej) => {
  const q = request({ host, port, path: "/", ca, checkServerIdentity: identidadServidor }, (r) => { let b = ""; r.on("data", (d) => { b += d; }); r.on("end", () => res(b)); });
  q.on("error", rej);
  q.end();
});

test("TLS con validación activa: conecta a 127.0.0.1 y a ::1 cuando ambas están en los SAN IP", async () => {
  const c = makeSelfSigned(["127.0.0.1", "::1"], new Date());
  for (const host of ["127.0.0.1", "::1"]) {
    const { srv, port } = await servirEn(c, host);
    try { assert.equal(await pedir(host, port, c.cert), "ok", host); } finally { srv.close(); }
  }
});

test("TLS con validación activa: una IP de escucha que no está en los SAN se rechaza (::1 y 127.0.0.1)", async () => {
  for (const [san, host] of [["127.0.0.1", "::1"], ["::1", "127.0.0.1"]] as const) {
    const c = makeSelfSigned([san], new Date());
    const { srv, port } = await servirEn(c, host);
    try {
      await assert.rejects(pedir(host, port, c.cert), (e: NodeJS.ErrnoException) => e.code === "ERR_TLS_CERT_ALTNAME_INVALID", `${host} con SAN ${san}`);
    } finally { srv.close(); }
  }
});

test("identidadServidor: IP en los SAN pasa; otra IP, CN coincidente sin SAN o certificado sin raw fallan (fail-closed)", () => {
  const c = makeSelfSigned(["127.0.0.1", "::1"], new Date());
  const x = new X509Certificate(c.cert);
  const peer = { raw: x.raw, subject: { CN: "Savia Soul Continuidad" }, subjectaltname: x.subjectAltName } as any;
  assert.equal(identidadServidor("::1", peer), undefined);
  assert.equal(identidadServidor("[::1]", peer), undefined);
  assert.equal(identidadServidor("0:0:0:0:0:0:0:1", peer), undefined);
  assert.equal(identidadServidor("127.0.0.1", peer), undefined);
  assert.ok(identidadServidor("::2", peer) instanceof Error);
  assert.ok(identidadServidor("127.0.0.2", peer) instanceof Error);
  assert.ok(identidadServidor("::1", { subject: { CN: "::1" }, subjectaltname: "" } as any) instanceof Error, "sin raw no hay PASS");
  assert.ok(identidadServidor("savia.example", peer) instanceof Error, "nombre DNS: comprobación estándar, sin SAN DNS falla");
});
