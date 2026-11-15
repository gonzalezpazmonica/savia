/**
 * Detecciones del equipo para instalar y diagnosticar Soul (`init`, `listen`, `doctor`, `serve`, `setup`).
 *
 * Todo entra inyectado (interfaces de red, `Run`, PATH, plataforma) para poder probarlo sin tocar la
 * máquina. Ninguna detección arregla nada que necesite administrador: da la orden exacta para que
 * la ejecute la persona.
 *
 * - VPN: `tailscale ip -4` y las interfaces con una IPv4 de 100.64.0.0/10 (rango de Tailscale,
 *   Headscale, NetBird y otras VPN de malla). Nunca se propone 0.0.0.0 ni una dirección de bucle.
 *   100.64/10 es también el CGNAT de operadoras móviles e ISP (RFC 6598): solo cuenta como VPN
 *   reconocida (`vpn: true`, se puede fijar sin preguntar) lo que da `tailscale ip -4` o una interfaz
 *   con nombre de VPN (`VPN_IF`). Una 100.64/10 en `eth0`, `wwan0`… solo se propone, y se pregunta.
 * - IP configurada ausente: si `api.listen` tiene una IP que no está en ninguna interfaz, `serve`
 *   fallaría con EADDRNOTAVAIL. Si NetworkManager gestiona `tailscale0`, le quita la IPv4: se da la
 *   orden del fichero `unmanaged-devices`.
 * - `secret-tool` (Linux): sin él no hay almacén de credenciales.
 * - macOS y Windows: el almacén no se da por bueno, se prueba (`checkKeychain`): guarda, lee y borra
 *   un elemento de prueba con el mismo backend que usa Soul. Un diálogo del sistema esperando es un fallo.
 */

import { randomBytes } from "node:crypto";
import { accessSync, constants, existsSync, statSync } from "node:fs";
import { isIPv4, isIPv6 } from "node:net";
import type { NetworkInterfaceInfo } from "node:os";
import { delimiter, join } from "node:path";
import { type Run, backendFor } from "../credentials/store.ts";

export type Interfaces = NodeJS.Dict<NetworkInterfaceInfo[]>;

/** 100.64.0.0/10 (RFC 6598): el rango que asignan Tailscale y otras VPN de malla. */
export function isCgnat(ip: string): boolean {
  if (!isIPv4(ip)) return false;
  const [a, b] = ip.split(".").map(Number);
  return a === 100 && b >= 64 && b <= 127;
}

/**
 * Nombres de interfaz de VPN de malla: Tailscale (`tailscale0`; «Tailscale» en Windows), NetBird
 * (`wt0`), WireGuard (`wg0`…), macOS (`utun3`…), ZeroTier (`zt…`). Una WAN o un módem (`eth0`,
 * `wwan0`, `enx…`) no entra aunque tenga una 100.64/10.
 */
export const VPN_IF = /^(tailscale\d*|wt\d+|wg\d*|utun\d+|zt[0-9a-z]+)$/i;

/** `vpn`: reconocida como VPN (de `tailscale ip -4` o de una interfaz `VPN_IF`). */
export interface VpnAddress { address: string; via: string; vpn: boolean }

/**
 * Direcciones IPv4 candidatas a VPN, sin repetir: primero las que da `tailscale ip -4`, después
 * las de cualquier interfaz en 100.64.0.0/10. Sin ninguna, lista vacía. Solo las `vpn: true` se
 * pueden fijar sin preguntar (`recognizedVpn`).
 */
export async function detectVpn(ifaces: Interfaces, run: Run): Promise<VpnAddress[]> {
  const out: VpnAddress[] = [];
  const add = (address: string, via: string, vpn: boolean) => { if (!out.some((x) => x.address === address)) out.push({ address, via, vpn }); };
  const r = await run("tailscale", ["ip", "-4"]);
  if (r.code === 0) for (const l of r.stdout.split(/\s+/)) if (isCgnat(l)) add(l, "tailscale", true);
  for (const [name, list] of Object.entries(ifaces)) {
    for (const i of list ?? []) if (!i.internal && i.family === "IPv4" && isCgnat(i.address)) add(i.address, name, VPN_IF.test(name));
  }
  return out;
}

