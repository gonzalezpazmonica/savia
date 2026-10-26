// context-drop-after-use.test.ts — SE-221 Slice 2 (OpenCode port)
//
// TDD for guards/context-drop-after-use.ts.
// Mirrors tests/test-context-drop-after-use.bats and exercises the
// post-tool drop/stub/keep decision engine adapted to OpenCode v1.14+.

import { test, expect, beforeAll, afterAll } from "bun:test";
import { contextDropAfterUse } from "../guards/context-drop-after-use.ts";
import { mkdtempSync, rmSync, existsSync, readFileSync } from "node:fs";
import { join, resolve } from "node:path";
import { tmpdir } from "node:os";

const STUB_RX = /^<stub origin=/;
// Raíz real del repo, sea cual sea la máquina (Linux, macOS o Windows).
const WORKSPACE = resolve(import.meta.dir, "..", "..", "..");

function makeLongOutput(lines: number, prefix = "content"): string {
  return Array.from({ length: lines }, (_, i) => `${prefix} ${i + 1}`).join("\n");
}

function makeInput(tool: string, args: Record<string, unknown>) {
  return { tool, args };
}

function makeOutput(text: string) {
  return { title: "x", output: text, metadata: {} };
}

let prevWorkspace: string | undefined;

beforeAll(() => {
  prevWorkspace = process.env.SAVIA_WORKSPACE_DIR;
  process.env.SAVIA_WORKSPACE_DIR = WORKSPACE;
});

afterAll(() => {
  if (prevWorkspace === undefined) delete process.env.SAVIA_WORKSPACE_DIR;
  else process.env.SAVIA_WORKSPACE_DIR = prevWorkspace;
});

// ── Shape & no-op cases ─────────────────────────────────────────────────────

test("non-targeted tool (edit): passthrough", async () => {
  const input = makeInput("edit", { filePath: "/tmp/x.md" });
  const output = makeOutput(makeLongOutput(800));
  await contextDropAfterUse(input as any, output);
  expect(output.output).not.toMatch(STUB_RX);
});

test("null output: does not throw", async () => {
  const input = makeInput("read", { filePath: "/tmp/x.md" });
  await expect(contextDropAfterUse(input as any, null as any)).resolves.toBeUndefined();
});

test("non-string output.output: passthrough", async () => {
  const input = makeInput("read", { filePath: "/tmp/x.md" });
  const output = { title: "x", output: 42 as any, metadata: {} };
  await contextDropAfterUse(input as any, output as any);
  expect(output.output).toBe(42);
});

// ── Threshold ──────────────────────────────────────────────────────────────

test("output under MIN_LINES threshold: passthrough", async () => {
  const input = makeInput("read", { filePath: `${WORKSPACE}/docs/critical-facts.md` });
  const output = makeOutput(makeLongOutput(100)); // < 500 default
  await contextDropAfterUse(input as any, output);
  expect(output.output).not.toMatch(STUB_RX);
});

// ── KEEP verdicts ──────────────────────────────────────────────────────────

test("KEEP: N1-anchor (docs/critical-facts.md) is always relevant", async () => {
  const input = makeInput("read", { filePath: `${WORKSPACE}/docs/critical-facts.md` });
  const output = makeOutput(makeLongOutput(600));
  await contextDropAfterUse(input as any, output);
  // KEEP should not stub the output
  expect(output.output).not.toMatch(STUB_RX);
});

test("KEEP: N2-eager (CLAUDE.md) is always relevant", async () => {
  const input = makeInput("read", { filePath: `${WORKSPACE}/CLAUDE.md` });
  const output = makeOutput(makeLongOutput(600));
  await contextDropAfterUse(input as any, output);
  expect(output.output).not.toMatch(STUB_RX);
});

test("KEEP override: next-task contains KEEP-CONTEXT", async () => {
  const input = makeInput("read", { filePath: `${WORKSPACE}/docs/rules/domain/critical-rules-extended.md` });
  const output = makeOutput(makeLongOutput(600));
  const prev = process.env.CONTEXT_DROP_NEXT_TASK;
  process.env.CONTEXT_DROP_NEXT_TASK = "do something KEEP-CONTEXT please";
  try {
    await contextDropAfterUse(input as any, output);
    expect(output.output).not.toMatch(STUB_RX);
  } finally {
    if (prev === undefined) delete process.env.CONTEXT_DROP_NEXT_TASK;
    else process.env.CONTEXT_DROP_NEXT_TASK = prev;
  }
});

test("KEEP: filename appears in next-task as textual reference", async () => {
  const filePath = `${WORKSPACE}/docs/rules/domain/critical-rules-extended.md`;
  const input = makeInput("read", { filePath });
  const output = makeOutput(makeLongOutput(600));
  const prev = process.env.CONTEXT_DROP_NEXT_TASK;
  process.env.CONTEXT_DROP_NEXT_TASK = "now apply critical-rules-extended.md rules";
  try {
    await contextDropAfterUse(input as any, output);
    expect(output.output).not.toMatch(STUB_RX);
  } finally {
    if (prev === undefined) delete process.env.CONTEXT_DROP_NEXT_TASK;
    else process.env.CONTEXT_DROP_NEXT_TASK = prev;
  }
});

