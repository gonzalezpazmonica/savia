/**
 * CLI `soul` de Soul Continuidad v1 (SE-490).
 *
 * Órdenes: status · q1…q4 · why <id> · correct <id> <resuelto|no-aplica|mio|no-mio> ·
 * mode <MODO> [--for 2h|--until ISO] · adapters · revoke <adaptador> · export [--out f] ·
 * uninstall [--yes] · stop [motivo] · resume · autostart install|uninstall [--dry-run] · bench · serve
 *
 * AC-4d: si la invoca un frontend de agente (Claude Code, OpenCode u otro, por variable de
 * entorno o `--frontend`), las respuestas son de nivel `recuentos` salvo un proveedor aprobado
 * para N4 en la configuración local; cada llamada así queda en `audit.jsonl` (solo recuentos).
 * Por esa ruta no se exporta, no se desinstala, no se revoca y no se corrige.
 *
 * Códigos de salida: 0 bien · 1 error · 2 uso · 3 sin perfil · 4 rechazado al frontend · 5 detenido.
 */

import { existsSync, readdirSync } from "node:fs";
import { join } from "node:path";
import type { Answer, Detail, QuestionId, SourceEnv } from "../contract/adapter.ts";
import { type Snapshot, iso, parseTs } from "../contract/claims.ts";
import {
  type Caller, ConfigError, NoProfileError, RANK, activeProfileName, agentLevel, elementId, loadConfig, resolveInstall,
  saveConfig,
} from "../core/config.ts";
import { type AdapterRegistry, makeEngine } from "../core/engine.ts";
import { StoppedError, resume, stop, stopState } from "../core/failsafe.ts";
import { appendJsonl, filesUnder, operatorDir, readJson, readJsonl, removeTree, writeJson } from "../core/store.ts";
import { autostartPlan, installAutostart, uninstallAutostart } from "../startup/autostart.ts";
import { ensureInstallCert } from "../api/cert.ts";
import { listDevices, pairDevice, revokeDevice } from "../api/devices.ts";
import { validateListen } from "../api/listen.ts";
import type { Run } from "../credentials/store.ts";

export interface CliDeps {
  dataDir: string;
  env: Record<string, string | undefined>;
  now: () => string;
  out: (s: string) => void;
  err: (s: string) => void;
  adapters: AdapterRegistry;
  sourceEnv: SourceEnv;
  credentials: { forget(service: string): Promise<string[]>; forgetAll(): Promise<string[]> };
  platform: NodeJS.Platform;
  home: string;
  run: Run;
  node: string;
  entry: string;
  serve?: (deps: CliDeps) => Promise<number>;
}

export const MODES = ["DISPONIBLE", "FOCO", "DESCANSO", "FUERA"] as const;
const CORRECTIONS: Record<string, string> = { resuelto: "resuelto", "no-aplica": "no_aplica", mio: "es_mio", "no-mio": "no_es_mio" };
const AGENT_ALLOWED = new Set(["status", "q1", "q2", "q3", "q4", "why", "adapters", "stop", "bench", "help"]);

const HELP = `Órdenes de soul (sin texto libre):
  status                         estado sin red: perfil, STOP, última lectura
  q1 | q2 | q4 [--cached]        qué tengo abierto · qué depende de mí · compromisos con fecha
  q3 --since <ISO>               qué cambió desde ese instante
  why <id>                       ¿por qué lo sé? fuente y antigüedad
  correct <id> resuelto|no-aplica|mio|no-mio
  mode DISPONIBLE | FOCO|DESCANSO|FUERA (--for 2h | --until <ISO>)
  adapters                       estado de cada fuente
  revoke <adaptador>             retira el consentimiento, borra su caché y su credencial
  export [--out <fichero>]       todo el estado local en JSON
  uninstall --yes                borra todo el estado, las credenciales y el arranque
  stop [motivo] | resume         fail-safe durable
  autostart install|uninstall [--dry-run]
  bench                          banco de continuidad contra este núcleo
  serve                          API local para la app (solo en las direcciones configuradas)
  pair <nombre> | unpair <id> | devices   dispositivos emparejados con la app
Opciones: --json · --frontend <nombre> · --provider <id>`;

interface Parsed { cmd: string; args: string[]; flags: Record<string, string | true> }

