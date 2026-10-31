// Validador mínimo de JSON Schema (el subconjunto que usa openapi.json), sin dependencias.
// Fail-closed: una palabra clave de validación que no conoce es un error, no se ignora.
const CONOCIDAS = new Set([
  '$ref', 'type', 'enum', 'const', 'required', 'properties', 'additionalProperties', 'propertyNames',
  'items', 'minItems', 'maxItems', 'uniqueItems', 'minimum', 'maximum', 'minLength', 'maxLength',
  'pattern', 'format', 'oneOf', 'description', 'default', 'title', 'summary',
]);
const FORMATOS = {
  'date-time': (s) => /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?(Z|[+-]\d{2}:\d{2})$/.test(s) && !Number.isNaN(Date.parse(s)),
  uuid: (s) => /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(s),
};

function tipoDe(v) {
  if (v === null) return 'null';
  if (Array.isArray(v)) return 'array';
  if (Number.isInteger(v)) return 'integer';
  return typeof v; // number | string | boolean | object
}

export function validar(raiz, esquema, valor, ruta = '$') {
  const errores = [];
  const ir = (s, v, r) => {
    if (s.$ref) {
      const destino = s.$ref.replace(/^#\//, '').split('/').reduce((o, k) => o?.[k], raiz);
      if (!destino) { errores.push(`${r}: $ref sin resolver ${s.$ref}`); return; }
      ir(destino, v, r);
      return;
    }
    for (const k of Object.keys(s)) if (!CONOCIDAS.has(k)) errores.push(`${r}: palabra clave no soportada «${k}»`);
    if (s.oneOf) {
      const aciertos = s.oneOf.filter((alt) => validar(raiz, alt, v, r).length === 0).length;
      if (aciertos !== 1) errores.push(`${r}: oneOf exige exactamente 1 alternativa y casan ${aciertos}`);
    }
    if ('const' in s && v !== s.const) errores.push(`${r}: debe ser ${JSON.stringify(s.const)}`);
    if (s.enum && !s.enum.includes(v)) errores.push(`${r}: ${JSON.stringify(v)} fuera de enum`);
    if (s.type) {
      const t = tipoDe(v);
      const ok = [].concat(s.type).some((x) => x === t || (x === 'number' && t === 'integer'));
      if (!ok) { errores.push(`${r}: tipo ${t}, se esperaba ${[].concat(s.type).join('|')}`); return; }
    }
    const t = tipoDe(v);
    if (t === 'string') {
      if (s.minLength != null && v.length < s.minLength) errores.push(`${r}: más corto que ${s.minLength}`);
      if (s.maxLength != null && v.length > s.maxLength) errores.push(`${r}: más largo que ${s.maxLength}`);
      if (s.pattern && !new RegExp(s.pattern).test(v)) errores.push(`${r}: no casa ${s.pattern}`);
      if (s.format) {
        if (!FORMATOS[s.format]) errores.push(`${r}: formato no soportado ${s.format}`);
        else if (!FORMATOS[s.format](v)) errores.push(`${r}: formato ${s.format} inválido`);
      }
    }
    if (t === 'integer' || t === 'number') {
      if (s.minimum != null && v < s.minimum) errores.push(`${r}: menor que ${s.minimum}`);
      if (s.maximum != null && v > s.maximum) errores.push(`${r}: mayor que ${s.maximum}`);
    }
    if (t === 'array') {
      if (s.minItems != null && v.length < s.minItems) errores.push(`${r}: menos de ${s.minItems} elementos`);
      if (s.maxItems != null && v.length > s.maxItems) errores.push(`${r}: más de ${s.maxItems} elementos`);
      if (s.uniqueItems && new Set(v.map((x) => JSON.stringify(x))).size !== v.length) errores.push(`${r}: elementos repetidos`);
      if (s.items) v.forEach((x, i) => ir(s.items, x, `${r}[${i}]`));
    }
    if (t === 'object') {
      for (const k of s.required ?? []) if (!(k in v)) errores.push(`${r}: falta «${k}»`);
      for (const [k, x] of Object.entries(v)) {
        if (s.propertyNames) ir(s.propertyNames, k, `${r}.«${k}»`);
        if (s.properties?.[k]) ir(s.properties[k], x, `${r}.${k}`);
        else if (s.additionalProperties === false) errores.push(`${r}: propiedad no declarada «${k}»`);
        else if (s.additionalProperties && typeof s.additionalProperties === 'object') ir(s.additionalProperties, x, `${r}.${k}`);
      }
    }
  };
  ir(esquema, valor, ruta);
  return errores;
}
