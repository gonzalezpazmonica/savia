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

export function senderAuth(from: string, headers: Header[] | undefined | null, myDomain: string): SenderAuth {
  if (!Array.isArray(headers)) return "unknown";
  const dom = from.split("@")[1]?.toLowerCase() ?? "";
  if (!dom) return "unauthenticated";
  const h = (n: string) => headers.filter((x) => String(x?.name).toLowerCase() === n.toLowerCase()).map((x) => String(x.value)).join(";");
  if (h("X-MS-Exchange-Organization-AuthAs").trim() === "Internal" && dom === myDomain.toLowerCase()) return "tenant";
  const ar = h("Authentication-Results");
  const hf = /header\.from=([^\s;]+)/i.exec(ar)?.[1]?.toLowerCase();
  if (/\bdkim=pass\b/i.test(ar) && /\bdmarc=pass\b/i.test(ar) && hf === dom) return "dkim_dmarc";
  return "unauthenticated";
}
