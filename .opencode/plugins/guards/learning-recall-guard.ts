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
//
// SE-515 S1 — recall trazado (misma fila que el hook bash ante la misma
// entrada): fila `start` con emitted=false antes de llamar al recall y fila
// `end` con los criterios emitidos y el motivo (emitted | no_hits | timeout |
// unavailable | error | bad_output | write_failed). Solo ids y hash del texto.
// SAVIA_LEARNING_APPLIED=off desactiva el registro.

import { bashExecutable } from "../lib/bash-runtime.ts";
import { appendFileSync, mkdirSync } from "node:fs";
import { dirname } from "node:path";
import { createHash, randomUUID } from "node:crypto";

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

type Hit = { criterion_id: string; principle: string };
type RecallResult = { hits: Hit[]; reason: string };

function recallTimeoutMs(): number {
  const seconds = Number(process.env.SCL_RECALL_TIMEOUT_S ?? "4");
  return Number.isFinite(seconds) && seconds > 0 ? seconds * 1000 : 4000;
}

async function runRecall(query: string): Promise<RecallResult> {
  const script = recallScriptPath();
  const { spawn } = await import("node:child_process");
  const limit = recallTimeoutMs();
  return new Promise((resolve) => {
    let settled = false;
    const done = (result: RecallResult) => {
      if (settled) return;
      settled = true;
      resolve(result);
    };
    const child = spawn(
      bashExecutable(),
      [script, "--query", query, "--top", "3", "--min-score", "10", "--mode", "effective", "--json"],
      { stdio: ["ignore", "pipe", "ignore"] },
    );
    let buf = "";
    child.stdout.on("data", (chunk) => {
      buf += String(chunk);
    });
    const timer = setTimeout(() => {
      try { child.kill("SIGKILL"); } catch {}
      done({ hits: [], reason: "timeout" });
    }, limit);
    child.on("close", (code) => {
      clearTimeout(timer);
      if (code === 3) return done({ hits: [], reason: "unavailable" });
      if (code !== 0) return done({ hits: [], reason: "error" });
      try {
        const parsed = JSON.parse(buf.trim());
        if (!Array.isArray(parsed.effective_hits)) return done({ hits: [], reason: "bad_output" });
        const hits = parsed.effective_hits as Hit[];
        done({ hits, reason: hits.length === 0 ? "no_hits" : "emitted" });
      } catch {
        done({ hits: [], reason: "bad_output" });
      }
    });
    child.on("error", () => {
      clearTimeout(timer);
      done({ hits: [], reason: "error" });
    });
  });
}

function emissionLogPath(): string {
  return process.env.SCL_EMISSION_LOG ?? `${workspaceRoot()}/output/learning-loop/recall-emission.jsonl`;
}

// trace — una fila con el mismo esquema que el hook bash. Nunca lanza.
function trace(eventId: string, queryHash: string, phase: string, emitted: boolean, reason: string, criteria: string[]): void {
  if (process.env.SAVIA_LEARNING_APPLIED === "off") return;
  try {
    const path = emissionLogPath();
    mkdirSync(dirname(path), { recursive: true });
    const row = {
      ts: new Date().toISOString().replace(/\.\d{3}Z$/, "Z"),
      event_id: eventId,
      frontend: "opencode",
      query_hash: queryHash,
      phase,
      emitted,
      criteria,
      reason,
    };
    appendFileSync(path, JSON.stringify(row) + "\n", "utf-8");
  } catch {
    // El registro no debe romper el mensaje.
  }
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

    // Mismo hash que el hook: el texto sin saltos de línea finales.
    const query = text.replace(/\n+$/, "");
    const queryHash = createHash("sha256").update(query, "utf8").digest("hex");
    const eventId = randomUUID();
    trace(eventId, queryHash, "start", false, "started", []);

    const { hits, reason } = await runRecall(query);
    if (hits.length === 0) {
      trace(eventId, queryHash, "end", false, reason, []);
      return;
    }

    const emittedHits = hits.slice(0, 3);
    const lines = ["## Criterios humanos aplicables", ""];
    for (const hit of emittedHits) {
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

    try {
      output.parts.unshift(synthetic);
    } catch {
      trace(eventId, queryHash, "end", false, "write_failed", []);
      return;
    }
    trace(eventId, queryHash, "end", true, "emitted", emittedHits.map((h) => h.criterion_id));
  } catch {
    // Best-effort: never throw from a chat.message guard.
  }
}
