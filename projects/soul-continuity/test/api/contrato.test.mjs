import test from 'node:test';
import assert from 'node:assert/strict';
import { validar } from '../lib/schema.mjs';
import { OPENAPI, MIN, arrancar, llamar, conforme, esquemaRespuesta, cadenas, fugas } from './ayudas.mjs';
import { OPERADORES, CARGAS } from '../mock/datos.mjs';

const GET = (b, r, o) => llamar(b, 'GET', r, o);
const ids = (j) => j.elementos.map((e) => e.id);

// ---------------------------------------------------------------- el propio contrato y el validador
test('openapi: 3.1, todos los $ref resuelven y cada operación declara 401', () => {
  assert.equal(OPENAPI.openapi, '3.1.0');
  const refs = [...JSON.stringify(OPENAPI).matchAll(/"\$ref":"([^"]+)"/g)].map((m) => m[1]);
  assert.ok(refs.length > 40);
  for (const r of refs) assert.ok(r.replace(/^#\//, '').split('/').reduce((o, k) => o?.[k], OPENAPI), `$ref roto ${r}`);
  for (const [ruta, ops] of Object.entries(OPENAPI.paths)) {
    for (const [m, op] of Object.entries(ops)) {
      assert.ok(op.operationId, `${m} ${ruta} sin operationId`);
      assert.ok(op.responses['401'], `${m} ${ruta} sin 401`);
    }
  }
});

test('validador: rechaza lo que el esquema prohíbe (el test de conformidad puede fallar)', () => {
  const S = (n) => OPENAPI.components.schemas[n];
  const ok = { texto: 'x', inerte: true, origen: 'tercero' };
  assert.deepEqual(validar(OPENAPI, S('TextoInerte'), ok), []);
  assert.ok(validar(OPENAPI, S('TextoInerte'), { ...ok, inerte: false }).length);
  assert.ok(validar(OPENAPI, S('TextoInerte'), { texto: 'x' }).length);
  assert.ok(validar(OPENAPI, S('TextoInerte'), { ...ok, extra: 1 }).length);
  assert.ok(validar(OPENAPI, S('Detalle'), { nivel: 'todo', maximo: 'completo' }).length);
  assert.ok(validar(OPENAPI, S('Atencion'), { modo: 'FOCO', hasta: 'mañana', vuelve_a: 'DISPONIBLE' }).length);
  assert.ok(validar(OPENAPI, { oneOf: [{ type: 'string' }, { type: 'string' }] }, 'a').length, 'oneOf ambiguo');
  assert.ok(validar(OPENAPI, { type: 'string', foo: 1 }, 'a').length, 'palabra clave desconocida = error');
});

// ---------------------------------------------------------------- conformidad del servidor simulado
test('el servidor simulado cumple el OpenAPI en todas las operaciones y solo sirve lo documentado', async () => {
  const { mock, base, cerrar } = await arrancar();
  try {
    mock.avanzar(20 * MIN);
    const vistas = new Set();
    const caso = async (metodo, plantilla, ruta, esperado, opts) => {
      const r = await llamar(base, metodo, ruta, opts);
      assert.equal(r.status, esperado, `${metodo} ${ruta}: ${r.texto.slice(0, 200)}`);
      assert.deepEqual(conforme(metodo, plantilla, r), [], `${metodo} ${ruta}`);
      vistas.add(OPENAPI.paths[plantilla][metodo.toLowerCase()].operationId);
      return r;
    };
    await caso('GET', '/estado', '/estado', 200);
    for (const q of ['q1', 'q2', 'q4']) await caso('GET', '/q/{pregunta}', `/q/${q}`, 200);
    await caso('GET', '/q/{pregunta}', '/q/q3?desde=2026-10-30T00:00:00Z', 200);
    await caso('GET', '/q/{pregunta}', '/q/q3', 400);
    await caso('GET', '/q/{pregunta}', '/q/q9', 400);
    await caso('GET', '/filtros', '/filtros', 200);
    await caso('GET', '/elementos/{id}/porque', '/elementos/e-2/porque', 200);
    await caso('GET', '/elementos/{id}/porque', '/elementos/no-existe/porque', 404);
    await caso('POST', '/elementos/{id}/correccion', '/elementos/e-6/correccion', 200, { cuerpo: { tipo: 'es_mio' } });
    await caso('POST', '/elementos/{id}/correccion', '/elementos/e-6/correccion', 400, { cuerpo: { tipo: 'borrar' } });
    await caso('POST', '/elementos/{id}/correccion', '/elementos/nada/correccion', 404, { cuerpo: { tipo: 'resuelto' } });
    await caso('GET', '/atencion', '/atencion', 200);
    const hasta = new Date(mock.ahora() + 2 * 60 * MIN).toISOString();
    await caso('PUT', '/atencion', '/atencion', 200, { cuerpo: { modo: 'FOCO', hasta } });
    await caso('PUT', '/atencion', '/atencion', 400, { cuerpo: { modo: 'FOCO' } });
    const av = (await caso('GET', '/avisos', '/avisos', 200)).json;
    const { alertas, ...resto } = av;
    const peticion = { ...resto, alertas: alertas.map(({ efectiva, nota, ...a }) => a) };
    await caso('PUT', '/avisos', '/avisos', 200, { cuerpo: peticion });
    await caso('PUT', '/avisos', '/avisos', 400, { cuerpo: { ...peticion, tope_alertas: 0 } });
    await caso('GET', '/sondeo', '/sondeo?limite=5', 200);
    await caso('GET', '/sondeo', '/sondeo?cursor=basura', 400);
    await caso('GET', '/adaptadores', '/adaptadores', 200);
    await caso('GET', '/detalle', '/detalle', 200);
    await caso('PUT', '/detalle', '/detalle', 200, { cuerpo: { nivel: 'recuentos' } });
    await caso('PUT', '/detalle', '/detalle', 400, { cuerpo: { nivel: 'otro' } });
    await caso('PUT', '/detalle', '/detalle', 422, { cuerpo: { nivel: 'completo' }, token: 'tok-beta-1' });
    await caso('GET', '/registro', '/registro', 200);
    await caso('POST', '/ordenes', '/ordenes', 200, { cuerpo: { orden: 'q1' } });
    await caso('POST', '/ordenes', '/ordenes', 200, { cuerpo: { orden: 'hola, ¿qué tengo hoy?' } });
    await caso('POST', '/ordenes', '/ordenes', 400, { cuerpo: { orden: '' } });
    await caso('POST', '/ordenes', '/ordenes', 404, { cuerpo: { orden: 'porque no-existe' } });
    await caso('GET', '/estado', '/estado', 401, { sinAuth: true });

    const todas = Object.values(OPENAPI.paths).flatMap((o) => Object.values(o).map((op) => op.operationId));
    assert.deepEqual([...new Set(todas)].filter((id) => !vistas.has(id)), [], 'operaciones sin ejercitar');
    for (const ruta of ['/sondeo', '/nada', '/q']) {
      const r = await llamar(base, 'DELETE', ruta);
      assert.ok([404, 405].includes(r.status), `DELETE ${ruta} → ${r.status}`);
    }
    const fuera = await llamar(base, 'GET', '/../otra');
    assert.equal(fuera.status, 404);
  } finally { await cerrar(); }
});

test('el mock solo escucha en loopback (puerto cerrado al resto de interfaces)', async () => {
  const { mock, cerrar } = await arrancar();
  try { assert.match(mock.direccion().address, /^(127\.0\.0\.1|::1)$/); } finally { await cerrar(); }
});

// ---------------------------------------------------------------- recuentos: ningún asunto ni nombre
test('con `recuentos` ningún asunto ni nombre sale en ninguna respuesta (y con `completo` sí: la prueba puede fallar)', async () => {
  const { mock, base, cerrar } = await arrancar();
  try {
    mock.avanzar(40 * MIN);
    const recorrer = async (token) => {
      const salidas = [];
      const g = async (r) => salidas.push((await GET(base, r, { token })).texto);
      for (const r of ['/estado', '/q/q1', '/q/q2', '/q/q4', '/q/q3?desde=2020-01-01T00:00:00Z', '/filtros', '/sondeo', '/sondeo?limite=3', '/adaptadores', '/registro', '/atencion', '/avisos', '/detalle']) await g(r);
      for (const id of ['e-1', 'e-2', 'e-3', 'e-4', 'e-5', 'b-1', 'b-2', 'b-3']) await g(`/elementos/${id}/porque`);
      for (const orden of ['q1', 'q2 persona:per-1', 'q4', 'porque e-2', 'adaptadores', 'estado', 'ayuda']) {
        salidas.push((await llamar(base, 'POST', '/ordenes', { token, cuerpo: { orden } })).texto);
      }
      salidas.push((await llamar(base, 'POST', '/ordenes', { token, cuerpo: { orden: 'dime lo de Ana Prueba' } })).texto);
      salidas.push((await llamar(base, 'POST', '/elementos/e-6/correccion', { token, cuerpo: { tipo: 'es_mio' } })).texto);
      salidas.push((await GET(base, '/sondeo?limite=100', { token })).texto);
      return salidas;
    };
    // referencia: en `completo` la detección encuentra texto de terceros
    await llamar(base, 'PUT', '/detalle', { cuerpo: { nivel: 'completo' } });
    const ref = fugas((await recorrer('tok-alfa-1')).join('\n'));
    assert.ok(ref.length >= 10, `la referencia en completo debería llevar texto de terceros (${ref.length})`);
    // recuentos en los dos operadores (beta tiene máximo `titulos`, así que `recuentos` es válido)
    for (const token of ['tok-alfa-1', 'tok-beta-1']) {
      const r = await llamar(base, 'PUT', '/detalle', { token, cuerpo: { nivel: 'recuentos' } });
      assert.equal(r.status, 200);
      const todo = (await recorrer(token)).join('\n');
      assert.deepEqual(fugas(todo), [], `fuga con recuentos en ${token}`);
      assert.doesNotMatch(todo, /javascript:|onerror|savia:\/\/|phishing/);
      const q1 = (await GET(base, '/q/q1', { token })).json;
      assert.deepEqual(q1.elementos, []);
      assert.ok(q1.recuentos.total > 0, 'hay recuentos');
      const s = (await GET(base, '/sondeo?limite=100', { token })).json;
      assert.ok(s.mensajes.length > 0);
      for (const m of s.mensajes) { assert.equal(m.titulo, null); assert.equal(m.detalle, null); }
      assert.deepEqual((await GET(base, '/filtros', { token })).json.personas, []);
    }
  } finally { await cerrar(); }
});

test('con `titulos` no salen personas, detalle ni proyecto; sí el asunto y la fuente', async () => {
  const { base, cerrar } = await arrancar();
  try {
    const q = (await GET(base, '/q/q1')).json;
    assert.equal(q.nivel, 'titulos');
    assert.ok(q.elementos.length > 0);
    for (const e of q.elementos) {
      assert.ok(e.titulo?.texto && e.fuente.adaptador);
      assert.deepEqual(e.personas, []); assert.equal(e.detalle, null); assert.equal(e.proyecto, null);
    }
    const t = JSON.stringify((await GET(base, '/q/q2')).json) + JSON.stringify((await GET(base, '/sondeo?limite=100')).json);
    assert.doesNotMatch(t, /Ana Prueba|Luis Muestra|Proyecto Cobalto|Hilo con 3 mensajes/);
  } finally { await cerrar(); }
});

// ---------------------------------------------------------------- texto inerte
test('todo texto de terceros va como TextoInerte; las cargas de inyección llegan marcadas y nunca sueltas', async () => {
  const { mock, base, cerrar } = await arrancar();
  try {
    await llamar(base, 'PUT', '/detalle', { cuerpo: { nivel: 'completo' } });
    mock.avanzar(30 * MIN);
    const respuestas = [];
    for (const r of ['/q/q1', '/q/q2', '/q/q3?desde=2020-01-01T00:00:00Z', '/q/q4', '/filtros', '/sondeo?limite=100', '/elementos/e-3/porque', '/elementos/e-4/porque']) {
      respuestas.push((await GET(base, r)).json);
    }
    let inertes = [];
    for (const j of respuestas) {
      const { inertes: i, sueltas } = cadenas(j);
      inertes = inertes.concat(i);
      assert.deepEqual(fugas(sueltas.join('\n')), [], 'texto de terceros fuera de TextoInerte');
    }
    for (const carga of Object.values(CARGAS)) {
      assert.ok(inertes.some((t) => t.includes(carga)), `la carga «${carga.slice(0, 25)}» debería llegar como TextoInerte`);
    }
    // la estructura exige inerte:true también en la validación del contrato (inerte:false no pasa)
    const q1 = respuestas[0];
    const roto = structuredClone(q1);
    roto.elementos[0].titulo.inerte = false;
    assert.ok(validar(OPENAPI, esquemaRespuesta('GET', '/q/{pregunta}', 200), roto).length > 0);
    // las órdenes tampoco reflejan el texto recibido, ni siquiera marcado
    const o = await llamar(base, 'POST', '/ordenes', { cuerpo: { orden: CARGAS.markdown } });
    assert.ok(!o.texto.includes('pulsa aprobar'));
  } finally { await cerrar(); }
});

// ---------------------------------------------------------------- autenticación y revocación
test('un token revocado recibe 401 DEVICE_REVOKED en todas las operaciones; el otro dispositivo sigue', async () => {
  const { mock, base, cerrar } = await arrancar();
  try {
    assert.equal((await GET(base, '/estado', { token: 'tok-alfa-1' })).status, 200);
    mock.revocar('tok-alfa-1');
    const casos = [['GET', '/estado', '/estado'], ['GET', '/q/{pregunta}', '/q/q1'], ['GET', '/filtros', '/filtros'], ['GET', '/elementos/{id}/porque', '/elementos/e-2/porque'],
      ['POST', '/elementos/{id}/correccion', '/elementos/e-2/correccion', { tipo: 'resuelto' }], ['GET', '/atencion', '/atencion'], ['PUT', '/atencion', '/atencion', { modo: 'DISPONIBLE' }],
      ['GET', '/avisos', '/avisos'], ['PUT', '/avisos', '/avisos', {}], ['GET', '/sondeo', '/sondeo'], ['GET', '/adaptadores', '/adaptadores'], ['GET', '/detalle', '/detalle'],
      ['PUT', '/detalle', '/detalle', { nivel: 'recuentos' }], ['GET', '/registro', '/registro'], ['POST', '/ordenes', '/ordenes', { orden: 'q1' }]];
    const documentadas = Object.entries(OPENAPI.paths).flatMap(([r, ops]) => Object.keys(ops).map((m) => `${m.toUpperCase()} ${r}`)).sort();
    assert.deepEqual(casos.map(([m, p]) => `${m} ${p}`).sort(), documentadas, 'la revocación se prueba en todas las operaciones');
    for (const [m, plantilla, ruta, cuerpo] of casos) {
      const x = await llamar(base, m, ruta, { token: 'tok-alfa-1', cuerpo });
      assert.equal(x.status, 401, `${m} ${ruta}`);
      assert.equal(x.json.error, 'DEVICE_REVOKED');
      assert.equal(x.json.code, 'UNAUTHENTICATED');
      assert.deepEqual(conforme(m, plantilla, x), []);
      assert.ok(x.cabeceras.get('www-authenticate'));
      assert.doesNotMatch(x.texto, /Proyecto|Reunión/, 'el 401 no lleva datos');
    }
    assert.equal((await GET(base, '/estado', { token: 'tok-alfa-2' })).status, 200, 'otro dispositivo del mismo operador sigue');
    assert.equal((await GET(base, '/estado', { token: 'tok-beta-1' })).status, 200);
  } finally { await cerrar(); }
});

test('401 genérico (sin DEVICE_REVOKED) para token desconocido, sin cabecera, esquema Bearer, sin prueba DPoP y token caducado', async () => {
  const { mock, base, cerrar } = await arrancar({ caducidadToken: true });
  try {
    const casos = [
      await GET(base, '/estado', { token: 'tok-inventado' }),
      await GET(base, '/estado', { sinAuth: true }),
      await GET(base, '/estado', { sinAuth: true, cabeceras: { Authorization: 'Bearer tok-alfa-1', DPoP: 'x' } }),
      await GET(base, '/estado', { sinAuth: true, cabeceras: { Authorization: 'DPoP tok-alfa-1' } }),
    ];
    mock.avanzar(301_000); // el token dura 300 s, como en Space
    casos.push(await GET(base, '/estado', { token: 'tok-alfa-1' }));
    for (const c of casos) {
      assert.equal(c.status, 401);
      assert.equal(c.json.error, undefined, 'solo la revocación lleva DEVICE_REVOKED');
      assert.equal(c.json.code, 'UNAUTHENTICATED');
    }
    mock.renovar('tok-alfa-1'); // la renovación (POST /api/v1/token en Space) la hace el emisor, no este contrato
    assert.equal((await GET(base, '/estado')).status, 200);
  } finally { await cerrar(); }
});

test('un operador no ve ni toca nada del otro (404 como si no existiera)', async () => {
  const { mock, base, cerrar } = await arrancar();
  try {
    mock.avanzar(30 * MIN);
    assert.equal((await GET(base, '/elementos/b-1/porque', { token: 'tok-alfa-1' })).status, 404);
    assert.equal((await GET(base, '/elementos/e-1/porque', { token: 'tok-beta-1' })).status, 404);
    assert.equal((await llamar(base, 'POST', '/elementos/e-1/correccion', { token: 'tok-beta-1', cuerpo: { tipo: 'resuelto' } })).status, 404);
    assert.equal((await GET(base, '/q/q1?proyecto=p-alfa', { token: 'tok-beta-1' })).json.elementos.length, 0);
    const a = (await GET(base, '/sondeo?limite=100', { token: 'tok-alfa-1' })).json;
    const b = (await GET(base, '/sondeo?limite=100', { token: 'tok-beta-1' })).json;
    const idsA = new Set(a.mensajes.flatMap((m) => [m.id, ...m.elemento_ids]));
    assert.ok(b.mensajes.every((m) => ![m.id, ...m.elemento_ids].some((i) => idsA.has(i))));
    const q = JSON.stringify((await GET(base, '/q/q1', { token: 'tok-beta-1' })).json);
    assert.doesNotMatch(q, /Cobalto|Ámbar|Ana Prueba/);
  } finally { await cerrar(); }
});

test('límite de peticiones: 429 con Retry-After', async () => {
  const { base, cerrar } = await arrancar({ peticionesPorVentana: 3 });
  try {
    const st = [];
    for (let i = 0; i < 5; i++) st.push(await GET(base, '/estado'));
    assert.deepEqual(st.map((r) => r.status), [200, 200, 200, 429, 429]);
    assert.ok(Number(st[3].cabeceras.get('retry-after')) >= 1);
    assert.deepEqual(conforme('GET', '/estado', st[3]), []);
  } finally { await cerrar(); }
});

// ---------------------------------------------------------------- sondeo y cursor
async function drenar(base, cursor, limite, token = 'tok-alfa-1') {
  const mensajes = []; let c = cursor, paginas = 0;
  for (;;) {
    const r = await GET(base, `/sondeo?limite=${limite}${c ? `&cursor=${encodeURIComponent(c)}` : ''}`, { token });
    assert.equal(r.status, 200, r.texto);
    assert.deepEqual(conforme('GET', '/sondeo', r), []);
    mensajes.push(...r.json.mensajes); c = r.json.cursor; paginas++;
    assert.ok(paginas < 500);
    if (!r.json.hay_mas) return { mensajes, cursor: c, paginas };
  }
}

test('el sondeo cambia con el tiempo y el cursor ni pierde ni duplica mensajes', async () => {
  const { mock, base, cerrar } = await arrancar();
  try {
    const q0 = (await GET(base, '/q/q1')).json.recuentos.total;
    const ini = await drenar(base, null, 4);
    // 3 horas en pasos de 5 minutos, sondeando con páginas pequeñas
    let cursor = ini.cursor; const recibidos = [...ini.mensajes];
    for (let i = 0; i < 36; i++) {
      mock.avanzar(5 * MIN);
      const d = await drenar(base, cursor, 3);
      recibidos.push(...d.mensajes); cursor = d.cursor;
    }
    assert.ok(recibidos.length > ini.mensajes.length + 10, 'el sondeo devuelve mensajes nuevos con el tiempo');
    assert.notEqual((await GET(base, '/q/q1')).json.recuentos.total, q0, 'Q1 cambia con el tiempo');
    const idsRec = recibidos.map((m) => m.id);
    assert.equal(new Set(idsRec).size, idsRec.length, 'sin duplicados');
    assert.deepEqual(recibidos.map((m) => m.seq), recibidos.map((_, i) => i + 1), 'seq contiguo desde 1: sin huecos');
    // referencia: un sondeo sin cursor y con página grande devuelve exactamente lo mismo
    const todo = await drenar(base, null, 100);
    assert.deepEqual(todo.mensajes.map((m) => m.id), idsRec);
    // sin mensajes nuevos: vacío, mismo cursor semántico, y repetir no consume nada
    const a = (await GET(base, `/sondeo?cursor=${encodeURIComponent(cursor)}`)).json;
    const b = (await GET(base, `/sondeo?cursor=${encodeURIComponent(cursor)}`)).json;
    assert.deepEqual(a.mensajes, []); assert.equal(a.hay_mas, false); assert.equal(b.cursor, a.cursor);
    // un cursor antiguo reentrega exactamente lo posterior (idempotente)
    const mitad = recibidos[Math.floor(recibidos.length / 2)];
    const c1 = (await GET(base, `/sondeo?limite=1&cursor=${encodeURIComponent(ini.cursor)}`)).json;
    const re = await drenar(base, ini.cursor, 7);
    assert.deepEqual(re.mensajes.map((m) => m.id), recibidos.slice(ini.mensajes.length).map((m) => m.id));
    assert.ok(c1.hay_mas && mitad);
    assert.equal(a.siguiente_sondeo_s, 300);
  } finally { await cerrar(); }
});

test('el cursor sobrevive a un cambio de nivel y los mensajes se pintan con el nivel vigente al leer', async () => {
  const { mock, base, cerrar } = await arrancar();
  try {
    mock.avanzar(30 * MIN);
    const p1 = (await GET(base, '/sondeo?limite=3')).json;
    await llamar(base, 'PUT', '/detalle', { cuerpo: { nivel: 'recuentos' } });
    mock.avanzar(30 * MIN);
    const resto = await drenar(base, p1.cursor, 50);
    assert.ok(resto.mensajes.length > 0);
    assert.ok(resto.mensajes.every((m) => m.titulo === null && m.detalle === null));
    assert.equal(resto.mensajes[0].seq, p1.mensajes.at(-1).seq + 1);
  } finally { await cerrar(); }
});

test('cursor ajeno, manipulado o anterior a lo retenido: 400 y 410, nunca datos', async () => {
  const { mock, base, cerrar } = await arrancar({ retencionMs: 60 * MIN });
  try {
    mock.avanzar(20 * MIN);
    const viejo = (await GET(base, '/sondeo?limite=1')).json.cursor;
    const deBeta = (await GET(base, '/sondeo?limite=1', { token: 'tok-beta-1' })).json.cursor;
    for (const c of [deBeta, viejo.replace(/.$/, 'x'), 'c1.-3.aaaa', 'c1.99999.aaaaaaaa', '..', 'a'.repeat(200)]) {
      const r = await GET(base, `/sondeo?cursor=${encodeURIComponent(c)}`);
      assert.equal(r.status, 400, c);
      assert.deepEqual(conforme('GET', '/sondeo', r), []);
    }
    mock.avanzar(5 * 60 * MIN); // pasa la retención: lo viejo se purga
    const r = await GET(base, `/sondeo?cursor=${encodeURIComponent(viejo)}`);
    assert.equal(r.status, 410); assert.equal(r.json.code, 'GONE');
    assert.deepEqual(conforme('GET', '/sondeo', r), []);
    const de0 = await drenar(base, null, 100);
    assert.ok(de0.mensajes.every((m) => Date.parse(m.creado_en) >= mock.ahora() - 60 * MIN), 'solo lo retenido');
  } finally { await cerrar(); }
});

// ---------------------------------------------------------------- consultas y filtros
test('Q1–Q4 con filtros: proyecto, persona, desde/hasta, limite', async () => {
  const { base, cerrar } = await arrancar();
  try {
    await llamar(base, 'PUT', '/detalle', { cuerpo: { nivel: 'completo' } });
    const q1 = (await GET(base, '/q/q1')).json;
    const q1p = (await GET(base, '/q/q1?proyecto=p-alfa')).json;
    assert.ok(q1p.elementos.length > 0 && q1p.elementos.length < q1.elementos.length);
    assert.ok(q1p.elementos.every((e) => e.proyecto.texto === 'Proyecto Cobalto'));
    assert.equal(q1p.recuentos.total, q1p.elementos.length);
    const q1a = (await GET(base, '/q/q1?persona=per-1')).json;
    assert.ok(q1a.elementos.length > 0 && q1a.elementos.every((e) => e.personas.some((p) => p.texto === 'Ana Prueba')));
    assert.equal((await GET(base, '/q/q1?limite=2')).json.elementos.length, 2);
    assert.equal((await GET(base, '/q/q1?limite=0')).status, 400);
    assert.equal((await GET(base, '/q/q1?proyecto=../x')).status, 400);
    const q2 = (await GET(base, '/q/q2')).json;
    assert.ok(q2.elementos.length > 0 && ids(q2).every((i) => ['e-1', 'e-3', 'e-4', 'e-6', 'e-9', 'e-12'].includes(i) || i.startsWith('g-')));
    // Q3: dos instantes
    const reciente = (await GET(base, '/q/q3?desde=2026-10-31T07:00:00Z')).json;
    const todo = (await GET(base, '/q/q3?desde=2026-10-01T00:00:00Z')).json;
    assert.ok(todo.elementos.length > reciente.elementos.length);
    assert.ok(ids(todo).includes('e-10') && !ids(reciente).includes('e-10'));
    assert.equal((await GET(base, '/q/q3?desde=2026-10-31T07:00:00Z&hasta=2026-10-31T06:00:00Z')).status, 400, 'hasta anterior a desde');
    assert.equal((await GET(base, '/q/q1?desde=2026-10-31T07:00:00Z')).status, 400, 'desde solo en Q3/Q4');
    // Q4: solo con fecha, y la ventana acota
    const q4 = (await GET(base, '/q/q4')).json;
    assert.ok(q4.elementos.length >= 5 && q4.elementos.every((e) => e.fecha));
    const q4h = (await GET(base, '/q/q4?hasta=2026-10-31T12:00:00Z')).json;
    assert.ok(q4h.elementos.length < q4.elementos.length && q4h.elementos.every((e) => Date.parse(e.fecha) <= Date.parse('2026-10-31T12:00:00Z')));
    assert.ok(q4.elementos.every((e) => ['tarea', 'reunion', 'compromiso'].includes(e.tipo)), 'solo compromisos estructurados');
  } finally { await cerrar(); }
});

test('«¿por qué lo sé?»: fuente, antigüedad que crece, validez; con recuentos sin referencias', async () => {
  const { mock, base, cerrar } = await arrancar();
  try {
    await llamar(base, 'PUT', '/detalle', { cuerpo: { nivel: 'completo' } });
    const a = (await GET(base, '/elementos/e-2/porque')).json;
    assert.equal(a.fuente.adaptador, 'm365-calendar'); assert.equal(a.fuente.ruta, 'graph');
    assert.deepEqual(a.referencias.map((r) => r.texto), ['evento-cal-7']);
    mock.avanzar(10 * MIN);
    const b = (await GET(base, '/elementos/e-2/porque')).json;
    assert.ok(b.antiguedad_s >= a.antiguedad_s + 600);
    assert.ok(Date.parse(b.valido_hasta) > Date.parse(b.observado_en));
    await llamar(base, 'PUT', '/detalle', { cuerpo: { nivel: 'recuentos' } });
    const c = (await GET(base, '/elementos/e-2/porque')).json;
    assert.deepEqual(c.referencias, []); assert.equal(c.fuente.adaptador, 'm365-calendar');
  } finally { await cerrar(); }
});

// ---------------------------------------------------------------- correcciones
test('correcciones: resuelto y no aplica no vuelven aunque la fuente repita el hecho; es_mio / no_es_mio; idempotencia; respuesta por sondeo', async () => {
  const { mock, base, cerrar } = await arrancar();
  try {
    await llamar(base, 'PUT', '/detalle', { cuerpo: { nivel: 'completo' } });
    const corr = (id, tipo) => llamar(base, 'POST', `/elementos/${id}/correccion`, { cuerpo: { tipo } });
    const antes = ids((await GET(base, '/q/q1')).json);
    assert.ok(['e-1', 'e-2', 'e-5'].every((i) => antes.includes(i)));
    const r1 = await corr('e-1', 'resuelto'); const r2 = await corr('e-1', 'resuelto');
    assert.equal(r1.status, 200); assert.equal(r2.status, 200); assert.equal(r1.json.registrada_en, r2.json.registrada_en, 'idempotente');
    assert.equal((await corr('e-5', 'no_aplica')).status, 200);
    assert.equal((await corr('e-2', 'es_mio')).status, 200);
    assert.equal((await corr('e-12', 'no_es_mio')).status, 200);
    const despues = (await GET(base, '/q/q1')).json;
    assert.ok(!ids(despues).includes('e-1') && !ids(despues).includes('e-5'));
    assert.ok(!ids((await GET(base, '/q/q2')).json).includes('e-12'), 'no_es_mio sale de Q2');
    assert.equal(despues.elementos.find((e) => e.id === 'e-2').correccion, 'es_mio');
    assert.equal((await GET(base, '/elementos/e-1/porque')).status, 404, 'un hecho revocado no se explica ni se usa');
    // la fuente vuelve a informar de los mismos hechos durante horas: no reaparecen; los no corregidos siguen vivos
    mock.avanzar(3 * 60 * MIN);
    const luego = (await GET(base, '/q/q1')).json;
    assert.ok(!ids(luego).includes('e-1') && !ids(luego).includes('e-5'), 'revocado que vuelve');
    assert.ok(!ids((await GET(base, '/q/q4')).json).includes('e-1'));
    assert.ok(mock.estadisticas('alfa').rebotadas > 0, 'la fuente sí repitió hechos revocados (la prueba puede fallar)');
    // el mensaje de confirmación llega por sondeo como `respuesta`
    const m = (await GET(base, '/sondeo?limite=100')).json.mensajes.filter((x) => x.tipo === 'respuesta');
    assert.ok(m.length >= 4 && m.every((x) => x.categoria === 'correccion_confirmada'));
    assert.deepEqual(m[0].elemento_ids, ['e-1']);
  } finally { await cerrar(); }
});

// ---------------------------------------------------------------- atención, avisos y alertas
test('modo de atención con ventana: validación, vuelta a DISPONIBLE y aplazamiento de avisos', async () => {
  const { mock, base, cerrar } = await arrancar();
  try {
    const put = (c) => llamar(base, 'PUT', '/atencion', { cuerpo: c });
    assert.equal((await put({ modo: 'FOCO' })).status, 400, 'sin ventana');
    assert.equal((await put({ modo: 'FOCO', hasta: new Date(mock.ahora() - MIN).toISOString() })).status, 400, 'ventana pasada');
    assert.equal((await put({ modo: 'FOCO', hasta: new Date(mock.ahora() + 8 * 24 * 60 * MIN).toISOString() })).status, 400, 'más de 7 días');
    assert.equal((await put({ modo: 'DISPONIBLE', hasta: new Date(mock.ahora() + 60 * MIN).toISOString() })).status, 400, 'DISPONIBLE no lleva ventana');
    assert.equal((await put({ modo: 'SIESTA', hasta: new Date(mock.ahora() + 60 * MIN).toISOString() })).status, 400);
    const base0 = (await drenar(base, null, 100)).cursor;
    const hasta = new Date(mock.ahora() + 90 * MIN).toISOString();
    assert.equal((await put({ modo: 'DESCANSO', hasta })).status, 200);
    mock.avanzar(60 * MIN);
    const dentro = (await GET(base, '/atencion')).json;
    assert.equal(dentro.modo, 'DESCANSO'); assert.equal(dentro.hasta, hasta);
    const enDescanso = (await drenar(base, base0, 100)).mensajes;
    assert.deepEqual(enDescanso.filter((m) => m.tipo === 'aviso'), [], 'en DESCANSO los avisos se difieren');
    assert.deepEqual(enDescanso.filter((m) => m.tipo === 'alerta'), [], 'las reglas de alfa no están marcadas para DESCANSO');
    mock.avanzar(60 * MIN); // acaba la ventana
    assert.equal((await GET(base, '/atencion')).json.modo, 'DISPONIBLE');
    const agrup = (await drenar(base, base0, 100)).mensajes.filter((m) => m.categoria === 'agrupado' && m.tipo === 'aviso');
    assert.ok(agrup.length >= 1 && agrup[0].agrupa > 1, 'lo diferido llega agrupado al volver');
  } finally { await cerrar(); }
});

test('alerta marcada para el modo activo suena en FOCO; la no marcada se difiere; el registro lo explica', async () => {
  const { mock, base, cerrar } = await arrancar();
  try {
    const c0 = (await drenar(base, null, 100)).cursor;
    await llamar(base, 'PUT', '/atencion', { cuerpo: { modo: 'FOCO', hasta: new Date(mock.ahora() + 5 * 60 * MIN).toISOString() } });
    mock.avanzar(120 * MIN);
    const m = (await drenar(base, c0, 100)).mensajes;
    const alertas = m.filter((x) => x.tipo === 'alerta' && x.categoria === 'alerta_definida');
    assert.ok(alertas.length >= 1, 'r-1 (persona, marcada para FOCO) suena');
    assert.deepEqual(m.filter((x) => x.tipo === 'aviso'), [], 'ningún aviso en FOCO');
    const reg = (await GET(base, '/registro?limite=200')).json;
    assert.ok(reg.entradas.some((e) => e.decision === 'avisar' && e.motivo === 'alerta_marcada_para_el_modo'));
    assert.ok(reg.entradas.some((e) => e.decision === 'diferir' && e.motivo === 'modo_activo'));
    assert.ok(reg.ahorrados > 0);
  } finally { await cerrar(); }
});

test('presupuesto de avisos y tope de alertas: lo que excede se agrupa y no se pierde nada', async () => {
  const { mock, base, cerrar } = await arrancar();
  try {
    const semillas = (await drenar(base, null, 100)).mensajes.length; // avisos del arranque, anteriores a esta configuración
    const av = (await GET(base, '/avisos')).json;
    const { alertas, ...resto } = av;
    const cfg = { ...resto, presupuesto: { max: 2, ventana_min: 60 }, tope_alertas: 1, alertas: alertas.map(({ efectiva, nota, ...a }) => a) };
    assert.equal((await llamar(base, 'PUT', '/avisos', { cuerpo: cfg })).status, 200);
    mock.avanzar(4 * 60 * MIN);
    mock.avanzar(61 * MIN); // cierra la última ventana para que se vacíen los agrupados
    const { mensajes } = await drenar(base, null, 100);
    const st = mock.estadisticas('alfa');
    const suma = (t, f) => mensajes.filter((m) => m.tipo === t && f(m)).reduce((s, m) => s + m.agrupa, 0);
    assert.ok(st.avisosGenerados > 6 && st.alertasGeneradas > 2, 'hay carga suficiente para exceder');
    assert.equal(suma('aviso', (m) => m.categoria !== 'resumen') + st.pendientesAvisos, st.avisosGenerados, 'ningún aviso se pierde');
    assert.equal(suma('alerta', () => true) + st.pendientesAlertas, st.alertasGeneradas, 'ninguna alerta se pierde');
    // por ventana: avisos sueltos ≤ 2; alertas sueltas ≤ 1 (las alertas no consumen el presupuesto de avisos)
    const porVentana = (tipo, solo1) => {
      const mapa = new Map();
      for (const m of mensajes.slice(semillas).filter((x) => x.tipo === tipo && x.categoria !== 'agrupado' && x.categoria !== 'resumen' && x.agrupa === 1 && (solo1 ?? true))) {
        const k = Math.floor(Date.parse(m.creado_en) / (60 * MIN)); mapa.set(k, (mapa.get(k) ?? 0) + 1);
      }
      return Math.max(0, ...mapa.values());
    };
    assert.ok(porVentana('aviso') <= 2, `avisos por ventana ${porVentana('aviso')}`);
    assert.ok(porVentana('alerta') <= 1, `alertas por ventana ${porVentana('alerta')}`);
    assert.ok(mensajes.some((m) => m.tipo === 'alerta' && m.categoria === 'agrupado' && m.agrupa > 1), 'hay un mensaje «hay N alertas más»');
    assert.ok(mensajes.some((m) => m.tipo === 'aviso' && m.categoria === 'agrupado' && m.agrupa > 1));
  } finally { await cerrar(); }
});

test('configuración de avisos: se guarda y se lee igual; entradas inválidas se rechazan; remitente por ruta web degrada a aviso', async () => {
  const { base, cerrar } = await arrancar();
  try {
    const av = (await GET(base, '/avisos')).json;
    const r2 = av.alertas.find((a) => a.tipo === 'remitente_palabra');
    assert.equal(r2.efectiva, 'aviso'); assert.equal(r2.nota, 'remitente_sin_identidad_autenticada');
    assert.equal(av.alertas.find((a) => a.tipo === 'persona').efectiva, 'alerta');
    const avB = (await GET(base, '/avisos', { token: 'tok-beta-1' })).json;
    assert.equal(avB.alertas[0].efectiva, 'alerta', 'misma regla por ruta Graph sí es alerta');
    const peticion = (c) => ({ ...c, alertas: c.alertas.map(({ efectiva, nota, ...a }) => a) });
    const nueva = peticion({ ...av, resumen_inicio: '06:45', resumen_cierre: null, avisos_activos: ['vencimiento'] });
    assert.equal((await llamar(base, 'PUT', '/avisos', { cuerpo: nueva })).status, 200);
    const leida = (await GET(base, '/avisos')).json;
    assert.equal(leida.resumen_inicio, '06:45'); assert.equal(leida.resumen_cierre, null); assert.deepEqual(leida.avisos_activos, ['vencimiento']);
    const malos = [
      { ...nueva, tope_alertas: 0 }, { ...nueva, tope_alertas: 51 }, { ...nueva, resumen_inicio: '25:00' },
      { ...nueva, presupuesto: { max: 5, ventana_min: 1 } }, { ...nueva, avisos_activos: ['gritar'] },
      { ...nueva, extra: true }, { ...nueva, alertas: [{ id: 'x', tipo: 'persona', objetivo: 'per-1', modos: ['SIESTA'] }] },
      { ...nueva, alertas: Array.from({ length: 21 }, (_, i) => ({ id: `a${i}`, tipo: 'persona', objetivo: 'per-1', modos: ['FOCO'] })) },
      { ...nueva, alertas: [{ id: 'x', tipo: 'persona', objetivo: 'per-inventada', modos: ['FOCO'] }] },
    ];
    for (const m of malos) assert.equal((await llamar(base, 'PUT', '/avisos', { cuerpo: m })).status, 400, JSON.stringify(m).slice(0, 80));
    assert.equal((await GET(base, '/avisos')).json.resumen_inicio, '06:45', 'los rechazos no cambian nada');
  } finally { await cerrar(); }
});

test('resumen de inicio y de cierre salen a la hora fijada (UTC)', async () => {
  const { mock, base, cerrar } = await arrancar();
  try {
    const c0 = (await drenar(base, null, 100)).cursor;
    mock.avanzar(24 * 60 * MIN);
    const res = (await drenar(base, c0, 100)).mensajes.filter((m) => m.tipo === 'resumen_inicio' || m.tipo === 'resumen_cierre');
    assert.deepEqual(res.map((m) => [m.tipo, m.creado_en]), [['resumen_cierre', '2026-10-31T17:30:00.000Z'], ['resumen_inicio', '2026-11-01T07:30:00.000Z']]);
    assert.ok(res.every((m) => m.categoria === 'resumen' && m.titulo === null));
  } finally { await cerrar(); }
});

test('reunión próxima: el aviso trae `programar_en` para la notificación local', async () => {
  const { base, cerrar } = await arrancar();
  try {
    const m = (await drenar(base, null, 100)).mensajes.filter((x) => x.categoria === 'reunion_proxima');
    assert.ok(m.length && m.every((x) => x.programar_en === null || Date.parse(x.programar_en) <= Date.parse(x.creado_en) + 24 * 60 * MIN));
    assert.ok(m.some((x) => x.programar_en), 'e-2 (reunión a las 09:30) se programa 15 min antes');
  } finally { await cerrar(); }
});

// ---------------------------------------------------------------- detalle, adaptadores
test('nivel de detalle: no se puede superar el máximo de la instalación (422) y sube/baja dentro de él', async () => {
  const { base, cerrar } = await arrancar();
  try {
    const put = (token, nivel) => llamar(base, 'PUT', '/detalle', { token, cuerpo: { nivel } });
    assert.deepEqual((await GET(base, '/detalle', { token: 'tok-beta-1' })).json, { nivel: 'titulos', maximo: 'titulos' });
    assert.equal((await put('tok-beta-1', 'completo')).status, 422);
    assert.equal((await put('tok-beta-1', 'completo')).json.code, 'LEVEL_NOT_ALLOWED');
    assert.equal((await put('tok-beta-1', 'titulos')).status, 200);
    assert.equal((await GET(base, '/q/q1', { token: 'tok-beta-1' })).json.nivel, 'titulos');
    assert.equal((await put('tok-alfa-1', 'completo')).status, 200);
    assert.equal((await put('tok-alfa-1', 'recuentos')).json.nivel, 'recuentos');
    assert.equal((await GET(base, '/estado', { token: 'tok-alfa-2' })).json.nivel, 'recuentos', 'es por instalación, no por dispositivo');
  } finally { await cerrar(); }
});

test('adaptadores: estado, motivo y ruta alternativa; fuentes caídas marcan la respuesta como obsoleta', async () => {
  const { mock, base, cerrar } = await arrancar();
  try {
    const a = (await GET(base, '/adaptadores')).json.adaptadores;
    assert.deepEqual(a.find((x) => x.id === 'web-portal'), { id: 'web-portal', ruta: 'web', estado: 'detenido', motivo: 'sesion_caducada', ruta_alternativa: null, ultima_lectura: null, ttl_s: a.find((x) => x.id === 'web-portal').ttl_s });
    const b = (await GET(base, '/adaptadores', { token: 'tok-beta-1' })).json.adaptadores.find((x) => x.id === 'm365-teams');
    assert.equal(b.motivo, 'requiere_consentimiento_admin'); assert.equal(b.ruta_alternativa, 'web'); assert.equal(b.estado, 'desactivado');
    const jira = a.find((x) => x.id === 'jira');
    mock.avanzar(10 * MIN);
    assert.ok(Date.parse((await GET(base, '/adaptadores')).json.adaptadores.find((x) => x.id === 'jira').ultima_lectura) > Date.parse(jira.ultima_lectura));
    assert.equal((await GET(base, '/q/q1')).json.obsoleto, false);
    mock.caerFuentes(true);
    mock.avanzar(30 * MIN);
    const q = (await GET(base, '/q/q1')).json;
    assert.equal(q.obsoleto, true); assert.ok(Date.parse(q.ultima_lectura) < mock.ahora() - 25 * MIN);
    assert.ok((await GET(base, '/adaptadores')).json.adaptadores.some((x) => x.motivo === 'sin_conexion'));
  } finally { await cerrar(); }
});

// ---------------------------------------------------------------- órdenes
test('órdenes: cada ejemplo válido de GRAMATICA.md se ejecuta y devuelve el mismo cuerpo que su endpoint', async () => {
  const { readFileSync } = await import('node:fs');
  const md = readFileSync(new URL('../GRAMATICA.md', import.meta.url), 'utf8');
  const bloque = md.split('Válidas')[1].split('```')[1].split('\n').map((l) => l.trim()).filter((l) => l && l !== 'text');
  assert.ok(bloque.length >= 12);
  const { base, cerrar } = await arrancar();
  try {
    await llamar(base, 'PUT', '/detalle', { cuerpo: { nivel: 'completo' } });
    for (const orden of bloque) {
      const r = await llamar(base, 'POST', '/ordenes', { cuerpo: { orden } });
      assert.equal(r.status, 200, orden);
      assert.equal(r.json.interpretada, true, `${orden}: ${r.texto.slice(0, 160)}`);
      assert.deepEqual(conforme('POST', '/ordenes', r), [], orden);
    }
    const viaOrden = (await llamar(base, 'POST', '/ordenes', { cuerpo: { orden: 'q1 proyecto:p-alfa' } })).json.resultado;
    const viaRest = (await GET(base, '/q/q1?proyecto=p-alfa')).json;
    assert.deepEqual({ ...viaOrden, generado_en: 0 }, { ...viaRest, generado_en: 0 });
    // surten efecto: no-aplica e-9 quita e-9; detalle titulos; presupuesto 5/2h
    assert.ok(!ids((await GET(base, '/q/q4')).json).includes('e-9'));
    assert.equal((await GET(base, '/detalle')).json.nivel, 'titulos');
    assert.deepEqual((await GET(base, '/avisos')).json.presupuesto, { max: 5, ventana_min: 120 });
    assert.equal((await GET(base, '/atencion')).json.modo, 'DESCANSO');
    const dur = await llamar(base, 'POST', '/ordenes', { cuerpo: { orden: 'modo foco durante:90m' } });
    assert.equal(Date.parse(dur.json.resultado.hasta) - Date.parse((await GET(base, '/estado')).json.generado_en), 90 * MIN);
  } finally { await cerrar(); }
});

test('texto libre: respuesta honesta, no se refleja el texto, no se guarda y no sale a ningún modelo', async () => {
  const { mock, base, cerrar } = await arrancar();
  try {
    const libres = ['¿qué tengo pendiente con Marta esta semana?', 'dime lo de Ana Prueba', CARGAS.markdown, 'q1 y además cuéntame un chiste', 'Q', '   ', 'resuelto', 'modo', 'q3', 'modo foco', 'modo foco durante:0m', 'modo foco durante:9999h', 'detalle todo', 'q1 desde:2026-10-30', 'q1 proyecto:p-alfa proyecto:p-alfa2', 'resumen inicio 25:99', 'presupuesto 5/2d', 'aviso on gritar', 'q1 filtro:x'];
    for (const orden of libres.filter((x) => x.trim())) {
      const r = await llamar(base, 'POST', '/ordenes', { cuerpo: { orden } });
      assert.equal(r.status, 200, orden);
      assert.equal(r.json.interpretada, false, orden);
      assert.match(r.json.mensaje, /^No puedo interpretar texto libre aquí; usa una de estas órdenes\.$/);
      assert.ok(r.json.ordenes.length >= 10);
      assert.deepEqual(conforme('POST', '/ordenes', r), [], orden);
      const sinAyuda = JSON.stringify({ ...r.json, ordenes: null }); // la lista de órdenes usa las palabras de la gramática
      for (const trozo of orden.split(/\s+/).filter((t) => t.length > 6)) assert.ok(!sinAyuda.includes(trozo), `se refleja «${trozo}»`);
    }
    assert.equal((await llamar(base, 'POST', '/ordenes', { cuerpo: { orden: 'q3' } })).json.motivo, 'argumento_invalido');
    assert.equal((await llamar(base, 'POST', '/ordenes', { cuerpo: { orden: 'hola qué tal' } })).json.motivo, 'texto_libre');
    assert.equal(mock.egresos(), 0, 'ningún byte del texto va a un modelo ni a otro destino');
    const secreto = 'zxq-secreto-4411';
    await llamar(base, 'POST', '/ordenes', { cuerpo: { orden: `cuéntame ${secreto}` } });
    assert.ok(!mock.volcarEstado().includes(secreto), 'no se guarda ni se registra');
    assert.ok(mock.volcarEstado().includes('Proyecto Cobalto'), 'el volcado sí contiene el estado (la prueba puede fallar)');
    assert.equal((await GET(base, '/estado')).json.texto_libre, 'desactivado');
    assert.equal((await llamar(base, 'POST', '/ordenes', { cuerpo: { orden: 'x'.repeat(201) } })).status, 400);
    assert.equal((await llamar(base, 'POST', '/ordenes', { cuerpo: { orden: 'q1', extra: 1 } })).status, 400);
    assert.equal((await llamar(base, 'POST', '/ordenes', { cuerpo: '{no es json' })).status, 400);
  } finally { await cerrar(); }
});
