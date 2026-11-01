// Comprobación de mutaciones: cada regla rota debe hacer fallar algún test o eval.
//
// Copia `src/attention` y `tests/attention` a un directorio temporal, aplica una mutación
// cada vez, ejecuta los tests y las evals y anota MUERTA (falla una aserción o una eval), ROTA
// (el mutante no arranca o lanza fuera de toda aserción: no prueba la regla) o VIVA (nada
// falla). Sale con 1 si queda alguna viva o rota, y con 2 si una mutación no se puede aplicar
// (el texto original debe aparecer exactamente una vez).
//
// M01–M18: las 18 mutaciones de Labs (soul-atencion), reescritas contra el código TypeScript.
// M19–M36: las de AC-4b (alertas con tope, modos, remitente, resúmenes, registro de demanda).
// M37–M41: redacción fail-closed y puente con el contrato (`src/contract`, que también se copia).
// M42–M50: revisión de la PR #1441 (la web no autentica, alertas vetadas o vencidas, control,
// franjas y estado).
// M51–M57: segunda revisión de la PR #1441 (lo entregado no queda pendiente, la web solo
// degrada avisos, ruta desconocida fail-closed y estado sin líneas repetidas).
// M58–M61: revisión independiente de la PR #1441 (una alerta sobre el tope sale una sola vez y
// una regla de alerta no salta el tipo del evento).
//
// Uso: node --experimental-strip-types tests/attention/bench/mutaciones.ts
import { spawnSync } from 'node:child_process';
import { cpSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, sep } from 'node:path';
import { fileURLToPath } from 'node:url';

const POL = 'src/attention/politica.ts';
const EST = 'src/attention/estado.ts';
const RES = 'src/attention/resumen.ts';
const LED = 'src/attention/ledger.ts';
const PUE = 'src/attention/contrato.ts';
const TIE = 'src/attention/tiempo.ts';

const TODOS = "['DISPONIBLE', 'FOCO', 'DESCANSO', 'FUERA'] as const";

