---
status: APPROVED
approved_at: 2026-10-06
approved_by: "operadora, AskUserQuestion 2026-10-06 (con las recomendaciones de Savia)"
delta_approved: "gonzalezpazmonica 2026-10-13, delta «niveles con proveedor en la nube»: N3+ sin pregunta y N2 con recibo"
priority: P1
developer_type: agent-team
created: 2026-10-06
author: Savia
phase: A
risk: L3
related_specs: [SE-428, SE-432, SE-434]
origin: "Validación e2e del caso «gallinero autónomo» en Savia Space (2026-10-06): 2 de 7 pasos OK. Esta spec cubre los huecos G-01 (crear proyecto), G-02 (crear cúpula y escribir notas), G-03 (adjuntar contexto a una sesión), G-06 (traza en modo interactivo) y G-07 (guardar el resultado). Diseño interno SS30. Decisiones D30-1..D30-6 y D23-14 (reformulada tras D-MODEL-CLOUD (inferencia en la nube por defecto)) resueltas con la recomendación de Savia el 2026-10-06."
timeline:
  - from: "2026-10-06"
    learned: "2026-10-06"
    value: "PROPOSED"
    source: "spec-lifecycle:auto"
  - from: "2026-10-13"
    learned: "2026-10-13"
    value: "APPROVED"
    source: "spec-lifecycle:auto"
---
# SE-436 — Savia Space: proyectos y cúpulas desde Space

## Problema

La validación e2e del caso «gallinero autónomo» intentó hacer, solo desde la UI de Space, un caso de uso normal: crear un proyecto con su cúpula, diseñar con el motor usando esa cúpula y guardar el resultado. Se quedó en 28 sobre 100. Lo que existe funciona; lo que falla son funciones que no existen:

- **G-01:** no se puede crear un proyecto. Solo existe `GET /api/v1/projects`, y los proyectos salen de `config.json`, que se edita a mano.
- **G-02:** no se puede crear una cúpula ni escribir notas. La capa de conocimiento es de solo lectura. Con el directorio vacío, la UI no avisa de que falta ni dice cómo crearla.
- **G-03:** no se puede adjuntar una cúpula o unas notas a una sesión. Hubo que escribir las rutas en el prompt.
- **G-06:** en modo interactivo no hay traza ni recibos de un run. REPLAY dice «solo modo mediado», y `GET /api/v1/engine/receipts` responde 503.
- **G-07:** el resultado solo vive en el hilo del chat. No hay forma de guardarlo como nota de la cúpula ni como fichero del proyecto.

Además pesan dos hechos:

- Desde D-MODEL-CLOUD, la inferencia va por defecto a un proveedor de nube y el contenido N2 o superior no puede salir en silencio. La recomendación anterior para adjuntar notas («solo N1 y solo con modelo local») deja hoy cero casos útiles por defecto.
- El registro de cúpulas por defecto de SaviaVaults (`savia-vaults.domes.json`) es un fichero versionado en el repositorio. Si una cúpula creada desde Space se registrara ahí, sus nombres y rutas se publicarían.

## Objetivo

Que una persona haga el caso completo desde la UI, sin tocar ficheros a mano:

1. crear el proyecto «Gallinero autónomo» con su cúpula;
2. escribir notas en ella;
3. adjuntarlas a una sesión, sabiendo qué sale y hacia qué proveedor;
4. guardar el resultado como nota o como fichero del proyecto;
5. revisar después qué hizo el motor.

Con tres garantías:

- **solo la persona escribe:** el agente propone y la persona acepta;
- **cada escritura deja un recibo;**
- **nada N2 o superior sale hacia la nube sin una confirmación explícita.**

## Diseño

### 1. Proyecto (G-01; D30-1, D30-6)

