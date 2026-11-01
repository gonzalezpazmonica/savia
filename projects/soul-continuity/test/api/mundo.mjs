// Mundo simulado de Labs (api-movil) como fixture: dos operadores sintéticos cuyos elementos nacen,
// alertan y se reobservan con el reloj virtual. Es la parte «mundo» del antiguo servidor simulado;
// la API que se prueba es la del producto (src/api/server.ts).
import { OPERADORES, PLANTILLAS } from './datos.mjs';

const MIN = 60_000;
const CATEGORIA = { reunion: 'reunion_proxima', tarea: 'vencimiento', documento: 'documento_sin_leer', hilo_espera: 'espera_respuesta' };

export const mundoSimulado = {
  semillas: () => Object.values(structuredClone(OPERADORES)),
  paso(ctx, o, i, t) {
    if (i % 3 === 0) nace(ctx, o, i, t);
    if (i % 7 === 0 && o.alertas.length) alerta(ctx, o, i, t);
    if (i % 11 === 0) reobserva(o, i, t);
  },
};

function nace(ctx, o, i, t) {
  const pl = PLANTILLAS[o.ref], p = pl[(i / 3) % pl.length], id = `g-${o.ref}-${i}`;
  const e = { id, tipo: p.tipo, titulo: p.titulo.replace('{n}', String(i)), proyecto: p.proyecto, personas: [], detalle: null, adaptador: p.adaptador, ruta: p.ruta,
    dep: p.dep, fecha: p.fechaMin == null ? null : t + p.fechaMin * MIN, nace: t, observado: t, estado: 'OBSERVED', sens: 'N4', refs: [], mio: false, noMio: false, fijo: false };
  o.elementos.set(id, e);
  const cat = CATEGORIA[p.tipo];
  if (cat) ctx.evento(o, { tipo: 'aviso', categoria: cat, ids: [id], programar: cat === 'reunion_proxima' && e.fecha - 15 * MIN > t ? e.fecha - 15 * MIN : null }, t);
}
function alerta(ctx, o, i, t) {
  const regla = o.alertas[(i / 7) % o.alertas.length];
  const vivos = [...o.elementos.values()].filter((e) => !o.ledger.has(e.id));
  const casa = vivos.find((e) => (regla.tipo === 'proyecto' ? e.proyecto === regla.objetivo : e.personas.includes(regla.objetivo))) ?? vivos.at(-1);
  ctx.evento(o, { tipo: 'alerta', regla, efectiva: ctx.efectiva(o, regla).efectiva, ids: casa ? [casa.id] : [] }, t);
}
function reobserva(o, i, t) { // la fuente repite hechos; los revocados no vuelven
  const fijos = o.d.elementos, id = fijos[(i / 11 - 1) % fijos.length].id;
  o.st.reobservaciones++;
  if (o.ledger.has(id)) { o.st.rebotadas++; return; }
  o.elementos.get(id).observado = t;
}