const MUTACIONES: Array<[string, string, string, string]> = [
  ['M01 sin comprobar ventana', POL, 'const inst = instanciaEn(ventanas, ahora);', 'const inst = instanciaEn(ventanas, ahora) ?? 0;'],
  ['M02 sin presupuesto', POL, '>= this.presupuesto) {', '>= Number.MAX_SAFE_INTEGER) {'],
  ['M03 alerta sin fuente autenticada', POL, "} else if (!sinAutenticar && (tipo.k === 'AVISO'", "} else if ((tipo.k === 'AVISO'"],
  ['M04 veto ignorado', POL, "} else if (ev.objetivo !== null && this.estado.vetos.has(ev.objetivo)) {\n      bloqueo = m('VETADO');", "} else if (false) {\n      bloqueo = m('VETADO');"],
  ['M05 silencio como permiso', POL, 'this.bandeja.anotar(ev.tipo.decisionId, {', 'this.bandeja.resolver(ev.tipo.decisionId);\n      this.bandeja.anotar(ev.tipo.decisionId, {'],
  ['M06 el LLM eleva urgencia', POL, 'return this.config.alertas.find((r) => r.codigo === ev.codigoAlerta) ?? null;', "return this.config.alertas.find((r) => r.codigo === ev.codigoAlerta) ?? (ev.urgenciaSugeridaLlm === 'CRITICA' ? (this.config.alertas[0] ?? null) : null);"],
  ['M07 reanudar desde cualquiera', POL, "case 'REANUDAR':\n        if (!persona) return false;", "case 'REANUDAR':"],
  ['M08 disponibilidad implícita', POL, 'return this.config.modoPorDefecto;\n  }', "return this.config.modoPorDefecto ?? 'DISPONIBLE';\n  }"],
  ['M09 sin redacción', POL, 'const redactado = redactar(ev.nivel, this.config.canalNivelMax);', 'const redactado = false;'],
  ['M10 seguridad agrupable', POL, "[tipo.decisionId, 'APROBACION', true,", "[tipo.decisionId, 'APROBACION', false,"],
  ['M11 contexto vencido ignorado', POL, "} else if (ev.caduca !== null && ev.caduca <= ahora) {\n      bloqueo = m('CONTEXTO_VENCIDO');", "} else if (false) {\n      bloqueo = m('CONTEXTO_VENCIDO');"],
  ['M12 reintento ambiguo se registra', POL, "tipo.efectoPrevio === 'NO_OCURRIO'", 'true'],
  ['M13 descanso declarado ignorado', POL, "if (instanciaEn(this.config.descansos, ahora) !== null) return 'DESCANSO';", "if (false) return 'DESCANSO';"],
  ['M14 PARA se pierde al reiniciar', EST, "e.parado = v === '1';", 'e.parado = false;'],
  ['M15 permiso fuera de contrato aceptado', POL, '(!tipo.dentroDeContrato || sinAutenticar)', '(false || sinAutenticar)'],
  ['M16 agente declara el modo', POL, "case 'DECLARAR_MODO':\n        if (!persona) return false;", "case 'DECLARAR_MODO':"],
  ['M17 decisión repetida se vuelve a preguntar', POL, 'if (this.estado.preguntadas.has(clave) || this.bandeja.porDecision(clave) !== undefined) {', 'if (false) {'],
  ['M18 estado ilegible aceptado', EST, 'default:\n        return null;', 'default:\n        break;'],
  ['M19 alerta sin tope propio', POL, 'if (usadas < this.topeAlertas) {', 'if (true) {'],
  ['M20 alerta no marcada para el modo pasa', POL, "const marcada = modo === 'DISPONIBLE' || (modo !== null && regla.modos.includes(modo));", 'const marcada = true;'],
  ['M21 la alerta gasta presupuesto de avisos', POL, 'this.estado.alertasUsadas.set(cubo, usadas + 1);', 'this.estado.alertasUsadas.set(cubo, usadas + 1);\n        const v = instanciaEn(this.config.ventanas, ahora);\n        if (v !== null) this.estado.usados.set(v, (this.estado.usados.get(v) ?? 0) + 1);'],
  ['M22 alerta sobre el tope se pierde', POL, 'this.estado.excedidas.push(ev.id);', 'void 0;'],
  ['M23 urgencia inyectada eleva a alerta', POL, 'const regla = this.reglaDe(ev);', `const regla = this.reglaDe(ev) ?? (ev.urgenciaEnContenido === 'CRITICA' ? { codigo: 'x', modos: ${TODOS} } : null);`],
  ['M24 regla en web es alerta', POL, '      if (web) {\n        // Por la web', '      if (false) {\n        // Por la web'],
  ['M25 aviso repetido gasta presupuesto otra vez', POL, 'this.estado.preguntadas.add(ev.id);\n      this.aBandeja(ev, null, false, ap, redactado, dec.contactarAhora);', 'this.aBandeja(ev, null, false, ap, redactado, dec.contactarAhora);'],
  ['M26 alerta repetida se duplica', POL, 'if (this.estado.preguntadas.has(ev.id)) {\n      const dec', 'if (false) {\n      const dec'],
  ['M27 resumen antes de su hora', RES, 'return hoy <= ahora ? hoy : hoy - DIA;', 'return hoy;'],
  ['M28 resumen repetido', RES, 'if (previo !== null && previo >= programado) continue;', ''],
  ['M29 el tope no se renueva por ventana', POL, 'const cubo = this.cuboAlertas(ahora);', 'const cubo = 0;'],
  ['M30 resumen tardío se emite igual', RES, 'if (ahora - programado > TOLERANCIA_RESUMEN) continue;', ''],
  ['M31 «¿por qué?» dice siempre que avisó', LED, 'const contactado = e?.ahora ?? false;', 'const contactado = true;'],
  ['M32 «¿qué ahorraste?» no descuenta', LED, 'ahorrados: ids.size - contactados.size,', 'ahorrados: ids.size,'],
  ['M33 presupuesto inválido abre el gate', POL, 'return ENTERO_NO_NEGATIVO(this.config.presupuesto) ? this.config.presupuesto : 0;', 'return this.config.presupuesto;'],
  ['M34 en DISPONIBLE la alerta exige marca', POL, "modo === 'DISPONIBLE' || (modo !== null", '(modo !== null'],
  ['M35 sin modo declarado la alerta se entrega', POL, 'const marcada = modo === ', 'const marcada = modo === null || modo === '],
  ['M36 el estado guarda alertas agrupadas sin persistir', EST, 'for (const id of e.excedidas) out +=', 'for (const id of []) out +='],
  ['M37 nivel fuera del contrato sin forzar a N4', PUE, '? NIVELES[level as Level] : 4;', '? NIVELES[level as Level] : (undefined as never);'],
  ['M38 redacción sin validar el nivel', POL, '!(NIVEL_VALIDO(nivel) && NIVEL_VALIDO(canal) && (nivel as number) <= (canal as number))', '(nivel as number) > (canal as number)'],
  ['M39 en la web solo se degradan las reglas de remitente', POL, '      if (web) {\n        // Por la web', '      if (regla.porRemitente === true && web) {\n        // Por la web'],
  ['M40 el puente autentica remitentes de la web', PUE, "  if (rutaDeContrato(route) === 'WEB') return 'NO_AUTENTICADO';\n", ''],
  ['M41 el puente autentica el remitente desconocido', PUE, "if (auth === 'unknown') return 'DESCONOCIDO';", "if (auth === 'unknown') return 'AGENTE_AUTENTICADO';"],
  ['M42 la política se fía del origen declarado en la web', POL, 'let sinAutenticar = web || (', 'let sinAutenticar = ('],
  ['M43 lo desconocido autentica', POL, "(ev.origen !== 'PERSONA' && ev.origen !== 'AGENTE_AUTENTICADO')", "ev.origen === 'NO_AUTENTICADO'"],
  ['M44 una regla web de remitente suplantado avisa', POL, "sinAutenticar = ev.origen === 'NO_AUTENTICADO';", 'sinAutenticar = false;'],
  ['M45 la alerta de un objetivo vetado se entrega', POL, "if (ev.objetivo !== null && this.estado.vetos.has(ev.objetivo)) descarte = m('VETADO');", "if (false) descarte = m('VETADO');"],
  ['M46 la alerta con el contexto vencido se entrega', POL, "else if (ev.caduca !== null && ev.caduca <= ahora) descarte", 'else if (false) descarte'],
  ['M47 un origen sin autenticar detiene', POL, "if (!autenticado) return false;\n        this.estado.parado = true;", 'this.estado.parado = true;'],
  ['M48 un origen sin autenticar veta', POL, "if (!autenticado || c.objetivo === '') return false;", "if (c.objetivo === '') return false;"],
  ['M49 franja con horas fuera de rango', TIE, 'hh >= 0 && hh < 24', 'hh >= 0 && hh <= 24'],
  ['M50 el estado acepta alertas agrupadas duplicadas', EST, "SINGULARES.has(k) ? k : `${k}=${decod(v)}`;", "SINGULARES.has(k) ? k : `${l}#${vistas.size}`;"],
  ['M51 lo avisado ahora sigue pendiente', POL, 'pendiente: !(entregado && decisionId === null),', 'pendiente: true,'],
  ['M52 el resumen resuelve decisiones', RES, 'if (i.decisionId === null) entregados.add(i);', 'entregados.add(i);'],
  ['M53 el resumen repite lo ya entregado', RES, 'for (const i of entregados) i.pendiente = false;', ''],
  ['M54 la web degrada cualquier tipo con regla', POL, "if (tipo.k === 'AVISO' || tipo.k === 'NOTIFICACION') {\n          degradadaAAviso", 'if (true) {\n          degradadaAAviso'],
  ['M55 una ruta desconocida es API', PUE, "return RUTAS_API.has(route as string) ? 'API' : 'WEB';", "return route === 'web' ? 'WEB' : 'API';"],
  ['M56 el estado acepta un PARA repetido', EST, 'if (vistas.has(unica)) return null;', ''],
  ['M57 contadores repetidos por ventana se aceptan', EST, "? `${k}=${entero(v.split(',')[0] ?? '')}`", "? l"],
  ['M58 la alerta drenada sigue pendiente', POL, 'for (const i of items) if (i) i.pendiente = false;', ''],
  ['M59 reencolar no la vuelve a dejar pendiente', POL, 'if (i) i.pendiente = true;', ''],
  ['M60 el resumen no saca la alerta de la cola agrupada', RES, 'if (dados.size > 0) pol.estado.excedidas', 'if (false) pol.estado.excedidas'],
  ['M61 una regla convierte cualquier tipo en alerta', POL, "} else if (!sinAutenticar && (tipo.k === 'AVISO' || tipo.k === 'NOTIFICACION')) {", '} else if (!sinAutenticar) {'],
  ['M62 un bloqueo reenviado vuelve a entrar en la bandeja', POL, 'if (this.bandeja.porDecision(clave) !== undefined) {\n        this.bandeja.anotar(clave, ap);', 'if (false) {\n        this.bandeja.anotar(clave, ap);'],
];

