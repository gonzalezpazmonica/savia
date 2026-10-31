/**
 * Escucha de la API local (SE-490): solo en las direcciones IP que configura el operador
 * (las de su VPN). Nunca en todas las interfaces: lista vacía, comodines o nombres de
 * host son error (fail-closed). Un servidor por dirección, todos en el mismo puerto.
 */

import { isIP } from "node:net";
import type { Server } from "node:net";

const WILDCARD = new Set(["0.0.0.0", "::", "::0", "0:0:0:0:0:0:0:0"]);

export function validateListen(addresses: string[]): string[] {
  if (!Array.isArray(addresses) || addresses.length === 0) {
    throw new Error("ninguna dirección de escucha configurada: añade la IP de tu VPN en api.listen");
  }
  for (const a of addresses) {
    if (typeof a !== "string" || isIP(a) === 0) throw new Error(`dirección de escucha no válida (solo IP literal): ${String(a)}`);
    if (WILDCARD.has(a)) throw new Error(`nunca se escucha en todas las interfaces: ${a}`);
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
