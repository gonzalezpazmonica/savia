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

import { existsSync, readdirSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import type { Answer, Detail, QuestionId, SourceEnv } from "../contract/adapter.ts";
import { type Snapshot, iso, parseTs } from "../contract/claims.ts";
import {
  type Caller, ConfigError, NoProfileError, RANK, type SoulConfig, activeProfileName, agentLevel, elementId, loadConfig, resolveInstall,
  saveConfig,
} from "../core/config.ts";
import { type AdapterRegistry, makeEngine } from "../core/engine.ts";
import { StoppedError, resume, stop, stopState } from "../core/failsafe.ts";
import { appendJsonl, filesUnder, operatorDir, readJson, readJsonl, removeSoulState, writeJson } from "../core/store.ts";
import { autostartPlan, installAutostart, uninstallAutostart } from "../startup/autostart.ts";
import { ensureInstallCert } from "../api/cert.ts";
import { listDevices, revokeDevice } from "../api/devices.ts";
import { closePairingWindow, openPairingWindow, pairLink, shortFingerprint } from "../api/pairing.ts";
import { encodeQr, qrToPng, qrToTerminal } from "../api/qr.ts";
import { validateListen } from "../api/listen.ts";
import type { Run } from "../credentials/store.ts";
import type { TokenSet } from "../adapters/oauth.ts";
import { randomBytes } from "node:crypto";
import { LoginUsage, PROFILE_NAME, initConfig, runLogin } from "./login.ts";

export interface CliDeps {
  dataDir: string;
  env: Record<string, string | undefined>;
  now: () => string;
  out: (s: string) => void;
  err: (s: string) => void;
  adapters: AdapterRegistry;
  /** Registro según la configuración (producción: solo los adaptadores que activó el operador). */
  adaptersFor?: (cfg: SoulConfig) => AdapterRegistry;
  sourceEnv: SourceEnv;
  /** Entorno de lectura de un operador: sus credenciales y el transporte de la configuración. */
  sourceEnvFor?: (operatorRef: string, cfg: SoulConfig) => SourceEnv;
  credentials: {
    /** AC-5: tokens y caché propia del adaptador (todas sus variantes de permisos). */
    revoke(adapter: string, operatorRef: string): Promise<{ tokens_removed: number; cache_removed: boolean }>;
    /** Todas las credenciales del índice del almacén único (desinstalar). */
    forgetAll(): Promise<string[]>;
  };
  /** Tokens de los adaptadores de API de un operador (almacén único). Necesario para `login`. */
  tokenStore?: (operatorRef: string, cfg: SoulConfig) => { put(service: string, scopes: string[], t: TokenSet): Promise<void> };
  /** Lee un secreto de stdin sin eco (solo `login --token-stdin`). */
  readSecret?: () => Promise<string>;
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
  init <perfil> [--email a@b]    crea la instalación: perfil sin fuentes ni adaptadores activos
  login <adaptador> [--token-stdin] [--days N]   inicia sesión (M365/Google: código; resto: token por stdin)
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
  pair [--days N] [--qr-png F] | unpair <id> [--undo] | devices   emparejar la app con clave y QR (10 min) y dispositivos
  corrections --device <id>      correcciones vigentes hechas desde ese dispositivo
  undo-device <id>               deshace las correcciones de ese dispositivo (móvil perdido)
Opciones: --json · --frontend <nombre>`;

interface Parsed { cmd: string; args: string[]; flags: Record<string, string | true> }

function parse(argv: string[]): Parsed {
  const args: string[] = [];
  const flags: Record<string, string | true> = {};
  const withValue = new Set(["--since", "--for", "--until", "--out", "--frontend", "--device", "--days", "--email", "--qr-png"]);
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (withValue.has(a)) flags[a.slice(2)] = argv[++i] ?? "";
    else if (a.startsWith("--")) flags[a.slice(2)] = true;
    else args.push(a);
  }
  return { cmd: args[0] ?? "help", args: args.slice(1), flags };
}

/**
 * Frontend de agente que invoca la CLI. Fail-closed: cualquier señal cuenta, y la detección por
 * entorno manda sobre `--frontend` (un agente no puede hacerse pasar por otro frontend).
 */
export function detectCaller(env: Record<string, string | undefined>, flags: Record<string, string | true>): Caller {
  if (env.CLAUDECODE || env.CLAUDE_CODE_ENTRYPOINT) return { frontend: "claude-code" };
  if (env.OPENCODE || env.OPENCODE_BIN_PATH || env.OPENCODE_SESSION) return { frontend: "opencode" };
  if (env.SOUL_AGENT_FRONTEND) return { frontend: env.SOUL_AGENT_FRONTEND };
  if (typeof flags.frontend === "string" && flags.frontend) return { frontend: flags.frontend };
  return { frontend: null };
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

/** Órdenes que no leen la configuración: si `config.json` está roto siguen funcionando. */
async function runWithoutConfig(p: Parsed, deps: CliDeps, print: (human: string, data: unknown) => void): Promise<number | null> {
  switch (p.cmd) {
    case "help":
      deps.out(HELP);
      return 0;

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
      const ajeno = removeSoulState(deps.dataDir);
      // removeSoulState lanza si no puede borrar algo propio (rmSync); eso acaba en exit 1 por el catch.
      const data = { removed: auto.ok, kept_foreign: ajeno.length, credentials: creds.length, autostart: auto.message, autostart_ok: auto.ok };
      if (!auto.ok) {
        // El estado ya no está, pero el arranque automático puede seguir relanzando `soul serve`.
        print(`Desinstalación incompleta: el arranque automático no se retiró del todo (${auto.message}).`, data);
        deps.err(`aviso: arranque automático sin retirar: ${auto.message}`);
        return 1;
      }
      print(ajeno.length
        ? `Desinstalado: no queda estado de Soul. Se conservan ${ajeno.length} elemento(s) ajenos en ${deps.dataDir}.`
        : "Desinstalado: no queda estado de Soul.", data);
      return 0;
    }

    case "init": {
      const name = p.args[0] ?? "";
      if (!PROFILE_NAME.test(name)) { deps.err("init <perfil> [--email a@b]: perfil en minúsculas, cifras, - y _"); return 2; }
      if (existsSync(join(deps.dataDir, "config.json"))) { deps.err(`ya hay una instalación en ${deps.dataDir}; no se pisa`); return 1; }
      const emails = typeof p.flags.email === "string" ? p.flags.email.split(",").map((e) => e.trim()).filter(Boolean) : [];
      const cfg = initConfig(name, emails, `inst-${randomBytes(6).toString("hex")}`);
      saveConfig(deps.dataDir, cfg);
      print(`Instalación creada en ${deps.dataDir} con el perfil «${name}». Ninguna fuente ni adaptador está activo: actívalos en config.json (ver docs/instalar.md).`,
        { data_dir: deps.dataDir, profile: name, operator_ref: cfg.profiles[name].operator.ref });
      return 0;
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

    default:
      return null;
  }
}

export async function runCli(argv: string[], deps: CliDeps): Promise<number> {
  const p = parse(argv);
  const caller = detectCaller(deps.env, p.flags);
  const audited = { done: false };
  const code = await dispatch(p, caller, deps, audited);
  // Toda llamada de un frontend de agente queda auditada, también status, stop, help, los rechazos
  // y los errores. La orden solo se anota si es una de las permitidas: nunca texto libre del agente.
  if (caller.frontend && !audited.done) {
    try {
      appendJsonl(join(deps.dataDir, "audit.jsonl"), {
        at: deps.now(), frontend: caller.frontend, provider: null, level: null, forced: null,
        cmd: AGENT_ALLOWED.has(p.cmd) ? p.cmd : "rechazada", total: null, exit: code,
      });
    } catch (e) {
      deps.err(`aviso: no se pudo registrar la auditoría (${(e as Error).name})`);
    }
  }
  return code;
}

async function dispatch(p: Parsed, caller: Caller, deps: CliDeps, audited: { done: boolean }): Promise<number> {
  const json = p.flags.json === true;
  const print = (human: string, data: unknown) => deps.out(json ? JSON.stringify(data, null, 1) : human);
  try {
    if (caller.frontend && !AGENT_ALLOWED.has(p.cmd)) {
      throw new Exit(4, `«${p.cmd}» no está disponible desde un frontend de agente (${caller.frontend}). Hazlo en tu terminal.`);
    }
    // El fail-safe, la ayuda y el borrado no dependen de que config.json sea válido.
    const early = await runWithoutConfig(p, deps, print);
    if (early !== null) return early;
    let cfg: SoulConfig;
    try { cfg = loadConfig(deps.dataDir); } catch (e) {
      if (p.cmd !== "status") throw e;
      // status responde siempre: con config.json ilegible dice eso y el estado del STOP, y sale con 1.
      const st = stopState(deps.dataDir);
      print([
        "Configuración ilegible (config.json): revísala o reinstala. Las preguntas no funcionarán hasta entonces.",
        st.stopped ? "DETENIDO — «soul resume» para reanudar" : "En marcha",
      ].join("\n"), { config_unreadable: true, error: (e as Error).name, stopped: st.stopped, stop_reason: caller.frontend ? null : st.reason ?? null });
      return 1;
    }
    const engine = makeEngine(deps.adaptersFor?.(cfg) ?? deps.adapters);
    const envFor = (ref: string) => deps.sourceEnvFor?.(ref, cfg) ?? deps.sourceEnv;
    const level = () => agentLevel(cfg, caller, cfg.detail.level);
    const audit = (cmd: string, lv: { level: Detail; forced: boolean; provider: string | null }, total: number) => {
      audited.done = true;
      if (caller.frontend) appendJsonl(join(deps.dataDir, "audit.jsonl"), { at: deps.now(), frontend: caller.frontend, provider: lv.provider, level: lv.level, forced: lv.forced, cmd, total });
    };

    switch (p.cmd) {
      case "status": {
        const st = stopState(deps.dataDir);
        let profile: string | null = null;
        try { profile = activeProfileName(cfg, deps.env); } catch { profile = null; }
        // status responde siempre: una caché ilegible o un perfil sin operador se dicen, no tumban la orden.
        let last: Snapshot | null = null;
        let unreadable = false;
        try { last = profile ? engine.lastSnapshot(deps.dataDir, cfg.profiles[profile].operator.ref) : null; } catch { unreadable = true; }
        const lv = level().level;
        const data = {
          installation: cfg.installation_id, profile, stopped: st.stopped,
          // El motivo del STOP es texto libre de la persona: no sale hacia un agente a nivel recuentos.
          stop_reason: caller.frontend && lv === "recuentos" ? null : st.reason ?? null,
          detail: lv, last_read: last?.issued_at ?? null, last_read_unreadable: unreadable,
          expired: last ? (parseTs(last.expires_at) ?? 0) <= (parseTs(deps.now()) ?? 0) : null,
          sources: profile ? cfg.profiles[profile].sources?.length ?? 0 : 0,
        };
        print([
          `Instalación ${data.installation} · perfil ${profile ?? "ninguno (no sé quién eres)"}`,
          st.stopped ? `DETENIDO${data.stop_reason ? `: ${data.stop_reason}` : ""} — «soul resume» para reanudar` : "En marcha",
          `Nivel ${data.detail} · fuentes ${data.sources} · última lectura ${unreadable ? "ilegible (se rehará en la próxima pregunta)" : data.last_read ?? "nunca"}${data.expired ? " (caducada)" : ""}`,
        ].join("\n"), data);
        return 0;
      }

      case "q1": case "q2": case "q3": case "q4": case "adapters": {
        // Uso incorrecto antes de tocar ninguna fuente.
        if (p.cmd === "q3" && parseTs(typeof p.flags.since === "string" ? p.flags.since : "") === null) throw new Exit(2, "q3 necesita --since <instante ISO con zona>");
        const install = resolveInstall(cfg, deps.env);
        const now = deps.now();
        const st = stopState(deps.dataDir);
        if (st.stopped) throw new StoppedError(st);
        // Por defecto se releen las fuentes. --cached usa la última lectura si sigue vigente,
        // con el libro de correcciones de ahora. Una fuente que no responde no aporta nada y se dice.
        const cached = p.flags.cached === true ? engine.cachedSnapshot(deps.dataDir, install.operator.ref, now) : null;
        const fresh = cached !== null && (parseTs(cached.expires_at) ?? 0) > (parseTs(now) ?? 0);
        const snap: Snapshot = cached && fresh ? cached : await engine.snapshot({ install, now, stateDir: deps.dataDir, env: envFor(install.operator.ref) });
        const unread = Object.entries(snap.adapters).filter(([, v]) => v.status !== "ok" && v.status !== "not_configured");
        const unreadLine = unread.length ? [`  ${unread.length} fuente(s) sin leer: ${unread.map(([k, v]) => `${k} (${v.status})`).join(", ")} — lo de ahí no está contado`] : [];
        const lv = level();
        if (p.cmd === "adapters") {
          const adapters = Object.fromEntries(Object.entries(snap.adapters).filter(([, v]) => v.status !== "not_configured")
            .map(([k, v]) => [k, { status: v.status, route: v.route ?? null, claims: v.claims ?? 0, message: v.message ?? null, fallback: v.fallback ?? null }]));
          audit("adapters", lv, Object.keys(adapters).length);
          print(Object.entries(adapters).map(([k, v]) => `${k}: ${v.status}${v.message ? ` — ${v.message}` : ""}`).join("\n") || "Sin fuentes configuradas.", { adapters });
          return 0;
        }
        const q = p.cmd.toUpperCase() as QuestionId;
        let previous: Snapshot | undefined;
        if (q === "Q3") {
          const since = p.flags.since as string; // validado arriba
          previous = engine.snapshotAt(deps.dataDir, install.operator.ref, since) ?? undefined;
          if (!previous) throw new Exit(1, `no hay ninguna lectura anterior a ${since}`);
        }
        const a: Answer = engine.answer(snap, { q, previous, detail: lv.level }, { install, now });
        const total = Object.values(a.counts).reduce((x, y) => x + (y ?? 0), 0);
        audit(p.cmd, lv, total);
        const items = a.items.map((it) => ({
          id: elementId(install.operator.ref, it.key), type: it.claim_type, adapter: it.source_refs[0]?.adapter, route: it.source_refs[0]?.route,
          age_s: it.age_s, ...(it.change ? { change: it.change } : {}),
          title: it.title ?? null, untrusted_text: it.title != null, ...(it.attrs ? { attrs: it.attrs } : {}),
        }));
        const data = { q, detail: a.detail, forced_by_frontend: lv.forced, read_at: snap.issued_at, unread_sources: unread.length, total, counts: a.counts, withheld: a.withheld, items, adapters: a.adapters };
        const human = [
          `${q} · ${total} elemento(s) · nivel ${a.detail}${lv.forced ? " (forzado por el frontend de agente)" : ""}`,
          ...unreadLine,
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
        const snap = engine.cachedSnapshot(deps.dataDir, install.operator.ref, deps.now());
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
        const msg = tipo === "es_mio" ? "Anotado: vuelve a contar como tuyo." : "Anotado. No volverá aunque la fuente lo repita.";
        print(`${id} ${kind}: ${msg}`, { id, tipo, aplicada: true, registrada_en: deps.now() });
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
        const ref = cfg.profiles[name].operator.ref;
        const purged = engine.purgeAdapter(deps.dataDir, ref, adapter);
        const r = await deps.credentials.revoke(adapter, ref);
        print(`Revocado ${adapter}: consentimiento retirado, ${purged} fichero(s) de instantánea limpiados, `
          + `${r.tokens_removed} credencial(es) borrada(s)${r.cache_removed ? ", caché propia del adaptador borrada" : ""}.`,
        { adapter, purged, tokens_removed: r.tokens_removed, adapter_cache_removed: r.cache_removed });
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
        // Emparejamiento directo (soul-pair-v2): abre una ventana de 10 min con una clave de un solo
        // uso. La app no recibe el token del dispositivo por aquí: lo obtiene al completar contra `serve`.
        const name = activeProfileName(cfg, deps.env);
        if (p.args.length) throw new Exit(2, "pair [--days N] [--qr-png F] (el nombre lo pone la app)");
        const png = p.flags["qr-png"];
        if (png === "" || png === true) throw new Exit(2, "--qr-png <fichero>");
        const listen = validateListen(cfg.api.listen);
        const tls = ensureInstallCert(deps.dataDir, listen);
        const days = typeof p.flags.days === "string" ? Number(p.flags.days) : undefined;
        if (days !== undefined && (!Number.isInteger(days) || days < 1 || days > 397)) throw new Exit(2, "--days: entre 1 y 397 días");
        const w = openPairingWindow(deps.dataDir, cfg.profiles[name].operator.ref, Date.parse(deps.now()), days);
        const huella = shortFingerprint(tls.cert);
        const qr = pairLink(listen[0], cfg.api.port, w.token, huella);
        const matriz = encodeQr(qr).modules;
        if (typeof png === "string") {
          // Solo para quien lo pide; 0600 y sin sobrescribir. Si no se puede escribir, la ventana se cierra.
          try { writeFileSync(png, qrToPng(matriz), { mode: 0o600, flag: "wx" }); } catch (e) {
            closePairingWindow(deps.dataDir);
            throw new Exit(1, `--qr-png: no se pudo crear ${png} (${(e as NodeJS.ErrnoException).code ?? "error"}); ventana cerrada`);
          }
        }
        print([
          "Emparejar la app (modo directo). En la app, «Escanear QR» con este código:",
          qrToTerminal(matriz),
          "O pega en la app:",
          `  IP: ${listen.join(", ")}`, `  puerto: ${cfg.api.port}`, `  clave de emparejamiento: ${w.token}`,
          `  huella del certificado: ${huella} (compárala con la que muestra la app)`,
          `  o enlace para QR: ${qr}`,
          `Válido hasta ${w.expires_at.slice(11, 16)} UTC (10 min), un solo uso y 3 intentos. «soul serve» tiene que estar en marcha.`,
          typeof png === "string" ? `QR guardado en ${png} (0600): bórralo al terminar.` : "Si el QR no se ve bien en esta terminal: soul pair --qr-png <fichero>.",
          "La clave y el QR son secretos mientras dure la ventana: no compartas capturas de esta pantalla.",
        ].join("\n"), { clave: w.token, ...(typeof png === "string" ? { qr_png: png } : {}), direcciones: listen, puerto: cfg.api.port, huella_corta: huella, pin: tls.pin, qr, caduca: w.expires_at });
        return 0;
      }

      case "unpair": {
        if (!p.args[0]) throw new Exit(2, "unpair <id> [--undo]");
        const dev = listDevices(deps.dataDir).find((d) => d.id === p.args[0]);
        if (!dev || !revokeDevice(deps.dataDir, p.args[0], deps.now())) throw new Exit(1, `no hay ningún dispositivo ${p.args[0]}`);
        const undone = p.flags.undo === true ? await engine.undoDevice(deps.dataDir, dev.operator_ref, dev.id, deps.now()) : 0;
        const pending = engine.deviceCorrections(deps.dataDir, dev.operator_ref, dev.id).length;
        print(`Desemparejado ${p.args[0]}: su token deja de valer.${undone ? ` ${undone} corrección(es) suya(s) deshecha(s).` : pending ? ` Tiene ${pending} corrección(es) vigente(s): «soul undo-device ${dev.id}» las deshace.` : ""}`,
          { id: p.args[0], revoked: true, undone, corrections_pending: pending });
        return 0;
      }

      case "corrections": {
        const id = typeof p.flags.device === "string" ? p.flags.device : "";
        const dev = listDevices(deps.dataDir).find((d) => d.id === id);
        if (!dev) throw new Exit(2, "corrections --device <id de «soul devices»>");
        const list = engine.deviceCorrections(deps.dataDir, dev.operator_ref, dev.id)
          .map((c) => ({ id: elementId(dev.operator_ref, c.key), action: c.action, at: c.at }));
        print(list.map((c) => `${c.id} ${c.action} ${c.at}`).join("\n") || "Sin correcciones vigentes de ese dispositivo.", { device: dev.id, corrections: list });
        return 0;
      }

      case "undo-device": {
        const dev = listDevices(deps.dataDir).find((d) => d.id === p.args[0]);
        if (!dev) throw new Exit(2, "undo-device <id de «soul devices»>");
        const n = await engine.undoDevice(deps.dataDir, dev.operator_ref, dev.id, deps.now());
        print(`${n} corrección(es) de ${dev.id} deshecha(s): cada elemento vuelve a su estado anterior.`, { device: dev.id, undone: n });
        return 0;
      }

      case "devices": {
        const devices = listDevices(deps.dataDir).map(({ token_sha256: _h, ...d }) => d);
        print(devices.map((d) => `${d.id} ${d.name}${d.revoked_at ? " (revocado)" : ""}`).join("\n") || "Sin dispositivos.", { devices });
        return 0;
      }

      case "login": {
        const install = resolveInstall(cfg, deps.env);
        const adapter = p.args[0] ?? "";
        if (!deps.tokenStore || !deps.readSecret) throw new Exit(1, "el inicio de sesión no está disponible en este punto de entrada");
        const days = typeof p.flags.days === "string" ? Number(p.flags.days) : undefined;
        try {
          const msg = await runLogin(adapter, { tokenStdin: p.flags["token-stdin"] === true, days }, {
            connectors: cfg.connectors, store: deps.tokenStore(install.operator.ref, cfg), readSecret: deps.readSecret,
            say: deps.err, now: () => parseTs(deps.now()) ?? Date.now(),
          });
          print(msg, { adapter, stored: true });
        } catch (e) {
          if (e instanceof LoginUsage) throw new Exit(2, e.message);
          throw e;
        }
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
