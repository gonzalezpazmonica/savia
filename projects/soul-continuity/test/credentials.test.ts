import { test } from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { CredentialError } from "../src/contract/adapter.ts";
import {
  type Run, type RunResult, SystemCredentialStore, WIN_MAX_PARTS, WIN_PS_ARGS, backendFor, hostRun, joinParts, linuxBackend,
  macBackend, powershellPath, splitParts, windowsBackend,
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
    // Windows: el script va como -EncodedCommand y las operaciones llegan por stdin en JSON; se aplica
    // el límite real de CredWrite (2560 bytes de blob, en UTF-16).
    const { ops } = JSON.parse(input) as { ops: { op: string; t: string; v?: string }[] };
    let out = "";
    for (const op of ops) {
      if (op.op === "r") out += vault.has(op.t) ? `+${vault.get(op.t)}\r\n` : "-\r\n";
      else if (op.op === "w") {
        if ((op.v ?? "").length * 2 > 2560) return { code: 4, stdout: "", stderr: "" };
        vault.set(op.t, op.v ?? "");
        out += "+\r\n";
      } else if (op.op === "d") out += vault.delete(op.t) ? "+\r\n" : "-\r\n";
      else return { code: 2, stdout: "", stderr: "" };
    }
    return { code: 0, stdout: out, stderr: "" };
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
    // En Windows viaja en base64 dentro de los trozos.
    const wire = kind === "win" ? Buffer.from(SECRET).toString("base64") : SECRET;
    assert.ok(f.calls.some((c) => c.input.includes(wire)), "el secreto viaja por stdin");
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
    const trunc: Run = async (cmd, args, input = "") => {
      if (kind !== "win") return f.run(cmd, args, input.replace(SECRET, SECRET.slice(0, 8)));
      const d = JSON.parse(input) as { ops: { op: string; v?: string }[] };
      for (const o of d.ops) if (o.op === "w" && o.v) o.v = o.v.slice(0, o.v.length - 4);
      return f.run(cmd, args, JSON.stringify(d));
    };
    await assert.rejects(new SystemCredentialStore(make(trunc), mkdtempSync(join(tmpdir(), "soul-cr-"))).put("graph", SECRET), /no guardó/);
    await new SystemCredentialStore(make(f.run), mkdtempSync(join(tmpdir(), "soul-cr-"))).put("graph", SECRET);
  });

  test(`${kind}: un borrado que sale con 0 sin borrar hace fallar forget y forgetAll, y la entrada sigue en el índice`, async () => {
    const f = fakeRunner(kind);
    const sordo: Run = async (cmd, args, input = "") => {
      if (kind === "win") {
        // Contesta «borrado» a cada operación sin borrar nada.
        const { ops } = JSON.parse(input) as { ops: { op: string }[] };
        return ops.every((o) => o.op === "d") ? { code: 0, stdout: ops.map(() => "+\r\n").join(""), stderr: "" } : f.run(cmd, args, input);
      }
      const borra = args[0] === "clear" || args[0] === "delete-generic-password";
      return borra ? { code: 0, stdout: "", stderr: "" } : f.run(cmd, args, input);
    };
    const core = new SystemCredentialStore(make(sordo), mkdtempSync(join(tmpdir(), "soul-cr-")));
    await core.put("graph", SECRET);
    await assert.rejects(core.forget("graph"), /no borró/);
    await assert.rejects(core.forgetAll(), /no se pudieron borrar 1/);
    assert.deepEqual(core.index(), [{ service: "graph", account: "default" }]);
  });
}

// ---------------------------------------------------------------- Windows: valor repartido (#1450)

/** Tokens de Entra con forma real: un JSON de más de 5 KB, el doble de lo que cabe en una entrada. */
const GRAPH = {
  access_token: `eyJ0eXAiOiJKV1QiLCJub25jZSI6${"A".repeat(3000)}.SECRETO-AT`,
  refresh_token: `0.AXoA${"r".repeat(1900)}SECRETO-RT`,
  expires_at: 9e15, scopes: ["Mail.Read", "Calendars.Read", "Chat.Read", "User.Read", "Files.Read"],
};
const GRAPH_BLOB = JSON.stringify(GRAPH);
const PS = "C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe";

