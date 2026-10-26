// learning-recall-guard.ts — SCL-003/SCL-008 (OpenCode port)
//
// Port of `.claude/hooks/learning-recall-hook.sh` for OpenCode v1.14+.
// Runs on `chat.message`: when a new user message arrives, extracts the text,
// queries SaviaLearning via scripts/learning-recall.sh in `effective` mode,
// and injects the applicable human-authorized criteria as a synthetic text
// part prepended to the user message.
//
// - Authority-filtered (SCL-008): only criteria with target=criterio,
//   lifecycle=active, provenance=human_authored are injected.
// - Non-blocking: any error, timeout or empty result returns silently.
// - Skip list mirrors the bash hook (s[ií]|no|ok|vale|claro|hecho|listo|...).
// - Gated by SAVIA_LEARNING_RECALL (default on).
//
// Spec: docs/specs/SCL-001-aprendizaje-continuo.spec.md (AC-2.1..2.6)

import { bashExecutable } from "../lib/bash-runtime.ts";

interface ChatMessageOutput {
  message: { id: string; sessionID: string };
  parts: Array<Record<string, unknown>>;
}

function workspaceRoot(): string {
  return process.env.SAVIA_WORKSPACE_DIR ?? process.cwd();
}

function recallScriptPath(): string {
  return `${workspaceRoot()}/scripts/learning-recall.sh`;
}

async function runRecall(query: string): Promise<Array<{ criterion_id: string; principle: string }>> {
  const script = recallScriptPath();
  const { spawn } = await import("node:child_process");
  return new Promise((resolve) => {
    const child = spawn(
      bashExecutable(),
      [script, "--query", query, "--top", "3", "--min-score", "10", "--mode", "effective", "--json"],
      { stdio: ["ignore", "pipe", "ignore"], timeout: 4000 },
    );
    let buf = "";
    child.stdout.on("data", (chunk) => {
      buf += String(chunk);
    });
    const timer = setTimeout(() => {
      try { child.kill(); } catch {}
      resolve([]);
    }, 4000);
    child.on("close", () => {
      clearTimeout(timer);
      try {
        const parsed = JSON.parse(buf.trim());
        resolve(Array.isArray(parsed.effective_hits) ? parsed.effective_hits : []);
      } catch {
        resolve([]);
      }
    });
    child.on("error", () => {
      clearTimeout(timer);
      resolve([]);
    });
  });
}

function extractUserText(parts: Array<Record<string, unknown>>): string {
  for (const part of parts) {
    if (part?.type === "text" && typeof part.text === "string") {
      return part.text;
    }
  }
  return "";
}

function isSkip(text: string): boolean {
  return /^(s[ií]|no|ok|vale|claro|hecho|listo|adelante|gracias|y|n)$/i.test(text.trim());
}

export async function learningRecallGuard(
  input: { messageID?: string },
  output: ChatMessageOutput,
): Promise<void> {
  try {
    if (process.env.SAVIA_LEARNING_RECALL === "off") return;
    if (!output || !Array.isArray(output.parts)) return;

    const text = extractUserText(output.parts);
    if (text.length < 8 || text.trim().startsWith("/") || isSkip(text)) return;

    const hits = await runRecall(text);
    if (hits.length === 0) return;

    const lines = ["## Criterios humanos aplicables", ""];
    for (const hit of hits.slice(0, 3)) {
      lines.push(`- [${hit.criterion_id}] ${hit.principle}`);
    }

    const msg = output.message;
    const synthetic = {
      id: `prt_${Date.now()}`,
      sessionID: msg.sessionID,
      messageID: msg.id,
      type: "text",
      text: lines.join("\n"),
      synthetic: true,
    };

    output.parts.unshift(synthetic);
  } catch {
    // Best-effort: never throw from a chat.message guard.
  }
}
