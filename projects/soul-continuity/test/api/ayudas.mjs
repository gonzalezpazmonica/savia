import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { validar } from '../lib/schema.mjs';
import { crearMock } from '../mock/servidor.mjs';
import { OPERADORES, textosTerceros } from '../mock/datos.mjs';

export const OPENAPI = JSON.parse(readFileSync(fileURLToPath(new URL('../openapi.json', import.meta.url)), 'utf8'));
export const MIN = 60_000;

export async function arrancar(opts = {}) {
  const mock = crearMock(opts);
  const base = await mock.escuchar();
  return { mock, base, cerrar: () => mock.cerrar() };
}

// Petición como la haría la app: DPoP <token> + cabecera DPoP.
export async function llamar(base, metodo, ruta, { token = 'tok-alfa-1', cuerpo, cabeceras = {}, sinAuth = false } = {}) {
  const h = { ...(sinAuth ? {} : { Authorization: `DPoP ${token}`, DPoP: 'prueba-simulada' }), ...cabeceras };
  if (cuerpo !== undefined) h['Content-Type'] = 'application/json';
  const r = await fetch(base + '/api/v1/soul' + ruta, { method: metodo, headers: h, body: cuerpo === undefined ? undefined : JSON.stringify(cuerpo) });
  const texto = await r.text();
  let json = null;
  try { json = JSON.parse(texto); } catch { /* cuerpo no JSON */ }
  return { status: r.status, json, texto, cabeceras: r.headers };
}

// Esquema de la respuesta documentada para (método, ruta, status), o undefined si no está documentada.
export function esquemaRespuesta(metodo, rutaPlantilla, status) {
  let resp = OPENAPI.paths[rutaPlantilla]?.[metodo.toLowerCase()]?.responses?.[String(status)];
  if (resp?.$ref) resp = resp.$ref.replace(/^#\//, '').split('/').reduce((o, k) => o?.[k], OPENAPI);
  return resp?.content?.['application/json']?.schema;
}

export function conforme(metodo, rutaPlantilla, r) {
  const esq = esquemaRespuesta(metodo, rutaPlantilla, r.status);
  if (!esq) return [`${metodo} ${rutaPlantilla}: status ${r.status} no documentado`];
  return validar(OPENAPI, esq, r.json);
}

// Recorre un JSON y devuelve {inertes: [texto], sueltas: [cadena fuera de TextoInerte]}.
export function cadenas(json) {
  const inertes = [], sueltas = [];
  const ir = (v) => {
    if (typeof v === 'string') sueltas.push(v);
    else if (Array.isArray(v)) v.forEach(ir);
    else if (v && typeof v === 'object') {
      if (v.inerte === true && v.origen === 'tercero' && typeof v.texto === 'string') inertes.push(v.texto);
      else Object.values(v).forEach(ir);
    }
  };
  ir(json);
  return { inertes, sueltas };
}

// ¿Contiene el texto algo de terceros de cualquiera de los operadores?
export function fugas(texto) {
  const halladas = [];
  for (const op of Object.keys(OPERADORES)) {
    const { fijos, prefijos } = textosTerceros(op);
    for (const f of [...fijos, ...prefijos]) if (texto.includes(f)) halladas.push(f);
  }
  return halladas;
}
