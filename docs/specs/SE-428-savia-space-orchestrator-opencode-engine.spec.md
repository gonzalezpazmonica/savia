---
status: IMPLEMENTING
priority: P1
developer_type: agent-single
created: 2026-10-02
author: Savia
phase: A
risk: L3
related_specs: [SE-429, SE-430, SE-431, SE-401, SE-396, SE-304]
origin: "Mandato de la operadora: Savia Space como cliente sustituto de OpenCode, compatible con él, con la arquitectura de Savia y con sus flujos y hooks. Decisiones 2026-10-02 (AskUserQuestion): modelo híbrido con OpenCode como motor; sustituto primero; hooks bash registrados; sesión interactiva en el checkout"
resource: https://opencode.ai/docs/server/
---

# SE-428 — Savia Space como sustituto de OpenCode, con OpenCode como motor

## Problema

Savia trabaja hoy a través de frontends de agentes, sobre todo OpenCode. El encargo de Savia
Space es un cliente que **sustituya a OpenCode y sea compatible con él**, con la arquitectura,
los flujos y los hooks de Savia. Un primer prototipo local (no publicado) se quedó en un espacio
de lectura con evidencia: sin sesiones de agente, herramientas, comandos ni hooks. La operadora
lo descartó como entrega; su código se reutiliza aquí (ver «Reutilización»).

## Objetivo

Que la operadora pueda hacer una jornada normal de Savia en Space sin abrir la TUI de OpenCode.

- **Mismo motor**: Space conduce el servidor de OpenCode con el mismo `opencode.json`, los mismos
  plugins y guards de Savia, y los mismos agentes, skills, comandos y MCP.
- **Sesiones compatibles en los dos sentidos**: también se abren con `opencode attach`.
- **Más de lo que da OpenCode**:
  - evidencia de bytes exactos (modo de evidencia, §8);
  - recibos, plano e inspector;
  - interop con terceros (SE-429) y móvil (SE-430);
  - Savia Soul (SE-431).

## Dos perfiles de ejecución

| | Interactivo (paridad) | Mediado |
|---|---|---|
| Cuándo | la operadora conduce la sesión | Soul, terceros, schedules y sprints autónomos |
| Permisos | los de `opencode.json`, sin cambios; las preguntas del motor van a la UI de Space | `opencode.json` endurecido por Space: toda acción con efecto pregunta; envolvente de tarea y lista bloqueada |
| Directorio | el checkout del proyecto, como hoy en OpenCode | worktree propio en una rama `agent/*` |
| Evidencia | historial y diff de la sesión | recibo firmado de la tarea |

Space nunca afloja `opencode.json`; solo puede endurecerlo. Las reglas de seguridad autónoma
(ramas `agent/*`, PR solo en Draft, nunca merge sin grant) aplican igual que hoy.

## Diseño

1. **Proceso del motor.**
   - Space arranca `opencode serve` en loopback, con puerto aleatorio y una contraseña aleatoria
     por arranque. El servidor de OpenCode no tiene autenticación sin ella (verificado en
     1.18.32).
   - Fija el hash de la OpenAPI del motor y no lo usa si no coincide.
   - Carga los plugins del workspace (sin `--pure`). Si falta el plugin de guards de Savia, el
     motor queda en modo degradado y no admite sesiones con escritura.
   - Si el motor cae, la ejecución queda interrumpida y nunca se reenvía un prompt
     automáticamente.
2. **Paridad con OpenCode.**
   - **P0**: sesiones (crear, listar, renombrar, borrar, fork), prompt con streaming y abort,
     permisos y preguntas, cambio de agente y de modelo, paleta de comandos, catálogo de agentes
     y skills, diff y revert, `opencode attach`.
   - **P1**: terminal, explorador de ficheros, todo y subagentes, MCP, compactar.
   - Compartir sesiones públicamente queda desactivado.
3. **Hooks de Savia.**
   - Dentro del motor, los guards del plugin de Savia siguen actuando como hoy.
   - Para los eventos que ocurren en Space (prompts desde la web, el móvil, la mensajería o A2A;
     exportar; crear ramas o PR Draft; compactar; fin de turno), Space ejecuta **los mismos hooks
     registrados en `.claude/settings.json`**, con el contrato de Claude Code y sin reimplementarlos.
   - Sin doble disparo: lo que ya cubre el plugin no se repite.
   - Nunca se ejecutan hooks declarados en assets importados.