function parse(argv: string[]): Parsed {
  const args: string[] = [];
  const flags: Record<string, string | true> = {};
  const withValue = new Set(["--since", "--for", "--until", "--out", "--frontend", "--provider"]);
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (withValue.has(a)) flags[a.slice(2)] = argv[++i] ?? "";
    else if (a.startsWith("--")) flags[a.slice(2)] = true;
    else args.push(a);
  }
  return { cmd: args[0] ?? "help", args: args.slice(1), flags };
}

/** Frontend de agente que invoca la CLI. Fail-closed: cualquier señal cuenta. */
export function detectCaller(env: Record<string, string | undefined>, flags: Record<string, string | true>): Caller {
  const provider = (typeof flags.provider === "string" ? flags.provider : env.SOUL_AGENT_PROVIDER) || null;
  if (typeof flags.frontend === "string" && flags.frontend) return { frontend: flags.frontend, provider };
  if (env.SOUL_AGENT_FRONTEND) return { frontend: env.SOUL_AGENT_FRONTEND, provider };
  if (env.CLAUDECODE || env.CLAUDE_CODE_ENTRYPOINT) return { frontend: "claude-code", provider };
  if (env.OPENCODE || env.OPENCODE_BIN_PATH || env.OPENCODE_SESSION) return { frontend: "opencode", provider };
  return { frontend: null, provider: null };
}

class Exit extends Error {
  readonly code: number;
  constructor(code: number, msg: string) { super(msg); this.code = code; }
}

function parseDuration(s: string): number | null {
  const m = /^(\d{1,4})([mh])$/.exec(s);
  if (!m) return null;
  const ms = Number(m[1]) * (m[2] === "h" ? 3_600_000 : 60_000);
  return ms > 0 && ms <= 7 * 86_400_000 ? ms : null;
}

