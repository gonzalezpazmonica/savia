import { test } from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { CredentialError } from "../src/contract/adapter.ts";
import {
  type Run, type RunResult, SystemCredentialStore, backendFor, linuxBackend, macBackend, windowsBackend,
} from "../src/credentials/store.ts";
import { filesUnder } from "../src/core/store.ts";

const SECRET = "tok-SECRETO-canario-123";

/** Doble de los programas del sistema: un llavero en memoria que habla como cada herramienta. */
function fakeRunner(kind: "linux" | "mac" | "win") {
  const vault = new Map<string, string>();
  const calls: { cmd: string; args: string[]; input: string }[] = [];
  const run: Run = async (cmd, args, input = ""): Promise<RunResult> => {
    calls.push({ cmd, args, input });
    if (kind === "linux") {
      const attrs = args.slice(1).join("|").replace(/^--label=[^|]*\|/, "");
      if (args[0] === "store") { vault.set(attrs, input); return { code: 0, stdout: "", stderr: "" }; }
      if (args[0] === "lookup") return vault.has(attrs) ? { code: 0, stdout: vault.get(attrs) as string, stderr: "" } : { code: 1, stdout: "", stderr: "" };
      if (args[0] === "clear") { vault.delete(attrs); return { code: 0, stdout: "", stderr: "" }; }
    }
    if (kind === "mac") {
      // Alta: `security -i` lee la orden (con el secreto) por stdin. Lectura y borrado: argumentos sin secreto.
      if (args[0] === "-i") {
        const m = /^add-generic-password -U -a "([^"]+)" -s "([^"]+)" -w "([^"]*)"$/.exec(input.trim());
        if (!m) return { code: 2, stdout: "", stderr: "orden inesperada" };
        vault.set(`${m[1]}|${m[2]}`, m[3]);
        return { code: 0, stdout: "", stderr: "" };
      }
      const k = `${args[args.indexOf("-a") + 1]}|${args[args.indexOf("-s") + 1]}`;
      if (args[0] === "find-generic-password") return vault.has(k) ? { code: 0, stdout: (vault.get(k) as string) + "\n", stderr: "" } : { code: 44, stdout: "", stderr: "not found" };
      if (args[0] === "delete-generic-password") { const had = vault.delete(k); return { code: had ? 0 : 44, stdout: "", stderr: "" }; }
      return { code: 2, stdout: "", stderr: "orden inesperada" };
    }
    // Windows: el script de PowerShell llega por stdin con una línea de datos JSON al final.
    const data = JSON.parse(input.trim().split("\n").at(-1) as string) as { op: string; target: string; secret?: string };
    if (data.op === "set") { vault.set(data.target, data.secret ?? ""); return { code: 0, stdout: "", stderr: "" }; }
    if (data.op === "get") return vault.has(data.target) ? { code: 0, stdout: vault.get(data.target) as string, stderr: "" } : { code: 3, stdout: "", stderr: "" };
    vault.delete(data.target);
    return { code: 0, stdout: "", stderr: "" };
  };
  return { run, calls, vault };
}

for (const [kind, make] of [["linux", linuxBackend], ["mac", macBackend], ["win", windowsBackend]] as const) {
  test(`${kind}: guarda, lee y borra; el secreto nunca va en la línea de órdenes`, async () => {
    const f = fakeRunner(kind);
    const b = make(f.run);
    await b.set("graph", "default", SECRET);
    assert.equal(await b.get("graph", "default"), SECRET);
    assert.equal(await b.get("graph", "otra"), null);
    await b.delete("graph", "default");
    assert.equal(await b.get("graph", "default"), null);
    for (const c of f.calls) assert.ok(!c.args.join(" ").includes(SECRET), `${c.cmd} ${c.args.join(" ")}`);
    assert.ok(f.calls.some((c) => c.input.includes(SECRET)), "el secreto viaja por stdin");
  });
}

test("mac: comillas en el secreto no rompen la orden (no hay inyección)", async () => {
  const f = fakeRunner("mac");
  const b = macBackend(f.run);
  await assert.rejects(b.set("graph", "default", 'a" -s "otro'), /carácter no admitido/);
});

test("fallo de la herramienta al leer => error, nunca «sin credencial» silencioso", async () => {
  const run: Run = async () => ({ code: 127, stdout: "", stderr: "secret-tool: not found" });
  await assert.rejects(linuxBackend(run).get("graph", "default"), /almacén de credenciales no disponible/);
});