/** Solo las direcciones reconocidas como VPN: lo único que `init` y `listen --detect` fijan solos. */
export const recognizedVpn = (v: VpnAddress[]) => v.filter((x) => x.vpn).map((x) => x.address);

/** «100.70.1.2 en wwan0» para proponer, sin fijar, una 100.64/10 que no es de una VPN reconocida. */
export const describeVpn = (v: VpnAddress[]) => v.map((x) => `${x.address} en ${x.via}${x.vpn ? "" : " (no parece una VPN: puede ser la red de tu operadora)"}`).join(", ");

/** Forma canónica de una IP para comparar (IPv6 en minúsculas y comprimida); lo que no es IP, tal cual. */
export function canonicalIp(ip: string): string {
  if (!isIPv6(ip)) return ip;
  try { return new URL(`http://[${ip}]/`).hostname.slice(1, -1); } catch { return ip.toLowerCase(); }
}

/** ¿Está esta IP asignada a alguna interfaz del equipo? IPv6 en cualquier escritura. */
export function onInterface(ip: string, ifaces: Interfaces): boolean {
  const want = canonicalIp(ip);
  return Object.values(ifaces).some((list) => (list ?? []).some((i) => canonicalIp(i.address) === want));
}

export const TAILSCALE_IF = "tailscale0";

/**
 * ¿Gestiona NetworkManager esta interfaz? `true` gestionada, `false` no gestionada,
 * `null` si no hay `nmcli` o no la conoce (no se puede afirmar nada).
 */
export async function nmManaged(device: string, run: Run): Promise<boolean | null> {
  const r = await run("nmcli", ["-t", "-f", "DEVICE,STATE", "device", "status"]);
  if (r.code !== 0) return null;
  for (const line of r.stdout.split("\n")) {
    const [dev, state] = line.trim().split(":");
    if (dev === device) return state !== "unmanaged";
  }
  return null;
}

/** Orden para que NetworkManager deje en paz `tailscale0`. Necesita administrador: la ejecuta la persona. */
export const NM_UNMANAGED_FIX = [
  "printf '[keyfile]\\nunmanaged-devices=interface-name:tailscale0\\n' | sudo tee /etc/NetworkManager/conf.d/unmanaged-devices.conf",
  "sudo systemctl reload NetworkManager",
  "sudo systemctl restart tailscaled",
].join(" && ");

/** ¿Hay un fichero ejecutable con ese nombre en el PATH? Un directorio con ese nombre no cuenta. */
export function onPath(cmd: string, path: string | undefined, platform: NodeJS.Platform): boolean {
  const exts = platform === "win32" ? ["", ".exe", ".cmd", ".bat"] : [""];
  for (const dir of (path ?? "").split(platform === "win32" ? ";" : delimiter)) {
    if (!dir) continue;
    for (const e of exts) {
      const f = join(dir, cmd + e);
      try { if (existsSync(f) && statSync(f).isFile()) return true; } catch { /* sin permiso: no cuenta */ }
    }
  }
  return false;
}

export const SECRET_TOOL_FIX = "sudo apt install libsecret-tools   (Fedora: sudo dnf install libsecret · Arch: sudo pacman -S libsecret)";

/** Sin VPN en macOS: el móvil no llega al Mac. Instalar una VPN puede necesitar administrador: lo decide la persona. */
export const NO_VPN_HELP_MAC = "No encuentro ninguna VPN en este Mac. Sin VPN el móvil no puede hablar con el Mac. Conecta la VPN de tu organización si ya tienes una. Instalar Tailscale (https://tailscale.com/download) puede necesitar administrador o el permiso de tu equipo de TI: lo decides tú, Soul no lo instala ni lo intenta. Con una VPN conectada: soul listen --detect (o soul listen <IP de la VPN>). Nunca 0.0.0.0.";

