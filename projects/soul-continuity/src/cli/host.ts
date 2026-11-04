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
 */

import { existsSync, statSync } from "node:fs";
import { isIPv4, isIPv6 } from "node:net";
import type { NetworkInterfaceInfo } from "node:os";
import { delimiter, join } from "node:path";
import type { Run } from "../credentials/store.ts";

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

export const NO_VPN_HELP = "No encuentro ninguna VPN en este equipo. Conecta la VPN de tu organización, o instala Tailscale (https://tailscale.com/download) en el portátil y en el móvil con la misma cuenta, y después: soul listen --detect (o soul listen <IP de la VPN>). Nunca 0.0.0.0.";

export type Level = "ok" | "aviso" | "fallo";
export interface Check { id: string; level: Level; message: string; fix?: string }

export interface HostProbe {
  platform: NodeJS.Platform;
  path: string | undefined;
  ifaces: Interfaces;
  run: Run;
}

/** Almacén de credenciales: en Linux, `secret-tool`. macOS y Windows lo traen de serie. */
export function checkSecretTool(h: HostProbe): Check {
  if (h.platform !== "linux") return { id: "almacen", level: "ok", message: "almacén de credenciales del sistema (viene de serie)" };
  if (onPath("secret-tool", h.path, h.platform)) return { id: "almacen", level: "ok", message: "secret-tool disponible (almacén de credenciales)" };
  return { id: "almacen", level: "fallo", message: "falta secret-tool: sin él Soul no puede guardar los tokens de las fuentes", fix: SECRET_TOOL_FIX };
}

/** Escucha: cada IP de `api.listen` tiene que estar en una interfaz del equipo. */
export async function checkListen(listen: string[], h: HostProbe): Promise<Check[]> {
  if (!listen.length) {
    const vpn = await detectVpn(h.ifaces, h.run);
    return [{
      id: "escucha", level: "fallo", message: "sin dirección de escucha (api.listen vacío)",
      fix: vpn.length ? `soul listen ${vpn.map((v) => v.address).join(" ")}   (detectada: ${describeVpn(vpn)})` : NO_VPN_HELP,
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
    fix: vpn.length ? `¿cambió la IP de tu VPN? soul listen ${vpn.map((v) => v.address).join(" ")}` : `conecta la VPN (por ejemplo «tailscale up») y vuelve a probar. ${NO_VPN_HELP}`,
  };
}