4. **Instrucciones y modelos.**
   - Las sesiones de agente cargan las instrucciones de `opencode.json`, como hoy.
   - Los modelos se resuelven por tier, con Space como un frontend más del esquema de tiers.
     Ningún modelo se fija en el código.
5. **Mediación** (solo en el perfil mediado). Space decide cada petición de permiso del motor:
   - **denegar**: lista bloqueada;
   - **automático**: dentro de la envolvente;
   - **persona**: en el resto, desde la web, el móvil o A2A.
   Una automatización nunca responde "siempre".
   - El worktree por ejecución y esta política solo rigen en el perfil mediado y en ejecuciones
     autónomas; en interactivo mandan los permisos de `opencode.json` sin cambios.
   - **Riesgo determinista**: el riesgo de una tarea de agente (edición o ejecución: al menos
     medio; push, PR Draft o salida a red: alto) lo calcula Space con la función de SE-429, nunca
     el modelo. Decide el sandbox y si la aprobación exige biometría.
   - **Salidas no fiables**: la salida, el resumen y el diff de una ejecución hija, los
     comentarios y descripciones de PR y los logs de CI llegan a quien los consume marcados como
     no fiables.
   - **Exclusión declarada (pendiente de mitigar)**: los procesos que lanza el agente (shell,
     terminal, MCP y LSP locales) heredan hoy el entorno del motor, incluida su contraseña, y
     podrían llamar a la API del motor saltándose la mediación. Hasta que se mitigue, la
     mediación no garantiza nada frente a un agente hostil en ejecuciones con shell, y el recibo
     lo declara.
6. **Evidencia** (perfil mediado). Recibo firmado con:
   - envolvente y aprobación;
   - versiones y hashes del motor, plugins y configuración;
   - commits base y final;
   - cada llamada a herramienta con su decisión;
   - hash del diff, checks y estado final.
7. **Flujos de Savia.** Clock-in/clock-out, `pr-plan`, validación local de CI, roadmap, memoria,
   overnight-sprint y code-improvement-loop se ofrecen como acciones ejecutadas por el motor. Space
   no los reescribe.
8. **Modo de evidencia.** Además de las sesiones de agente, Space conserva un modo propio para
   trabajo de lectura sobre las cúpulas:
   - la persona ve los bytes exactos que recibirá un modelo local y aprueba su hash;
   - las citas se comprueban literalmente contra las fuentes.
   Es un modo dentro del sustituto, no el producto.

## Reutilización del prototipo

El prototipo descartado (servidor Rust y cliente Vue) se reutiliza en la 0.2:

| Pieza del prototipo | Uso en el sustituto |
|---|---|
| JSON estricto, canonicalización JCS (RFC 8785), hashes y vectores de test | contratos, recibos y verificación en el cliente |
| journal SQLite con eventos por secuencia, idempotencia, retención y bloqueo de instancia | estado de Space: sesiones, eventos del motor normalizados y recibos |
| máquina de estados de ejecuciones, cancelación con valla y recuperación sin reenvío | supervisión de las ejecuciones del motor y del modo de evidencia |
| SSE con backlog, deduplicación por secuencia y revalidación de la sesión web | streaming hacia la web y el móvil |
| seguridad local: Host/Origin, marcas de mutación, cookie `HttpOnly`, emparejado por socket | base de la UI propia |
| ensamblado de contexto, validación determinista de citas y adaptador de Ollama | modo de evidencia (§8) |
| cliente Vue: API, reductor de eventos, verificación de hash e inspector | base del cliente sustituto (sesiones, permisos, diff) |

Lo que es nuevo: el adaptador del motor de OpenCode, la paridad de la UI, el bus de hooks y la
mediación.

## Fuera de alcance

- Efectos externos generales (API de terceros, despliegues): siguen esperando a un contrato de
  admisión aprobado (AEK, ADR-002 fase F).
- Merge de PRs por agentes.
- Sustituir el motor de OpenCode en esta spec.

## Entregas