test("backendFor elige por sistema; un sistema desconocido no tiene almacén", () => {
  const run: Run = async () => ({ code: 0, stdout: "", stderr: "" });
  assert.equal(backendFor("linux", run).name, "secret-service");
  assert.equal(backendFor("darwin", run).name, "keychain");
  assert.equal(backendFor("win32", run).name, "credential-manager");
  assert.throws(() => backendFor("aix", run));
});

test("SystemCredentialStore cumple el contrato y el índice en disco no guarda secretos", async () => {
  const d = mkdtempSync(join(tmpdir(), "soul-cr-"));
  const f = fakeRunner("linux");
  const s = new SystemCredentialStore(linuxBackend(f.run), d);
  await assert.rejects(s.acquire("graph", ["Mail.ReadBasic"]), (e: unknown) => e instanceof CredentialError && e.code === "no_credential");
  await s.put("graph", SECRET);
  assert.equal(await s.acquire("graph", ["Mail.ReadBasic"]), SECRET);
  const disk = filesUnder(d).map((p) => readFileSync(p, "utf8")).join("\n");
  assert.ok(disk.includes("graph"));
  assert.ok(!disk.includes(SECRET), "0 tokens en disco fuera del almacén del sistema");
  assert.deepEqual(await s.forget("graph"), ["graph"]);
  await assert.rejects(s.acquire("graph", []), CredentialError);
});

test("forgetAll borra todas las credenciales registradas", async () => {
  const d = mkdtempSync(join(tmpdir(), "soul-cr-"));
  const f = fakeRunner("win");
  const s = new SystemCredentialStore(windowsBackend(f.run), d);
  await s.put("graph", "a");
  await s.put("jira", "b");
  assert.deepEqual((await s.forgetAll()).sort(), ["graph", "jira"]);
  assert.equal(f.vault.size, 0);
});

// ---------------------------------------------------------------- almacén único (H-2)

import { SystemCredentialStore as ApiTokenStore, entryKey } from "../src/adapters/credential-store.ts";

const TOKENS = JSON.stringify({ access_token: SECRET, refresh_token: "rt-canario", expires_at: 9e15, scopes: ["Mail.Read"] });

for (const kind of ["linux", "mac", "win"] as const) {
  test(`${kind}: los tokens de un adaptador de API van al almacén único y quedan en su índice (H-2)`, async () => {
    const d = mkdtempSync(join(tmpdir(), "soul-cr-"));
    const f = fakeRunner(kind);
    const core = new SystemCredentialStore(backendFor(kind === "linux" ? "linux" : kind === "mac" ? "darwin" : "win32", f.run), d);
    const api = new ApiTokenStore({ backend: core.keyed(), operatorRef: "op-a", now: () => 0 });
    // El JSON del token lleva comillas: el llavero de macOS las rechazaría sin la codificación.
    await api.put("graph", ["Mail.Read"], JSON.parse(TOKENS));
    assert.equal(await api.acquire("graph", ["Mail.Read"]), SECRET);
    assert.equal(core.index().length, 1);
    assert.match(core.index()[0].service, /^api-graph$/);
    const disk = filesUnder(d).map((p) => readFileSync(p, "utf8")).join("\n");
    assert.ok(!disk.includes(SECRET) && !disk.includes("rt-canario") && !disk.includes("op-a"), "índice sin secretos ni operador en claro");
    for (const c of f.calls) assert.ok(!c.args.join(" ").includes(SECRET), "el token nunca en argv");
  });
}

test("desinstalar (forgetAll) borra también los tokens de los adaptadores de API y los del núcleo", async () => {
  const d = mkdtempSync(join(tmpdir(), "soul-cr-"));
  const f = fakeRunner("linux");
  const core = new SystemCredentialStore(linuxBackend(f.run), d);
  await core.put("legado", "x");
  await new ApiTokenStore({ backend: core.keyed(), operatorRef: "op-a" }).put("graph", ["Mail.Read"], JSON.parse(TOKENS));
  await new ApiTokenStore({ backend: core.keyed(), operatorRef: "op-b" }).put("github", ["repo:read"], JSON.parse(TOKENS));
  assert.equal(f.vault.size, 3);
  assert.equal((await core.forgetAll()).length, 3);
  assert.equal(f.vault.size, 0, "no queda ningún secreto en el almacén del sistema");
  assert.deepEqual(core.index(), []);
});