test("win: un JSON de tokens de Graph de más de 5 KB se guarda, se lee y se borra; cada trozo cabe en CredWrite", async () => {
  assert.ok(GRAPH_BLOB.length > 5000);
  const f = fakeRunner("win");
  const b = windowsBackend(f.run);
  await b.set("api-graph", "a.b", GRAPH_BLOB);
  assert.equal(await b.get("api-graph", "a.b"), GRAPH_BLOB);
  assert.ok(f.vault.size > 1, "repartido en varias entradas");
  for (const v of f.vault.values()) assert.ok(v.length * 2 <= 2560);
  for (const c of f.calls) {
    assert.equal(c.cmd, PS, "PowerShell por ruta absoluta");
    assert.deepEqual(c.args, WIN_PS_ARGS);
    assert.ok(!c.input.includes("SECRETO"), "ni en claro por stdin");
  }
  // Un valor más corto encima no deja trozos del anterior.
  await b.set("api-graph", "a.b", "corto");
  assert.equal(await b.get("api-graph", "a.b"), "corto");
  assert.deepEqual([...f.vault.keys()], ["soul-continuity/api-graph/a.b"]);
  await b.delete("api-graph", "a.b");
  assert.equal(f.vault.size, 0);
  assert.equal(await b.get("api-graph", "a.b"), null);
});

test("win: los tokens de Graph de un adaptador pasan por el almacén único (keyed) y desinstalar borra todos los trozos", async () => {
  const d = mkdtempSync(join(tmpdir(), "soul-cr-"));
  const f = fakeRunner("win");
  const core = new SystemCredentialStore(windowsBackend(f.run), d);
  const api = new ApiTokenStore({ backend: core.keyed(), operatorRef: "op-pm", now: () => 0 });
  await api.put("graph", ["Mail.Read"], GRAPH);
  assert.equal(await api.acquire("graph", ["Mail.Read"]), GRAPH.access_token);
  assert.ok(f.vault.size > 1);
  assert.equal(core.index().length, 1, "un registro por credencial, no por trozo");
  await core.put("legado", "x");
  assert.equal((await core.forgetAll()).length, 2);
  assert.equal(f.vault.size, 0, "no queda ningún trozo en Credential Manager");
});

test("win: fallo de PowerShell o respuesta que no cuadra es error, nunca «sin credencial»", async () => {
  const down = windowsBackend(async () => ({ code: 1, stdout: "", stderr: "" }));
  await assert.rejects(down.get("graph", "default"), /no disponible/);
  await assert.rejects(down.set("graph", "default", "v"), /no disponible/);
  await assert.rejects(down.delete("graph", "default"), /no disponible/);
  const short = windowsBackend(async () => ({ code: 0, stdout: "-\r\n", stderr: "" }));
  await assert.rejects(short.get("graph", "default"), /no disponible/);
  const absent = windowsBackend(async () => ({ code: 127, stdout: "", stderr: "ENOENT" }));
  await assert.rejects(absent.get("graph", "default"), /código 127/);
});

test("win: entrada incompleta, ajena o del formato anterior se lee como sin credencial", async () => {
  const f = fakeRunner("win");
  const b = windowsBackend(f.run);
  await b.set("api-graph", "a.b", GRAPH_BLOB);
  f.vault.delete("soul-continuity/api-graph/a.b/part-2");
  assert.equal(await b.get("api-graph", "a.b"), null, "falta un trozo");
  f.vault.clear();
  f.vault.set("soul-continuity/graph/default", "tok-sin-cabecera");
  assert.equal(await b.get("graph", "default"), null);
  // El borrado limpia también la entrada antigua.
  await b.delete("graph", "default");
  assert.equal(f.vault.size, 0);
  await assert.rejects(b.get("graph/part-1", "default"), /no admitido/);
});