- Un proyecto de Space **es un proyecto de Savia**: vive en `projects/{slug}/` del workspace, que git ignora por la regla `projects/*`. `config.json` (estado privado de Space, modo 0600) guarda solo el **binding**.
- `ProjectConfig` pasa a `schemaVersion: 2` y gana un campo, `root`: el slug relativo a `projects/`. Las configuraciones v1 se migran al cargar, sin `root`, y quedan como proyectos «sin carpeta».
- `POST /api/v1/projects`. Entrada:
  `{title: string 1..80, slug: string, description: string ≤ 280, dome: {mode: NEW | EXISTING | NONE, domeId?: string, level?: N1 | N2}, registerInWorkspace: boolean, expectedConfigRevision: Hash, idempotencyKey: Key}`
- Salida 201: `{project: ProjectSummary, receipts: WriteReceipt[]}`.
- Lo que crea:
  - `projects/{slug}/CLAUDE.md` mínimo: título, descripción y la línea «Proyecto creado desde Savia Space». Sin instrucciones para agentes.
  - la cúpula, si `dome.mode = NEW` (§2);
  - el binding, con escritura atómica (fichero temporal y `rename` en el mismo directorio) y copia de la revisión anterior;
  - con `registerInWorkspace: true`, una fila en la tabla de proyectos de `CLAUDE.local.md`, que git ignora.
- Validación:
  - El slug cumple `^[a-z0-9]+(-[a-z0-9]+)*$` y tiene como máximo 48 caracteres; si no, 400 `INVALID_SLUG`.
  - Si `projects/{slug}/` ya existe: 409 `SLUG_TAKEN`. Nunca se reutiliza ni se sobrescribe un directorio.
  - Si `expectedConfigRevision` está desfasada: 409 `STALE_REVISION`.
- Enlazar un proyecto que ya existe es otra acción, `POST /api/v1/projects/link` con `{slug, …}`. Solo escribe el binding.
- La alta es un acto de la persona en la UI emparejada (cookie `HttpOnly` y `SameSite=Strict`, con comprobación de Host y Origin). El motor y sus procesos no tienen esa cookie, así que no pueden crear proyectos. Esto cumple D-MED-8: la configuración escribible por el agente no amplía su propio entorno.

### 2. Cúpula y notas (G-02; D30-2, D30-3)

- **Cúpula de proyecto:** `projects/{slug}/vault/`, con la plantilla de vault de proyecto (`00-Index` … `99-Inbox`). **Cúpula de workspace:** `vaults/{name}/`. Ambas son repositorios git de SaviaVaults, y git ignora las dos rutas.
- **Registro:** las cúpulas creadas desde Space se registran en un **registro local no versionado**, que SaviaVaults fusiona con el registro base (D30-2). Space nunca escribe en el registro versionado. Si SaviaVaults no admite todavía un registro local, S2 lo añade primero.
- **Niveles:**
  - Space crea cúpulas N1 y N2.
  - N3, N4 y N4b se crean por CLI. En Space aparecen como objetos opacos: nombre, nivel y la leyenda «fuera del alcance de Space», sin contenido (D30-3).
  - Una nota nunca tiene un nivel inferior al de su cúpula.
- **API:**

| Método y ruta | Entrada | Salida |
|---|---|---|
| `POST /api/v1/domes` | `{name, projectId \| null, level: N1 \| N2, description ≤ 280, idempotencyKey}` | 201 `{dome, receipt}` |
| `GET /api/v1/domes/{id}/notes/{path}` | — | 200 `{path, content, contentHash, level, frontmatter}` |
| `PUT /api/v1/domes/{id}/notes/{path}` | `{content, expectedHash: Hash \| null, idempotencyKey}` | 200 o 201 `{note, receipt}`; 409 `STALE_CONTENT` |

- **Cómo escribe:** por MCP con `vault_write`, que hace un commit git con el hash, usando una credencial de **escritura** separada de la lectora. Si no hay MCP, escribe el fichero y hace un commit en la cúpula por directorio, y lo declara.
- **Frontmatter de toda nota escrita por Space:** `title`, `confidentiality`, `provenance: person | generated`, `source_session`, `receipt`, y `trust: untrusted` cuando la procedencia es `generated`. Esta última marca solo la quita la persona, editando la nota a mano.