export async function runCli(argv: string[], deps: CliDeps): Promise<number> {
  const p = parse(argv);
  const json = p.flags.json === true;
  const caller = detectCaller(deps.env, p.flags);
  const print = (human: string, data: unknown) => deps.out(json ? JSON.stringify(data, null, 1) : human);
  const engine = makeEngine(deps.adapters);
  try {
    if (caller.frontend && !AGENT_ALLOWED.has(p.cmd)) {
      throw new Exit(4, `«${p.cmd}» no está disponible desde un frontend de agente (${caller.frontend}). Hazlo en tu terminal.`);
    }
    const cfg = loadConfig(deps.dataDir);
    const level = () => agentLevel(cfg, caller, cfg.detail.level);
    const audit = (cmd: string, lv: { level: Detail; forced: boolean; provider: string | null }, total: number) => {
      if (caller.frontend) appendJsonl(join(deps.dataDir, "audit.jsonl"), { at: deps.now(), frontend: caller.frontend, provider: lv.provider, level: lv.level, forced: lv.forced, cmd, total });
    };

    switch (p.cmd) {
      case "help":
        deps.out(HELP);
        return 0;

      case "status": {
        const st = stopState(deps.dataDir);
        let profile: string | null = null;
        try { profile = activeProfileName(cfg, deps.env); } catch { profile = null; }
        const last = profile ? engine.lastSnapshot(deps.dataDir, cfg.profiles[profile].operator.ref) : null;
        const data = {
          installation: cfg.installation_id, profile, stopped: st.stopped, stop_reason: st.reason ?? null,
          detail: level().level, last_read: last?.issued_at ?? null,
          expired: last ? (parseTs(last.expires_at) ?? 0) <= (parseTs(deps.now()) ?? 0) : null,
          sources: profile ? cfg.profiles[profile].sources.length : 0,
        };
        print([
          `Instalación ${data.installation} · perfil ${profile ?? "ninguno (no sé quién eres)"}`,
          st.stopped ? `DETENIDO${st.reason ? `: ${st.reason}` : ""} — «soul resume» para reanudar` : "En marcha",
          `Nivel ${data.detail} · fuentes ${data.sources} · última lectura ${data.last_read ?? "nunca"}${data.expired ? " (caducada)" : ""}`,
        ].join("\n"), data);
        return 0;
      }

      case "q1": case "q2": case "q3": case "q4": case "adapters": {
        const install = resolveInstall(cfg, deps.env);
        const now = deps.now();
        const st = stopState(deps.dataDir);
        if (st.stopped) throw new StoppedError(st);
        let snap: Snapshot;
        let stale = false;
        const cached = engine.lastSnapshot(deps.dataDir, install.operator.ref);
        const fresh = cached !== null && (parseTs(cached.expires_at) ?? 0) > (parseTs(now) ?? 0);
        if (p.flags.cached === true && cached && fresh) snap = engine.applyCorrections(cached, deps.dataDir, now);
        else {
          try {
            snap = await engine.snapshot({ install, now, stateDir: deps.dataDir, env: deps.sourceEnv });
          } catch (e) {
            // Sin conexión: lo último conocido, marcado como tal. Nunca datos caducados.
            if (e instanceof StoppedError || !cached || !fresh) throw e;
            snap = engine.applyCorrections(cached, deps.dataDir, now);
            stale = true;
          }
        }
        const lv = level();
        if (p.cmd === "adapters") {
          const adapters = Object.fromEntries(Object.entries(snap.adapters).filter(([, v]) => v.status !== "not_configured")
            .map(([k, v]) => [k, { status: v.status, route: v.route ?? null, claims: v.claims ?? 0, message: v.message ?? null, fallback: v.fallback ?? null }]));
          audit("adapters", lv, Object.keys(adapters).length);
          print(Object.entries(adapters).map(([k, v]) => `${k}: ${v.status}${v.message ? ` — ${v.message}` : ""}`).join("\n") || "Sin fuentes configuradas.", { adapters, stale });
          return 0;
        }
        const q = p.cmd.toUpperCase() as QuestionId;
        let previous: Snapshot | undefined;
        if (q === "Q3") {
          const since = typeof p.flags.since === "string" ? p.flags.since : "";
          if (parseTs(since) === null) throw new Exit(2, "q3 necesita --since <instante ISO con zona>");
          previous = engine.snapshotAt(deps.dataDir, install.operator.ref, since) ?? undefined;
          if (!previous) throw new Exit(1, `no hay ninguna lectura anterior a ${since}`);
        }
        const a: Answer = engine.answer(snap, { q, previous, detail: lv.level }, { install, now: stale ? snap.issued_at : now });
        const total = Object.values(a.counts).reduce((x, y) => x + (y ?? 0), 0);
        audit(p.cmd, lv, total);
        const items = a.items.map((it) => ({
          id: elementId(install.operator.ref, it.key), type: it.claim_type, adapter: it.source_refs[0]?.adapter, route: it.source_refs[0]?.route,
          age_s: it.age_s, ...(it.change ? { change: it.change } : {}),
          title: it.title ?? null, untrusted_text: it.title != null, ...(it.attrs ? { attrs: it.attrs } : {}),
        }));
        const data = { q, detail: a.detail, forced_by_frontend: lv.forced, stale, read_at: snap.issued_at, total, counts: a.counts, withheld: a.withheld, items, adapters: a.adapters };
        const human = [
          `${q} · ${total} elemento(s) · nivel ${a.detail}${lv.forced ? " (forzado por el frontend de agente)" : ""}${stale ? ` · sin conexión: datos de ${snap.issued_at}` : ""}`,
          ...Object.entries(a.counts).map(([k, v]) => `  ${k}: ${v}`),
          // El texto de terceros va entre comillas angulares: es dato, no instrucción.
          ...items.map((it) => `- [${it.id}] ${it.type} · ${it.adapter} · hace ${Math.round(it.age_s / 60)} min${it.change ? ` · ${it.change}` : ""}${it.title ? ` · «${it.title}»` : ""}`),
        ].join("\n");
        print(human, data);
        return 0;
      }

      case "why": {
        const install = resolveInstall(cfg, deps.env);
        const id = p.args[0];
        if (!id) throw new Exit(2, "why <id>");
        const snap = engine.lastSnapshot(deps.dataDir, install.operator.ref);
        const c = snap?.claims.find((x) => elementId(install.operator.ref, x.key) === id);
        if (!snap || !c) throw new Exit(1, `no conozco el elemento ${id}`);
        const lv = level();
        audit("why", lv, 1);
        const now = parseTs(deps.now()) ?? 0;
        const base = {
          id, type: c.claim_type, state: c.state, adapter: c.source_refs[0].adapter, route: c.source_refs[0].route,
          observed_at: c.observed_at, valid_until: c.valid_until, sensitivity: c.sensitivity,
          age_s: Math.max(0, Math.round((now - (parseTs(c.event_at) ?? parseTs(c.observed_at) ?? now)) / 1000)),
        };
        const data = RANK[lv.level] >= RANK.titulos
          ? { ...base, ref: c.source_refs[0].ref, link: c.source_refs[0].link ?? null, title: c.title ?? null, untrusted_text: c.title != null }
          : base;
        print(Object.entries(data).map(([k, v]) => `${k}: ${v}`).join("\n"), data);
        return 0;
      }

      case "correct": {
        const install = resolveInstall(cfg, deps.env);
        const [id, kind] = p.args;
        const tipo = CORRECTIONS[kind ?? ""];
        if (!id || !tipo) throw new Exit(2, "correct <id> resuelto|no-aplica|mio|no-mio");
        const snap = engine.lastSnapshot(deps.dataDir, install.operator.ref);
        const c = snap?.claims.find((x) => elementId(install.operator.ref, x.key) === id);
        if (!c) throw new Exit(1, `no conozco el elemento ${id}`);
        await engine.correct({ install, stateDir: deps.dataDir, now: deps.now(), key: c.key, action: tipo === "es_mio" ? "restore" : "revoke", reason: tipo });
        print(`Anotado: ${id} ${kind}. No volverá aunque la fuente lo repita.`, { id, tipo, aplicada: true, registrada_en: deps.now() });
        return 0;
      }

      case "mode": {
        const install = resolveInstall(cfg, deps.env);
        const modo = (p.args[0] ?? "").toUpperCase();
        if (!(MODES as readonly string[]).includes(modo)) throw new Exit(2, `mode ${MODES.join("|")}`);
        const now = parseTs(deps.now()) as number;
        let hasta: string | null = null;
        if (modo !== "DISPONIBLE") {
          const d = typeof p.flags.for === "string" ? parseDuration(p.flags.for) : null;
          const u = typeof p.flags.until === "string" ? parseTs(p.flags.until) : null;
          const t = d !== null ? now + d : u;
          if (t === null || t <= now || t > now + 7 * 86_400_000) throw new Exit(2, "el modo necesita ventana: --for 2h o --until <ISO> (máximo 7 días)");
          hasta = iso(t);
        }
        const data = { modo, hasta, vuelve_a: "DISPONIBLE" };
        writeJson(join(operatorDir(deps.dataDir, install.operator.ref), "attention.json"), { ...data, at: deps.now() });
        print(`Modo ${modo}${hasta ? ` hasta ${hasta}` : ""}.`, data);
        return 0;
      }

      case "revoke": {
        const name = activeProfileName(cfg, deps.env);
        const adapter = p.args[0];
        const src = cfg.profiles[name].sources.filter((s) => s.adapter === adapter);
        if (!adapter || !src.length) throw new Exit(1, `el adaptador ${adapter ?? ""} no está configurado en este perfil`);
        for (const s of src) s.consent = { ...s.consent, revoked_at: deps.now() };
        saveConfig(deps.dataDir, cfg);
        const purged = engine.purgeAdapter(deps.dataDir, cfg.profiles[name].operator.ref, adapter);
        const creds = await deps.credentials.forget(adapter);
        print(`Revocado ${adapter}: consentimiento retirado, ${purged} fichero(s) de caché limpiados, credencial borrada.`, { adapter, purged, credentials: creds });
        return 0;
      }

      case "export": {
        const operators = Object.entries(cfg.profiles).map(([profile, pc]) => {
          const ref = pc.operator.ref;
          const dir = operatorDir(deps.dataDir, ref);
          return {
            profile, operator_ref: ref, ledger: readJsonl(join(dir, "ledger.jsonl")), snapshot: engine.lastSnapshot(deps.dataDir, ref),
            history: existsSync(join(dir, "history")) ? readdirSync(join(dir, "history")).sort() : [],
            attention: readJson(join(dir, "attention.json"), null),
          };
        });
        const data = { schema: "se490/export/v1", exported_at: deps.now(), config: cfg, operators, failsafe: readJsonl(join(deps.dataDir, "failsafe.jsonl")), audit: readJsonl(join(deps.dataDir, "audit.jsonl")) };
        if (typeof p.flags.out === "string") {
          writeJson(p.flags.out, data);
          deps.out(`Exportado a ${p.flags.out}`);
        } else deps.out(JSON.stringify(data, null, 1));
        return 0;
      }

      case "uninstall": {
        const o = { platform: deps.platform, home: deps.home, env: deps.env, node: deps.node, entry: deps.entry };
        if (p.flags.yes !== true) {
          deps.err([
            "Desinstalar borra todo el estado local y las credenciales de Soul. Repite con --yes para hacerlo:",
            `  - directorio de datos: ${deps.dataDir} (${filesUnder(deps.dataDir).length} ficheros)`,
            ...autostartPlan(o).files.map((f) => `  - arranque automático: ${f.path}`),
            "  - credenciales de Soul en el almacén del sistema",
          ].join("\n"));
          return 2;
        }
        const creds = await deps.credentials.forgetAll();
        const auto = await uninstallAutostart(o, deps.run);
        removeTree(deps.dataDir);
        const left = existsSync(deps.dataDir);
        print(left ? "No se pudo borrar todo el directorio de datos." : "Desinstalado: no queda estado de Soul.", { removed: !left, credentials: creds.length, autostart: auto.message });
        return left ? 1 : 0;
      }

      case "stop": {
        const s = stop(deps.dataDir, p.args.join(" ") || "lo pide el operador", deps.now());
        print("Detenido. No se leerá ninguna fuente hasta «soul resume», también tras reiniciar.", s);
        return 0;
      }

      case "resume": {
        const s = resume(deps.dataDir, deps.now());
        print("Reanudado.", s);
        return 0;
      }

      case "autostart": {
        const o = { platform: deps.platform, home: deps.home, env: deps.env, node: deps.node, entry: deps.entry };
        const dry = p.flags["dry-run"] === true;
        const r = p.args[0] === "install" ? await installAutostart(o, deps.run, { dryRun: dry })
          : p.args[0] === "uninstall" ? await uninstallAutostart(o, deps.run, { dryRun: dry }) : null;
        if (!r) throw new Exit(2, "autostart install|uninstall [--dry-run]");
        print([r.message, ...r.planned.map((x) => `  ${x}`)].join("\n"), r);
        return r.ok ? 0 : 1;
      }

      case "bench": {
        const { runBench } = await import("../../bench/src/runner.ts");
        const { default: impl } = await import("../core/bench-impl.ts");
        const r = await runBench(impl());
        print([`Banco SE-490 — ${r.impl}: ${r.gate.pass ? "PASS" : "FAIL"}`, ...r.gate.failures.map((f) => `  ${f}`),
          ...Object.entries(r.metrics.per_question).map(([q, v]) => `  ${q}: ${(v.precision * 100).toFixed(1)} %`)].join("\n"), { gate: r.gate, metrics: r.metrics });
        return r.gate.pass ? 0 : 1;
      }

      case "pair": {
        const name = activeProfileName(cfg, deps.env);
        if (!p.args[0]) throw new Exit(2, "pair <nombre del dispositivo>");
        const listen = validateListen(cfg.api.listen);
        const tls = ensureInstallCert(deps.dataDir, listen);
        const d = pairDevice(deps.dataDir, cfg.profiles[name].operator.ref, p.args[0], deps.now());
        const direcciones = listen.map((a) => `${a.includes(":") ? `[${a}]` : a}:${cfg.api.port}`);
        print([
          `Emparejado «${p.args[0]}» (${d.id}). Introduce en la app, solo esta vez:`,
          `  token: ${d.token}`, `  huella: ${tls.pin}`, `  dirección: ${direcciones.join(", ")}`,
          "El token no se vuelve a mostrar; si se pierde, desempareja y vuelve a emparejar.",
        ].join("\n"), { id: d.id, token: d.token, pin: tls.pin, direcciones });
        return 0;
      }

      case "unpair": {
        if (!p.args[0]) throw new Exit(2, "unpair <id>");
        if (!revokeDevice(deps.dataDir, p.args[0], deps.now())) throw new Exit(1, `no hay ningún dispositivo ${p.args[0]}`);
        print(`Desemparejado ${p.args[0]}: su token deja de valer.`, { id: p.args[0], revoked: true });
        return 0;
      }

      case "devices": {
        const devices = listDevices(deps.dataDir).map(({ token_sha256: _h, ...d }) => d);
        print(devices.map((d) => `${d.id} ${d.name}${d.revoked_at ? " (revocado)" : ""}`).join("\n") || "Sin dispositivos.", { devices });
        return 0;
      }

      case "serve":
        if (!deps.serve) throw new Exit(1, "la API local no está disponible en este punto de entrada");
        return await deps.serve(deps);

      default:
        deps.err(`No interpreto texto libre ni órdenes desconocidas.\n${HELP}`);
        return 2;
    }
  } catch (e) {
    if (e instanceof Exit) { deps.err(e.message); return e.code; }
    if (e instanceof NoProfileError) { deps.err(e.message); return 3; }
    if (e instanceof StoppedError) { deps.err(e.message); return 5; }
    if (e instanceof ConfigError) { deps.err(e.message); return 1; }
    deps.err(`error: ${(e as Error).message}`);
    return 1;
  }
}
