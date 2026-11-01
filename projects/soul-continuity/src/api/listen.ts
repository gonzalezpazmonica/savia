/**
 * Escucha de la API local (SE-490): solo en las direcciones IP que configura el operador
 * (las de su VPN). Nunca en todas las interfaces: lista vacía, comodines o nombres de
 * host son error (fail-closed). Un servidor por dirección, todos en el mismo puerto.
 */

import { isIP, isIPv4 } from "node:net";
import type { Server } from "node:net";

/**
 * Bytes de una IP literal. IPv6 sin zona (`%eth0`) ni IPv4 incrustada (`::ffff:a.b.c.d`):
 * esas formas se rechazan para que ninguna escritura equivalente se cuele.
 */
export function ipBytes(ip: string): Buffer {
  if (isIPv4(ip)) return Buffer.from(ip.split(".").map(Number));
  if (isIP(ip) !== 6 || ip.includes("%") || ip.includes(".")) throw new Error(`dirección no admitida (solo IPv4 o IPv6 sin zona ni IPv4 incrustada): ${ip}`);
  const [head, tail = ""] = ip.split("::");
  const h = head ? head.split(":") : [];
  const t = ip.includes("::") ? (tail ? tail.split(":") : []) : [];
  const groups = ip.includes("::") ? [...h, ...Array(8 - h.length - t.length).fill("0"), ...t] : h;
  return Buffer.concat(groups.map((g) => { const b = Buffer.alloc(2); b.writeUInt16BE(parseInt(g || "0", 16)); return b; }));
}

export function validateListen(addresses: string[]): string[] {
  if (!Array.isArray(addresses) || addresses.length === 0) {
    throw new Error("ninguna dirección de escucha configurada: añade la IP de tu VPN en api.listen");
  }
  for (const a of addresses) {
    if (typeof a !== "string" || isIP(a) === 0) throw new Error(`dirección de escucha no válida (solo IP literal): ${String(a)}`);
    // Cualquier escritura de la dirección no especificada (0.0.0.0, ::, 0::, ::0:0…) es un comodín.
    const b = ipBytes(a);
    if (b.every((x) => x === 0)) throw new Error(`nunca se escucha en todas las interfaces: ${a}`);
    // IPv4 mapeada en hexadecimal (::ffff:0:0 = 0.0.0.0, ::ffff:7f00:1…): misma familia que la forma con puntos, rechazada.
    if (b.length === 16 && b.subarray(0, 10).every((x) => x === 0) && b[10] === 0xff && b[11] === 0xff) {
      throw new Error(`dirección no admitida (IPv4 mapeada en IPv6): ${a}`);
    }
  }
  return [...new Set(addresses)];
}

export interface Listening {
  port: number;
  addresses: { address: string; port: number }[];
  servers: Server[];
  close(): Promise<void>;
}

export async function listenOnly(addresses: string[], port: number, make: () => Promise<Server> | Server): Promise<Listening> {
  const list = validateListen(addresses);
  const servers: Server[] = [];
  let p = port;
  try {
    for (const a of list) {
      const s = await make();
      await new Promise<void>((res, rej) => {
        s.once("error", rej);
        s.listen({ host: a, port: p, ipv6Only: isIP(a) === 6 }, () => { s.off("error", rej); res(); });
      });
      p = (s.address() as { port: number }).port; // con puerto 0, todos comparten el primero asignado
      servers.push(s);
    }
  } catch (e) {
    for (const s of servers) s.close();
    throw e;
  }
  const close = () => Promise.all(servers.map((s) => new Promise<void>((r) => {
    (s as Server & { closeAllConnections?: () => void }).closeAllConnections?.();
    s.close(() => r());
  }))).then(() => undefined);
  return { port: p, addresses: servers.map((s) => s.address() as { address: string; port: number }), servers, close };
}