### 3. Escritura segura: propuestas y recibos (G-07)

- **Quién escribe:** solo Space, por una acción de la persona. El agente nunca escribe en una cúpula ni en un proyecto a través de Space.
- **`Proposal`:** `{id, sessionId, runId | null, origin: PERSON | AGENT, target: {kind: NOTE | PROJECT_FILE, domeId | projectId, path}, content, contentHash, baseHash | null, rationale ≤ 500, state: PENDING | ACCEPTED | REJECTED | EXPIRED, createdAt}`. Caduca a los 7 días.
  - Se crea desde un mensaje del asistente, con «Guardar como nota» o «Guardar en el proyecto»: `POST /api/v1/sessions/{id}/proposals`.
  - O la crea el agente con la tool MCP de Space `space_propose_write {target, content, rationale}`, que **solo crea la propuesta**.
- **Aceptar:** `POST /api/v1/proposals/{id}/accept {content, contentHash, expectedBaseHash}`. La persona ve el destino, el nivel y el diff contra `baseHash`, y puede editar antes de aceptar. Si la base cambió: 409 `STALE_CONTENT` y la UI recalcula el diff. Rechazar: `POST /api/v1/proposals/{id}/reject`.
- **`WriteReceipt`:** `{receiptId, kind: PROJECT_CREATE | DOME_CREATE | NOTE_WRITE | FILE_WRITE | ATTACH_CONSENT, target: {kind, id, relPath}, contentHash, previousHash | null, origin: PERSON | AGENT_PROPOSAL, proposalId | null, principal, at, signature: JWS | null, unsignedReason: string | null}`. Se guarda en el journal de Space. Lleva firma cuando se resuelva D23-15; hasta entonces va sin firma y lo declara en `unsignedReason`.
- **Rutas:**
  - relativas;
  - segmentos `[A-Za-z0-9._-]`, sin `..` y sin `.` inicial;
  - profundidad ≤ 4 y ≤ 200 caracteres; `.md` en las notas;
  - contenido ≤ 256 KiB;
  - ningún componente puede ser un symlink, y se comprueba por descriptor, no por texto.
- **Destinos denegados para `PROJECT_FILE`** (403 `PATH_DENIED`): `.git/`, `.claude/`, `.opencode/`, `CLAUDE.md`, `AGENTS.md`, `opencode.json` y `*.local.*`. Un agente no puede proponer sus propias instrucciones.

### 4. Adjuntar contexto (G-03; D23-14)

- **Dos formas:**
  - **notas:** el contenido exacto va en línea. Como máximo 8 notas y 16 KiB por nota, marcadas `untrusted_source`.
  - **cúpula por referencia:** el índice y la raíz van en el prompt, y el motor lee bajo demanda.
- Adjuntar nunca escribe y nunca cambia los permisos de `opencode.json`.
- **API:** `PUT /api/v1/sessions/{id}/attachments`. Entrada:
  `{items: ({kind: NOTE, domeId, path, contentHash} | {kind: DOME, domeId})[1..8], providerProfileId, expectedRevision, idempotencyKey}`
- Salida: `AttachmentSet = {revision, items, destination: CLOUD | LOCAL, egressPreview: {bytes, hashes, levels}, requiresConfirmation: boolean}`.
- **Política por nivel y destino** (D23-14 resuelta con la opción (d), aprobada el 2026-10-06):

| Nivel | Destino LOCAL | Destino CLOUD |
|---|---|---|
| N1 | se adjunta | se adjunta |
| N2 | se adjunta | solo tras `POST /api/v1/sessions/{id}/attachments/{revision}/confirm {payloadHash}`, que deja un recibo `ATTACH_CONSENT` |
| N3, N4, N4b | fuera del alcance de Space (D30-3) | 403 `LEVEL_NOT_ALLOWED`, siempre |

