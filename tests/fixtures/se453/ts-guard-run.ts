// ts-guard-run.ts — SE-453 S2 (DUAL_BINDING). Ejecuta un guard TypeScript de OpenCode con una orden bash
// y devuelve el mismo vocabulario que el hook bash equivalente: 2 si bloquea, 0 si deja pasar,
// 70 si el guard lanza algo que no es un bloqueo (mensaje sin «BLOCKED»).
// Uso: node --experimental-strip-types tests/fixtures/se453/ts-guard-run.ts <guard.ts> <exportName>
// La orden se lee de SAVIA_GUARD_CMD para no escribir literales sensibles en argv ni en ficheros.
import { pathToFileURL } from "node:url";
import { resolve } from "node:path";

const [guardPath, exportName] = process.argv.slice(2);
const command = process.env.SAVIA_GUARD_CMD ?? "";
if (!guardPath || !exportName) {
  console.error("uso: ts-guard-run.ts <guard.ts> <exportName>");
  process.exit(64);
}

// Sin top-level await: node < 22.7 trata un .ts sin "type": "module" como CommonJS (SE-453).
(async () => {
  const mod = await import(pathToFileURL(resolve(guardPath)).href);
  const guard = mod[exportName];
  if (typeof guard !== "function") {
    console.error(`ts-guard-run: ${exportName} no es una función en ${guardPath}`);
    process.exit(64);
  }
  const args = { command };
  try {
    await guard({ tool: "bash", args }, { args });
    process.exit(0);
  } catch (e) {
    const msg = String((e as Error)?.message ?? e);
    console.error(msg);
    // Solo un bloqueo deliberado cuenta como 2; un guard roto (TypeError…) no puede pasar por bloqueo.
    process.exit(/^BLOCKED/.test(msg) ? 2 : 70);
  }
})();
