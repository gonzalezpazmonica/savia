/**
 * El núcleo del producto bajo el banco de continuidad (`npm run bench`).
 *
 * Usa los adaptadores de referencia del banco mientras los adaptadores del producto
 * (parte `adapters` de SE-490) no estén integrados: así se mide el núcleo (libro, TTL,
 * aislamiento, niveles, Q1–Q4) con el mismo runner y los mismos dobles.
 */

import { makeAdapters } from "../../bench/src/reference/adapters.ts";
import { makeEngine } from "./engine.ts";

export default function impl() {
  return makeEngine(makeAdapters({}), "soul-core");
}
