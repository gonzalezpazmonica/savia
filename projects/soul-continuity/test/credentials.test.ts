import { test } from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, readFileSync } from "node:fs";
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