test("revocar un adaptador borra sus tokens del almacén único y los saca del índice; los de otro operador siguen", async () => {
  const d = mkdtempSync(join(tmpdir(), "soul-cr-"));
  const f = fakeRunner("linux");
  const core = new SystemCredentialStore(linuxBackend(f.run), d);
  const a = new ApiTokenStore({ backend: core.keyed(), operatorRef: "op-a" });
  await a.put("graph", ["Mail.Read"], JSON.parse(TOKENS));
  await new ApiTokenStore({ backend: core.keyed(), operatorRef: "op-b" }).put("graph", ["Mail.Read"], JSON.parse(TOKENS));
  assert.equal(await a.revoke("graph", ["Mail.Read"]), true);
  assert.equal(await a.revoke("graph", ["Mail.Read"]), false, "segunda vez: no había nada");
  assert.equal(f.vault.size, 1);
  assert.equal(core.index().length, 1);
});

test("forgetAll con un borrado que falla: borra los demás, conserva en el índice el fallido y lanza", async () => {
  const d = mkdtempSync(join(tmpdir(), "soul-cr-"));
  const f = fakeRunner("linux");
  const run: Run = async (cmd, args, input) => (args[0] === "clear" && args.includes("roto") ? { code: 1, stdout: "", stderr: "dbus" } : f.run(cmd, args, input));
  const core = new SystemCredentialStore(linuxBackend(run), d);
  await core.put("bien", "1");
  await core.put("roto", "2");
  await assert.rejects(core.forgetAll(), /no se pudieron borrar 1/);
  assert.deepEqual(core.index(), [{ service: "roto", account: "default" }]);
  assert.equal(f.vault.size, 1);
});

test("keyed() rechaza una clave que no es de un adaptador de API (fail-closed)", async () => {
  const d = mkdtempSync(join(tmpdir(), "soul-cr-"));
  const core = new SystemCredentialStore(linuxBackend(fakeRunner("linux").run), d);
  await assert.rejects(core.keyed().set("../otra-app/clave", "v"), /no admitida/);
  await assert.rejects(core.keyed().get("soul-continuity/xx/graph/yy"), /no admitida/);
  assert.match(entryKey("op", "graph", ["a"]), /^soul-continuity\//);
});

test("índice en el formato anterior (`services`) se sigue leyendo y se borra al desinstalar", async () => {
  const d = mkdtempSync(join(tmpdir(), "soul-cr-"));
  const f = fakeRunner("linux");
  await linuxBackend(f.run).set("graph", "default", "viejo");
  writeFileSync(join(d, "credentials-index.json"), JSON.stringify({ services: ["graph"] }));
  const core = new SystemCredentialStore(linuxBackend(f.run), d);
  assert.deepEqual(await core.forgetAll(), ["graph"]);
  assert.equal(f.vault.size, 0);
});

test("hostRun: una herramienta que sale sin leer stdin no tumba el proceso (EPIPE) y su código manda", async () => {
  const { hostRun } = await import("../src/credentials/store.ts");
  const r = await hostRun(process.execPath, ["-e", "process.exit(3)"], "x".repeat(4 * 1024 * 1024));
  assert.equal(r.code, 3);
});

for (const [kind, make] of [["linux", linuxBackend], ["mac", macBackend], ["win", windowsBackend]] as const) {
  test(`${kind}: un almacén que trunca al guardar hace fallar put; uno íntegro, no (control)`, async () => {
    const f = fakeRunner(kind);
    const trunc: Run = async (cmd, args, input = "") => f.run(cmd, args, input.replace(SECRET, SECRET.slice(0, 8)));
    await assert.rejects(new SystemCredentialStore(make(trunc), mkdtempSync(join(tmpdir(), "soul-cr-"))).put("graph", SECRET), /no guardó/);
    await new SystemCredentialStore(make(f.run), mkdtempSync(join(tmpdir(), "soul-cr-"))).put("graph", SECRET);
  });

  test(`${kind}: un borrado que sale con 0 sin borrar hace fallar forget y forgetAll, y la entrada sigue en el índice`, async () => {
    const f = fakeRunner(kind);
    const sordo: Run = async (cmd, args, input = "") => {
      const borra = args[0] === "clear" || args[0] === "delete-generic-password" || /"op":"delete"/.test(input);
      return borra ? { code: 0, stdout: "", stderr: "" } : f.run(cmd, args, input);
    };
    const core = new SystemCredentialStore(make(sordo), mkdtempSync(join(tmpdir(), "soul-cr-")));
    await core.put("graph", SECRET);
    await assert.rejects(core.forget("graph"), /no borró/);
    await assert.rejects(core.forgetAll(), /no se pudieron borrar 1/);
    assert.deepEqual(core.index(), [{ service: "graph", account: "default" }]);
  });
}