const aqui = dirname(fileURLToPath(import.meta.url));
const proyecto = join(aqui, '..', '..', '..');
const NODE = ['--experimental-strip-types', '--no-warnings'];

const TESTS = [
  '--test', '--test-reporter=tap',
  'tests/attention/politica.test.ts', 'tests/attention/ac4b.test.ts', 'tests/attention/contrato.test.ts',
  'tests/attention/resumen.test.ts',
];

/** Copia lo que necesitan los tests: la librería, el contrato del que tira el puente y los tests. */
function copiar(dest: string): void {
  for (const d of [['src', 'attention'], ['src', 'contract']]) cpSync(join(proyecto, ...d), join(dest, ...d), { recursive: true });
  const origen = join(proyecto, 'tests', 'attention');
  const banco = join(origen, 'bench');
  cpSync(origen, join(dest, 'tests', 'attention'), { recursive: true, filter: (s) => s !== banco && !s.startsWith(banco + sep) });
}

type Salida = 'pasa' | 'FALLA' | 'CRASH';

/** Un mutante que cuelga la ejecución no debe bloquear el job: pasado este plazo, no arrancó. */
const PLAZO_MS = 120_000;

function correr(args: string[], cwd: string): { status: number; out: string; colgado: boolean } {
  const r = spawnSync(process.execPath, [...NODE, ...args], { cwd, encoding: 'utf8', maxBuffer: 64 * 1024 * 1024, timeout: PLAZO_MS });
  const colgado = (r.error as NodeJS.ErrnoException | undefined)?.code === 'ETIMEDOUT';
  return { status: r.status ?? 1, out: r.stdout ?? '', colgado };
}

