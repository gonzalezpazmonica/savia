/**
 * «Esperando mi respuesta» solo con metadatos e identidad del remitente (SE-490).
 *
 * Regla de la spec, por hilo (`conversationId` o `threadId`):
 *   1. el último mensaje del hilo (entrada y enviados juntos, por fecha) no es mío;
 *   2. alguna de mis direcciones está en `To` de ese mensaje (CC y listas no cuentan);
 *   3. no hay ningún mensaje mío en enviados del mismo buzón posterior a él.
 * Así cuentan las respuestas desde cualquier cliente (web, móvil, escritorio).
 * Un reenvío mío dentro de la misma conversación cuenta como mensaje mío:
 * limitación consciente de la regla de metadatos.
 *
 * La identidad del remitente sale de cabeceras puestas por el servidor, nunca de
 * `From` solo (AC-4c).
 */

import { type SenderAuth, parseTs } from "../contract/claims.ts";

export interface Msg {
  id: string;
  conv: string;
  from: string;
  to: string[];
  cc: string[];
  at: string;
  sent: boolean;
  subject: string;
  auth: SenderAuth;
}

export function awaitingReply(msgs: Msg[], mine: string[]): Msg[] {
  const me = new Set(mine.map((x) => x.toLowerCase()));
  const isMe = (a: string) => me.has(a.toLowerCase());
  const byConv = new Map<string, { m: Msg; t: number }[]>();
  for (const m of msgs) {
    const t = parseTs(m.at);
    if (t === null || !m.conv) continue;
    const list = byConv.get(m.conv) ?? [];
    list.push({ m, t });
    byConv.set(m.conv, list);
  }
  const out: Msg[] = [];
  for (const list of byConv.values()) {
    // A igual instante, lo enviado va después: lo mío cierra.
    list.sort((a, b) => a.t - b.t || Number(a.m.sent || isMe(a.m.from)) - Number(b.m.sent || isMe(b.m.from)));
    const last = list[list.length - 1];
    if (last.m.sent || isMe(last.m.from)) continue;
    if (!last.m.to.some(isMe)) continue;
    // Condición 3 (ningún enviado mío posterior): entrada y enviados van ordenados
    // juntos, así que un enviado posterior sería el último y ya se descartó arriba.
    out.push(last.m);
  }
  return out;
}

export interface Header {
  name: string;
  value: string;
}

/**
 * Identidad del remitente según el servidor receptor.
 *
 * Solo cuenta la cabecera `Authentication-Results` de más arriba: el receptor
 * antepone la suya, y las de más abajo pueden venir del remitente (RFC 8601 §5).
 * Con `authservIds`, además su `authserv-id` debe ser uno de ellos (Gmail pone
 * `mx.google.com`; Exchange Online no pone ninguno, por eso es opcional).
 * `dkim=pass`, `dmarc=pass` y `header.from` salen de esa misma cabecera; dentro de
 * ella, un resultado DMARC discordante también deja sin autenticar.
 */
export function senderAuth(from: string, headers: Header[] | undefined | null, myDomain: string, authservIds?: string[]): SenderAuth {
  if (!Array.isArray(headers)) return "unknown";
  const dom = from.split("@")[1]?.toLowerCase() ?? "";
  if (!dom) return "unauthenticated";
  const all = (n: string) => headers.filter((x) => String(x?.name).toLowerCase() === n.toLowerCase()).map((x) => String(x.value));
  const authAs = all("X-MS-Exchange-Organization-AuthAs");
  if (authAs.length === 1 && authAs[0].trim() === "Internal" && dom === myDomain.toLowerCase()) return "tenant";
  const top = all("Authentication-Results")[0];
  if (top === undefined) return "unauthenticated";
  const parts = top.split(";").map((p) => p.trim()).filter(Boolean);
  if (authservIds) {
    const id = parts[0] && !parts[0].includes("=") ? parts[0].split(/\s/)[0].toLowerCase() : "";
    if (!authservIds.map((x) => x.toLowerCase()).includes(id)) return "unauthenticated";
  }
  const dmarc = parts.filter((p) => /^dmarc=/i.test(p));
  if (dmarc.length !== 1 || !/^dmarc=pass\b/i.test(dmarc[0])) return "unauthenticated";
  const hf = /\bheader\.from=([^\s;]+)/i.exec(dmarc[0])?.[1]?.toLowerCase();
  if (!parts.some((p) => /^dkim=pass\b/i.test(p)) || hf !== dom) return "unauthenticated";
  return "dkim_dmarc";
}
