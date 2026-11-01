import { test } from "node:test";
import assert from "node:assert/strict";
import { existsSync, mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import {
  CommandBackend, MemoryBackend, SecretToolBackend, SystemCredentialStore, WIN_MAX_PARTS, WIN_PS_ARGS, WindowsCredentialBackend,
  entryKey, joinParts, macosCommands, splitParts, systemBackend, type RunFn,
} from "../../src/adapters/credential-store.ts";

const NOW = 1_000_000_000;
const set = (over = {}) => JSON.stringify({ access_token: "at-ok", refresh_token: "rt-ok", expires_at: NOW + 3600_000, scopes: ["Mail.Read"], ...over });

test("entryKey: por operador (con hash), servicio y permisos, sin el ref en claro", () => {
  const k = entryKey("op-pm", "graph", ["Mail.Read"]);
  assert.match(k, /^soul-continuity\/[0-9a-f]{16}\/graph\/[0-9a-f]{16}$/);
  assert.ok(!k.includes("op-pm"));
  assert.equal(k, entryKey("op-pm", "graph", ["Mail.Read"]));
  assert.notEqual(k, entryKey("op-pm", "graph", ["Mail.ReadBasic"]));
  assert.notEqual(k, entryKey("op-dir", "graph", ["Mail.Read"]));
  assert.equal(entryKey("op", "g", ["b", "a"]), entryKey("op", "g", ["a", "b"]));
});

test("acquire: sin entrada → no_credential; vigente → el token", async () => {
  const b = new MemoryBackend();
  const s = new SystemCredentialStore({ backend: b, operatorRef: "op-pm", now: () => NOW });
  await assert.rejects(s.acquire("graph", ["Mail.Read"]), (e: { code?: string }) => e.code === "no_credential");
  await b.set(entryKey("op-pm", "graph", ["Mail.Read"]), set());
  assert.equal(await s.acquire("graph", ["Mail.Read"]), "at-ok");
  await assert.rejects(new SystemCredentialStore({ backend: b, operatorRef: "op-otro", now: () => NOW }).acquire("graph", ["Mail.Read"]),
    (e: { code?: string }) => e.code === "no_credential", "otro operador no usa el token");
});

test("acquire: caducado → renueva con el refresh y guarda el nuevo en el almacén", async () => {
  const b = new MemoryBackend();
  const key = entryKey("op-pm", "graph", ["Mail.Read"]);
  await b.set(key, set({ expires_at: NOW - 1 }));
  const calls: string[] = [];
  const s = new SystemCredentialStore({
    backend: b, operatorRef: "op-pm", now: () => NOW,
    refresh: async (service, rt, scopes) => { calls.push(`${service}:${rt}:${scopes.join(",")}`); return { access_token: "at-new", refresh_token: "rt-new", expires_at: NOW + 3600_000, scopes }; },
  });
  assert.equal(await s.acquire("graph", ["Mail.Read"]), "at-new");
  assert.deepEqual(calls, ["graph:rt-ok:Mail.Read"]);
  assert.equal(JSON.parse((await b.get(key))!).access_token, "at-new");
});

test("acquire: dos lecturas a la vez con el token caducado renuevan una sola vez", async () => {
  const b = new MemoryBackend();
  await b.set(entryKey("op-pm", "graph", ["Mail.Read"]), set({ expires_at: NOW - 1 }));
  let calls = 0;
  const s = new SystemCredentialStore({
    backend: b, operatorRef: "op-pm", now: () => NOW,
    refresh: async (_s, _rt, scopes) => { calls++; await new Promise((r) => setTimeout(r, 10)); return { access_token: `at-${calls}`, refresh_token: `rt-${calls}`, expires_at: NOW + 3600_000, scopes }; },
  });
  assert.deepEqual(await Promise.all([s.acquire("graph", ["Mail.Read"]), s.acquire("graph", ["Mail.Read"])]), ["at-1", "at-1"]);
  assert.equal(calls, 1);
  // Terminada la renovación, la siguiente lectura usa el token guardado sin renovar.
  assert.equal(await s.acquire("graph", ["Mail.Read"]), "at-1");
  assert.equal(calls, 1);
});

test("acquire: caducado sin forma de renovar → no_credential; renovación con administración → admin_consent_required", async () => {
  const b = new MemoryBackend();
  await b.set(entryKey("op-pm", "graph", ["Mail.Read"]), set({ expires_at: NOW - 1 }));
  await assert.rejects(new SystemCredentialStore({ backend: b, operatorRef: "op-pm", now: () => NOW }).acquire("graph", ["Mail.Read"]),
    (e: { code?: string }) => e.code === "no_credential");
  const s = new SystemCredentialStore({
    backend: b, operatorRef: "op-pm", now: () => NOW,
    refresh: async () => { throw Object.assign(new Error("x"), { code: "admin_consent_required" }); },
  });
  await assert.rejects(s.acquire("graph", ["Mail.Read"]), (e: { code?: string }) => e.code === "admin_consent_required");
});

test("marca de administración guardada: acquire falla cerrado sin red", async () => {
  const b = new MemoryBackend();
  const s = new SystemCredentialStore({ backend: b, operatorRef: "op-pm", now: () => NOW, refresh: async () => { throw new Error("no debe llamarse"); } });
  await s.markAdminRequired("graph", ["Mail.Read"]);
  await assert.rejects(s.acquire("graph", ["Mail.Read"]), (e: { code?: string }) => e.code === "admin_consent_required");
});

test("put y revoke: guardar un login y revocarlo deja el almacén sin la entrada", async () => {
  const b = new MemoryBackend();
  const s = new SystemCredentialStore({ backend: b, operatorRef: "op-pm", now: () => NOW });
  await s.put("graph", ["Chat.Read"], { access_token: "at", refresh_token: "rt", expires_at: NOW + 1000_000, scopes: ["Chat.Read"] });
  assert.equal(await s.acquire("graph", ["Chat.Read"]), "at");
  assert.equal(await s.revoke("graph", ["Chat.Read"]), true);
  assert.equal(await b.get(entryKey("op-pm", "graph", ["Chat.Read"])), null);
  assert.equal(await s.revoke("graph", ["Chat.Read"]), false);
});

// Dobles de ejecutable portables: un script .cjs lanzado con el propio Node. Un fichero
// con shebang no se puede lanzar sin shell en Windows (ENOENT).
function double(dir: string, name: string, body: string): { cmd: string; args: string[] } {
  const f = join(dir, `${name}.cjs`);
  writeFileSync(f, body);
  return { cmd: process.execPath, args: [f] };
}
const toolDouble = (dir: string, name: string, body: string) => {
  const d = double(dir, name, body);
  return new SecretToolBackend({ command: d.cmd, commandArgs: d.args });
};

test("secret-tool: el secreto viaja por stdin, nunca en argv", async () => {
  const dir = mkdtempSync(join(tmpdir(), "s490-st-"));
  const store = join(dir, "store.json");
  const argvLog = join(dir, "argv.log");
  // Doble de secret-tool: guarda por atributo account en un JSON de prueba.
  const b = toolDouble(dir, "secret-tool", `const fs=require("fs");const [cmd,...a]=process.argv.slice(2);fs.appendFileSync(${JSON.stringify(argvLog)},JSON.stringify(process.argv.slice(2))+"\\n");
const f=${JSON.stringify(store)};const db=fs.existsSync(f)?JSON.parse(fs.readFileSync(f,"utf8")):{};const acc=a[a.indexOf("account")+1];
if(cmd==="store"){let s="";process.stdin.on("data",c=>s+=c).on("end",()=>{db[acc]=s;fs.writeFileSync(f,JSON.stringify(db));});}
else if(cmd==="lookup"){if(acc in db)process.stdout.write(db[acc]);else process.exit(1);}
else if(cmd==="clear"){delete db[acc];fs.writeFileSync(f,JSON.stringify(db));}
`);
  await b.set("soul-continuity/x/graph/y", "SECRETO-123");
  assert.equal(await b.get("soul-continuity/x/graph/y"), "SECRETO-123");
  await b.delete("soul-continuity/x/graph/y");
  assert.equal(await b.get("soul-continuity/x/graph/y"), null);
  assert.ok(existsSync(argvLog));
  assert.ok(!readFileSync(argvLog, "utf8").includes("SECRETO-123"), "el secreto no aparece en la línea de órdenes");
});

test("secret-tool: si clear falla, delete lanza en vez de informar de un borrado", async () => {
  const dir = mkdtempSync(join(tmpdir(), "s490-st-"));
  // Doble: lookup siempre encuentra la entrada y clear falla (almacén bloqueado).
  const stuck = toolDouble(dir, "secret-tool", `const [cmd]=process.argv.slice(2);
if(cmd==="lookup")process.stdout.write("SECRETO");else if(cmd==="clear")process.exit(1);
`);
  await assert.rejects(stuck.delete("soul-continuity/x/graph/y"), /no borró/);
  // Si no había entrada, no hay nada que borrar: false, sin error.
  assert.equal(await toolDouble(dir, "secret-tool-vacio", "process.exit(1);\n").delete("soul-continuity/x/graph/y"), false);
});

test("macOS: delete que no borra lanza; sin entrada devuelve false", async () => {
  const dir = mkdtempSync(join(tmpdir(), "s490-cb-"));
  const sh = (name: string, body: string) => double(dir, name, body);
  const found = sh("found", 'process.stdout.write("U0VDUkVUTw==\\n");');
  const fail = sh("fail", "process.exit(1);");
  const cmds = (get: { cmd: string; args: string[] }, del: { cmd: string; args: string[] }) => ({
    ...macosCommands,
    get: () => ({ ...get, stdin: "" }),
    delete: () => ({ ...del, stdin: "" }),
  }) as typeof macosCommands;
  await assert.rejects(new CommandBackend(cmds(found, fail), true).delete("k"), /no borró/);
  assert.equal(await new CommandBackend(cmds(fail, fail), true).delete("k"), false);
});

test("macOS: set relee y falla si el almacén truncó o no guardó el valor", async () => {
  const dir = mkdtempSync(join(tmpdir(), "s490-cb-"));
  const sh = (name: string, body: string) => double(dir, name, body);
  const okCmd = sh("ok", "process.exit(0);");
  const stored = sh("stored", 'process.stdout.write("U0VDUkVUTw==\\n");'); // «SECRETO»
  const cmds = { ...macosCommands, set: () => ({ ...okCmd, stdin: "" }), get: () => ({ ...stored, stdin: "" }) } as typeof macosCommands;
  await new CommandBackend(cmds, true).set("k", "SECRETO");
  await assert.rejects(new CommandBackend(cmds, true).set("k", "SECRETO-MAS-LARGO"), /íntegra/);
});

test("secret-tool ausente: falla cerrado con error, no devuelve vacío", async () => {
  const b = new SecretToolBackend({ command: "/nonexistent/secret-tool" });
  await assert.rejects(b.set("k", "v"));
  await assert.rejects(b.get("k"));
});

test("macOS: órdenes con el secreto solo en stdin", () => {
  const m = macosCommands.set("soul-continuity/x/graph/y", "SECRETO-123");
  assert.ok(!m.args.join(" ").includes("SECRETO"));
  assert.ok(m.stdin.includes(Buffer.from("SECRETO-123").toString("base64")));
  assert.ok(!m.stdin.includes("SECRETO-123"));
  assert.throws(() => macosCommands.set('k"; rm', "v"), /clave/);
});

// ---------------------------------------------------------------------------
// Windows Credential Manager

/** Tokens de Entra con forma real: un JSON de más de 5 KB, el doble de lo que cabe en una entrada. */
const GRAPH_BLOB = JSON.stringify({
  access_token: `eyJ0eXAiOiJKV1QiLCJub25jZSI6${"A".repeat(3000)}.SECRETO-AT`,
  refresh_token: `0.AXoA${"r".repeat(1900)}SECRETO-RT`,
  expires_at: NOW + 3600_000, scopes: ["Mail.Read", "Calendars.Read", "Chat.Read", "User.Read", "Files.Read"],
});

/**
 * Doble de PowerShell + Credential Manager: interpreta las operaciones que llegan por stdin y
 * aplica el límite real de CredWrite (2560 bytes de blob, que va en UTF-16).
 */
function credManagerDouble(o: { truncate?: number; failCode?: number } = {}) {
  const vault = new Map<string, string>();
  const calls: { cmd: string; args: string[]; stdin: string }[] = [];
  const run: RunFn = async (cmd, args, stdin) => {
    calls.push({ cmd, args, stdin });
    if (o.failCode) return { code: o.failCode, stdout: "" };
    const { ops } = JSON.parse(stdin) as { ops: { op: string; t: string; v?: string }[] };
    let out = "";
    for (const op of ops) {
      if (op.op === "r") out += vault.has(op.t) ? `+${vault.get(op.t)}\r\n` : "-\r\n";
      else if (op.op === "w") {
        if ((op.v ?? "").length * 2 > 2560) return { code: 4, stdout: "" }; // CredWrite: ERROR_INVALID_PARAMETER
        vault.set(op.t, o.truncate ? (op.v ?? "").slice(0, o.truncate) : (op.v ?? ""));
        out += "+\r\n";
      } else if (op.op === "d") out += vault.delete(op.t) ? "+\r\n" : "-\r\n";
      else return { code: 2, stdout: "" };
    }
    return { code: 0, stdout: out };
  };
  return { run, vault, calls };
}
const K = "soul-continuity/0123456789abcdef/graph/fedcba9876543210";

test("Windows: un JSON de tokens de Graph de más de 5 KB se guarda, se lee y se borra", async () => {
  assert.ok(GRAPH_BLOB.length > 5000);
  const d = credManagerDouble();
  const b = new WindowsCredentialBackend({ run: d.run });
  await b.set(K, GRAPH_BLOB);
  assert.equal(await b.get(K), GRAPH_BLOB);
  assert.ok(d.vault.size > 1, "repartido en varias entradas");
  for (const v of d.vault.values()) assert.ok(v.length * 2 <= 2560, "cada entrada cabe en CredWrite");
  // Ni en la línea de órdenes ni en claro por stdin: el script va sin datos y el valor en base64.
  for (const c of d.calls) {
    assert.equal(c.cmd, "powershell.exe");
    assert.deepEqual(c.args, WIN_PS_ARGS);
    assert.ok(!c.args.join(" ").includes("SECRETO"));
    assert.ok(!c.stdin.includes("SECRETO"));
  }
  // Un valor más corto encima no deja trozos del anterior.
  await b.set(K, "corto");
  assert.equal(await b.get(K), "corto");
  assert.deepEqual([...d.vault.keys()], [K]);
  assert.equal(await b.delete(K), true);
  assert.equal(d.vault.size, 0);
  assert.equal(await b.get(K), null);
  assert.equal(await b.delete(K), false);
});

test("Windows: el almacén de credenciales del adaptador funciona en win32 con tokens de Graph", async () => {
  const d = credManagerDouble();
  const s = new SystemCredentialStore({ backend: new WindowsCredentialBackend({ run: d.run }), operatorRef: "op-pm", now: () => NOW });
  const t = JSON.parse(GRAPH_BLOB) as { access_token: string; refresh_token: string; expires_at: number; scopes: string[] };
  await s.put("graph", ["Mail.Read"], t);
  assert.equal(await s.acquire("graph", ["Mail.Read"]), t.access_token);
  assert.equal(await s.revoke("graph", ["Mail.Read"]), true);
  await assert.rejects(s.acquire("graph", ["Mail.Read"]), (e: { code?: string }) => e.code === "no_credential");
});

test("Windows: fallo de PowerShell o del almacén es error, nunca «sin credencial»", async () => {
  const down = new WindowsCredentialBackend({ run: credManagerDouble({ failCode: 1 }).run });
  await assert.rejects(down.get(K), /no disponible/);
  await assert.rejects(down.set(K, "v"), /no disponible/);
  await assert.rejects(down.delete(K), /no disponible/);
  // Respuesta con menos líneas que operaciones: tampoco se toma por vacía.
  const short = new WindowsCredentialBackend({ run: async () => ({ code: 0, stdout: "-\r\n" }) });
  await assert.rejects(short.get(K), /no disponible/);
  // PowerShell ausente: el spawn falla y se propaga.
  const absent = new WindowsCredentialBackend({ run: async () => { throw new Error("almacén del sistema no disponible (ENOENT)"); } });
  await assert.rejects(absent.get(K), /ENOENT/);
});

test("Windows: si el almacén trunca, set lo detecta al releer y falla", async () => {
  const b = new WindowsCredentialBackend({ run: credManagerDouble({ truncate: 500 }).run });
  await assert.rejects(b.set(K, GRAPH_BLOB), /íntegra/);
});

test("Windows: entrada incompleta o ajena se lee como sin credencial", async () => {
  const d = credManagerDouble();
  const b = new WindowsCredentialBackend({ run: d.run });
  await b.set(K, GRAPH_BLOB);
  d.vault.delete(`${K}/part-2`);
  assert.equal(await b.get(K), null, "falta un trozo");
  d.vault.clear();
  d.vault.set(K, "texto sin cabecera");
  assert.equal(await b.get(K), null);
  await assert.rejects(b.get('k"; rm'), /clave/);
});

test("Windows: reparto en trozos — límites", () => {
  assert.deepEqual(splitParts(""), ["1:"]);
  assert.equal(joinParts(["1:"]), "");
  assert.equal(joinParts(splitParts("ñandú €")), "ñandú €");
  assert.equal(joinParts([null]), null);
  assert.equal(joinParts(["0:"]), null, "cero trozos");
  assert.equal(joinParts([`${WIN_MAX_PARTS + 1}:QQ==`]), null, "más trozos de los admitidos");
  assert.equal(joinParts(["2:QQ==", "no base64!"]), null);
  // Justo en el máximo cabe; un byte más, error explícito.
  const max = (WIN_MAX_PARTS * 1200 / 4) * 3;
  assert.equal(splitParts("x".repeat(max)).length, WIN_MAX_PARTS);
  assert.throws(() => splitParts("x".repeat(max + 1)), /demasiado grande/);
});

test("Windows real: Credential Manager guarda, lee y borra tokens de Graph", { skip: process.platform !== "win32" && "solo en Windows" }, async () => {
  const b = systemBackend("win32");
  const k = `soul-continuity/ci${Date.now().toString(16)}/graph/test`;
  try {
    await b.set(k, GRAPH_BLOB);
    assert.equal(await b.get(k), GRAPH_BLOB);
    await b.set(k, "corto");
    assert.equal(await b.get(k), "corto");
    assert.equal(await b.delete(k), true);
    assert.equal(await b.get(k), null);
    assert.equal(await b.delete(k), false);
  } finally {
    await b.delete(k).catch(() => undefined);
  }
});
