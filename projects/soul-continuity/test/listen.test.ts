import { test } from "node:test";
import assert from "node:assert/strict";
import { connect } from "node:net";
import { networkInterfaces } from "node:os";
import { listenOnly, validateListen } from "../src/api/listen.ts";

test("validateListen: lista vacía, comodines y nombres se rechazan (fail-closed)", () => {
  assert.throws(() => validateListen([]), /ninguna dirección/);
  for (const bad of ["0.0.0.0", "::", "::0", "localhost", "*", "100.64.0.1/24", "",
    // formas equivalentes de la dirección no especificada, mapeadas y con zona
    "0::", "0:0::", "::0:0", "::0.0.0.0", "0:0:0:0:0:0:0.0.0.0", "::ffff:0.0.0.0", "::ffff:100.64.0.1", "fe80::1%eth0"]) {
    assert.throws(() => validateListen([bad]), Error, bad);
  }
  assert.deepEqual(validateListen(["100.64.0.7", "fd7a:115c:a1e0::1"]), ["100.64.0.7", "fd7a:115c:a1e0::1"]);
});

function tryConnect(host: string, port: number): Promise<boolean> {
  return new Promise((res) => {
    const s = connect({ host, port, timeout: 800 });
    s.on("connect", () => { s.destroy(); res(true); });
    s.on("error", () => res(false));
    s.on("timeout", () => { s.destroy(); res(false); });
  });
}

test("test de puertos: solo escucha en las direcciones configuradas", async () => {
  const handler = (_q: unknown, r: { end(s: string): void }) => r.end("ok");
  const l = await listenOnly(["127.0.0.1"], 0, () => import("node:http").then((h) => h.createServer(handler as never)));
  try {
    const port = l.port;
    assert.deepEqual(l.addresses.map((a) => a.address), ["127.0.0.1"]);
    assert.equal(await tryConnect("127.0.0.1", port), true, "control positivo: la dirección configurada responde");
    const others = Object.values(networkInterfaces()).flat()
      .filter((i) => i && !i.internal && i.family === "IPv4").map((i) => (i as { address: string }).address);
    const candidates = [...others, ...(process.platform === "linux" ? ["127.0.0.2"] : []), "::1"];
    for (const h of candidates) assert.equal(await tryConnect(h, port), false, `no debe escuchar en ${h}`);
  } finally {
    await l.close();
  }
});