export const NO_VPN_HELP = "No encuentro ninguna VPN en este equipo. Conecta la VPN de tu organización, o instala Tailscale (https://tailscale.com/download) en el portátil y en el móvil con la misma cuenta, y después: soul listen --detect (o soul listen <IP de la VPN>). Nunca 0.0.0.0.";

export type Level = "ok" | "aviso" | "fallo";
export interface Check { id: string; level: Level; message: string; fix?: string }

export interface HostProbe {
  platform: NodeJS.Platform;
  path: string | undefined;
  ifaces: Interfaces;
  run: Run;
  /** Carpeta personal (arranque de usuario de macOS). */
  home?: string;
  /** Tiempo máximo de cada paso de la prueba del almacén (un diálogo del sistema esperando). Por defecto, `probeTimeoutFor`. */
  timeoutMs?: number;
}

/**
 * Tiempo máximo por paso de la prueba del almacén. Windows tiene más margen: el primer `Add-Type` de
 * PowerShell compila C# y un antivirus corporativo puede tardar en dejarlo pasar.
 */
export const probeTimeoutFor = (platform: NodeJS.Platform) => (platform === "win32" ? 60_000 : 20_000);

export const noVpnHelp = (platform: NodeJS.Platform) => (platform === "darwin" ? NO_VPN_HELP_MAC : NO_VPN_HELP);

/**
 * Almacén de credenciales, solo la parte de Linux (`secret-tool`). En otros sistemas esta función
 * no comprueba nada y lo dice: la prueba real es `checkKeychain` (la usa `doctor`).
 */
export function checkSecretTool(h: HostProbe): Check {
  if (h.platform !== "linux") return { id: "almacen", level: "aviso", message: "almacén de credenciales sin comprobar aquí: «soul doctor» lo prueba" };
  if (onPath("secret-tool", h.path, h.platform)) return { id: "almacen", level: "ok", message: "secret-tool disponible (almacén de credenciales)" };
  return { id: "almacen", level: "fallo", message: "falta secret-tool: sin él Soul no puede guardar los tokens de las fuentes", fix: SECRET_TOOL_FIX };
}

class ProbeTimeout extends Error {}

/**
 * `run` que da por fallido un paso que no termina (p. ej. un diálogo del sistema pidiendo la contraseña)
 * y mata el proceso hijo: vivo, mantendría `doctor` sin devolver el control.
 */
function withTimeout(run: Run, ms: number): Run {
  return (cmd, args, input) => new Promise((resolve, reject) => {
    const ac = new AbortController();
    const t = setTimeout(() => { ac.abort(); reject(new ProbeTimeout(`sin respuesta tras ${Math.round(ms / 1000)} s`)); }, ms);
    run(cmd, args, input, { signal: ac.signal }).then((r) => { clearTimeout(t); resolve(r); }, (e) => { clearTimeout(t); reject(e); });
  });
}

const KEYCHAIN_FIX = "abre «Acceso a Llaveros», comprueba que el llavero «inicio de sesión» está desbloqueado (o cierra y abre sesión) y vuelve a probar. Si tu organización restringe el llavero, díselo a quien administra el equipo: sin él Soul no puede guardar tokens";
const KEYCHAIN_TIMEOUT_FIX = "puede que el sistema esté esperando en un diálogo (contraseña del llavero o permiso): ciérralo o respóndelo y vuelve a probar «soul doctor»";
const CREDMAN_FIX = "revisa que PowerShell se puede ejecutar en tu cuenta (una directiva de la organización puede bloquearlo) y que Credential Manager está disponible; si no, díselo a quien administra el equipo";

