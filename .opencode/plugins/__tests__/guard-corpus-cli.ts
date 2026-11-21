// guard-corpus-cli.ts — SE-510 AC-7: veredicto de los guards TS para cada caso del corpus.
//
// Entrada (stdin): JSON [{id, tool, command, cwd}]. Salida: una línea JSON por caso
// {id, decision: ALLOW|BLOCK, guard, reason}. Corre BEFORE_GUARDS (lib/before-guards.ts, la lista de savia-foundation.ts)
// por el mismo camino que OpenCode (runGuardsOnVariants), con `workdir` y el directorio
// de proceso en el `cwd` del caso, como hace el despachador bash con sus hooks.
// `--entry <módulo>` usa otro módulo que exporte BEFORE_GUARDS (el test de mutación
// lo usa para comprobar que un guard desviado hace fallar la paridad).
import { pathToFileURL } from "node:url";
import { resolve } from "node:path";
import { runGuardsOnVariants } from "../lib/sandbox.ts";
import { guardNameOf } from "../lib/guard-blocks.ts";

const i = process.argv.indexOf("--entry");
const entry = i > 0 ? pathToFileURL(resolve(process.argv[i + 1])).href : "../lib/before-guards.ts";
const mod: any = await import(entry);
const guards = mod.BEFORE_GUARDS;
if (!Array.isArray(guards) || guards.length === 0) {
  process.stderr.write(`guard-corpus-cli: ${entry} no exporta BEFORE_GUARDS\n`);
  process.exit(2);
}

const jobs = JSON.parse(await new Response(Bun.stdin.stream()).text());
const home = process.cwd();
for (const job of jobs) {
  const args = { command: job.command, workdir: job.cwd };
  const input = { tool: String(job.tool).toLowerCase(), args: { ...args } };
  const output = { args: { ...args } };
  let row: Record<string, string> = { id: job.id, decision: "ALLOW", guard: "", reason: "" };
  process.chdir(job.cwd);
  try {
    await runGuardsOnVariants(guards, input, output);
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    row = { id: job.id, decision: "BLOCK", guard: guardNameOf(message), reason: message.split("\n")[0].slice(0, 200) };
  } finally {
    process.chdir(home);
  }
  process.stdout.write(JSON.stringify(row) + "\n");
}