/** Los tests solo matan si falla una aserción; cualquier otro fallo es que no arrancó. */
function tests(cwd: string): Salida {
  const r = correr(TESTS, cwd);
  if (r.colgado) return 'CRASH';
  if (r.status === 0) return 'pasa';
  return r.out.includes("code: 'ERR_ASSERTION'") ? 'FALLA' : 'CRASH';
}

/** Las evals solo matan si terminan y alguna métrica falla; sin resumen final, no arrancaron. */
function evals(cwd: string): Salida {
  const r = correr(['tests/attention/evals.ts'], cwd);
  if (r.colgado) return 'CRASH';
  const fin = /^PASS (\d+) · FAIL (\d+)$/m.exec(r.out);
  if (r.status === 0 && fin !== null && fin[2] === '0') return 'pasa';
  return fin !== null && fin[2] !== '0' ? 'FALLA' : 'CRASH';
}

function main(): number {
  const filas = ['mutacion\ttests\tevals\tveredicto'];
  let vivas = 0;
  let rotas = 0;
  // La base debe estar verde: si no, todo parecería «muerto».
  const base = mkdtempSync(join(tmpdir(), 'mut-base-'));
  copiar(base);
  const tb = tests(base);
  const eb = evals(base);
  rmSync(base, { recursive: true, force: true });
  if (tb !== 'pasa' || eb !== 'pasa') {
    console.error('La base no está en verde: no se puede medir.');
    return 2;
  }
  for (const [nombre, fichero, antes, despues] of MUTACIONES) {
    const tmp = mkdtempSync(join(tmpdir(), 'mut-'));
    try {
      copiar(tmp);
      const ruta = join(tmp, fichero);
      const texto = readFileSync(ruta, 'utf8');
      if (texto.split(antes).length - 1 !== 1) {
        console.error(`NO APLICABLE: ${nombre}`);
        return 2;
      }
      writeFileSync(ruta, texto.replace(antes, () => despues));
      const t = tests(tmp);
      const e = evals(tmp);
      const veredicto = t === 'FALLA' || e === 'FALLA' ? 'MUERTA' : t === 'CRASH' || e === 'CRASH' ? 'ROTA' : 'VIVA';
      if (veredicto === 'VIVA') vivas++;
      if (veredicto === 'ROTA') rotas++;
      const fila = `${nombre}\t${t}\t${e}\t${veredicto}`;
      filas.push(fila);
      console.log(fila);
    } finally {
      rmSync(tmp, { recursive: true, force: true });
    }
  }
  writeFileSync(join(aqui, 'mutaciones.tsv'), `${filas.join('\n')}\n`);
  console.log(`vivas: ${vivas} · rotas: ${rotas} de ${MUTACIONES.length}`);
  return vivas > 0 || rotas > 0 ? 1 : 0;
}

process.exitCode = main();