/**
 * macOS y Windows: no se da por bueno el almacén, se prueba. Guarda un secreto aleatorio con un
 * servicio propio de diagnóstico, lo lee, comprueba que es el mismo y lo borra (también si la lectura
 * falla). `ok` solo si lo leído es lo guardado y el borrado se comprueba. Un almacén que no borra es
 * un fallo: revocar o desinstalar no podrían quitar los tokens. El secreto va por stdin, como en el uso normal.
 * Tras un tiempo agotado no se relee para comprobar el borrado (sería otra espera entera).
 */
export async function checkKeychain(h: HostProbe): Promise<Check> {
  const nombre = h.platform === "darwin" ? "llavero de macOS" : "Credential Manager de Windows";
  const fix = h.platform === "darwin" ? KEYCHAIN_FIX : CREDMAN_FIX;
  const service = `doctor-${randomBytes(4).toString("hex")}`;
  const account = "probe";
  const secret = randomBytes(16).toString("hex");
  const manual = h.platform === "darwin"
    ? `bórralo en «Acceso a Llaveros» (busca «${service}») o con: security delete-generic-password -a ${account} -s soul-continuity.${service}`
    : `bórralo en Credential Manager (entrada «soul-continuity/${service}/${account}»)`;
  const fail = (message: string, timeout = false): Check =>
    ({ id: "almacen", level: "fallo", message: `${nombre}: ${message}`, fix: timeout ? `${KEYCHAIN_TIMEOUT_FIX}. Si respondes al diálogo más tarde, puede quedar el elemento de prueba «${service}»: ${manual}` : fix });
  const backend = backendFor(h.platform, withTimeout(h.run, h.timeoutMs ?? probeTimeoutFor(h.platform)));
  let failure: Check | null = null;
  let timedOut = false;
  const why = (e: unknown, paso: string) => {
    if (!(e instanceof ProbeTimeout)) return fail(`no pude ${paso} el elemento de prueba (${(e as Error).message})`);
    timedOut = true;
    return fail(`no respondió al ${paso} (${e.message})`, true);
  };
  try {
    await backend.set(service, account, secret);
    try {
      const got = await backend.get(service, account);
      if (got !== secret) failure = fail("guarda el elemento de prueba pero devuelve otra cosa al leerlo: no es fiable para guardar tokens");
    } catch (e) { failure = why(e, "leer"); }
  } catch (e) { failure = why(e, "guardar"); }
  // El borrado se intenta siempre, también si guardar o leer fallaron.
  let borrado = false;
  try {
    await backend.delete(service, account);
    // Fail-closed: si la relectura falla, el borrado no está comprobado (no se da por borrado).
    if (!timedOut) borrado = (await backend.get(service, account)) === null;
  } catch (e) {
    if (!failure && e instanceof ProbeTimeout) failure = why(e, "borrar");
  }
  if (failure) return failure;
  if (!borrado) return { id: "almacen", level: "fallo", message: `${nombre}: guarda y lee, pero no pude borrar el elemento de prueba «${service}»: revocar o desinstalar no podrían quitar tus tokens`, fix: manual };
  return { id: "almacen", level: "ok", message: `${nombre}: guarda, lee y borra (probado con un elemento de prueba)` };
}

/** Almacén para `doctor`: Linux por `secret-tool`; macOS y Windows, por prueba real. Otro sistema: fallo. */
export async function checkCredentialStore(h: HostProbe): Promise<Check> {
  if (h.platform === "linux") return checkSecretTool(h);
  if (h.platform === "darwin" || h.platform === "win32") return checkKeychain(h);
  return { id: "almacen", level: "fallo", message: `sin almacén de credenciales para ${h.platform}` };
}

/**
 * Arranque de usuario en macOS: `~/Library/LaunchAgents` existe y se puede escribir, o se puede crear
 * (`~/Library` escribible). No carga nada: eso lo hace `soul autostart install`.
 */
