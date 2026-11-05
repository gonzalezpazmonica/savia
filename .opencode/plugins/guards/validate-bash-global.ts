// validate-bash-global.ts — SPEC-127 Slice 2b-ii
//
// Port of `.opencode/hooks/validate-bash-global.sh`. Blocks dangerous Bash
// commands: rm -rf /, chmod 777, curl | bash, sudo, gh pr review/merge
// with auto-approve flags.
//
// Note: the bash original also blocks `git commit/add` on `main` for the
// savia/pm-workspace repo. Detecting current branch from inside a TS
// plugin requires `$` shell access. To keep the port pure (no side
// effects), the branch-check is intentionally OMITTED here and remains
// covered by the bash hook under Claude Code. Under OpenCode, branch
// protection should rely on git pre-commit (TIER-2 reroute).
//
// Reference: SPEC-127 Slice 2b-ii AC-2.2

import { extractToolName, extractCommand, type ToolInput, type ToolOutput } from "../lib/hook-input.ts";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const RULES: Array<{ rx: RegExp; msg: string }> = [
  {
    rx: /rm[\s]+-rf[\s]+\//i,
    msg: "rm -rf with root path. Potentially destructive.",
  },
  {
    rx: /chmod[\s]+777/i,
    msg: "chmod 777 is insecure. Use more restrictive permissions.",
  },
  {
    rx: /curl[\s]+.*\|\s*(ba)?sh/i,
    msg: "curl | bash is insecure. Download first, review, then execute.",
  },
  {
    rx: /gh[\s]+pr[\s]+review.*--approve/i,
    msg: "Cannot self-approve PR. Assign reviewer or use branch protection.",
  },
  {
    rx: /gh[\s]+pr[\s]+merge.*--admin/i,
    msg: "--admin bypasses branch protection. Requires human review.",
  },
  {
    // Al inicio de cualquier orden: tras separador o subshell, y con prefijos (VAR=valor, env…).
    rx: /(^|[;&|(`]|\$\()\s*(([A-Za-z_][A-Za-z0-9_]*=\S*|env|command|nohup|time|exec)\s+)*sudo(\s|$)/i,
    msg: "sudo not permitted from agents. Request elevation from operator.",
  },
];

const STRIPPER = fileURLToPath(new URL("../../../scripts/lib/strip_inert_heredocs.py", import.meta.url));

/**
 * La orden sin el TEXTO de los heredocs que solo escriben un fichero
 * (`cat > f <<'EOF' … EOF`): ese texto no se ejecuta. Lo decide
 * `scripts/lib/strip_inert_heredocs.py` (lista cerrada; ante la duda no quita
 * nada). El hook bash validate-bash-global.sh aún no lo usa: allí el texto del
 * heredoc sigue bloqueando. Sin Python o ante un fallo: la orden intacta (fail-closed).
 */
export function withoutInertHeredocs(command: string): string {
  if (!command.includes("<<")) return command;
  const res = spawnSync("python3", [STRIPPER], { encoding: "utf8", timeout: 3000, input: command });
  return res.status === 0 && !res.error && typeof res.stdout === "string" ? res.stdout : command;
}

export async function validateBashGlobal(input: ToolInput, output: ToolOutput): Promise<void> {
  if (extractToolName(input) !== "bash") return;
  const raw = extractCommand(input, output);
  if (!raw) return;
  const command = withoutInertHeredocs(raw);
  for (const r of RULES) {
    if (r.rx.test(command)) {
      throw new Error(`BLOCKED [validate-bash-global]: ${r.msg}`);
    }
  }
}