// ── STUB verdicts ──────────────────────────────────────────────────────────

test("STUB: N4b lazy-on-demand without future reference becomes stub", async () => {
  // critical-rules-extended.md is N4b-on-demand (not in eager imports list).
  // radical-honesty.md is N2-eager and would be KEPT — wrong choice.
  const input = makeInput("read", { filePath: `${WORKSPACE}/docs/rules/domain/critical-rules-extended.md` });
  const output = makeOutput(makeLongOutput(600));
  const prev = process.env.CONTEXT_DROP_NEXT_TASK;
  process.env.CONTEXT_DROP_NEXT_TASK = "unrelated next task here";
  try {
    await contextDropAfterUse(input as any, output);
    expect(output.output).toMatch(STUB_RX);
    expect(output.output).toContain('full-content-at="');
    expect(output.output).toContain('abstract="');
  } finally {
    if (prev === undefined) delete process.env.CONTEXT_DROP_NEXT_TASK;
    else process.env.CONTEXT_DROP_NEXT_TASK = prev;
  }
});

test("Idempotency: re-running on a stub does not re-stub it", async () => {
  const input = makeInput("read", { filePath: `${WORKSPACE}/docs/rules/domain/critical-rules-extended.md` });
  const output = makeOutput(makeLongOutput(600));
  const prev = process.env.CONTEXT_DROP_NEXT_TASK;
  process.env.CONTEXT_DROP_NEXT_TASK = "unrelated";
  try {
    await contextDropAfterUse(input as any, output);
    const after1 = output.output;
    await contextDropAfterUse(input as any, output);
    expect(output.output).toBe(after1);
  } finally {
    if (prev === undefined) delete process.env.CONTEXT_DROP_NEXT_TASK;
    else process.env.CONTEXT_DROP_NEXT_TASK = prev;
  }
});

// ── DROP verdicts ──────────────────────────────────────────────────────────

test("DROP: untrusted external path becomes minimal stub with DROP marker", async () => {
  const input = makeInput("read", { filePath: "/etc/some-untrusted-file" });
  const output = makeOutput(makeLongOutput(600));
  await contextDropAfterUse(input as any, output);
  // DROP also produces a stub but marked verdict="DROP"
  expect(output.output).toMatch(STUB_RX);
  expect(output.output).toContain('verdict="DROP"');
});

// ── WebFetch / Bash ────────────────────────────────────────────────────────

test("WebFetch: URL is used as path for tier resolution", async () => {
  const input = makeInput("webfetch", { url: "https://example.com" });
  const output = makeOutput(makeLongOutput(600));
  await contextDropAfterUse(input as any, output);
  // External URL → DROP or untrusted-stub
  expect(output.output).toMatch(STUB_RX);
});

test("Bash: sandbox placeholder is exempt", async () => {
  const input = makeInput("bash", { command: "ls -la" });
  const output = makeOutput(makeLongOutput(600));
  await contextDropAfterUse(input as any, output);
  expect(output.output).not.toMatch(STUB_RX);
});

// ── Audit log ──────────────────────────────────────────────────────────────

test("Audit log: DROP/STUB decision appends one JSONL line", async () => {
  const auditDir = mkdtempSync(join(tmpdir(), "se221-drop-audit-"));
  const auditFile = join(auditDir, "context-drop-audit.jsonl");
  const prev = process.env.CONTEXT_DROP_AUDIT_LOG;
  process.env.CONTEXT_DROP_AUDIT_LOG = auditFile;
  try {
    const input = makeInput("read", { filePath: `${WORKSPACE}/docs/rules/domain/critical-rules-extended.md` });
    const output = makeOutput(makeLongOutput(600));
    process.env.CONTEXT_DROP_NEXT_TASK = "unrelated";
    await contextDropAfterUse(input as any, output);
    expect(existsSync(auditFile)).toBe(true);
    const content = readFileSync(auditFile, "utf-8");
    const lines = content.trim().split("\n").filter(Boolean);
    expect(lines.length).toBe(1);
    const entry = JSON.parse(lines[0]);
    expect(entry.verdict).toMatch(/STUB|DROP|KEEP/);
    expect(entry.path).toBe(`${WORKSPACE}/docs/rules/domain/critical-rules-extended.md`);
    expect(typeof entry.tokens_saved_est).toBe("number");
  } finally {
    if (prev === undefined) delete process.env.CONTEXT_DROP_AUDIT_LOG;
    else process.env.CONTEXT_DROP_AUDIT_LOG = prev;
    delete process.env.CONTEXT_DROP_NEXT_TASK;
    rmSync(auditDir, { recursive: true, force: true });
  }
});

// ── After-guard contract ──────────────────────────────────────────────────

test("after-guard contract: never throws on garbage input", async () => {
  await expect(contextDropAfterUse(null as any, null as any)).resolves.toBeUndefined();
  await expect(contextDropAfterUse({} as any, {} as any)).resolves.toBeUndefined();
  await expect(contextDropAfterUse({ tool: "read" } as any, { output: "x" } as any)).resolves.toBeUndefined();
});
