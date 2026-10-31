/**
 * Certificado TLS propio de la instalación (SE-490), sin OpenSSL ni módulos nativos:
 * X.509 v3 autofirmado con clave EC P-256, construido en DER con `node:crypto`.
 *
 * - SAN con las IP de escucha (las de la VPN del operador); `CA:false`; uso: firma digital, serverAuth.
 * - La app lo fija por huella SPKI (`spkiPin`), como el emparejamiento de Space.
 * - Clave privada en el directorio de datos del usuario con permisos 0600.
 */

import { X509Certificate, createHash, generateKeyPairSync, randomBytes, sign } from "node:crypto";
import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { readJson, writeAtomic, writeJson } from "../core/store.ts";
import { ipBytes } from "./listen.ts";

// ---------------------------------------------------------------- DER mínimo

function len(n: number): Buffer {
  if (n < 0x80) return Buffer.from([n]);
  const b: number[] = [];
  for (let x = n; x > 0; x >>= 8) b.unshift(x & 0xff);
  return Buffer.from([0x80 | b.length, ...b]);
}
const tlv = (tag: number, body: Buffer) => Buffer.concat([Buffer.from([tag]), len(body.length), body]);
const seq = (...items: Buffer[]) => tlv(0x30, Buffer.concat(items));
const set = (...items: Buffer[]) => tlv(0x31, Buffer.concat(items));
const ctx = (n: number, body: Buffer) => tlv(0xa0 + n, body);
const octets = (b: Buffer) => tlv(0x04, b);
const bits = (b: Buffer) => tlv(0x03, Buffer.concat([Buffer.from([0]), b]));
const bool = (v: boolean) => tlv(0x01, Buffer.from([v ? 0xff : 0]));
const utf8 = (s: string) => tlv(0x0c, Buffer.from(s, "utf8"));

function int(b: Buffer): Buffer {
  let x = b;
  while (x.length > 1 && x[0] === 0 && x[1] < 0x80) x = x.subarray(1);
  if (x[0] & 0x80) x = Buffer.concat([Buffer.from([0]), x]);
  return tlv(0x02, x);
}

function oid(s: string): Buffer {
  const p = s.split(".").map(Number);
  const out = [40 * p[0] + p[1]];
  for (const n of p.slice(2)) {
    const stack = [n & 0x7f];
    for (let x = n >>> 7; x > 0; x >>>= 7) stack.unshift((x & 0x7f) | 0x80);
    out.push(...stack);
  }
  return tlv(0x06, Buffer.from(out));
}

function utcTime(d: Date): Buffer {
  const s = d.toISOString(); // AAAA-MM-DDTHH:MM:SS
  return tlv(0x17, Buffer.from(`${s.slice(2, 4)}${s.slice(5, 7)}${s.slice(8, 10)}${s.slice(11, 13)}${s.slice(14, 16)}${s.slice(17, 19)}Z`));
}

// ---------------------------------------------------------------- certificado

const ECDSA_SHA256 = seq(oid("1.2.840.10045.4.3.2"));
const NAME = seq(set(seq(oid("2.5.4.3"), utf8("Savia Soul Continuidad"))));

export interface InstallCert { cert: string; key: string }

export function makeSelfSigned(addresses: string[], now: Date, days = 397): InstallCert {
  if (!addresses.length) throw new Error("el certificado necesita al menos una dirección de escucha");
  const { privateKey, publicKey } = generateKeyPairSync("ec", { namedCurve: "prime256v1" });
  const spki = publicKey.export({ type: "spki", format: "der" });
  const serial = randomBytes(16);
  serial[0] &= 0x7f;
  const san = seq(...addresses.map((a) => tlv(0x87, ipBytes(a))));
  const exts = seq(
    seq(oid("2.5.29.19"), bool(true), octets(seq())),                           // basicConstraints: CA:false
    seq(oid("2.5.29.15"), bool(true), octets(tlv(0x03, Buffer.from([0x07, 0x80])))), // keyUsage: digitalSignature
    seq(oid("2.5.29.37"), octets(seq(oid("1.3.6.1.5.5.7.3.1")))),               // extKeyUsage: serverAuth
    seq(oid("2.5.29.17"), octets(san)),                                           // subjectAltName: IP
  );
  const tbs = seq(
    ctx(0, int(Buffer.from([2]))), int(serial), ECDSA_SHA256, NAME,
    seq(utcTime(new Date(now.getTime() - 3_600_000)), utcTime(new Date(now.getTime() + days * 86_400_000))),
    NAME, spki, ctx(3, exts),
  );
  const der = seq(tbs, ECDSA_SHA256, bits(sign("sha256", tbs, privateKey)));
  const b64 = der.toString("base64").match(/.{1,64}/g)?.join("\n") ?? "";
  const cert = `-----BEGIN CERTIFICATE-----\n${b64}\n-----END CERTIFICATE-----\n`;
  const key = privateKey.export({ type: "pkcs8", format: "pem" }).toString();
  return { cert, key };
}

/** Huella SPKI que fija la app (`sha256/<base64>`). */
export function spkiPin(certPem: string): string {
  const spki = new X509Certificate(certPem).publicKey.export({ type: "spki", format: "der" });
  return "sha256/" + createHash("sha256").update(spki).digest("base64");
}

/** Certificado de la instalación: se genera una vez y se renueva si cambian las direcciones o caduca en < 30 días. */
export function ensureInstallCert(dataDir: string, addresses: string[], now = new Date()): InstallCert & { pin: string } {
  const dir = join(dataDir, "tls");
  const certP = join(dir, "cert.pem");
  const keyP = join(dir, "key.pem");
  const metaP = join(dir, "meta.json");
  const want = [...addresses].sort();
  const meta = readJson<{ addresses: string[] } | null>(metaP, null);
  if (existsSync(certP) && existsSync(keyP) && meta && JSON.stringify(meta.addresses) === JSON.stringify(want)) {
    const cert = readFileSync(certP, "utf8");
    if (Date.parse(new X509Certificate(cert).validTo) - now.getTime() > 30 * 86_400_000) {
      return { cert, key: readFileSync(keyP, "utf8"), pin: spkiPin(cert) };
    }
  }
  const c = makeSelfSigned(want, now);
  writeAtomic(keyP, c.key);
  writeAtomic(certP, c.cert);
  writeJson(metaP, { addresses: want });
  return { ...c, pin: spkiPin(c.cert) };
}
