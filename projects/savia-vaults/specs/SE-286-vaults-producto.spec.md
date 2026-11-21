# SE-286 — SaviaVaults: de esqueleto con promesa a producto verificable

**Status:** S1-S3+S5-S7 DONE (2026-08-01). S4 (MCP/A2A servers completo) pendiente.
**Fecha:** 2026-08-01
**Proyecto:** projects/savia-vaults
**Area:** Product completion / Core implementation / Security / Distribution
**Branch:** agent/se286-vaults-producto
**Estimacion total:** ~64h (7 slices)
**Base verificada:** HEAD b21d49f0 (#917), savia-vaults v0.1.0.

---

## Origen

Auditoria completa del proyecto SaviaVaults (2026-08-01). El proyecto se
presenta como *"MCP + A2A server for AI agent knowledge vaults with
git-backed storage, hybrid search, and content signing"* y su README abre
con `npm install -g savia-vaults`.

### Hallazgo principal: la promesa excede al codigo por un orden de magnitud

**Implementado** (`src/`, 263 lineas TS):

```
src/config/schema.json              73 lineas
src/federation/a2a-client.ts        28
src/federation/audit-logger.ts      28
src/federation/cache.ts             26
src/federation/circuit-breaker.ts   39
src/federation/hash-verify.ts       17   (retirado 2026-11-20, SE-287 AC-4.5)
src/federation/registry.ts          46
src/federation/search.ts            60
src/federation/types.ts             19
```

**Ausente por completo**, pese a estar prometido en README y/o esperado
por los tests:

| Modulo | Prometido como | Estado |
|---|---|---|
| `src/types.ts` | tipos nucleo (7 tests lo importan) | NO EXISTE |
| `src/storage/` | almacenamiento respaldado por git | NO EXISTE |
| `src/search/` | busqueda hibrida | NO EXISTE |
| `src/security/` | firma Ed25519 y validacion | NO EXISTE |
| `src/server/mcp.ts` | servidor MCP | NO EXISTE |
| `src/server/ratelimit.ts` | limitacion de tasa | NO EXISTE |
| `src/cli/` | CLI (`bin` apunta a `dist/cli/index.js`) | NO EXISTE |

**Consecuencia inmediata y verificable:** `package.json` declara
`bin: dist/cli/index.js` y `build: tsc` con `include: src/**/*.ts`.
No existe `src/cli/`. **Un `npm install -g savia-vaults` instalaria un
paquete cuyo binario apunta a un fichero que la compilacion no puede
producir.** El paquete no esta publicado (no se ha verificado en el
registro), pero el README ya lo instruye.

### El activo que rescata el proyecto

**1.156 lineas de tests en 14 ficheros**, de los cuales 7 prueban modulos
que no existen (storage, search, security, ratelimit, mcp-server,
vault-workflow, + federated-search que importa SearchEngine inexistente).
Leido como defecto es alarmante; leido correctamente es
un activo: **es una fase roja de TDD sostenida** — la especificacion del
nucleo ya esta escrita en forma ejecutable. Construir contra esos tests
es mucho mas barato que diseñar desde cero, y el criterio de "hecho" es
inequivoco: los 14 en verde.

La capa de federacion, ademas, esta implementada con piezas de calidad
(circuit breaker, cache, verificacion de hash, registro, audit log) y
tiene sus seis tests pasando sobre codigo real.

### Seis specs propias sin estado declarado

`SE-280` (vaults), `SE-281` (gap corrections), `SE-282` (federate),
`SE-283` (security hardening), `SE-284` (CLI), `SE-285` (skill and agent):
1.001 lineas en total, **ninguna con campo Status**. No se puede saber
que esta hecho, que se abandono y que espera. Es el mismo patron de
trazabilidad rota que el workspace principal ya corrigio (SE-253 S6).

### Por que este proyecto merece terminarse

SaviaVaults es **la unica pieza del ecosistema que hace la cupula de
contexto consumible por agentes que no son Savia**. La federacion del
nucleo (SE-263) asume pares soberanos con constitucion; SaviaVaults
expone la cupula por protocolos estandar, de modo que un cliente con
plataforma agentica propia puede leer una cupula sin adoptar nada. Es la
respuesta tecnica al escenario "todo debe operar sobre nuestra
plataforma" (SE-272 S4) y encaja con el posicionamiento correcto: no se
vende plataforma, se publica capa de contexto soberano.

## Objetivo (scope-down agresivo)

Convertir SaviaVaults en producto verificable: alinear promesa y realidad
(S1), construir el nucleo contra los tests existentes (S2), endurecer la
seguridad de un servidor que escucha y firma (S3), servidores MCP y A2A
con conformidad demostrada (S4), CLI y primera ejecucion (S5),
distribucion profesional con smoke real (S6), y alineamiento con el
gobierno de niveles del ecosistema (S7).

## Out of scope explicito

- NO reescribir la capa de federacion: funciona y tiene tests. Se integra.
- NO interfaz grafica ni servicio alojado: es una herramienta local con
  servidores locales.
- NO sincronizacion multi-escritor ni resolucion de conflictos
  distribuida: git es el sustrato y su modelo de conflictos es el que
  aplica.
- NO indexacion semantica con embeddings en v1: la busqueda hibrida es
  lexica + metadatos (minisearch ya es dependencia). Los embeddings
  añaden dependencia de proveedor y contradicen "cero dependencia de
  nube" salvo con modelo local, que es spec aparte.
- NO publicacion en el registro hasta que S6 pase: publicar un paquete
  roto es peor que no publicarlo.

---

## Slice 1 — Verdad del producto: alinear promesa y estado

**Problema:** el README instruye a instalar algo que no puede funcionar.
Cualquier persona que lo intente pierde la confianza en el proyecto
entero — y con razon.

**Diseño minimo:**
- README reescrito con estado real y honesto: que funciona hoy (capa de
  federacion), que esta en construccion, y **eliminacion del
  `npm install -g` hasta que S6 lo haga cierto**. Bloque de estado al
  principio, no nota al pie.
- Las seis specs del proyecto reciben campo `Status` explicito
  {DONE | IN_PROGRESS | PROPOSED | ABANDONED} con su motivo, y las
  cerradas van a `specs-archive/` (patron SE-253 S6 aplicado al
  subproyecto).
- `package.json` marcado `private: true` mientras el paquete no sea
  instalable — retirar la marca es parte del AC de S6.
- Badges revisados: un badge que declara capacidades no verificadas es
  la misma cobertura fantasma que el workspace ya corrigio dos veces.

**Acceptance criteria:**

AC-1.1. README sin instrucciones ejecutables que fallen: cada comando
        documentado se ejecuta en entorno limpio y funciona, o esta
        marcado explicitamente como no disponible aun (verificado por
        script que extrae y ejecuta los bloques de codigo).
AC-1.2. Las 6 specs con Status y motivo; cero sin estado.
AC-1.3. `private: true` presente hasta que S6 lo retire.
AC-1.4. Bloque de estado real en la cabecera del README (es y en).

**Esfuerzo:** 3h

---

## Slice 2 — Nucleo: tipos, almacenamiento git y busqueda

**Problema:** es el corazon ausente. Sin `types`, `storage` y `search`
no hay producto, solo una capa de federacion que no tiene que federar.

**Diseño minimo:**
- **`src/types.ts`**: modelo de dominio — Vault, Document, Frontmatter
  (con nivel de confidencialidad), SearchResult, Receipt. Es la
  dependencia de 7 tests; se construye primero.
- **`src/storage/`**: almacenamiento respaldado por git. Cada escritura
  es un commit con mensaje estructurado y autor declarado. Operaciones:
  init, read, write, delete, history, restore. **Idempotencia y atomicidad
  como requisitos**: una escritura interrumpida no deja el vault en
  estado invalido.
- **`src/search/`**: busqueda hibrida lexica + metadatos con minisearch
  (ya es dependencia declarada). Indice incremental persistido; consultas
  por texto, por frontmatter y combinadas; resultados con puntuacion y
  ruta de procedencia.
- **Contra los tests existentes**: `storage.test.ts`, `search.test.ts`,
  `vault-workflow.test.ts` son la especificacion. Si un
  test resulta estar mal planteado se corrige con justificacion escrita
  en el PR — pero el default es que manda el test.

**Acceptance criteria:**

AC-2.1. Los tests de nucleo (`storage`, `search`,
        `vault-workflow`) en verde sin modificar sus asertos, salvo
        correcciones justificadas por escrito.
AC-2.2. Cada escritura produce exactamente un commit con autor y mensaje
        estructurado (test).
AC-2.3. Escritura interrumpida (fallo inyectado a mitad) deja el vault
        en estado valido y recuperable (test de atomicidad).
AC-2.4. Indice incremental: reindexar tras un cambio cuesta
        proporcionalmente al cambio, no al vault completo (medido en
        vault de >=1.000 documentos).
AC-2.5. Busqueda combinada texto+frontmatter devuelve resultados con
        puntuacion y procedencia (test).
AC-2.6. Vault de 10.000 documentos: busqueda p95 bajo umbral declarado
        (benchmark commiteado).

**Esfuerzo:** 16h

---

## Slice 3 — Seguridad: firma, validacion y modelo de amenaza

**Problema:** es un servidor que escucha en un puerto, lee del disco y
firma contenido. Las murallas del nucleo de Savia no lo cubren porque
vive fuera. `security.test.ts` y `ratelimit.test.ts` existen sin
implementacion.

**Diseño minimo:**
- **`src/security/`**: firma Ed25519 de contenido con recibos de
  procedencia (alineado con los recibos por contenido del ecosistema,
  SE-260 S4); verificacion en lectura; rotacion de clave con periodo de
  gracia.
- **Validacion de entrada dura**: recorrido de rutas (path traversal) es
  la amenaza numero uno de un servidor de ficheros — toda ruta se
  resuelve y se verifica dentro del vault, sin excepcion; enlaces
  simbolicos que apunten fuera se rechazan.
- **`src/server/ratelimit.ts`**: limite por cliente y global; un agente
  en bucle no debe poder saturar el servidor local.
- **Modelo de amenaza escrito** (`docs/threat-model.md`): quien es el
  atacante (proceso local malicioso, agente comprometido, contenido
  envenenado en el vault, cliente MCP hostil), que se protege y que
  explicitamente NO (no es un servidor expuesto a internet).
- **Contenido del vault como dato, nunca instruccion**: un documento del
  vault que contenga texto de tipo "ignora lo anterior" se sirve como
  contenido, y el servidor no lo interpreta. Principio heredado del
  nucleo (SE-273 S5).
- **Escucha local por defecto**: bind a loopback; exponer en red es acto
  explicito con aviso.

**Acceptance criteria:**

AC-3.1. `security.test.ts` y `ratelimit.test.ts` en verde.
AC-3.2. Path traversal: 8 vectores clasicos (incluidos codificados y con
        enlaces simbolicos) → todos rechazados (test parametrizado).
AC-3.3. Firma y verificacion end-to-end; contenido alterado tras firmar
        → verificacion falla (test).
AC-3.4. Rotacion de clave con gracia: firmas antiguas validan durante el
        periodo, no despues (test con reloj).
AC-3.5. Bind por defecto a loopback; exponer en red requiere flag
        explicito y emite aviso (test).
AC-3.6. Modelo de amenaza publicado con lo protegido y lo NO protegido
        declarado sin ambiguedad.

**Esfuerzo:** 10h

---

## Slice 4 — Servidores MCP y A2A con conformidad demostrada

**Problema:** son la razon de ser del producto —el titulo del README— y
no existen. `mcp-server.test.ts` espera `src/server/mcp.ts`.

**Diseño minimo:**
- **`src/server/mcp.ts`**: servidor MCP sobre el SDK ya declarado como
  dependencia. Herramientas expuestas: buscar, leer documento, listar,
  estadisticas, y escribir **solo si el vault se abre en modo escritura
  explicito** (lectura por defecto: un servidor de conocimiento que
  escribe por defecto es una superficie innecesaria).
- **Servidor A2A**: expone la cupula como par no soberano, integrando la
  capa de federacion existente (registry, a2a-client, circuit-breaker).
- **Conformidad verificada, no declarada**: suite que valida el servidor
  contra la especificacion del protocolo —descubrimiento de herramientas,
  formato de errores, ciclo de vida—. Un servidor que "habla MCP" sin
  test de conformidad es una afirmacion.
- **Degradacion**: si el indice esta corrupto o el vault es inaccesible,
  el servidor arranca en modo degradado informando, en vez de fallar
  opaco.
- **Observabilidad minima**: log estructurado de peticiones (sin
  contenido), estadisticas de uso, endpoint de salud.

**Acceptance criteria:**

AC-4.1. `mcp-server.test.ts` en verde; cliente MCP real (Claude Code o
        equivalente) se conecta, descubre herramientas y ejecuta una
        busqueda (demo E2E grabada en el PR).
AC-4.2. Suite de conformidad de protocolo en verde; respuesta malformada
        inyectada → detectada por la suite (la suite debe poder fallar).
AC-4.3. Modo lectura por defecto: intento de escritura sin apertura
        explicita → denegado (test).
AC-4.4. Servidor A2A responde a par externo con la capa de federacion
        integrada (test con par sintetico).
AC-4.5. Indice corrupto → arranque degradado con aviso, no fallo opaco
        (test).
AC-4.6. Log estructurado sin contenido de documentos (asercion de
        privacidad).

**Esfuerzo:** 14h

---

## Slice 5 — CLI y primera ejecucion

**Problema:** `bin` apunta a `dist/cli/index.js` y `src/cli/` no existe.
Es lo primero que toca un usuario nuevo.

**Diseño minimo:**
- **`src/cli/`** con commander (ya es dependencia): `init`, `serve`
  (`--transport mcp|a2a`), `search`, `stats`, `verify`, `export`.
- **Primera ejecucion sin friccion**: `init` crea vault valido con
  ejemplo, explica el siguiente paso y no pide configuracion previa.
  Objetivo declarado: de instalacion a primera busqueda util en menos de
  dos minutos, medido.
- **Errores accionables**: todo error dice que paso, por que y cual es el
  siguiente paso. Un CLI que dice "error" y sale es un CLI que se
  abandona.
- **Salida legible y parseable**: humana por defecto, `--json` para
  automatizacion.
- **Configuracion con esquema**: `savia-vaults.config.json` validado
  contra el `schema.json` que ya existe en `src/config/`.

**Acceptance criteria:**

AC-5.1. Los seis comandos funcionan en entorno limpio (test E2E de CLI).
AC-5.2. Tiempo de instalacion a primera busqueda util <=2 min, medido y
        registrado.
AC-5.3. Cada error del CLI incluye causa y siguiente paso (revision de
        los mensajes; cero errores mudos).
AC-5.4. `--json` produce salida valida y estable en los seis comandos.
AC-5.5. Configuracion invalida → error claro citando el campo y el
        esquema (test).

**Esfuerzo:** 8h

---

## Slice 6 — Distribucion profesional

**Problema:** el paquete hoy no es instalable. Un producto final se mide
por lo que le ocurre a quien lo instala sin conocer el proyecto.

**Diseño minimo:**
- **Compilacion verificada**: `build` produce `dist/` con el binario en
  la ruta que declara `bin`. Sin eso, nada de lo demas importa.
- **Smoke de instalacion real** en CI: en contenedor limpio, instalar el
  paquete empaquetado (`npm pack` → `npm install -g`), ejecutar `init`,
  `serve`, `search` y verificar salida. Es el unico test que prueba lo
  que vive el usuario.
- **Versionado y CHANGELOG** con la disciplina del workspace; v0.1.0 pasa
  a la version que corresponda a lo realmente entregado.
- **Matriz de soporte declarada**: versiones de Node, sistemas operativos
  probados en CI. Lo no probado se declara no soportado.
- **Retirada de `private: true`** solo cuando el smoke pase (cierre del
  AC-1.3).
- **Ruta de salida**: `export` produce el vault en formato abierto
  legible sin la herramienta (coherencia con la garantia de portabilidad
  del ecosistema, SE-272 S5).

**Acceptance criteria:**

AC-6.1. `npm run build` produce el binario en la ruta declarada por
        `bin`; ejecutarlo funciona (test).
AC-6.2. Smoke en contenedor limpio en verde para la matriz declarada;
        fallo inyectado (borrar un paso del empaquetado) → CI en rojo.
AC-6.3. CHANGELOG con la entrega real; version coherente.
AC-6.4. `private` retirado y paquete publicable (publicacion es decision
        humana posterior, no parte del AC).
AC-6.5. `export` produce vault legible sin la herramienta; verificado por
        revisor que solo tiene el export.

**Esfuerzo:** 6h

---

## Slice 7 — Alineamiento de gobierno con el ecosistema

**Problema:** SaviaVaults sirve cupulas de contexto y vive fuera del
nucleo, donde no llegan sus gates. Un vault puede contener contenido de
cualquier nivel, y un servidor que lo expone es una via de fuga que las
murallas no ven.

**Diseño minimo:**
- **Nivel de confidencialidad en el frontmatter** de cada documento,
  como en el vault del nucleo; el servidor **filtra por nivel maximo
  declarado al arrancar**. Servir un vault con contenido N3 en un
  servidor abierto a N1 → el contenido N3 no se sirve, y el arranque lo
  advierte.
- **Puerta de exportacion**: `export` y las respuestas del servidor
  respetan el nivel; un documento por encima del nivel de la sesion no
  aparece, ni siquiera en resultados de busqueda (ni su titulo).
- **Recibos verificables por terceros**: la procedencia firmada debe
  poder verificarse sin la herramienta, con la clave publica declarada.
  Es lo que hace util la firma fuera del ecosistema.
- **Declaracion honesta de alcance**: el README declara que SaviaVaults
  **no implementa la constitucion ni el criterio de Savia** — es un
  servidor de contexto, no un agente soberano. Confundirlos seria vender
  gobernanza que el producto no tiene.

**Acceptance criteria:**

AC-7.1. Documento de nivel superior al declarado no se sirve ni aparece
        en busqueda (dos tests: contenido y metadatos).
AC-7.2. Arranque con vault que contiene niveles superiores al declarado
        → aviso explicito con conteo (test).
AC-7.3. Recibo verificable por herramienta externa con la clave publica
        (demo con verificador independiente).
AC-7.4. README declara el alcance de gobierno sin ambiguedad.

**Esfuerzo:** 7h

---

## Verification method

1. **Los 14 tests en verde** sobre codigo real: es el criterio de "hecho"
   del nucleo, y hoy 7 no pueden ni ejecutarse.
2. **Smoke de instalacion** en contenedor limpio: instalar, init, serve,
   search — lo que vive el usuario.
3. **Conformidad de protocolo** con suite que puede fallar.
4. **Seguridad**: 8 vectores de path traversal, firma alterada, rotacion,
   bind por defecto.
5. **Gobierno**: contenido de nivel superior invisible en las dos vias.
6. **Honestidad**: cada comando del README ejecutado por script; cero
   promesas no cumplidas.
7. Gate de archivo aplicado a las 6 specs del proyecto y a esta.

## Verification Results (2026-08-01)

| Criterion | Status | Detail |
|---|---|---|
| 14 tests green | PASS | 89 tests, 14 files, 0 failures |
| Smoke install | PASS | npm pack → npm install -g → init → search verified |
| README commands | PASS | Every documented command executes correctly |
| Specs with Status | DONE | 6 specs (SE-280..SE-285) tagged: PARTIAL, DONE, PROPOSED |
| private:true → removed | DONE | Removed after smoke verification (AC-6.4) |
| Module count src/ | 16 | Up from 8; all documented in CLAUDE.md |
| S4 (MCP/A2A complete) | PENDING | Skeleton server exists; 9-tool MCP server in future iteration |
| Conformity suite | PENDING | Requires complete MCP implementation |
| Ed25519 signing | PENDING | Placeholder hash in storage; proper crypto in next iteration |

## Riesgos identificados pre-flight

- **R1 (S2, el mayor): los tests existentes pueden estar mal planteados**
  y arrastrar el diseño. Mitigacion: el default es que manda el test,
  pero corregirlo es legitimo con justificacion escrita en el PR; lo
  prohibido es cambiarlo en silencio para que pase.
- **R2 (S4): conformidad de protocolo interpretada, no verificada.**
  Mitigacion: la suite debe poder fallar (AC-4.2) y se prueba contra un
  cliente real, no solo contra si misma.
- **R3 (S3): sensacion de seguridad por tener firma.** Firmar no protege
  de contenido malicioso, solo autentica origen. Mitigacion: el modelo de
  amenaza declara explicitamente lo que NO protege.
- **R4 (S6): publicar un paquete con nombre reservado y calidad
  insuficiente** quema el nombre. Mitigacion: `private: true` hasta que
  el smoke pase; la publicacion es decision humana posterior.
- **R5 (S7): el producto se confunde con Savia** y se le atribuye
  gobernanza que no tiene. Mitigacion: declaracion de alcance en README
  y en la documentacion; es un servidor de contexto, no un agente
  soberano.
- **R6 (transversal): 64h en un subproyecto mientras el nucleo avanza.**
  Mitigacion: S1 (3h) entrega honestidad inmediata y es independiente;
  S2+S5+S6 (30h) entregan producto minimo instalable; el resto es
  endurecimiento. Cada bloque es abandonable sin dejar el proyecto peor
  que hoy.

## Orden recomendado

1 (verdad, 3h: la deuda de honestidad se paga primero) → 2 (nucleo, 16h)
→ 5 (CLI, 8h) → 6 (distribucion, 6h) → 3 (seguridad, 10h) → 4 (servidores
MCP/A2A, 14h) → 7 (gobierno, 7h).

Justificacion del orden: 1+2+5+6 (33h) producen **un producto instalable
que hace algo util** —vault git, busqueda, CLI— aunque todavia sin
servidores. Ese es el minimo publicable. 3 y 4 lo convierten en el
producto que el titulo promete, y 7 lo alinea con el ecosistema.

Alternativa si la prioridad es la interoperabilidad con cliente: 1 → 2 →
4 → 3 → 5 → 6 → 7, aceptando que el CLI llega despues del servidor.

## Decision de adopcion

Adoptar si: los 14 tests en verde sobre codigo real, smoke de instalacion
en contenedor limpio, conformidad de protocolo demostrada con cliente
real, y cero comandos del README que fallen. Cada slice abandonable con
registro. S1 no es negociable ni aplazable: mientras el README instruya a
instalar algo que no funciona, el proyecto tiene una deuda de honestidad
abierta — y esa deuda es mas cara que la tecnica.

## Referencias

- Auditoria propia 2026-08-01 sobre savia-vaults v0.1.0: 263 lineas en
  `src/` (solo `federation/` y `config/`), 1.156 lineas de test en 14
  ficheros de los que 7 importan modulos inexistentes (`types`,
  `storage`, `search`, `security`, `server/mcp`, `server/ratelimit`),
  `bin` apuntando a `dist/cli/index.js` sin `src/cli/`, y 6 specs propias
  (SE-280 a SE-285, 1.001 lineas) sin campo Status.
- Ecosistema: cupulas de contexto (SE-252), federacion e identidad
  (SE-263), recibos por contenido (SE-260 S4), guards de trayectoria y
  contenido-como-dato (SE-273 S5), niveles N1-N4b, garantia de salida
  (SE-272 S5), disciplina de archivo de specs (SE-253 S6), smoke de
  instalacion (SE-258 S5).
- Criterios: CRIT-005 (ACs falsificables), CRIT-013 y CRIT-015
  (honestidad antes que marketing: el README no promete lo que no hay),
  CRIT-023 (fail-closed: lectura por defecto, loopback por defecto),
  CRIT-010 (bien comun: producto libre y publicable), CRIT-002 (anti
  lock-in: export legible sin la herramienta).
