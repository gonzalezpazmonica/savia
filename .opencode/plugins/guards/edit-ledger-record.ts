// edit-ledger-record.ts — SE-402
//
// OpenCode binding of `.opencode/hooks/edit-ledger-record.sh`. Runs AFTER an
// edit/write tool call and records path + sha256 (never content) in the local
// attributed-edit ledger via `scripts/edit-ledger.sh record`, feeding it the
// same payload shape Claude Code sends, so both frontends share one script.
// Non-blocking: any failure is swallowed.
//
// Reference: docs/specs/SE-402-attributed-edit-ledger.spec.md

import {
  extractToolName,
  extractFilePath,
  type ToolInput,
  type ToolOutput,
} from "../lib/hook-input.ts";
import { bashExecutable } from "../lib/bash-runtime.ts";

function workspaceRoot(): string {
  return process.env.SAVIA_WORKSPACE_DIR ?? process.cwd();
}

export function buildLedgerPayload(input: ToolInput & { sessionID?: string }, output: ToolOutput): string | null {
  const tool = extractToolName(input);
  if (tool !== "edit" && tool !== "write") return null;
  const filePath = extractFilePath(input, output);
  if (!filePath) return null;
  const failed = typeof output?.metadata?.error === "string" && output.metadata.error.length > 0;
  if (failed) return null;
  return JSON.stringify({
    session_id: input.sessionID ?? "opencode",
    tool_name: tool === "edit" ? "Edit" : "Write",
    tool_input: { file_path: filePath },
    tool_response: {},
    agent_type: process.env.SAVIA_AGENT ?? "main",
    cwd: workspaceRoot(),
  });
}

export async function editLedgerRecord(input: ToolInput, output: ToolOutput): Promise<void> {
  const payload = buildLedgerPayload(input as ToolInput & { sessionID?: string }, output);
  if (!payload) return;
  try {
    const { spawnSync } = await import("node:child_process");
    spawnSync(bashExecutable(), [workspaceRoot() + "/scripts/edit-ledger.sh", "record"], {
      input: payload,
      encoding: "utf8",
      timeout: 3000,
    });
  } catch {
    // Non-blocking by design.
  }
}
