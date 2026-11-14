/**
 * `soul doctor` y `soul setup`: instalación en un paso para una persona sin conocimientos técnicos.
 *
 * - `doctor`: perfil, almacén de credenciales (`secret-tool` en Linux) y escucha (la IP de
 *   `api.listen` está en una interfaz; si no, la causa probable y la orden exacta del arreglo).
 * - `setup`: encadena init, la escucha en la VPN, las comprobaciones, `serve` como servicio de
 *   usuario (arranque automático) y `pair`, con preguntas sencillas. Es interactiva y la ejecuta la
 *   persona: desde un frontend de agente la CLI la rechaza antes de llegar aquí (no está en la lista
 *   de órdenes permitidas), y sin terminal interactiva no hace nada.
 */

import { X509Certificate } from "node:crypto";
import { existsSync, readFileSync } from "node:fs";
import { isIP } from "node:net";
import { connect as tlsConnect } from "node:tls";
import { join } from "node:path";
import type { CliDeps } from "./cli.ts";
import { type Check, type HostProbe, NO_VPN_HELP, checkListen, checkSecretTool, describeVpn, detectVpn } from "./host.ts";
import { ConfigError, NoProfileError, loadConfig, resolveInstall } from "../core/config.ts";
import { validateListen } from "../api/listen.ts";
import { spkiPin } from "../api/cert.ts";

export function hostProbe(deps: CliDeps): HostProbe {
  return { platform: deps.platform, path: deps.env.PATH ?? deps.env.Path, ifaces: deps.ifaces?.() ?? {}, run: deps.run };
}

/** Comprobaciones de `doctor`, en orden. Fail-closed: un error al leer cuenta como fallo. */
export async function doctorChecks(deps: CliDeps): Promise<Check[]> {
  const h = hostProbe(deps);
  const out: Check[] = [];
  let listen: string[] = [];
  if (!existsSync(join(deps.dataDir, "config.json"))) {
    out.push({ id: "perfil", level: "fallo", message: "Soul no está instalado en esta cuenta", fix: "soul setup" });
  } else {
    try {
      const cfg = loadConfig(deps.dataDir);
      listen = cfg.api.listen;
      resolveInstall(cfg, deps.env);
      out.push({ id: "perfil", level: "ok", message: `perfil «${cfg.active_profile}» activo` });
    } catch (e) {
      const fix = e instanceof ConfigError ? "revisa config.json o reinstala (soul uninstall --yes y soul setup)" : "soul setup";
      out.push({ id: "perfil", level: "fallo", message: e instanceof NoProfileError || e instanceof ConfigError ? e.message : `configuración ilegible (${(e as Error).name})`, fix });
    }
  }
  out.push(checkSecretTool(h));
  out.push(...(await checkListen(listen, h)));
  return out;
}

export function formatChecks(checks: Check[]): string {
  const tag = { ok: "ok   ", aviso: "AVISO", fallo: "FALLO" } as const;
  return checks.flatMap((c) => [`${tag[c.level]} ${c.message}`, ...(c.fix ? [`      arreglo: ${c.fix}`] : [])]).join("\n");
}

const yes = (a: string) => /^(|s|si|sí|y|yes)$/i.test(a.trim());

/**
 * ¿Responde `serve` de esta instalación en esa dirección y puerto? Hace el handshake TLS y exige que
 * la huella SPKI del certificado presentado sea la de `tls/cert.pem` de la instalación: cualquier otro
 * proceso escuchando en ese puerto (o un TCP sin TLS) no cuenta. Sin certificado aún, `false`.
 */
export function servePinned(dataDir: string, host: string, port: number, timeoutMs = 1500): Promise<boolean> {
  let want: string;
  try { want = spkiPin(readFileSync(join(dataDir, "tls", "cert.pem"), "utf8")); } catch { return Promise.resolve(false); }
  return new Promise((resolve) => {
    // Sin validación de CA a propósito: el certificado es autofirmado y la confianza es la huella.
    const s = tlsConnect({ host, port, rejectUnauthorized: false, servername: isIP(host) ? undefined : host });
    const done = (ok: boolean) => { s.destroy(); resolve(ok); };
    s.setTimeout(timeoutMs, () => done(false));
    s.once("secureConnect", () => {
      let got = "";
      try { const raw = s.getPeerCertificate().raw; got = raw ? spkiPin(new X509Certificate(raw).toString()) : ""; } catch { got = ""; }
      done(got !== "" && got === want);
    });
    s.once("error", () => done(false));
  });
}

async function waitReachable(deps: CliDeps, host: string, port: number): Promise<boolean> {
  const probe = deps.reachable ?? ((h: string, p: number) => servePinned(deps.dataDir, h, p));
  for (let i = 0; i < 10; i++) {
    if (await probe(host, port)) return true;
    if (!deps.reachable) await new Promise((r) => setTimeout(r, 1000));
  }
  return false;
}

/**
 * `soul setup`. `sub` ejecuta otra orden de la CLI con las mismas dependencias (init, listen,
 * autostart, pair): setup no duplica su lógica ni sus salvaguardas.
 */
