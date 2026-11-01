// Coincidencia de URLs contra la lista cerrada de una receta. Estricta a
// propósito: mismo origen exacto, ruta y consulta completas, sin prefijos.
//
// Un patrón es relativo al origen de la receta (`/tareas?pagina=*`) o absoluto
// con su propio origen exacto (`https://cdn.example/app/*.js`). Los absolutos
// existen para los clientes reales, que cargan scripts o leen datos de otro
// origen; el cortafuegos nunca deja NAVEGAR a otro origen (decision.ts).

import type { PatronUrl } from "./tipos.ts";

// Un segmento comodín no cruza / ? & = # ni su forma codificada (%2F, %3F,
// %26, %3D, %23) ni la barra invertida (%5C): hay servidores que las decodifican.
// Tampoco el propio `%` codificado (%25): `%252F` es `/` tras dos decodificaciones.
// Los patrones de login son detección (más ancho = más seguro) y sí los admiten:
// `/login?vuelta=%2Ftareas`.
const COMODIN = "(?:[^/?&=#%]|%(?!2[Ff]|3[Ff]|26|3[Dd]|23|5[Cc]|25))+";
const COMODIN_LOGIN = "[^/?&=#]+";
const ABSOLUTO = /^(https?|wss?):\/\/([^/?#*{}@]+)(\/.*)$/;
const SOLO_ORIGEN = /^(https?):\/\/([^/?#*{}@]+)$/;

export function compilarPatron(patron: PatronUrl, login = false): RegExp {
  const ruta = esAbsoluto(patron) ? partirAbsoluto(patron).ruta : patron;
  if (!ruta.startsWith("/")) throw new Error(`patrón sin barra inicial: ${patron}`);
  if (ruta.includes("**")) throw new Error(`patrón con **: ${patron}`);
  if (ruta.includes("#")) throw new Error(`patrón con fragmento: ${patron}`);
  const partes = ruta.split("*").map((p) => p.replace(/[.+?^${}()|[\]\\]/g, "\\$&"));
  return new RegExp(`^${partes.join(login ? COMODIN_LOGIN : COMODIN)}$`);
}

export function esAbsoluto(patron: PatronUrl): boolean {
  return /^[a-z]+:\/\//i.test(patron);
}

/** Origen y ruta de un patrón absoluto. El origen no admite comodines ni credenciales. */
export function partirAbsoluto(patron: PatronUrl): { origen: string; ruta: string } {
  const m = ABSOLUTO.exec(patron);
  if (!m) throw new Error(`patrón absoluto inválido: ${patron}`);
  const u = new URL(`${m[1]}://${m[2]}/`);
  if (u.username || u.password) throw new Error(`patrón absoluto con credenciales: ${patron}`);
  return { origen: u.origin, ruta: m[3] };
}

/** `https://login.example` (sin ruta): todo ese origen delata un inicio de sesión. */
export function esOrigenLogin(patron: PatronUrl): boolean {
  return SOLO_ORIGEN.test(patron);
}

/** Ruta + consulta serializadas por WHATWG URL, sin fragmento. */
export function rutaDe(url: URL): string {
  return url.pathname + url.search;
}

export function mismoOrigen(url: URL, origen: string): boolean {
  if (url.username || url.password) return false;
  return url.origin === new URL(origen).origin;
}

/** ¿Casa `url` con algún patrón de `patrones` bajo `origen`? `prefijo` solo lo
 *  usa el mutante del banco (coincidencia por prefijo, el error típico). */
export function casa(url: string, origen: string, patrones: PatronUrl[], prefijo = false, login = false): boolean {
  let u: URL;
  try {
    u = new URL(url);
  } catch {
    return false;
  }
  if (prefijo) {
    // Mutante: compara solo el pathname y por prefijo; ignora la consulta.
    return u.host === new URL(origen).host &&
      patrones.some((p) => !esAbsoluto(p) && u.pathname.startsWith(p.split("?")[0].replace(/\*.*$/, "")));
  }
  if (u.username || u.password) return false;
  const ruta = rutaDe(u);
  return patrones.some((p) => {
    if (esAbsoluto(p)) {
      let a: { origen: string; ruta: string };
      try { a = partirAbsoluto(p); } catch { return false; }
      return u.origin === a.origen && compilarPatron(p, login).test(ruta);
    }
    return mismoOrigen(u, origen) && compilarPatron(p, login).test(ruta);
  });
}

/** ¿Es `url` una página de inicio de sesión? Patrones relativos estrictos u
 *  orígenes enteros de login federado (SSO). `sinExterno` solo para el mutante. */
export function casaLogin(url: string, origen: string, login: PatronUrl[], prefijo = false, sinExterno = false): boolean {
  const relativos = login.filter((p) => !esOrigenLogin(p));
  if (casa(url, origen, relativos, prefijo, true)) return true;
  if (sinExterno) return false;
  let u: URL;
  try { u = new URL(url); } catch { return false; }
  return login.filter(esOrigenLogin).some((p) => new URL(p).origin === u.origin);
}

/** Origen WebSocket equivalente al origen HTTP de la receta. */
export function origenWs(origen: string): string {
  const u = new URL(origen);
  return u.origin.replace(/^http/, "ws");
}