- Un `payloadHash` que no coincide con la vista previa da 409 `CONTEXT_CHANGED`.
- **Límite declarado:** en modo interactivo, el motor puede leer cualquier fichero que su configuración permita. Adjuntar solo es una frontera de confidencialidad si lo respalda el guard de §5.

### 5. Guard de cúpulas en el motor (D30-4)

- Un hook registrado en el bus de Space y en el plugin savia-gates lee las raíces y los niveles del registro fusionado:
  - **escritura** del motor (`edit`, `write` o `bash` que escriba) dentro de la raíz de una cúpula → `ask`, con el mensaje «Usa una propuesta: Guardar como nota»;
  - **lectura** de una cúpula N3, N4 o N4b con un proveedor de nube → `deny` con `LEVEL_NOT_ALLOWED`, sin pregunta. Lo privado nunca se resuelve con una pregunta. La denegación queda en la traza y en el registro de decisiones;
  - **lectura** de una cúpula N2 que no está adjunta, con un proveedor de nube → `ask` con la cúpula, el nivel y el proveedor. Se pregunta una vez por cúpula y sesión. Si la persona acepta, Space deja un recibo `ATTACH_CONSENT` de esa cúpula para la sesión, y cada fichero leído bajo ese consentimiento queda en la traza con su `contentHash`. Si rechaza, las lecturas siguientes de esa cúpula en la sesión dan `deny`;
  - la regla vale igual para las lecturas por las tools MCP `vault_*` que para `read`, `grep`, `glob` o `bash`.
- En modo mediado ya rige SE-434: las cúpulas son de solo lectura en el sandbox. Además, Space aplica la misma regla de niveles de lectura al decidir cada permiso de las tools del motor. **Límite declarado:** las lecturas por `bash` dentro del sandbox no pasan por esa decisión; las cubre el sandbox solo cuando oculta al motor las cúpulas de esos niveles (máscaras de nivel de SE-434).

### 6. Traza en modo interactivo (G-06; D30-5)

- Cada run persiste una **traza observada**: spans de pasos y tool calls, cada uno con `{tool, argsHash, resultHash, durationMs}`, permisos con su decisor (`OPENCODE_CONFIG` o `PERSON`), hooks disparados y las decisiones del registro de decisiones. No incluye los prompts completos.
- La traza va etiquetada «observada, sin mediación» y **sin firma**. No es un `AgentRunReceipt`.
- `GET /api/v1/sessions/{id}/trace` y `GET /api/v1/runs/{id}/trace` la devuelven, y REPLAY la muestra con la misma vista que en mediado.
- En interactivo, `GET /api/v1/engine/receipts` responde 200 `{mode: "INTERACTIVE", items: [], writeReceipts: […]}`, nunca 503.

### 7. UX en el escritorio infinito

- **Paleta:** «Nuevo proyecto», «Enlazar proyecto», «Nueva cúpula», «Nueva nota», «Adjuntar a la sesión», «Guardar como nota» y «Guardar en el proyecto».
- **Estados vacíos:**
  - con solo el proyecto de demostración, una tarjeta «Crea tu primer proyecto»;
  - con la capa de conocimiento sin cúpulas, «No hay cúpulas. Crear una».
- **Hoja de alta** de proyecto, con tres campos: nombre (el slug se deriva y se puede editar), descripción y cúpula (nueva con nivel N1 o N2, existente, o ninguna). Debajo, «Se creará» lista las rutas relativas.
  - Al crear, el objeto aparece en un hueco libre del Universo sin mover nada de lo que ya colocó la persona.
  - La cámara lo enfoca, y un aviso enlaza el recibo.
