// guard-blocks.test.ts — SE-510 D2: registro de bloqueos desde el corredor TS (AC-4).
// Separado de se510-guard-blocks.test.ts para que la puerta TDD encuentre los tests de lib/guard-blocks.ts.
import { test, expect } from "bun:test";
import { mkdtempSync, readFileSync, existsSync, writeFileSync, mkdirSync, chmodSync } from "node:fs";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { guardNameOf, recordGuardBlock } from "../lib/guard-blocks.ts";

const RECORDER_DIR = fileURLToPath(new URL("../../../scripts", import.meta.url));
const tmp = () => mkdtempSync(join(tmpdir(), "se510-ts-"));
const bash = (command: string, workdir?: string) => ({ tool: "bash", args: { command, workdir } }) as any;

test("guardNameOf: etiqueta del mensaje o nombre genérico", () => {
  expect(guardNameOf("BLOCKED [force-push]: no")).toBe("force-push");
  expect(guardNameOf("BLOQUEADO [pr-summary-gate]: x")).toBe("pr-summary-gate");
  expect(guardNameOf("BLOCKED [credential-leak/aws]: x")).toBe("credential-leak/aws");
  expect(guardNameOf("BLOCKED: sin etiqueta")).toBe("ts-before-guards");
});

test("recordGuardBlock no registra una excepción que no es un bloqueo (TypeError)", () => {
  const d = tmp();
  const log = join(d, "blocks.jsonl");
  process.env.SAVIA_GUARD_BLOCKS_LOG = log;
  process.env.SAVIA_GUARD_BLOCKS_KEY = join(d, "k");
  try {
    expect(recordGuardBlock(new TypeError("cannot read properties of undefined"), bash("ls"), {})).toBe(false);
    // Un error interno que solo CITA la marca (no empieza por ella) tampoco es un bloqueo.
    expect(recordGuardBlock(new Error("fallo al leer 'BLOCKED [x]' del log"), bash("ls"), {})).toBe(false);
    expect(existsSync(log)).toBe(false);
    expect(recordGuardBlock(new Error("BLOCKED: sin etiqueta"), bash("ls"), {})).toBe(true);
    expect(JSON.parse(readFileSync(log, "utf8").trim()).guard).toBe("ts-before-guards");
  } finally {
    delete process.env.SAVIA_GUARD_BLOCKS_LOG;
    delete process.env.SAVIA_GUARD_BLOCKS_KEY;
  }
});

test("recordGuardBlock deja una línea sin la orden en claro", () => {
  const d = tmp();
  const log = join(d, "blocks.jsonl");
  const key = join(d, "k");
  process.env.SAVIA_GUARD_BLOCKS_LOG = log;
  process.env.SAVIA_GUARD_BLOCKS_KEY = key;
  delete process.env.SAVIA_GUARD_LOG_INPUT;
  try {
    const ok = recordGuardBlock(new Error("BLOCKED [force-push]: git push --force blocked."),
      bash("git push --force origin main TOKENSECRETO"), {});
    expect(ok).toBe(true);
    const text = readFileSync(log, "utf8");
    const row = JSON.parse(text.trim());
    expect(row.guard).toBe("force-push");
    expect(row.engine).toBe("ts");
    expect(row.cmd_hmac).toMatch(/^[0-9a-f]{64}$/);
    expect(text).not.toContain("TOKENSECRETO");
    expect(row.input).toBeUndefined();
  } finally {
    delete process.env.SAVIA_GUARD_BLOCKS_LOG;
    delete process.env.SAVIA_GUARD_BLOCKS_KEY;
  }
});

test("recordGuardBlock nunca lanza aunque no pueda escribir", () => {
  const d = tmp();
  writeFileSync(join(d, "f"), "x");
  process.env.SAVIA_GUARD_BLOCKS_LOG = join(d, "f", "no-dir", "x.jsonl");
  process.env.SAVIA_GUARD_BLOCKS_KEY = join(d, "k");
  try {
    expect(recordGuardBlock(new Error("BLOCKED [x]: y"), bash("ls"), {})).toBe(false);
    expect(existsSync(join(d, "f", "no-dir"))).toBe(false);
  } finally {
    delete process.env.SAVIA_GUARD_BLOCKS_LOG;
    delete process.env.SAVIA_GUARD_BLOCKS_KEY;
  }
});