- **0.2 (sustituto mínimo)**: motor, paridad P0 en modo interactivo, hooks de Savia en eventos
  de Space y `opencode attach`.
- **0.3**: paridad P1, modo mediado con recibos y flujos de Savia como acciones.
- **0.4**: interop con terceros (SE-429) y móvil (SE-430).
- **0.5**: Savia Soul (SE-431).

## Criterios de aceptación

- **AC1**: un motor con OpenAPI distinta de la fijada no se usa; uno sin el plugin de guards no
  admite escritura.
- **AC2**: el puerto del motor rechaza peticiones sin contraseña.
- **AC3**: en una sesión interactiva, un `git push --force` del agente lo bloquea el guard de Savia,
  igual que en OpenCode.
- **AC4**: un prompt enviado desde Space ejecuta los hooks `UserPromptSubmit` registrados; si uno
  bloquea, el prompt no llega al motor.
- **AC5**: un comando de la paleta produce la misma salida que en OpenCode, con el mismo modelo y
  la misma sesión.
- **AC6**: una sesión creada en Space se abre con `opencode attach` con el mismo historial, y un
  permiso pendiente aparece en ambos.
- **AC7**: en modo mediado, un permiso de edición que `opencode.json` permite se convierte en
  pregunta, sin modificar el fichero.
- **AC8**: un hook declarado en un asset importado no se ejecuta.
- **AC9**: en modo mediado, el recibo verifica con la clave pública de la instancia y su hash de
  diff coincide con el worktree.
- **AC11**: la misma envolvente da siempre el mismo riesgo, y ningún texto del modelo o del
  agente autónomo lo cambia; una envolvente con edición no se aprueba con delegación acotada
  desde el móvil.
- **AC12**: la salida de una ejecución hija llega a su consumidor marcada como no fiable.
- **AC13**: un test del worktree, lanzado por un comando aprobado en modo mediado, que llama a la
  API del motor con su contraseña recibe 401 y genera un aviso. Mientras no pase, la exclusión
  sigue declarada en los recibos.
- **AC10**: cinco jornadas de trabajo real de la operadora solo con Space, sin abrir la TUI de
  OpenCode para nada de P0. Cada apertura necesaria se registra con su causa.

## Hallazgos de la implementación (2026-10-03)

Medidos en el prototipo local contra OpenCode 1.18.32, con un modelo local (Ollama).

- **Contraseña del motor**: `OPENCODE_SERVER_PASSWORD` activa HTTP Basic con usuario fijo
  `opencode`. Sin cabecera, con otro usuario o con Bearer, responde 401 (AC2).
- **Guards ya dentro del motor**: el plugin de guards de Savia ejecuta el registro de hooks bash
  del workspace. Un `git push --force` pedido por el agente se bloqueó antes de pedir permiso
  (AC3). En interactivo, el bus de Space no repite PreToolUse.
- **Reglas de sesión**: un `PermissionRuleset` pasado al crear una sesión prevalece sobre la
  configuración global. Con `bash: ask` global, una sesión creada con `bash * allow` ejecutó sin
  preguntar.
  - `PATCH /session` añade reglas y gana la última.
  - La API de Space no acepta reglas de sesión.
  - En modo mediado, Space neutraliza las que traiga cualquier otro cliente del motor (añade
    `ask *`, con aviso y freno anti-bucle).
  - En interactivo, avisa.
- **Salida a red sin preguntar**: con la configuración por defecto, el modelo pidió varios
  `webfetch` a URLs inventadas, una de ellas para descargar un script.
  - El modo mediado superpone una configuración más estricta (`OPENCODE_CONFIG_CONTENT`): lo no
    denegado pasa a `ask` y nunca se relaja un `deny`.
  - El resultado se verifica regla a regla.
- **Sandbox del usuario**: algunos plugins envuelven el comando (`bwrap … bash -c '<cmd>'`) en
  la entrada de la herramienta y en el patrón del permiso.
  - Desenvolver no basta: `bwrap … -c 'echo hola'; rm -rf x` se desenvolvería a `echo hola`.
  - Solo se desenvuelve un envoltorio limpio (tras la última comilla simple, solo cierres de
    comillas) y los guards evalúan la forma original y la desenvuelta; manda la más estricta.
  - La interfaz muestra el comando entero si no es un envoltorio limpio.
