/**
 * `soul serve`: la API local para la app, sobre el núcleo (SE-490).
 *
 * - Escucha solo en `api.listen` (las IP de la VPN del operador); sin direcciones no arranca.
 * - TLS con el certificado propio de la instalación; muestra la huella SPKI para fijarlo.
 * - Emparejamiento directo por código (`soul pair` abre la ventana; `/v1/pair/*`, ver pairing.ts):
 *   el dispositivo queda ligado a su clave al emparejar.
 * - Autentica dispositivos emparejados; revocado => 401 DEVICE_REVOKED. Exige una prueba DPoP
 *   válida con la clave ligada; token caducado => 401.
 * - Estado de atención por operador en disco (`attention-state.json`): modo, avisos, alertas,
 *   pendientes, registro de demanda y mensajes del sondeo sobreviven a un reinicio. `soul mode`
 *   (`attention.json`) se aplica en el siguiente tic.
 * - Relee las fuentes al arrancar y cada 5 min; con STOP no lee nada y la API da 503.
 */

import { loadConfig, resolveInstall } from "../core/config.ts";
import { makeEngine } from "../core/engine.ts";
import { stopState } from "../core/failsafe.ts";
import type { CliDeps } from "../cli/cli.ts";
import { ensureInstallCert } from "./cert.ts";
import { coreWorld } from "./core-world.ts";
import { createHash } from "node:crypto";
import { join } from "node:path";
import { operatorDir, readJson, writeJson } from "../core/store.ts";
import { bindKey, verifyToken } from "./devices.ts";
import { DpopError, makeDpopVerifier } from "./dpop.ts";
import { makePairing } from "./pairing.ts";
import { validateListen } from "./listen.ts";
import { type EstadoAtencion, crearServidor } from "./server.ts";

export const ATTENTION_STATE = "attention-state.json";

export const REFRESH_MS = 5 * 60_000;

export async function serveFromCli(deps: CliDeps, opts: { signal?: AbortSignal; onListening?: () => void; refreshMs?: number } = {}): Promise<number> {
  let listen: string[];
  const cfg = loadConfig(deps.dataDir);
  try {
    listen = validateListen(cfg.api.listen);
  } catch (e) {
    deps.err((e as Error).message);
    return 1;
  }
  const engine = makeEngine(deps.adaptersFor?.(cfg) ?? deps.adapters);
  const tls = ensureInstallCert(deps.dataDir, listen);
  const world = coreWorld({ cfg, engine, stateDir: deps.dataDir });

  const refresh = async () => {
    if (stopState(deps.dataDir).stopped) return;
    // La configuración se relee en cada lectura: un revoke o un consentimiento nuevo se aplican sin reiniciar.
    let now;
    try { now = loadConfig(deps.dataDir); } catch (e) { deps.err(`configuración ilegible; no se leen fuentes (${(e as Error).name})`); return; }
    for (const name of Object.keys(now.profiles)) {
      try {
        const install = resolveInstall(now, { SOUL_PROFILE: name });
        // Registro y entorno de la configuración recién leída: activar o quitar un adaptador no exige reiniciar.
        const reader = deps.adaptersFor ? makeEngine(deps.adaptersFor(now)) : engine;
        const env = deps.sourceEnvFor?.(install.operator.ref, now) ?? deps.sourceEnv;
        await reader.snapshot({ install, now: deps.now(), stateDir: deps.dataDir, env });
      } catch (e) {
        deps.err(`lectura fallida (${(e as Error).name})`); // sin datos de trabajo en el log
      }
    }
  };
  await refresh();

  const dpop = makeDpopVerifier();
  const server = crearServidor({
    tls, mundo: world, reloj: () => Date.now(),
    autenticar: (token, prueba) => {
      const v = verifyToken(deps.dataDir, token);
      if (!v) return null;
      if (v.revoked) return { ref: v.operator_ref, revocado: true };
      if (v.expired) return null;
      let jkt: string;
      try {
        jkt = dpop({ proof: prueba.proof, method: prueba.method, path: prueba.path, host: prueba.host, token, now: Date.now(), expectedJkt: v.jkt }).jkt;
      } catch (e) {
        if (e instanceof DpopError) return null;
        throw e;
      }
      if (!v.jkt && bindKey(deps.dataDir, v.device, jkt) !== jkt) return null;
      return { ref: v.operator_ref, revocado: false, dispositivo: v.device };
    },
    secretoCursor: createHash("sha256").update(`soul-cursor|${tls.key}`).digest("hex"),
    persistencia: {
      cargar: (ref) => readJson<EstadoAtencion | null>(join(operatorDir(deps.dataDir, ref), ATTENTION_STATE), null),
      guardar: (ref, e) => writeJson(join(operatorDir(deps.dataDir, ref), ATTENTION_STATE), e),
    },
    detenido: () => stopState(deps.dataDir).stopped,
    // Emparejamiento directo: la ventana la abre `soul pair` (pairing.json); aquí solo se consume.
    emparejamiento: makePairing({ dataDir: deps.dataDir, certPem: tls.cert }),
    // Una app sondea cada 5 min: 120 peticiones cada 10 s sobran y frenan un abuso.
    peticionesPorVentana: 120,
  });
  world.conectar(server);
  // `soul mode` deja el modo en attention.json: se aplica una vez por declaración (por su `at`, persistido).
  // Un attention.json sin «at» se avisa una vez por contenido, no en cada tic.
  const avisadoSinAt = new Map<string, string>();
  const modoDeCli = () => {
    let c;
    try { c = loadConfig(deps.dataDir); } catch { return; }
    for (const p of Object.values(c.profiles)) {
      const ref = p.operator?.ref;
      if (!ref) continue;
      type Declarado = { modo?: unknown; hasta?: unknown; at?: unknown };
      const a = (() => { try { return readJson<Declarado | null>(join(operatorDir(deps.dataDir, ref), "attention.json"), null); } catch { return null; } })();
      // Ya aplicada (también antes de un reinicio: el `at` se guarda con el estado): no pisa lo que fijó después la app.
      if (!a) continue;
      if (typeof a.at !== "string" || typeof a.modo !== "string") {
        const firma = JSON.stringify(a);
        if (avisadoSinAt.get(ref) !== firma) deps.err("attention.json sin modo o sin «at»: se ignora (vuelve a ejecutar soul mode)");
        avisadoSinAt.set(ref, firma);
        continue;
      }
      avisadoSinAt.delete(ref);
      if (server.declaracionCli(ref) === a.at) continue;
      // Sin operador en la API (perfil creado tras arrancar) no se marca: se reintenta en el siguiente tic.
      const r = server.declararModo(ref, a.modo, typeof a.hasta === "string" ? a.hasta : null, a.at);
      if (r === "invalida") deps.err("soul mode no aplicado: modo o ventana inválidos (vuelve a declararlo)");
    }
  };
  modoDeCli();
  const l = await server.escuchar(listen, cfg.api.port);
  deps.out(`Escuchando en ${l.addresses.map((a) => `${a.address.includes(":") ? `[${a.address}]` : a.address}:${a.port}`).join(", ")} (TLS)`);
  deps.out(`Huella del certificado para emparejar: ${tls.pin}`);
  opts.onListening?.();

  // Sin solapes: si una lectura tarda más que el intervalo, el siguiente tic se salta.
  let leyendo = false;
  const timer = setInterval(() => {
    if (leyendo) return;
    leyendo = true;
    void refresh().then(modoDeCli).finally(() => { leyendo = false; });
  }, opts.refreshMs ?? REFRESH_MS);
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