// Codex a15100d P1-3: lo que el guard de credenciales reconoce no puede quedar en claro en el
// registro (opt-in SAVIA_GUARD_LOG_INPUT=1). Muestras sintéticas montadas en tiempo de ejecución
// (partidas para que los guards de credenciales no bloqueen el propio fichero de test).
test("redact tapa toda credencial que detectCredentialLeak reconoce", () => {
  const { detectCredentialLeak } = require("../lib/credential-patterns.ts");
  const a = (n: number) => "a1B2c3D4e5".repeat(4).slice(0, n);
  const PK = "PRIVATE" + " KEY-----";
  const secrets: Array<[string, string]> = [
    ["vault login s." + a(24), "s." + a(24)],
    ["vault login hvs." + a(26), "hvs." + a(26)],
    ["curl https://x/?key=AI" + "za" + a(35), "za" + a(35)],
    ["az x 'Default" + "EndpointsProtocol=https;AccountName=n;Account" + "Key=" + a(20) + "'", a(20)],
    ["curl 'https://x/c?sv=2024-01-01&ss=b&sig=" + a(20) + "'", a(20)],
    ["kubectl --token eyJhbGciOiJSUzI1NiI" + a(20), a(20)],
    ["echo '-----BEGIN RSA " + PK + "\n" + a(30) + "\n-----END RSA " + PK + "' > k", a(30)],
    ["export X=eyJ" + a(12) + ".eyJ" + a(12) + "." + a(22), a(12)],
    ["connection_string=" + a(10) + " run", a(10)],
  ];
  const r = spawnSync("python3", ["-c",
    "import json,sys; sys.path.insert(0,sys.argv[1]); from guard_blocks import redact; " +
    "print(json.dumps([redact(s) for s in json.load(sys.stdin)]))", RECORDER_DIR],
    { input: JSON.stringify(secrets.map(([s]) => s)), encoding: "utf8" });
  expect(r.status).toBe(0);
  const out: string[] = JSON.parse(r.stdout);
  secrets.forEach(([cmd, secret], i) => {
    expect(detectCredentialLeak(cmd)).not.toBeNull();
    expect(out[i]).not.toContain(secret);
    expect(out[i]).toContain("[REDACTED]");
  });
  // Negativo: una orden sin credencial sale intacta.
  const clean = spawnSync("python3", ["-c",
    "import sys; sys.path.insert(0,sys.argv[1]); from guard_blocks import redact; print(redact('git status -s'))",
    RECORDER_DIR], { encoding: "utf8" });
  expect(clean.stdout.trim()).toBe("git status -s");
});

// Seguridad a15100d P2-3: el motivo (puede citar el fragmento detectado) no viaja en argv,
// que cualquier usuaria de la máquina ve en /proc; va por el entorno del proceso hijo.
test("recordGuardBlock pasa el motivo por el entorno, no por la línea de órdenes", () => {
  const d = tmp();
  const bin = join(d, "bin");
  mkdirSync(bin);
  writeFileSync(join(bin, "python3"),
    `#!/bin/sh\nprintf '%s\\n' "$@" > "${d}/argv"\nprintf '%s' "$SAVIA_GUARD_BLOCK_REASON" > "${d}/env"\n`);
  chmodSync(join(bin, "python3"), 0o755);
  const oldPath = process.env.PATH;
  process.env.PATH = `${bin}:${oldPath}`;
  try {
    recordGuardBlock(new Error("BLOCKED [x]: fragmento MOTIVOSECRETO"), bash("ls"), {});
  } finally {
    process.env.PATH = oldPath;
  }
  expect(readFileSync(join(d, "argv"), "utf8")).not.toContain("MOTIVOSECRETO");
  expect(readFileSync(join(d, "env"), "utf8")).toContain("MOTIVOSECRETO");
});