- **Nota:** editor markdown con vista previa en el panel enfocado. El nivel y la procedencia son de solo lectura. Guardar deja un recibo.
- **Adjuntar:** se arrastra la nota o la cúpula a la sesión, o se usa el chip «+ Contexto» del compositor. El **anillo de contexto** muestra cada adjunto con su nivel y su destino («Nube · {proveedor}» o «Local»). Si hace falta confirmación, el anillo lo dice y abre la vista previa.
- **Ontología** (SE-432):
  - tipos nuevos: `Proposal` (capa de trabajo, con insignia de pendiente) y `Receipt` de escritura;
  - enlaces nuevos: `PROPOSES` (sesión → propuesta), `WRITES` (recibo → nota o fichero) y `ATTACHED_TO` (nota o cúpula → sesión, con soporte `DECLARED`).
- **Traza:** una pestaña «Traza» en el inspector de sesión y en el de run, que sobrevive a recargar la página.

### 8. Decisiones (resueltas el 2026-10-06: la operadora aprobó la recomendación de Savia en cada una)

El diseño de §1–§7 aplica estas decisiones, todas resueltas con la recomendación de Savia (operadora, 2026-10-06).

| ID | Pregunta | Opciones | Decisión (recomendación aprobada) | Afecta a |
|---|---|---|---|---|
| D30-1 | Dónde vive un proyecto creado desde Space | (a) en `projects/{slug}/` del workspace, con el binding en `config.json`; (b) solo en el estado privado de Space; (c) no crear: solo enlazar proyectos que ya existen | **(a)**: un único proyecto para Savia y para Space, y la regla de leer `projects/{nombre}/CLAUDE.md` sigue valiendo. (b) crea proyectos que Savia no ve; (c) deja G-01 sin resolver | S1, AC1–AC4 |
| D30-2 | Dónde se registran las cúpulas nuevas | (a) en el registro base versionado de SaviaVaults; (b) en un registro local no versionado que SaviaVaults fusiona con el base; (c) en un registro propio de Space que solo lee Space | **(b)**: (a) publica nombres y rutas en el repositorio; (c) deja la cúpula invisible para el MCP y para los demás frontends | S2, AC5 |
| D30-3 | Qué niveles crea y muestra Space | (a) crea N1 y N2; N3, N4 y N4b se crean por CLI y aparecen opacos; (b) crea todos los niveles y muestra el contenido N3 o superior solo con inferencia local; (c) solo N1 | **(a)** ahora; **(b)** cuando se resuelva la semántica de revocación de N2 y superiores (D-N2). (c) no sirve para proyectos de empresa | S2, AC8; S4, AC15 |
| D23-14 | Adjuntar notas de las cúpulas a sesiones del motor (reformulada tras D-MODEL-CLOUD) | (a) solo con modelo local; (b) solo notas N1, a cualquier proveedor; (c) nunca; (d) por nivel y destino: N1 sin fricción; N2 hacia la nube solo con vista previa, confirmación y recibo; N3 o superior nunca hacia la nube; con un perfil local, N1 y N2 sin el paso extra | **(d)**. Con la inferencia local desactivada por defecto, (a) deja adjuntar inservible; la combinación anterior, (a) y (b), da cero casos útiles por defecto. (d) cumple «nada N2 o superior a la nube en silencio» y da uso real | S4, AC13–AC16 |
| D30-4 | Lecturas y escrituras directas del motor sobre cúpulas en modo interactivo | (a) declararlo y no hacer nada; (b) guard con `ask`: escritura en una cúpula, y lectura de una cúpula N2 o superior no adjunta con proveedor de nube; (c) denegar | **(b)**. Con (a), adjuntar no protege nada, porque el motor lee lo que su configuración permite; (c) rompe la paridad del modo interactivo | S5, AC17–AC18 |
| D30-5 | Traza de los runs en modo interactivo | (a) traza observada, persistida y sin firma; (b) `AgentRunReceipt` firmado también en interactivo; (c) nada | **(a)**: (b) aparenta una mediación que en interactivo no existe; (c) deja G-06 abierto | S6, AC19–AC21 |
| D30-6 | Registrar el proyecto nuevo en `CLAUDE.local.md` | (a) siempre, de forma automática; (b) con una casilla visible, marcada por defecto; (c) nunca | **(b)**: Savia conoce el proyecto sin pasos manuales, y la persona ve y decide qué se escribe fuera de `projects/{slug}/` | S1, AC1 |

