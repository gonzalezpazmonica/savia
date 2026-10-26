// bash-runtime.ts — bash used by guards that delegate to workspace .sh scripts.
//
// On Windows a bare "bash" resolves first to the WSL launcher
// (C:\Windows\System32\bash.exe), which cannot run C:\ script paths and does not
// see the Windows environment; Git for Windows bash can. Resolution order:
// SAVIA_BASH, CLAUDE_CODE_GIT_BASH_PATH (the bash Claude Code runs hooks with),
// the standard Git for Windows locations, then "bash" as a last resort.
import { existsSync } from "node:fs";
import { win32 } from "node:path";

export function bashExecutable(
  env: NodeJS.ProcessEnv = process.env,
  platform: string = process.platform,
  exists: (p: string) => boolean = existsSync,
): string {
  if (env.SAVIA_BASH) return env.SAVIA_BASH;
  if (platform !== "win32") return "bash";
  if (env.CLAUDE_CODE_GIT_BASH_PATH && exists(env.CLAUDE_CODE_GIT_BASH_PATH)) {
    return env.CLAUDE_CODE_GIT_BASH_PATH;
  }
  const roots = [
    env.ProgramFiles,
    env["ProgramFiles(x86)"],
    env.LOCALAPPDATA && win32.join(env.LOCALAPPDATA, "Programs"),
  ];
  for (const root of roots) {
    if (!root) continue;
    const candidate = win32.join(root, "Git", "bin", "bash.exe");
    if (exists(candidate)) return candidate;
  }
  return "bash";
}
