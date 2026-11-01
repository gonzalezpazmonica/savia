// block-gitignored-references.ts — SPEC-127 Slice 2b-ii
//
// Port of `.opencode/hooks/block-gitignored-references.sh`. Scans the
// content of Edit/Write operations for references to gitignored paths or
// internal-only metrics. Skips when the target file IS itself a private
// destination (writing TO gitignored is fine) or a hook source file
// (self-reference legitimate).
//
// Project references follow rule 9 of the bash hook: allowed only when the name is whitelisted in
// .gitignore or authorized by the operator in .claude/.project-authorizations of the edited file's
// repo (fail-closed). See detectProjectLeakage.
//
// Reference: SPEC-127 Slice 2b-ii AC-2.2 (PV-02 critical safety hook)

import {
  extractToolName,
  extractFilePath,
  extractContent,
  type ToolInput,
  type ToolOutput,
} from "../lib/hook-input.ts";
import { detectLeakage, detectProjectLeakage } from "../lib/leakage-patterns.ts";

const PRIVATE_DESTINATIONS = [
  /\/projects\//,
  /^projects\//,
  /\.local\./,
  /\/output\//,
  /private-agent-memory/,
  /\/\.savia\//,
  /\/\.claude\/sessions\//,
  /settings\.local\.json/,
];

const SOURCE_SELF_REFS = [
  /\/tests\/test-/,
  /\/tests\/.*\.bats$/,
  /\/\.claude\/hooks\//,
  /\/\.opencode\/hooks\//,
  /\/scripts\/test-/,
  // The hook port itself is allowed to reference patterns in source/test
  /\/\.opencode\/plugins\/lib\/leakage-patterns/,
  /\/\.opencode\/plugins\/.*\.test\.ts$/,
  /\/\.opencode\/plugins\/block-gitignored-references/,
];

function isPrivateDestination(p: string): boolean {
  return PRIVATE_DESTINATIONS.some((rx) => rx.test(p));
}

function isSourceSelfRef(p: string): boolean {
  return SOURCE_SELF_REFS.some((rx) => rx.test(p));
}

export async function blockGitignoredReferences(input: ToolInput, output: ToolOutput): Promise<void> {
  const tool = extractToolName(input);
  if (tool !== "edit" && tool !== "write") return;

  const filePath = extractFilePath(input, output);
  if (!filePath) return;
  if (isPrivateDestination(filePath)) return;
  if (isSourceSelfRef(filePath)) return;

  const content = extractContent(input, output);
  if (!content) return;

  const projectDir = process.env.CLAUDE_PROJECT_DIR || process.cwd();
  const violations = [...detectLeakage(content), ...detectProjectLeakage(content, filePath, projectDir)];
  if (violations.length > 0) {
    const list = violations.map((v) => `  - ${v}`).join("\n");
    throw new Error(
      `BLOCKED [gitignored-references]: leak detected in ${filePath}:\n${list}\n` +
        `Use generic terms instead of internal paths/metrics. ` +
        `See: docs/rules/domain/zero-project-leakage.md`,
    );
  }
}
