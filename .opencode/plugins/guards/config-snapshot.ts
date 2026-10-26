// config-snapshot.ts — SE-405 Slice 2
//
// OpenCode binding of `.claude/hooks/config-snapshot-hook.sh`. Runs BEFORE an
// edit/write on a watched configuration file and saves a copy through
// `scripts/config-snapshot.sh snapshot`. Never blocks: failures are swallowed.
//
// Reference: docs/specs/SE-405-harness-observability-increments.spec.md

import {
  extractToolName,
  extractFilePath,
  type ToolInput,
  type ToolOutput,
} from "../lib/hook-input.ts";
import { bashExecutable } from "../lib/bash-runtime.ts";

export function isWatchedConfig(filePath: string, home: string): boolean {
  if (!filePath) return false;
  const p = filePath.replace(/\\/g, "/");
  return p.endsWith("/.claude/settings.json")
    || p.endsWith("/.claude/settings.local.json")
    || p.endsWith("/opencode.json")
    || p === `${home}/.savia/preferences.yaml`;
}

export async function configSnapshot(input: ToolInput, output: ToolOutput): Promise<void> {
  const tool = extractToolName(input);
  if (tool !== "edit" && tool !== "write") return;
  const filePath = extractFilePath(input, output);
  if (!isWatchedConfig(filePath, process.env.HOME ?? "")) return;
  try {
    const { existsSync } = await import("node:fs");
    if (!existsSync(filePath)) return;
    const { spawnSync } = await import("node:child_process");
    const root = process.env.SAVIA_WORKSPACE_DIR ?? process.cwd();
    spawnSync(bashExecutable(), [root + "/scripts/config-snapshot.sh", "snapshot", filePath], {
      encoding: "utf8",
      timeout: 3000,
    });
  } catch {
    // Non-blocking by design.
  }
}
