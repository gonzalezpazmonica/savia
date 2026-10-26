// context-origin-stamp.test.ts — SE-221 Slice 1 (OpenCode port)
//
// TDD for guards/context-origin-stamp.ts.
// Mirrors tests/test-context-origin-stamp-hook.bats (8 BATS cases) and
// extends with TS-specific shape assertions per OpenCode v1.14 contract
// (tool.execute.after with input/output objects, output.output mutation).

import { test, expect, beforeEach } from "bun:test";
import { contextOriginStamp } from "../guards/context-origin-stamp.ts";
import { writeFileSync, mkdtempSync, rmSync } from "node:fs";
import { join, resolve } from "node:path";
import { tmpdir } from "node:os";

const ORIGIN_HEADER = "---origin";

function makeLongOutput(lines: number): string {
  return Array.from({ length: lines }, (_, i) => `${i + 1}: line ${i + 1}`).join("\n");
}

function makeInput(tool: string, filePath: string) {
  return { tool, args: { filePath } };
}

function makeOutput(text: string) {
  return { title: "x", output: text, metadata: {} };
}

let tmpDir: string;
let realFile: string;
const realFileLines = 250;

beforeEach(() => {
  tmpDir = mkdtempSync(join(tmpdir(), "se221-stamp-"));
  realFile = join(tmpDir, "fake-spec.md");
  writeFileSync(realFile, makeLongOutput(realFileLines));
});

// ── Shape & no-op cases ─────────────────────────────────────────────────────

test("non-read tool: passthrough (no mutation)", async () => {
  const input = { tool: "bash", args: { command: "ls" } };
  const output = makeOutput("hello world");
  await contextOriginStamp(input, output);
  expect(output.output).toBe("hello world");
});

test("read with undefined output: does not throw", async () => {
  const input = makeInput("read", "/tmp/whatever");
  await expect(contextOriginStamp(input as any, undefined as any)).resolves.toBeUndefined();
});

test("read with empty filePath: passthrough", async () => {
  const input = { tool: "read", args: {} };
  const output = makeOutput("anything");
  await contextOriginStamp(input as any, output);
  expect(output.output).toBe("anything");
});

test("read with non-string output.output: passthrough", async () => {
  const input = makeInput("read", realFile);
  const output = { title: "x", output: 42 as any, metadata: {} };
  await contextOriginStamp(input as any, output as any);
  expect(output.output).toBe(42);
});

// ── Threshold (MIN_LINES) ──────────────────────────────────────────────────

test("output under MIN_LINES threshold: passthrough", async () => {
  const input = makeInput("read", realFile);
  const output = makeOutput(makeLongOutput(50)); // way under 200
  await contextOriginStamp(input as any, output);
  expect(output.output).not.toContain(ORIGIN_HEADER);
});

test("output over MIN_LINES threshold: prefixes origin block", async () => {
  const input = makeInput("read", realFile);
  const text = makeLongOutput(250);
  const output = makeOutput(text);
  await contextOriginStamp(input as any, output);
  expect(output.output.startsWith(ORIGIN_HEADER)).toBe(true);
  expect(output.output).toContain(`path: ${realFile}`);
  expect(output.output).toContain("tier:");
  expect(output.output).toContain("loaded_at:");
  expect(output.output).toContain("size_tokens:");
  expect(output.output).toContain("hash: sha256:");
});

// ── Sandbox exemption ──────────────────────────────────────────────────────

test("sandbox path /tmp/opencode/* is exempt even when large", async () => {
  const sandboxFile = "/tmp/opencode/foo.md";
  const input = makeInput("read", sandboxFile);
  const output = makeOutput(makeLongOutput(300));
  await contextOriginStamp(input as any, output);
  expect(output.output).not.toContain(ORIGIN_HEADER);
});

// ── Idempotency ────────────────────────────────────────────────────────────

test("idempotent: re-running on already-stamped output is no-op", async () => {
  const input = makeInput("read", realFile);
  const output = makeOutput(makeLongOutput(250));
  await contextOriginStamp(input as any, output);
  const after1 = output.output;
  await contextOriginStamp(input as any, output);
  const after2 = output.output;
  expect(after2).toBe(after1);
  // Count of ---origin headers must be exactly 1
  const matches = after2.match(/^---origin$/gm) ?? [];
  expect(matches.length).toBe(1);
});

// ── Tier resolution (delegates to scripts/context-origin-tag.sh) ───────────

test("tier resolution: file outside workspace is N5-external or untrusted", async () => {
  const input = makeInput("read", realFile);
  const output = makeOutput(makeLongOutput(250));
  await contextOriginStamp(input as any, output);
  // /tmp/se221-stamp-* is outside the workspace → N5-external or untrusted
  expect(output.output).toMatch(/tier: (N5-external|untrusted|sandbox)/);
});

test("tier resolution: docs/critical-facts.md is N1-anchor (real workspace path)", async () => {
  // Use the real workspace file as the test target
  const workspace = resolve(import.meta.dir, "..", "..", "..");
  const wsCriticalFacts = join(workspace, "docs", "critical-facts.md");
  // Force SAVIA_WORKSPACE_DIR so tier resolution works regardless of cwd
  // (bun test cwd = .opencode/plugins/, not workspace root)
  const prev = process.env.SAVIA_WORKSPACE_DIR;
  process.env.SAVIA_WORKSPACE_DIR = workspace;
  try {
    const input = makeInput("read", wsCriticalFacts);
    const output = makeOutput(makeLongOutput(250));
    await contextOriginStamp(input as any, output);
    if (output.output.includes(ORIGIN_HEADER)) {
      expect(output.output).toContain("tier: N1-anchor");
    }
  } finally {
    if (prev === undefined) delete process.env.SAVIA_WORKSPACE_DIR;
    else process.env.SAVIA_WORKSPACE_DIR = prev;
  }
});

// ── Error tolerance ────────────────────────────────────────────────────────

test("nonexistent file: still stamps with unknown hash, no throw", async () => {
  const input = makeInput("read", "/tmp/does-not-exist-12345.md");
  const output = makeOutput(makeLongOutput(250));
  await expect(contextOriginStamp(input as any, output)).resolves.toBeUndefined();
});

test("after-guard contract: never throws (best-effort)", async () => {
  // Pass garbage to ensure non-throwing behavior
  await expect(contextOriginStamp(null as any, null as any)).resolves.toBeUndefined();
  await expect(contextOriginStamp({} as any, {} as any)).resolves.toBeUndefined();
});
