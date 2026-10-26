// context-origin-stamp.ts — SE-221 Slice 1 (OpenCode port)
//
// Capa context-engineering of Savia Shield: post-Read origin tagger.
// Port of `.claude/hooks/context-origin-stamp.sh` for OpenCode v1.14+.
//
// Runs AFTER `read` tool execution. If the output is over CONTEXT_ORIGIN_MIN_LINES
// (default 200) lines, prefixes the output.output string with a YAML block:
//
//   ---origin
//   path: <abs>
//   tier: <N1..N5|untrusted|sandbox>
//   loaded_at: <ISO-8601>
//   size_tokens: <est>
//   hash: sha256:<8>
//   ---
//
// - Exempt: /tmp/opencode/* sandbox.
// - Idempotent: skips if first line is already "---origin".
// - Non-blocking: any error returns silently (passthrough).
// - Tier resolution: delegated to scripts/context-origin-tag.sh
//   (single source of truth shared with the bash hook).
//
// Spec: docs/propuestas/SE-221-inverted-security-patterns-as-context-engineering.md (AC-02, AC-03)
// Empirical: probe SE-221 confirmed output.output mutation is observed by the LLM.

import { extractToolName, extractFilePath, type ToolInput, type ToolOutput } from "../lib/hook-input.ts";
import { bashExecutable } from "../lib/bash-runtime.ts";

const MIN_LINES = Number(process.env.CONTEXT_ORIGIN_MIN_LINES ?? "200");

function workspaceRoot(): string {
  return process.env.SAVIA_WORKSPACE_DIR ?? process.cwd();
}

function tagScriptPath(): string {
  return `${workspaceRoot()}/scripts/context-origin-tag.sh`;
}

async function resolveTier(filePath: string): Promise<string> {
  try {
    const script = tagScriptPath();
    const { spawn } = await import("node:child_process");
    return await new Promise<string>((resolve) => {
      const child = spawn(bashExecutable(), [script, filePath], { stdio: ["ignore", "pipe", "ignore"] });
      let buf = "";
      child.stdout.on("data", (chunk) => {
        buf += String(chunk);
      });
      const timeout = setTimeout(() => {
        try { child.kill(); } catch {}
        resolve("untrusted");
      }, 2000);
      child.on("close", () => {
        clearTimeout(timeout);
        const tier = buf.trim().split(/\r?\n/)[0] || "untrusted";
        resolve(tier);
      });
      child.on("error", () => {
        clearTimeout(timeout);
        resolve("untrusted");
      });
    });
  } catch {
    return "untrusted";
  }
}

async function fileHash(filePath: string): Promise<string> {
  try {
    const { readFile } = await import("node:fs/promises");
    const { createHash } = await import("node:crypto");
    const buf = await readFile(filePath);
    return createHash("sha256").update(buf).digest("hex").slice(0, 8);
  } catch {
    return "unknown";
  }
}

function countLines(s: string): number {
  let n = 0;
  for (let i = 0; i < s.length; i++) if (s.charCodeAt(i) === 10) n++;
  return n;
}

function estimateTokens(s: string): number {
  return Math.floor(Buffer.byteLength(s, "utf-8") / 4);
}

export async function contextOriginStamp(input: ToolInput, output: ToolOutput): Promise<void> {
  try {
    if (!output || typeof output !== "object") return;

    const tool = extractToolName(input);
    if (tool !== "read") return;

    const filePath = extractFilePath(input, output);
    if (!filePath) return;

    if (filePath.startsWith("/tmp/opencode/")) return;

    const text = (output as any).output;
    if (typeof text !== "string") return;

    if (countLines(text) < MIN_LINES) return;

    const firstNewline = text.indexOf("\n");
    const firstLine = firstNewline === -1 ? text : text.slice(0, firstNewline);
    if (firstLine === "---origin") return;

    const tier = await resolveTier(filePath);
    const hash = await fileHash(filePath);
    const sizeTokens = estimateTokens(text);
    const loadedAt = new Date().toISOString().replace(/\.\d{3}Z$/, "Z");

    const block =
      "---origin\n" +
      "path: " + filePath + "\n" +
      "tier: " + tier + "\n" +
      "loaded_at: " + loadedAt + "\n" +
      "size_tokens: " + sizeTokens + "\n" +
      "hash: sha256:" + hash + "\n" +
      "---";

    (output as any).output = block + "\n" + text;
  } catch {
    // Best-effort: never throw from an after-guard.
  }
}