## Slices

| Slice | Contenido | Depende de | Aceptación |
|---|---|---|---|
| S1 | Binding v2, migración, `POST /api/v1/projects` y `/link`, hoja de alta, estado vacío, recibos `PROJECT_CREATE` | — | AC1–AC4 |
| S2 | Registro local de cúpulas, `POST /api/v1/domes`, lectura y escritura de notas, editor, recibos `DOME_CREATE` y `NOTE_WRITE` | S1 | AC5–AC8 |
| S3 | `Proposal`, «Guardar como nota» y «Guardar en el proyecto», tool `space_propose_write`, aceptar y rechazar, destinos denegados | S2 | AC9–AC12 |
| S4 | Adjuntos, política por nivel y destino, vista previa y confirmación, anillo de contexto | S2 (D23-14 resuelta) | AC13–AC16 |
| S5 | Guard de cúpulas en el bus de Space y en savia-gates | S2 (D30-4 resuelta) | AC17–AC18b |
| S6 | Traza observada en interactivo, pestaña Traza y receipts con 200 | — | AC19–AC21 |

Orden: S1 → S2 → (S3 en paralelo con S4) → S5. S6 va en paralelo desde el principio. El e2e del gallinero se repite al final como AC22.

## Criterios de aceptación

Datos de prueba comunes:

- proyecto «Gallinero autónomo», con slug `gallinero-autonomo`;
- cúpula de proyecto `gallinero`, de nivel N2, en `projects/{slug}/vault/`;
- nota `00-Index/requisitos.md` con el texto «Presupuesto máximo: 400 €. Puerta automática al amanecer y al anochecer.»

**S1**
- **AC1:** `POST /api/v1/projects` con los datos comunes y `dome.mode = NEW` responde 201. Crea `projects/{slug}/CLAUDE.md` y `projects/{slug}/vault/`, añade el binding con `root` igual al slug y devuelve dos recibos (`PROJECT_CREATE` y `DOME_CREATE`). `git status` del workspace no muestra ficheros nuevos versionables.
- **AC2:** repetir la alta con el mismo slug da 409 `SLUG_TAKEN`, y el directorio no cambia (mismo hash del árbol). Con el slug `Gallinero_1` da 400 `INVALID_SLUG`. Con `../x` da 400 y no crea nada fuera de `projects/`.
- **AC3:** con `expectedConfigRevision` desfasada (porque la config se editó a mano entre medias), da 409 `STALE_REVISION` y `config.json` queda byte a byte como estaba. Una config v1 de ejemplo carga, se migra a v2 y conserva sus proyectos.
- **AC4:** una petición a la API de alta sin la cookie de la UI emparejada, como la haría un proceso del motor, recibe 401 y no crea nada. Test e2e en la UI: con solo el proyecto de demostración aparece «Crea tu primer proyecto»; tras crear, el objeto está en el Universo, la cámara lo enfoca y ningún objeto colocado a mano ha cambiado de posición.

**S2**
- **AC5:** tras crear la cúpula, el registro versionado de SaviaVaults no cambia (mismo hash) y la cúpula figura en el registro local. La capa de conocimiento la lista con nivel N2.
- **AC6:** `PUT` de `00-Index/requisitos.md` con `expectedHash: null` responde 201, con un commit en la cúpula y un recibo `NOTE_WRITE` cuyo `contentHash` coincide con el del fichero. El frontmatter lleva `provenance: person`. `GET` de la nota devuelve el contenido exacto.
- **AC7:** un segundo `PUT` con un `expectedHash` antiguo da 409 `STALE_CONTENT`, sin escribir nada. Con un symlink en `00-Index` que apunte fuera de la cúpula, da 403 `PATH_DENIED` y el destino del symlink no cambia.
- **AC8:** crear una cúpula N3 desde la API da 422 `LEVEL_NOT_ALLOWED`. Una cúpula N4 creada por CLI aparece en la capa como opaca, sin contenido, y `GET` de sus notas da 403.

