/**
 * `soul serve`: la API local para la app, sobre el núcleo (SE-490).
 *
 * - Escucha solo en `api.listen` (las IP de la VPN del operador); sin direcciones no arranca.
 * - TLS con el certificado propio de la instalación; muestra la huella SPKI para fijarlo.
 * - Autentica dispositivos emparejados (`soul pair`); revocado => 401 DEVICE_REVOKED.
 * - Relee las fuentes al arrancar y cada 5 min; con STOP no lee nada y la API da 503.
 */

import { loadConfig, resolveInstall } from "../core/config.ts";
import { makeEngine } from "../core/engine.ts";
import { stopState } from "../core/failsafe.ts";
import type { CliDeps } from "../cli/cli.ts";
import { ensureInstallCert } from "./cert.ts";
import { coreWorld } from "./core-world.ts";
import { verifyToken } from "./devices.ts";
import { validateListen } from "./listen.ts";
import { crearServidor } from "./server.ts";

export const REFRESH_MS = 5 * 60_000;

export async function serveFromCli(deps: CliDeps, opts: { signal?: AbortSignal; onListening?: () => void } = {}): Promise<number> {
  let listen: string[];
  const cfg = loadConfig(deps.dataDir);
  try {
    listen = validateListen(cfg.api.listen);
  } catch (e) {
    deps.err((e as Error).message);
    return 1;
  }
  const engine = makeEngine(deps.adapters);
  const tls = ensureInstallCert(deps.dataDir, listen);
  const world = coreWorld({ cfg, engine, stateDir: deps.dataDir });

  const refresh = async () => {
    if (stopState(deps.dataDir).stopped) return;
    for (const name of Object.keys(cfg.profiles)) {
      try {
        const install = resolveInstall(cfg, { SOUL_PROFILE: name });
        await engine.snapshot({ install, now: deps.now(), stateDir: deps.dataDir, env: deps.sourceEnv });
      } catch (e) {
        deps.err(`lectura fallida (${(e as Error).name})`); // sin datos de trabajo en el log
      }
    }
  };
  await refresh();

  const server = crearServidor({
    tls, mundo: world, reloj: () => Date.now(),
    autenticar: (token) => {
      const v = verifyToken(deps.dataDir, token);
      return v ? { ref: v.operator_ref, revocado: v.revoked } : null;
    },
    detenido: () => stopState(deps.dataDir).stopped,
  });
  world.conectar(server);
  const l = await server.escuchar(listen, cfg.api.port);
  deps.out(`Escuchando en ${l.addresses.map((a) => `${a.address.includes(":") ? `[${a.address}]` : a.address}:${a.port}`).join(", ")} (TLS)`);
  deps.out(`Huella del certificado para emparejar: ${tls.pin}`);
  opts.onListening?.();

  const timer = setInterval(() => { void refresh(); }, REFRESH_MS);
  await new Promise<void>((resolve) => {
    const end = () => resolve();
    if (opts.signal) {
      if (opts.signal.aborted) end();
      else opts.signal.addEventListener("abort", end, { once: true });
    } else {
      process.once("SIGINT", end);
      process.once("SIGTERM", end);
    }
  });
  clearInterval(timer);
  await server.cerrar();
  return 0;
}