export function checkLaunchAgents(h: HostProbe): Check {
  const home = h.home;
  const dir = home ? join(home, "Library", "LaunchAgents") : "";
  const fix = `crea la carpeta con «mkdir -p ~/Library/LaunchAgents» y comprueba que es tuya (ls -ld ~/Library/LaunchAgents). Si tu organización la bloquea, Soul seguirá funcionando pero tendrás que arrancarlo a mano con «soul serve»`;
  // Aviso, no fallo: el arranque automático es opcional (SE-490, modo por defecto bajo demanda).
  const bad = (message: string): Check => ({ id: "arranque", level: "aviso", message, fix });
  if (!home) return bad("no sé cuál es tu carpeta personal");
  const writable = (p: string) => { try { accessSync(p, constants.W_OK | constants.X_OK); return true; } catch { return false; } };
  const isDir = (p: string) => { try { return statSync(p).isDirectory(); } catch { return false; } };
  let ok: boolean;
  let msg: string;
  if (existsSync(dir)) {
    ok = isDir(dir) && writable(dir);
    msg = isDir(dir) ? `no puedo escribir en ${dir}: el arranque automático de Soul no se podrá instalar` : `${dir} existe pero no es una carpeta`;
  } else {
    const lib = join(home, "Library");
    ok = isDir(lib) && writable(lib);
    msg = `${dir} no existe y no puedo crearla (${lib} no es escribible)`;
  }
  if (!ok) return bad(msg);
  if (!onPath("launchctl", h.path, h.platform) && !existsSync("/bin/launchctl")) {
    return { id: "arranque", level: "aviso", message: "no encuentro «launchctl»: el arranque automático no se podrá cargar", fix: "comprueba que /bin/launchctl existe y está en el PATH; mientras, arranca Soul a mano con «soul serve»" };
  }
  return { id: "arranque", level: "ok", message: `${dir} se puede escribir (el arranque automático se podrá instalar; doctor no carga nada)` };
}

/** Escucha: cada IP de `api.listen` tiene que estar en una interfaz del equipo. */
export async function checkListen(listen: string[], h: HostProbe): Promise<Check[]> {
  if (!listen.length) {
    const vpn = await detectVpn(h.ifaces, h.run);
    return [{
      id: "escucha", level: "fallo", message: "sin dirección de escucha (api.listen vacío)",
      fix: vpn.length ? `soul listen ${vpn.map((v) => v.address).join(" ")}   (detectada: ${describeVpn(vpn)})` : noVpnHelp(h.platform),
    }];
  }
  const out: Check[] = [];
  for (const ip of listen) {
    out.push(onInterface(ip, h.ifaces) ? { id: "escucha", level: "ok", message: `${ip} está en una interfaz de este equipo` } : await missingAddress(ip, h));
  }
  return out;
}

/**
 * Diagnóstico de una IP configurada que no está en ninguna interfaz (lo que daría EADDRNOTAVAIL).
 * Una IP de VPN de malla en Linux con `tailscale0` gestionada por NetworkManager: la causa es esa.
 */
export async function missingAddress(ip: string, h: HostProbe): Promise<Check> {
  const base = `la IP configurada ${ip} no está en ninguna interfaz de este equipo`;
  if (h.platform === "linux" && isCgnat(ip) && (await nmManaged(TAILSCALE_IF, h.run)) === true) {
    return {
      id: "escucha", level: "fallo",
      message: `${base}: NetworkManager gestiona ${TAILSCALE_IF} y le quita la IPv4. Ejecuta esta orden una vez (pide tu contraseña) y vuelve a probar`,
      fix: NM_UNMANAGED_FIX,
    };
  }
  const vpn = (await detectVpn(h.ifaces, h.run)).filter((v) => v.address !== ip);
  return {
    id: "escucha", level: "fallo", message: base,
    fix: vpn.length ? `¿cambió la IP de tu VPN? soul listen ${vpn.map((v) => v.address).join(" ")}` : `conecta la VPN (por ejemplo «tailscale up») y vuelve a probar. ${noVpnHelp(h.platform)}`,
  };
}