export async function runSetup(deps: CliDeps, sub: (argv: string[]) => Promise<number>): Promise<number> {
  const ask = deps.ask;
  if (!ask) { deps.err("soul setup es interactiva: ejecútala tú en tu terminal."); return 2; }
  const say = deps.out;
  say("Instalación de Soul en este equipo. Contesta a cada pregunta; Intro acepta lo que va entre corchetes.");

  // 1. Perfil
  if (existsSync(join(deps.dataDir, "config.json"))) {
    say(`1/5 Ya hay una instalación en ${deps.dataDir}: la uso tal cual.`);
  } else {
    say("1/5 Tu perfil");
    const name = (await ask("Nombre corto para este perfil (minúsculas) [trabajo]: ")).trim() || "trabajo";
    const email = (await ask("Tu correo de trabajo, para reconocer lo que es tuyo (Intro para saltar): ")).trim();
    const code = await sub(["init", name, ...(email ? ["--email", email] : [])]);
    if (code !== 0) return code;
  }

  // 2. Escucha en la VPN
  say("2/5 Por dónde te encuentra el móvil (solo por tu VPN)");
  let cfg;
  try { cfg = loadConfig(deps.dataDir); } catch (e) {
    deps.err(`No puedo leer la instalación (${e instanceof ConfigError || e instanceof NoProfileError ? e.message : (e as Error).name}). Mira qué dice: soul doctor`);
    return 1;
  }
  if (cfg.api.listen.length) {
    say(`Escucha configurada: ${cfg.api.listen.join(", ")}`);
  } else {
    const vpn = await detectVpn(hostProbe(deps).ifaces, deps.run);
    let ips: string[] = [];
    // Una 100.64/10 que no es de una VPN reconocida (CGNAT de la operadora) no se acepta con Intro.
    const known = vpn.every((v) => v.vpn);
    const q = known
      ? `He encontrado tu VPN: ${describeVpn(vpn)}. ¿Escucho solo ahí? [S/n]: `
      : `He encontrado ${describeVpn(vpn)}. ¿Es tu VPN? Escribe «si» para escuchar ahí [s/N]: `;
    if (vpn.length) {
      const a = await ask(q);
      if (known ? yes(a) : yes(a) && a.trim() !== "") ips = vpn.map((v) => v.address);
    }
    if (!ips.length) {
      if (!vpn.length) say(NO_VPN_HELP);
      const typed = (await ask("Escribe la IP de tu VPN en este equipo (Intro para salir y hacerlo luego): ")).trim();
      if (!typed) { deps.err("Sin dirección de escucha no se puede emparejar el móvil. Cuando tengas la VPN: soul setup"); return 1; }
      ips = typed.split(/[\s,]+/).filter(Boolean);
    }
    const code = await sub(["listen", ...ips]);
    if (code !== 0) return code;
    cfg = loadConfig(deps.dataDir);
  }

  // 3. Comprobaciones
  say("3/5 Comprobaciones");
  const checks = await doctorChecks(deps);
  say(formatChecks(checks));
  if (checks.some((c) => c.level === "fallo" && (c.id === "escucha" || c.id === "perfil"))) {
    say("Arregla lo marcado como FALLO (la orden está debajo) y vuelve a ejecutar: soul setup");
    return 1;
  }
  if (checks.some((c) => c.level === "fallo")) say("Puedes emparejar el móvil ya; lo marcado como FALLO hace falta para conectar tus fuentes.");

  // 4. serve como servicio de usuario
  say("4/5 Servicio de Soul");
  const listen = validateListen(cfg.api.listen);
  if (yes(await ask("¿Arranco Soul ahora y cada vez que inicies sesión? (servicio de tu usuario, sin administrador) [S/n]: "))) {
    const code = await sub(["autostart", "install"]);
    if (code !== 0) return code;
  } else {
    say("De acuerdo. Abre otra terminal y deja en marcha: soul serve");
    await ask("Pulsa Intro cuando «soul serve» diga «Escuchando en…»: ");
  }
  if (!(await waitReachable(deps, listen[0], cfg.api.port))) {
    deps.err(`Soul no responde en ${listen[0]}:${cfg.api.port}. Mira qué dice: soul doctor`
      + (deps.platform === "linux" ? " · journalctl --user -u soul-continuity -n 30" : ""));
    return 1;
  }
  say(`Soul está en marcha en ${listen.join(", ")}:${cfg.api.port}.`);

  // 5. Emparejar el móvil
  say("5/5 Emparejar el móvil");
  let code = 0;
  if (yes(await ask("¿Emparejas el móvil ahora? Ten la app Savia Space abierta [S/n]: "))) {
    code = await sub(["pair"]);
    if (code !== 0) return code;
  } else say("Cuando quieras: soul pair.");

  // Conectar una fuente: lo mismo que `soul source add` (declaración y «s» incluidas). Intro no añade nada.
  const fuente = (await ask("¿Quieres conectar una fuente ahora? (github, jira, azure-devops… / Intro para no): ")).trim().toLowerCase();
  if (fuente) {
    if (/^[a-z0-9][a-z0-9-]{0,40}$/.test(fuente)) await sub(["source", "add", fuente]);
    else deps.err("Escribe solo el nombre de la fuente (por ejemplo github) o Intro para no. Más tarde: soul source add <fuente>");
  } else say("Cuando quieras: soul source add <fuente> (github, jira, azure-devops, m365-mail…).");
  say("Hecho. Siguiente paso: iniciar sesión en tus fuentes (docs/instalar.md, paso 4).");
  return code;
}
