// context-drop-after-use.ts — SE-221 Slice 2 (OpenCode port)
//
// Capa context-engineering of Savia Shield: post-tool context minimizer.
// Port of `.claude/hooks/context-drop-after-use.sh` for OpenCode v1.14+.
//
// Runs AFTER `read`/`webfetch`/`bash` tool execution. If the output is over
// CONTEXT_DROP_MIN_LINES (default 500) lines, delegates to
// scripts/context-drop-after-use.sh for a KEEP/STUB/DROP verdict.
// STUB and DROP rewrite output.output to a compact stub marker:
//
//   <stub origin="<path>" tier="<tier>" full-content-at="<path>" abstract="<line>"/>
//
// Each decision (including KEEP) is logged to the audit JSONL
// (default: <workspace>/output/context-drop-audit.jsonl; overridable via
// CONTEXT_DROP_AUDIT_LOG).
//
// - Non-blocking: never throws.
// - Idempotent: if output already starts with "<stub origin=", passthrough.
// - Tier and verdict logic: delegated to scripts/context-drop-after-use.sh
//   (single source of truth shared with the bash hook).
//
// Spec: docs/propuestas/SE-221-inverted-security-patterns-as-context-engineering.md (AC-07, AC-08, AC-09)
// Empirical: probe SE-221 confirmed output.output mutation is observed by the LLM.

import { extractToolName, extractFilePath, type ToolInput, type ToolOutput } from "../lib/hook-input.ts";
import { bashExecutable } from "../lib/bash-runtime.ts";

const MIN_LINES = Number(process.env.CONTEXT_DROP_MIN_LINES ?? "500");

function workspaceRoot(): string {
  return process.env.SAVIA_WORKSPACE_DIR ?? process.cwd();
}

function dropScriptPath(): string {
  return workspaceRoot() + "/scripts/context-drop-after-use.sh";
}

function defaultAuditPath(): string {
  return process.env.CONTEXT_DROP_AUDIT_LOG ?? (workspaceRoot() + "/output/context-drop-audit.jsonl");
}

function countLines(s: string): number {
  let n = 0;
  for (let i = 0; i < s.length; i++) if (s.charCodeAt(i) === 10) n++;
  return n;
}

function estimateTokens(s: string): number {
  return Math.floor(Buffer.byteLength(s, "utf-8") / 4);
}

type Verdict = "KEEP" | "STUB" | "DROP";

interface VerdictResult {
  verdict: Verdict;
  tier: string;
  abstract: string;
  reason: string;
}

async function runDropScript(filePath: string, nextTask: string): Promise<VerdictResult | null> {
  try {
    const script = dropScriptPath();
    const { spawn } = await import("node:child_process");
    return await new Promise<VerdictResult | null>((resolve) => {
      const args = [bashExecutable(), script, "--json", "--path", filePath, "--next-task", nextTask];
      const child = spawn(args[0], args.slice(1), { stdio: ["ignore", "pipe", "ignore"] });
      let buf = "";
      child.stdout.on("data", (chunk) => { buf += String(chunk); });
      const timeout = setTimeout(() => {
        try { child.kill(); } catch {}
        resolve(null);
      }, 3000);
      child.on("close", () => {
        clearTimeout(timeout);
        try {
          const parsed = JSON.parse(buf.trim());
          if (!parsed || typeof parsed !== "object" || !parsed.verdict) {
            resolve(null);
            return;
          }
          const v = String(parsed.verdict).toUpperCase();
          if (v !== "KEEP" && v !== "STUB" && v !== "DROP") {
            resolve(null);
            return;
          }
          resolve({
            verdict: v as Verdict,
            tier: String(parsed.tier ?? "untrusted"),
            abstract: String(parsed.abstract ?? ""),
            reason: String(parsed.reason ?? ""),
          });
        } catch {
          resolve(null);
        }
      });
      child.on("error", () => {
        clearTimeout(timeout);
        resolve(null);
      });
    });
  } catch {
    return null;
  }
}

function buildStub(filePath: string, tier: string, verdict: Verdict, abstract: string, reason: string): string {
  if (verdict === "DROP") {
    return '<stub origin="' + filePath + '" tier="' + tier + '" verdict="DROP" reason="' + reason.replace(/"/g, "'") + '"/>';
  }
  // STUB
  const safeAbstract = (abstract || "(abstract no disponible)").replace(/"/g, "'");
  return '<stub origin="' + filePath + '" tier="' + tier + '" full-content-at="' + filePath + '" abstract="' + safeAbstract + '"/>';
}

async function appendAudit(entry: object): Promise<void> {
  try {
    const { appendFile, mkdir } = await import("node:fs/promises");
    const { dirname } = await import("node:path");
    const auditPath = defaultAuditPath();
    await mkdir(dirname(auditPath), { recursive: true });
    await appendFile(auditPath, JSON.stringify(entry) + "\n");
  } catch {
    // Best-effort audit logging
  }
}

function resolvePath(tool: string, input: ToolInput, output: ToolOutput): string {
  if (tool === "read") {
    return extractFilePath(input, output);
  }
  if (tool === "webfetch") {
    const args = (output as any)?.args ?? (input as any)?.args ?? {};
    const url = args?.url;
    return typeof url === "string" ? url : "";
  }
  if (tool === "bash") {
    // Bash has no canonical path; sandbox placeholder triggers exemption
    return "/tmp/opencode/bash-output.txt";
  }
  return "";
}

export async function contextDropAfterUse(input: ToolInput, output: ToolOutput): Promise<void> {
  try {
    if (!output || typeof output !== "object") return;
    const tool = extractToolName(input);
    if (tool !== "read" && tool !== "webfetch" && tool !== "bash") return;

    const filePath = resolvePath(tool, input, output);
    if (!filePath) return;

    // Sandbox exemption for bash and any /tmp/opencode/* read
    if (filePath.startsWith("/tmp/opencode/")) return;

    const text = (output as any).output;
    if (typeof text !== "string") return;

    if (countLines(text) < MIN_LINES) return;

    // Idempotency: already a stub
    const firstNewline = text.indexOf("\n");
    const firstLine = firstNewline === -1 ? text : text.slice(0, firstNewline);
    if (firstLine.startsWith("<stub origin=")) return;

    const nextTask = process.env.CONTEXT_DROP_NEXT_TASK ?? "";
    const verdict = await runDropScript(filePath, nextTask);
    if (!verdict) return;

    const origBytes = Buffer.byteLength(text, "utf-8");
    let tokensSaved = 0;
    let newOutput = text;

    if (verdict.verdict === "KEEP") {
      // No mutation, just audit
    } else if (verdict.verdict === "DROP") {
      newOutput = buildStub(filePath, verdict.tier, "DROP", "", verdict.reason);
      tokensSaved = Math.floor(origBytes / 4);
      (output as any).output = newOutput;
    } else if (verdict.verdict === "STUB") {
      newOutput = buildStub(filePath, verdict.tier, "STUB", verdict.abstract, verdict.reason);
      const savedBytes = origBytes - verdict.abstract.length - 200;
      tokensSaved = savedBytes > 0 ? Math.floor(savedBytes / 4) : 0;
      (output as any).output = newOutput;
    }

    await appendAudit({
      ts: new Date().toISOString().replace(/\.\d{3}Z$/, "Z"),
      tool,
      path: filePath,
      tier: verdict.tier,
      verdict: verdict.verdict,
      reason: verdict.reason,
      next_task_excerpt: nextTask.slice(0, 80),
      tokens_saved_est: tokensSaved,
    });
  } catch {
    // Best-effort: never throw from an after-guard.
  }
}
