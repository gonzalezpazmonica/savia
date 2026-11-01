import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { request } from 'node:https';
import { validar } from '../../src/api/schema.ts';
import { makeSelfSigned } from '../../src/api/cert.ts';
import { crearServidor } from '../../src/api/server.ts';
import { mundoSimulado } from './mundo.mjs';
import { INICIO, OPERADORES, textosTerceros } from './datos.mjs';

// Adaptado de Labs: el servidor es el del producto (TLS, solo en la dirección dada) con el mundo simulado.
export const OPENAPI = JSON.parse(readFileSync(fileURLToPath(new URL('../../src/contract/openapi.json', import.meta.url)), 'utf8'));
export const MIN = 60_000;
const TLS = makeSelfSigned(['127.0.0.1'], new Date(INICIO));

export async function arrancar(opts = {}) {
  const mock = crearServidor({ ahora: INICIO, ...opts, tls: TLS, mundo: mundoSimulado });
  const l = await mock.escuchar(['127.0.0.1'], 0);
  return { mock, base: `https://127.0.0.1:${l.port}`, cerrar: () => mock.cerrar() };
}

// Petición como la haría la app: DPoP <token> + cabecera DPoP, por TLS con el certificado fijado.
export function llamar(base, metodo, ruta, { token = 'tok-alfa-1', cuerpo, cabeceras = {}, sinAuth = false } = {}) {
  const h = { ...(sinAuth ? {} : { Authorization: `DPoP ${token}`, DPoP: 'prueba-simulada' }), ...cabeceras };
  if (cuerpo !== undefined) h['Content-Type'] = 'application/json';
  const u = new URL(base + '/api/v1/soul' + ruta);
  return new Promise((res, rej) => {
    const q = request({ host: u.hostname, port: u.port, path: u.pathname + u.search, method: metodo, headers: h, ca: TLS.cert }, (r) => {
      let texto = '';
      r.setEncoding('utf8');
      r.on('data', (d) => { texto += d; });
      r.on('end', () => {
        let json = null;
        try { json = JSON.parse(texto); } catch { /* cuerpo no JSON */ }
        res({ status: r.statusCode, json, texto, cabeceras: { get: (k) => r.headers[k.toLowerCase()] ?? null } });
      });
    });
    q.on('error', rej);
    q.end(cuerpo === undefined ? undefined : JSON.stringify(cuerpo));
  });
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