- **Orden de plugins**: si el plugin de sandbox se carga antes que el de guards, los guards del
  motor reciben la orden ya envuelta. Con los guards reales, `rm -rf` y `sudo` dejaron de
  bloquearse (rc 2 → 0). El plugin de guards debe evaluar ambas formas (PR #1237) y Space avisa
  del orden.
- **«Permitir siempre»**: el motor guarda la aprobación en su base de datos, por proyecto y sin
  caducidad, y deja de preguntar. Space no recibiría la petición de permiso para mediarla, así que
  no ofrece «siempre» y su diagnóstico lista las aprobaciones permanentes que existan.
- **Doble disparo** (canario por hook, modo mediado): `UserPromptSubmit` y `PreToolUse` se
  ejecutan en el motor y en Space; `PostCompact`, solo en el motor. El contexto inyectado llegaba
  dos veces: con el plugin de guards presente, Space decide el bloqueo pero no lo inyecta.
- **Contrato de salida distinto**: un hook de prompt que escribe texto plano añade contexto en
  Claude Code y bloquea el prompt en el plugin de guards del motor. El prompt se perdía en
  silencio; Space muestra ahora el motivo.
- **Sesión ocupada**: revertir con la sesión trabajando devuelve 409; compactar se queda colgado.
  Space rechaza antes y la interfaz desactiva esas acciones. `POST /api/session/{id}/compact`
  devuelve 503 en 1.18.32; se usa `POST /session/{id}/summarize` con el modelo de la sesión.
- **Contexto de modelos locales**: el prompt del motor ocupa ~14 800 tokens y Ollama lo trunca a
  4 096 por defecto, sin error. El diagnóstico y el selector de modelo lo avisan.
- **Cambios de sesión**: `GET /session/{id}/diff` volvió vacío aunque el agente escribió un
  fichero. Space calcula los cambios con el git del workspace, solo con rutas dentro de él.
- **Parada del motor**: `opencode serve` ignora SIGTERM. Space lo para con SIGKILL al apagarse y,
  al arrancar, recoge un motor huérfano de una ejecución anterior.
- **Compatibilidad con `opencode attach` (AC6)**: la contraseña llega por un canal local del
  mismo usuario y nunca pasa por HTTP. La historia vista por el motor y por Space coincide.

## Decisiones tomadas

- **D23-5 (operadora, 2026-10-03)**: en modo mediado, un hook marcado `blocking: true` que
  falla o no responde bloquea el permiso con la causa. En interactivo, el fallo no bloquea, como
  en Claude Code, y queda en la traza.

## Decisiones pendientes

- **D1**: addendum a ADR-002 — Space como frontend de Savia no amplía la autoridad: herramientas
  locales con los hooks de Savia; efectos externos con admisión externa.
- **D2**: un motor por proyecto (propuesto) o uno por usuaria.
- **D3**: sandbox obligatorio para ejecuciones mediadas con shell (propuesto).

## OpenCode Implementation Plan

### Bindings touched

| Componente | Claude Code | OpenCode |
|---|---|---|
| Motor de agentes | no aplica en esta spec | `opencode serve` como proceso hijo; API fijada por hash de OpenAPI; `opencode attach` compatible |
| Hooks de Savia | los scripts de `.claude/settings.json` se ejecutan desde el bus de Space con el contrato de Claude Code | el plugin de guards de Savia sigue cargado en el motor |
| Agentes, skills y comandos | sin cambios | se leen del catálogo del motor (`.opencode/agents`, skills, commands) |

### Verification protocol

- [ ] Tests de contrato del adaptador contra la versión de OpenCode fijada.
- [ ] Canarios por hook: cada evento se dispara una sola vez (motor o bus).
- [ ] Escenarios AC1–AC9 y AC11–AC13 en CI con un motor local de prueba; AC10 con la operadora.

### Portability classification

- [x] **DUAL_BINDING**: los hooks de Savia funcionan con el contrato de Claude Code (bus de Space) y
  con el plugin de OpenCode (motor) desde el primer slice. El motor es OpenCode; los adaptadores
  de Codex y Claude Agent SDK quedan para después de la ablación (ADR-002 fase D).
