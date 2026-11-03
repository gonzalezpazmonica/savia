/**
 * El núcleo del producto bajo el banco de continuidad (`npm run bench`), con los adaptadores
 * reales de API (`src/adapters`) contra los dobles del banco (AC-3).
 *
 * - Rutas de API: los adaptadores del producto, que hablan con los dobles por `Transport`.
 * - Rutas web (adaptador `web` y la ruta `web` de Microsoft 365): los adaptadores de referencia
 *   del banco. El adaptador web real necesita un navegador y tiene su propia batería (AC-4e,
 *   `src/web/bench`), que este banco no sustituye.
 *
 * `reference: true` mide el núcleo solo con los adaptadores de referencia (el control).
 */

import type { AdapterContext, SourceAdapter } from "../contract/adapter.ts";
import { makeAdapters } from "../../bench/src/reference/adapters.ts";
import { makeApiAdapters } from "../adapters/index.ts";
import { makeEngine } from "./engine.ts";
import type { AdapterRegistry } from "./engine.ts";

/** Un adaptador por nombre que reparte por ruta: la del producto o, si no la tiene, la de referencia. */
function byRoute(real: SourceAdapter | undefined, ref: SourceAdapter | undefined): SourceAdapter | undefined {
  if (!real) return ref;
  if (!ref) return real;
  return {
    name: real.name, purpose: real.purpose, routes: [...new Set([...real.routes, ...ref.routes])],
    read: (ctx: AdapterContext) => (real.routes.includes(ctx.route) ? real : ref).read(ctx),
  };
}

export function benchRegistry(o: { reference?: boolean } = {}): AdapterRegistry {
  const ref = makeAdapters({});
  if (o.reference) return ref;
  // Los dobles firman Gmail como `mx.google.example` (dominio reservado de pruebas).
  const real: Record<string, SourceAdapter> = makeApiAdapters({ gmailAuthservIds: ["mx.google.example"] });
  // Los dobles del banco no sirven `/me` y en ellos el id de Teams es el correo: se da como
  // `m365_user_id`, igual que lo configuraría el operador (como el arnés de test/adapters).
  const teams = real["m365-teams"];
  if (teams) {
    real["m365-teams"] = {
      ...teams,
      read: (ctx) => {
        const email = ctx.operator.identities.emails[0];
        if (ctx.params.m365_user_id !== undefined || !email) return teams.read(ctx);
        return teams.read({ ...ctx, params: { ...ctx.params, m365_user_id: email } });
      },
    };
  }
  const out: AdapterRegistry = {};
  for (const name of new Set([...Object.keys(ref), ...Object.keys(real)])) {
    const a = byRoute(real[name], ref[name]);
    if (a) out[name] = a;
  }
  return out;
}

export default function impl(o: { reference?: boolean } = {}) {
  return makeEngine(benchRegistry(o), o.reference ? "soul-core-referencia" : "soul-core");
}