**S3**
- **AC9:** «Guardar como nota» sobre un mensaje del asistente crea una propuesta `PENDING` con `origin: PERSON`. Hasta aceptar no hay ningún fichero nuevo. Al aceptarla se escribe una nota con `provenance: generated` y `trust: untrusted`, y un recibo con `origin: PERSON` y `proposalId`.
- **AC10:** cuando el agente llama a `space_propose_write` con el destino `10-PBIs/puerta.md` de la cúpula `gallinero`, se crea una propuesta con `origin: AGENT` y no se escribe nada. Aceptarla deja un recibo con `origin: AGENT_PROPOSAL`. Rechazarla deja el estado `REJECTED` y ningún fichero.
- **AC11:** una propuesta de `PROJECT_FILE` hacia `CLAUDE.md`, `.claude/x.md`, `.opencode/agents/a.md` o `opencode.json` da 403 `PATH_DENIED`.
- **AC12:** aceptar con un `expectedBaseHash` desfasado da 409 `STALE_CONTENT`, y la UI muestra el diff recalculado.

**S4**
- **AC13:** adjuntar una nota N1 con un perfil de nube responde `requiresConfirmation: false`. El prompt que recibe el motor contiene el texto exacto de la nota dentro del bloque marcado `untrusted_source`.
- **AC14:** adjuntar `requisitos.md` (N2) con un perfil de nube responde `requiresConfirmation: true`. Sin confirmar, enviar un turno no incluye el contenido. Al confirmar con el `payloadHash` de la vista previa se crea un recibo `ATTACH_CONSENT`, y el siguiente turno sí lo incluye. Con un `payloadHash` alterado en un carácter da 409 `CONTEXT_CHANGED`.
- **AC15:** adjuntar una nota N3 o N4 con un perfil de nube da 403 `LEVEL_NOT_ALLOWED`, siempre.
- **AC16:** en la UI, el anillo de contexto muestra `requisitos.md · N2 · Nube · {proveedor}` y la leyenda «requiere confirmación». Mover la nota por el plano no cambia la selección ni la vista previa.

**S5**
- **AC17:** en interactivo, un `edit` del motor sobre `00-Index/requisitos.md` de la cúpula `gallinero` produce `ask` con el mensaje de propuesta. La misma orden fuera de cualquier cúpula sigue la configuración de `opencode.json` sin cambios.
- **AC18:** con un perfil de nube, un `read` del motor sobre una cúpula N2 no adjunta produce `ask` la primera vez. Si se permite, queda un recibo `ATTACH_CONSENT` de la cúpula para la sesión; la segunda lectura de la misma cúpula en la misma sesión no pregunta, y ambas quedan en la traza con su `contentHash`. Si se rechaza, la segunda lectura da `deny`.
- **AC18b:** con un perfil de nube, un `read` del motor sobre una cúpula N4 da `deny` con `LEVEL_NOT_ALLOWED` sin preguntar, y la petición al proveedor no contiene ningún byte de la cúpula. Lo mismo con N3 y N4b, y con `vault_read` sobre esa cúpula. Con un perfil local, la regla no aplica.

**S6**
- **AC19:** un run interactivo que lee 3 ficheros deja una traza con 3 spans `read`, cada uno con `argsHash` y `resultHash`. Tras recargar la página, la pestaña Traza muestra los mismos 3 spans.
- **AC20:** en interactivo, `GET /api/v1/engine/receipts?limit=50` responde 200 con `mode: "INTERACTIVE"`, y abrir REPLAY no produce errores de consola.
- **AC21:** la traza interactiva lleva la etiqueta «observada, sin mediación» y no tiene campo de firma. Ninguna vista la presenta como `AgentRunReceipt`.