test("win: un set cortado a medias no deja una mezcla legible de dos valores", async () => {
  const f = fakeRunner("win");
  const b = windowsBackend(f.run);
  await b.set("api-graph", "a.b", GRAPH_BLOB);
  const other = GRAPH_BLOB.replace(/r/g, "s");
  assert.equal(splitParts(other).length, splitParts(GRAPH_BLOB).length);
  let w = 0;
  const flaky = windowsBackend(async (cmd, args, input = "") => {
    const { ops } = JSON.parse(input) as { ops: { op: string; t: string; v?: string }[] };
    if (!ops.some((x) => x.op === "w")) return f.run(cmd, args, input);
    const applied = ops.filter((x) => x.op === "w").slice(0, 2);
    for (const x of applied) f.vault.set(x.t, x.v ?? "");
    w += applied.length;
    return { code: 4, stdout: "", stderr: "" };
  });
  await assert.rejects(flaky.set("api-graph", "a.b", other), /no disponible/);
  assert.equal(w, 2);
  assert.equal(await b.get("api-graph", "a.b"), null, "cabecera vieja + trozos nuevos = sin credencial");
});

test("win: reparto en trozos — límites", () => {
  assert.match(splitParts("")[0], /^1:[0-9a-f]{16}:$/);
  assert.equal(joinParts(splitParts("")), "");
  assert.equal(joinParts(["1:"]), null, "cabecera sin hash");
  assert.equal(joinParts(splitParts("ñandú €")), "ñandú €");
  assert.equal(joinParts([null]), null);
  assert.equal(joinParts(["0:"]), null);
  assert.equal(joinParts([`${WIN_MAX_PARTS + 1}:QQ==`]), null);
  const two = splitParts("y".repeat(1000));
  assert.equal(two.length, 2);
  assert.equal(joinParts(two), "y".repeat(1000));
  assert.equal(joinParts([two[0], "no base64!"]), null);
  assert.equal(joinParts([two[0], two[1].replace(/^./, "A")]), null, "trozo cambiado: el hash no cuadra");
  const max = (WIN_MAX_PARTS * 1200 / 4) * 3;
  assert.equal(splitParts("x".repeat(max)).length, WIN_MAX_PARTS);
  assert.throws(() => splitParts("x".repeat(max + 1)), /demasiado grande/);
});

test("win: PowerShell por ruta absoluta, nunca por nombre", () => {
  assert.equal(powershellPath({}), PS);
  assert.equal(powershellPath({ SystemRoot: "D:\\WINNT\\" }), "D:\\WINNT\\System32\\WindowsPowerShell\\v1.0\\powershell.exe");
  assert.throws(() => powershellPath({ SystemRoot: "powershell" }), /absoluta/);
  assert.throws(() => powershellPath({ SystemRoot: "\\\\srv\\share" }), /absoluta/);
});

test("win: el script y el protocolo usan los mismos campos (op, t, v; ops)", async () => {
  const script = Buffer.from(WIN_PS_ARGS[3], "base64").toString("utf16le");
  for (const s of ["$d.ops", "$o.op", "$o.t", "$o.v", "'r'", "'w'", "'d'", "[SoulCred]::Read", "[SoulCred]::Write", "[SoulCred]::Delete", "class SoulCred"]) {
    assert.ok(script.includes(s), `el script contiene ${s}`);
  }
  const f = fakeRunner("win");
  const b = windowsBackend(f.run);
  await b.set("graph", "default", "SECRETO-1");
  await b.delete("graph", "default");
  for (const c of f.calls) {
    for (const op of (JSON.parse(c.input) as { ops: Record<string, unknown>[] }).ops) {
      assert.ok(Object.keys(op).every((x) => ["op", "t", "v"].includes(x)));
      assert.ok(["r", "w", "d"].includes(op.op as string));
    }
  }
});

test("win real: Credential Manager guarda, lee y borra tokens de Graph", { skip: process.platform !== "win32" && "solo en Windows" }, async () => {
  const b = windowsBackend(hostRun);
  const a = `ci${Date.now().toString(16)}`;
  try {
    await b.set("api-graph", a, GRAPH_BLOB);
    assert.equal(await b.get("api-graph", a), GRAPH_BLOB);
    await b.set("api-graph", a, "corto");
    assert.equal(await b.get("api-graph", a), "corto");
    await b.delete("api-graph", a);
    assert.equal(await b.get("api-graph", a), null);
  } finally {
    await b.delete("api-graph", a).catch(() => undefined);
  }
});