**Conjunto**
- **AC22:** el e2e del gallinero, sin precarga manual, completa los pasos de crear el proyecto (2), crear la cúpula (3), la sesión con la cúpula adjunta (4) y el journal con la traza (7), y guarda el resultado como nota con recibo.

## Fuera de alcance

- G-04 (la búsqueda «#» no encuentra notas de las cúpulas), G-05 (abrir una nota no muestra su contenido) y G-08 (las tarjetas de herramientas desaparecen al recargar) se corrigen por separado. S2 y S6 reutilizan esos arreglos si llegan antes; no los duplican.
- Crear desde Space cúpulas N3, N4 o N4b, y mostrar su contenido (queda pendiente de D-N2).
- Firmar los recibos (D23-15).
- Las preguntas de `/project-new` sobre la herramienta de PM, los entornos y Azure DevOps.
- Borrar proyectos o cúpulas desde Space.
- Aprobar propuestas desde el móvil (llega con la bandeja móvil de SE-430).

## Riesgos

- **Inyección persistente:** un resultado guardado vuelve después como contexto. Se mitiga con `trust: untrusted` en el frontmatter, con que nada se adjunta solo y con el marcado `untrusted_source` al adjuntar.
- **Escritura en el workspace desde la web:** CSRF, path traversal y symlinks. Se mitiga con la comprobación de Host y Origin, las reglas de rutas por descriptor y la lista de ficheros de instrucciones denegados.
- **Fatiga de confirmación en N2:** si molesta, se cambia el alcance (una confirmación por cúpula y sesión), nunca el nivel.
- **Registro de cúpulas versionado:** si se escribe el registro base, se publican nombres y rutas. Lo comprueba AC5.
- **Migración de la config:** `config.json` usa `deny_unknown_fields`. Una config v2 abierta por un binario v1 falla con un error claro, nunca en silencio.
- **Credencial de escritura de Vaults:** es nueva y va separada de la lectora. Si falta, se escribe por directorio y se declara en el recibo.

## Deltas aprobados

- **Niveles con proveedor en la nube.** Las lecturas del motor sobre cúpulas N3, N4 o N4b se deniegan
  sin pregunta (§5). Las de N2 piden confirmación y dejan recibo `ATTACH_CONSENT`, como los adjuntos
  de §4. La regla cubre también las tools MCP `vault_*`. AC18 revisado y AC18b nuevo. La spec sigue
  APPROVED.

## OpenCode Implementation Plan

### Bindings touched

| Componente | Claude Code | OpenCode v1.14 |
|---|---|---|
| API de proyectos, cúpulas, notas, propuestas y adjuntos | No aplica: cliente propio de Space | No aplica: servidor de Space |
| Tool `space_propose_write` | Tool MCP del servidor MCP de Space | La misma tool, servida por MCP al motor `opencode serve` |
| Guard de cúpulas (S5) | Hook PreToolUse registrado en `.claude/settings.json`, ejecutado por el bus de Space | Regla en el plugin `savia-gates` con la misma entrada y la misma salida (`ask`) |
| Adjuntos (S4) | No aplica | Texto del prompt que se envía con `prompt_async` |
| Traza (S6) | No aplica | Eventos SSE `/event` del motor (`tool.*`, `permission.*`) persistidos por Space |

### Verification protocol

- [ ] Funciona en runtime OpenCode: AC17, AC18 y AC19 se ejecutan con el motor `opencode serve` real.
- [ ] El guard de S5 se prueba con la misma entrada en el hook bash y en `savia-gates`, y ambos dan la misma decisión.
- [ ] Si añade hooks, quedan registrados en el plugin `savia-gates`: el guard de cúpulas de S5.

### Portability classification

- [x] **DUAL_BINDING**: el guard de S5 se implementa a la vez como hook de Claude Code (ejecutado por el bus de Space) y como regla de `savia-gates` para OpenCode, desde su slice. La tool `space_propose_write` se sirve por MCP a cualquiera de los dos motores. S1–S4 y S6 son API y UI propias de Space, sin binding de frontend.
