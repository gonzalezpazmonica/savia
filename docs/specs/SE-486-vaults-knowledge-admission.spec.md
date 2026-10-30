---
status: PROPOSED
priority: P1
developer_type: agent-single
created: 2026-10-30
author: Savia
phase: D
risk: L3
related_specs: [SE-309, SE-413, SE-418, SE-419, SE-423, SE-481, SE-482]
origin: SE-482 fase F1 (propuesta externa «Savia Vaults — del RAG híbrido al contexto gobernado» v0.1, F1, §5, §6, §8.2 y §11); respuestas de la operadora del 2026-10-30 (admitir es un permiso propio que ningún agente tiene; ninguna cúpula es crítica por defecto); verificada contra origin/main ed328300d
timeline:
  - from: "2026-10-30"
    learned: "2026-10-30"
    value: "PROPOSED"
    source: "spec-lifecycle:auto"
---
# SE-486 — Vaults: admisión del conocimiento (F1 de SE-482)

## Problema (verificado contra origin/main ed328300d)

1. **No existe un estado de admisión.** Vaults sabe si un documento se extrajo bien (`files/types.ts::ExtractionStatus`) y si está vigente (`status`, `valid_until` y `superseded_by` del frontmatter, que lee `rag/chunker.ts::parseNote` y aplica `rag/policy.ts::excludedReason`). No sabe si alguien con autoridad editorial lo ha **revisado y aceptado** como referencia. Un `READY` se trata igual que una fuente revisada.
2. **`status` no sirve como admisión.** Es un campo libre que redacta quien escribe la nota, a menudo un agente. En un vault de trabajo real medimos decenas de valores distintos, entre ellos `approved`, `validated` y `published`. Si la admisión se leyera de ahí, cualquier escritor se autoadmitiría.
3. **`PARTIAL` es invisible al servir (H5 de SE-482).** `files/rag-source.ts` indexa `READY` y `PARTIAL` (`INDEXABLE`), pero `RagHit` no lleva ninguna señal de cobertura. Una respuesta no puede advertir de que el documento se leyó solo en parte.
4. **No hay permiso para admitir.** `auth/controller.ts` tiene una escala `reader < writer < admin`. Si «admitir» fuera un nivel más, lo heredaría `admin` y cualquier token con `maxRole: admin`, incluido el que usa un agente en su configuración MCP.

## Decisión

- **Dos ejes separados.** El técnico (extracción) no cambia. El de admisión es nuevo: `UNREVIEWED`, `ACCEPTED`, `RESTRICTED`, `REJECTED`, `SUPERSEDED`, `QUARANTINED`. El eje técnico solo puede **bajar** la admisión efectiva, nunca subirla.
- **Una sola autoridad de vigencia.** `SUPERSEDED` **no se almacena**: se deriva de los campos que ya existen (`status ∈ excludeStatuses`, `superseded_by` o `valid_until` vencido; en Files, una revisión que ya no es la vigente).
- **La admisión vive fuera del contenido.** Hay un ledger de admisión por cúpula, append-only y firmado. Vive en el directorio de estado del servidor, fuera del alcance de `vault_write`, y está atado al **digest de contenido** que ya existe. Las decisiones positivas (`ACCEPTED`, `RESTRICTED`) caducan con cualquier edición: el documento vuelve a `UNREVIEWED`. Las negativas (`REJECTED`, `QUARANTINED`) **no** caducan al editar, porque si no, un escritor levantaría un rechazo cambiando un byte. Un escritor sin `admit` no escribe decisiones. Solo puede bajar la admisión indirectamente: editando, o marcando el documento como sustituido con los campos de vigencia.
- **«Admitir» es un permiso ortogonal**, solo para sujetos humanos, con una credencial específica y sin superficie MCP ni A2A. **Ningún agente lo tiene nunca.**
- **La admisión se aplica al servir**, no al indexar. Cambiar la admisión no re-trocea ni re-embebe nada.
- **Perfil `governed` opt-in por cúpula.** Por defecto, ninguna cúpula lo tiene.
- **Lo legado es `UNREVIEWED`.** No hay admisión masiva.

## Requisitos

### R1 — Modelo y función pura de admisión efectiva

Nuevo `src/admission/state.ts`:

```ts
type AdmissionState = 'UNREVIEWED'|'ACCEPTED'|'RESTRICTED'|'REJECTED'|'SUPERSEDED'|'QUARANTINED';
type StoredDecision = 'ACCEPTED'|'RESTRICTED'|'REJECTED'|'QUARANTINED';
function effectiveAdmission(input: {
  technicalQuarantine: boolean;               // SE-481 o Files QUARANTINED
  decision?: { admission: StoredDecision; digest: string; scope?: string };  // la entrada de mayor seq del objetivo
  currentDigest: string;
  negativeDigests: ReadonlyMap<string, 'REJECTED'|'QUARANTINED'>;  // digests con rechazo o cuarentena vigentes en la cúpula
  superseded: boolean;                        // derivado: excludedReason(...) !== undefined o superseded_by
}): { state: AdmissionState; scope?: string }
```

Las reglas se aplican en orden y gana la primera que se cumple:

1. cuarentena técnica → `QUARANTINED`;
2. decisión **propia** vigente `REJECTED` o `QUARANTINED`, **con cualquier digest** → esa decisión;
3. **herencia por contenido:** el objetivo no tiene una decisión propia `ACCEPTED`/`RESTRICTED` con digest igual al actual, **y** `negativeDigests.get(currentDigest)` existe → ese estado (`REJECTED` o `QUARANTINED`);
4. `superseded` → `SUPERSEDED`;
5. decisión propia vigente `ACCEPTED` o `RESTRICTED` con digest igual al actual → esa decisión;
6. en cualquier otro caso → `UNREVIEWED`.

Una decisión positiva **explícita** sobre un objetivo prevalece sobre la herencia por contenido. Solo la toma alguien con `admit`, a sabiendas de que el mismo contenido está rechazado en otra ruta: `admission set` lo advierte y exige `--override-inherited`.

`RESTRICTED` exige `scope` no vacío. Lo comprueba la CLI al escribir, que falla con `ADMIT_SCOPE_REQUIRED`. Si al cargar aparece una entrada firmada `RESTRICTED` sin `scope`, o cualquier entrada que no cumpla el esquema, se trata como **ledger inválido** (degradación, R2). La función pura nunca lanza al servir.

Semántica de varias entradas:

- La decisión vigente de un objetivo es su entrada de **mayor `seq`**.
- Un rechazo solo se levanta con una decisión nueva de alguien con `admit`.
- **Límite declarado: reutilización de ruta.** Un objetivo `REJECTED` sigue rechazado con cualquier digest. Una nota nueva e independiente creada después en la misma ruta nace `REJECTED`. `admission show` y `admission report` lo señalan como «rechazo propio anterior a este contenido», con el `seq` y la fecha.
- **Conjunto de digests negativos (definición).** `negativeDigests` = { `e.digest` ↦ `e.admission` | `e` es la entrada vigente (mayor `seq`) de algún objetivo y `e.admission ∈ {REJECTED, QUARANTINED}` }.
  - Un digest **sale** del conjunto cuando ninguna entrada vigente lo aporta, por ejemplo porque el objetivo que lo aportaba recibe una decisión nueva no negativa.
  - Si varios objetivos aportan el mismo digest con estados distintos, gana `QUARANTINED` sobre `REJECTED`.
  - Una copia o un renombrado **con los mismos bytes** hereda el estado en cualquier ruta, salvo decisión positiva explícita propia (regla 3).
  - `admission show <cúpula> <target>` indica si el estado es propio o heredado, y en ese caso de qué objetivo o objetivos y `seq` viene, para poder levantarlo.
- **Límite declarado:** una copia con otra ruta **y** contenido modificado es contenido nuevo: queda `UNREVIEWED` y se sirve con advertencia. F1 no hace detección por similitud.
- Si el fichero se edita y luego se revierte a los mismos bytes, el `ACCEPTED` previo vuelve a aplicarse, siempre que siga siendo la última entrada. Es intencionado: son exactamente los bytes revisados (caso ABA).

### R2 — Ledger de admisión

El ledger vive en el **directorio de estado del servidor**, `~/.savia-vaults/admission/<cúpula>/`, hermano del índice RAG (`defaultRagHome()` = `~/.savia-vaults/rag`) y protegido con `ensureSafeHome`: **fuera de cualquier cúpula**. La comprobación de que esa ruta (resuelta con `realpath`) no queda bajo la raíz `realpath` de ninguna cúpula registrada se hace al arrancar, en `dome create` y en cada recarga del registro. Si alguna cúpula la contiene:
- el servidor **no** se aborta;
- `admission set` y `repair` fallan con `ADMIT_LEDGER_INSIDE_DOME`;
- las cúpulas **con** ledger entran en admisión degradada, con detalle `admission_ledger_inside_dome`;
- las cúpulas **sin** ledger se comportan como en main (AC-11);
- `vault_health` lo avisa;
- la operadora puede reubicar el directorio de estado con `SAVIA_ADMISSION_HOME`, que indica una ubicación, no una credencial. Así ni `vault_write`, ni A2A, ni el repo sincronizado de la cúpula pueden alcanzarlo. La clave de firma vive en el mismo directorio de estado, nunca dentro de la cúpula. Los efectos de esta ubicación:

- el ledger no viaja con las notas (exportación, copias, federación);
- no se respalda con `backup` de la cúpula: necesita su propio respaldo, que se documenta en la implementación.

Cada entrada es un JSON canónico con estos campos:

- `seq`, `target` (`notes/<ruta>` o `files/<docId>`);
- `digest`, `admission`, `scope?`, `reason` (≤ 200 caracteres);
- `subject`, `credential`, `at`;
- `prev`: sha256 de la entrada anterior;
- `sig`: Ed25519 con el firmante de recibos de Files (`files/receipts.ts`).

Reglas del ledger:

- Nunca contiene texto del documento.
- El digest de una nota es `DocEntry.hash` (sha256 de los bytes del fichero). El de Files es `sha256(rev.sha256 + "\n" + (extraction.digest ?? ""))`. Una re-extracción con otra versión del extractor cambia el texto que se sirve, así que invalida los `ACCEPTED` previos. Es intencionado: se revisó otro texto.
- **Ancla de cabeza contra el truncado.** Hay un checkpoint firmado `{dome, seq, head}`.
- **Orden de escritura**, bajo un lock de cúpula (`acquireLock` del indexador, que no bloquea; si está tomado, `admission set` reintenta durante 5 s y después falla con `ADMIT_LOCKED`). Los lectores no toman el lock: el orden de lectura los protege.
  1. añadir la entrada con fsync;
  2. reescribir el checkpoint de forma atómica (`writeAtomic`);
  3. si existe checkpoint y falta la marca, marcar `domes.<n>.admission.initialized: true` en el registro de cúpulas. Se hace en **cualquier** escritura, no solo en la primera, para cerrar el hueco de un fallo entre los pasos 2 y 3.

  Con el ledger inválido, `admission set` se niega (`ADMIT_LEDGER_INVALID`). Solo funciona `admission repair`.
- Al cargar se lee **primero el checkpoint y después el ledger**. Así una escritura concurrente solo puede dejar el ledger por delante, que se tolera, y nunca por detrás, que sería un falso truncado. `admission repair` sí acorta el ledger. Por eso, ante un aparente truncado, el lector **reintenta la lectura una vez**, con el orden checkpoint → ledger, antes de declarar el ledger inválido. La recarga se dispara si cambia `(mtimeMs, size)` de cualquiera de los dos o el `seq` del checkpoint. Así se evita servir un ledger obsoleto cuando dos escrituras caen en el mismo tick de mtime.
- Comprobaciones:
  - si el `seq` del checkpoint es mayor que el último `seq` del ledger, o su `head` no coincide con el hash de la entrada con ese `seq`, el ledger es inválido;
  - si falta el checkpoint y el ledger tiene entradas:
    - **válido** si la cúpula **no** está marcada como inicializada, el ledger empieza en `seq = 1` y su cadena y firmas cuadran. Es el fallo entre los pasos 1 y 3 de la primera escritura. La siguiente escritura completa el checkpoint y la marca;
    - **inválido** en cualquier otro caso;
  - si los dos faltan: válido y vacío si la cúpula no está marcada; inválido si lo está. Si alguien borra también la marca, el ledger se da por vacío: es el residuo de quien escribe en el directorio de estado;
  - se toleran entradas firmadas y encadenadas **posteriores** al checkpoint: es el caso de un fallo entre los pasos 1 y 2. La siguiente escritura adelanta el checkpoint.
- **Ledger inválido.** Ocurre si una firma, la cadena `prev` o el ancla no cuadran, o si el ledger no se puede leer. Entonces la cúpula entra en **admisión degradada**:
  - ningún documento puede salir `ACCEPTED` ni `RESTRICTED`;
  - la cuarentena técnica (regla 1) **sigue aplicándose**: esos documentos no se sirven;
  - no se aplica la herencia por contenido, porque el conjunto tampoco es fiable;
  - en `standard`, los hits vigentes se sirven como `UNREVIEWED` y, con `includeStale`, los sustituidos como `SUPERSEDED` (la vigencia no depende del ledger). `DomeOutcome.detail` incluye `admission_ledger_invalid`, de modo que el aviso llega **en la respuesta** y no solo en `vault_health`;
  - en `governed`, la cúpula **no sirve ningún hit** (`status` degradado) hasta que se repare;
- **Reparación.** Solo por CLI local: `savia-vaults admission repair <cúpula>`, con `authorizeAdmit` y TTY:
  1. muestra el diagnóstico: qué comprobación falla y los `seq` de checkpoint y ledger, sin contenido;
  2. propone volver a anclar en el **mayor prefijo válido** del ledger, con cadena y firmas correctas. Si el prefijo válido está vacío, `REANCHOR` es la primera entrada viva, con `prev` = hash cero, y su `seq` sigue la regla del paso 3;
  3. tras confirmar, descarta las entradas posteriores inválidas (las archiva aparte, no las borra) y añade, bajo el lock de admisión, una entrada firmada de tipo `REANCHOR` con `seq` = max(`seq` del checkpoint, último `seq` visto) + 1, **también con el prefijo vacío**, para que ningún `seq` se reutilice. El verificador de cadena exige `seq` consecutivos **salvo** justo antes de una `REANCHOR`, que puede saltar y registra el hueco en `lostRange`. Como `repair` siempre escribe checkpoint y marca, un ledger reparado nunca cae en el caso (f) de AC-7, el de «empieza en `seq` 1 y no tiene marca». Lleva `kind: 'REANCHOR'`, `target: null`, `digest: null` y `admission: null`, junto con `reason`, el `seq` y el `head` anteriores y el sujeto. Las entradas `REANCHOR` **no** cuentan como decisión de ningún objetivo, así que no entran en el cálculo de la decisión vigente ni en `negativeDigests`;
  4. reescribe checkpoint y marca.

  No distingue por sí misma un truncado malicioso de un fallo benigno; eso lo decide la persona con el diagnóstico delante. Por eso queda auditado.
  - consecuencia declarada: en `standard`, un `REJECTED` vuelve a servirse con aviso mientras dure la degradación. Para provocarla hace falta escribir en el directorio de estado del servidor, que ninguna superficie de agente alcanza (R4, AC-6).
- `admission:` en el frontmatter **se ignora** y se cuenta en `vault_health` como `admission_claim_ignored`, sin rutas.

### R3 — Permiso «admitir»

- `DomePermission.admit?: true` y `Credential.admit?: true`. **`AuthAction` no cambia**, y `admit` no entra en `ROLE_LEVEL` ni en `ACTION_LEVEL`. Es un método aparte, `AccessController.authorizeAdmit({ authToken, dome })`, que solo usa la CLI. Exige las cuatro condiciones a la vez:
  - `user.type === 'human'`;
  - `permissions[dome].admit === true`;
  - la credencial tiene `admit: true`;
  - el rol es ≥ `writer`.

  Si falla cualquiera, `forbidden`. Se audita con `tool: 'admit'`, sea cual sea el resultado.
- `admin` **no** implica `admit`, y `maxRole` no lo concede.
- Para otorgarlo solo hay CLI local: `user grant-admit <u> <cúpula>` y `user revoke-admit <u> <cúpula>`. Las dos rechazan usuarios `service`.
- `user token-create <u> --admit [--expires-days N]`:
  - N entero entre 1 y 7, por defecto 1; si no, falla con `ADMIT_TTL_INVALID` (o `ADMIT_TTL_EXCEEDED` si es mayor que 7);
  - el secreto se muestra una vez;
  - no admite los formatos de salida para la configuración MCP.
- `domes.json` gana `owner?: subjectId`:
  - `dome create --owner <usuario>` lo rellena y otorga `admin` + `admit` en esa cúpula a ese usuario. Si el usuario es `service`, falla. Sin `--owner`, queda vacío (la CLI local no sabe quién la ejecuta);
  - en las cúpulas existentes queda vacío, y nadie tiene `admit` hasta que la operadora lo otorgue.

### R4 — Superficie de admisión

- CLI local:
  - `savia-vaults admission set <cúpula> <target> <ACCEPTED|RESTRICTED|REJECTED|QUARANTINED> --reason … [--scope …]`;
  - `admission show <cúpula> <target>`;
  - `admission report <cúpula>`, que da recuentos por estado efectivo, por estado técnico y por `admission_claim_ignored`, y solo en local las rutas.
  - `admission repair <cúpula>` (R2).
- Cómo se usa:
  - La credencial de admitir se pide por prompt en la TTY, nunca por argv ni por variable de entorno. Si `stdin` no es una TTY, la CLI termina con `ADMIT_REQUIRES_TTY`.
  - **Punto de prueba**, sin atajos:
    - el núcleo `recordDecision(ctx, auth: AdmitAuthorization, input)` solo acepta un `AdmitAuthorization`. El tipo estructural no basta: hace falta una **marca en tiempo de ejecución**. `authorizeAdmit()` registra cada autorización emitida en un `WeakSet` privado del módulo, y `recordDecision` comprueba que el objeto pertenece a ese conjunto y que no ha caducado (≤ 5 min). Si no, falla con `ADMIT_FORBIDDEN` y no escribe;
    - los tests llaman a `authorizeAdmit(token)` con la credencial como argumento de función, en un directorio de estado temporal;
    - la capa de prompt recibe el lector de TTY por inyección de dependencias en el código, **no** por variable de entorno ni por flag.
  - Un objetivo se confirma tecleando su id corto.
  - El lote son ids explícitos, **≤ 50** por llamada, y se confirma tecleando el nombre de la cúpula y el número de objetivos. No existe `--all`.
- **No** se añade ninguna herramienta MCP ni ruta A2A ni HTTP para escribir admisión. El ledger está fuera de la raíz de cualquier cúpula, así que el confinamiento de rutas de `vault_write` y de Files ya lo deja fuera de alcance; AC-6 lo prueba. La lectura de la admisión efectiva sí aparece en los hits (R5).
- En `governed`, aceptar una revisión `PARTIAL` exige `--accept-partial`.

### R5 — Admisión y cobertura al servir

- `RagHit` gana dos campos informativos, que **no** son autoridad:
  - `admission: { state, scope?, decidedAt? }`;
  - `coverage?: { status: 'PARTIAL', extracted, units, skipped }`.
- `files/rag-source.ts` lleva `rev.extraction` al `FileSourceRef` del chunk.
- `RagService` calcula la admisión efectiva de cada hit al servir, con el mismo patrón que la revalidación de SE-481 R3:
  - el ledger se carga en memoria y se recarga si cambia su mtime;
  - `REJECTED` y `QUARANTINED` se descartan siempre, también con `includeStale`, y se cuentan en `DomeOutcome.degradation.admission`, solo el número;
  - `SUPERSEDED` sigue la regla actual de `includeStale`;
  - `RESTRICTED`: en `standard` se sirve con advertencia y con el `scope` visible; en `governed` se descarta y se cuenta en `degradation.admission`. F1 **no** define un parámetro de propósito: evaluar el alcance contra un propósito declarado corresponde a F3 (ContextBundle).
- `rag/format.ts` antepone una advertencia a cada hit `UNREVIEWED`, `RESTRICTED` (con su alcance) o con `coverage` (`extracción parcial: n/m unidades`).
- Campo **nuevo** `DomeOutcome.policyDigest = sha256(cabeza del ledger + excludeStatuses + perfil)`: hoy `DomeOutcome` no lo tiene.
- El hash de la fuente virtual de Files **no** incluye la admisión.

### R6 — Perfil `governed`

- `domes.<n>.governance.profile: 'standard' | 'governed'`. Por defecto `standard`.
- Se cambia solo por CLI local (`dome governance <n> <perfil>`), con auditoría.
- Las únicas diferencias de `governed` en F1 son tres:
  - `RESTRICTED` no se sirve en `vault_rag` (R5);
  - aceptar un `PARTIAL` exige `--accept-partial` (R4);
  - con el ledger inválido no se sirve nada (R2).
- Lo que el perfil haga en F3 y F5 se especifica allí.

### R7 — Interruptor de rollback

- `SAVIA_VAULTS_ADMISSION=off` hace que el retriever ignore el ledger **en las cúpulas `standard`**: no hay campo `admission` y `REJECTED` vuelve a servirse.
- En las cúpulas `governed`, el interruptor **no tiene efecto**: se sigue aplicando la admisión y se registra un aviso. Para desactivar la admisión en una cúpula `governed`, primero hay que bajarla a `standard` con `dome governance`, que queda auditado.
- **La cuarentena técnica sigue aplicándose.**
- El ledger no se borra.

## Criterios de aceptación

- **AC-1 (función pura):** test de tabla que recorre las 6 reglas de R1 y el orden entre ellas. Incluye estos casos:
  - el objetivo B sin decisión, copia de A `REJECTED` ⇒ `REJECTED` (heredado);
  - B con `ACCEPTED` propio y digest igual ⇒ `ACCEPTED` (la decisión explícita prevalece);
  - A pasa a `ACCEPTED` ⇒ su digest sale de `negativeDigests` y B sin decisión ⇒ `UNREVIEWED`;
  - dos objetivos aportan el mismo digest, uno `REJECTED` y otro `QUARANTINED` ⇒ `QUARANTINED`.

  Otros casos: objetivo sin decisión, con `negativeDigests` que contiene su digest como `REJECTED` ⇒ `REJECTED` (copia o renombrado); el mismo sin el digest en el mapa ⇒ `UNREVIEWED`; `REJECTED` + `superseded` ⇒ `REJECTED`; `ACCEPTED` + `superseded` ⇒ `SUPERSEDED`; `ACCEPTED` con digest distinto ⇒ `UNREVIEWED`; **`REJECTED` con digest distinto ⇒ `REJECTED`**; con dos entradas para el mismo objetivo, gana la de mayor `seq`). Una entrada `RESTRICTED` sin `scope` en el ledger hace que la carga lo marque como inválido, sin excepción al servir. La CLI rechaza escribirla con `ADMIT_SCOPE_REQUIRED`.
- **AC-2 (autoadmisión por frontmatter):** una nota con `admission: accepted` y `status: approved` se sirve como `UNREVIEWED`, y `vault_health` cuenta 1 en `admission_claim_ignored`.
- **AC-3 (edición y copia):**
  - una nota `ACCEPTED` cuyo cuerpo se edita pasa a `UNREVIEWED` en la siguiente consulta. Lo mismo si solo se edita `valid_until` a **otra fecha futura**. Si se edita a una fecha pasada, sale `SUPERSEDED` (regla 4);
  - una nota `REJECTED` cuyo cuerpo se edita **sigue** `REJECTED` y no se sirve;
  - una nota `REJECTED` renombrada o copiada a otra ruta con los mismos bytes sale `REJECTED` en las dos rutas y no se sirve;
  - una copia con otra ruta y un byte cambiado sale `UNREVIEWED` (límite declarado, que se prueba para que no cambie sin querer).
- **AC-4 (permiso ortogonal):** `authorizeAdmit()` devuelve `forbidden` en cada uno de estos casos, y `allowed` solo cuando se cumplen las cuatro condiciones:
  - `admin` sin `admit`;
  - humano con `admit` pero con una credencial sin `admit`;
  - usuario `service` con `admit:true` metido a mano en `savia-vaults.users.json`;
  - credencial `admit` sobre una cúpula sin `admit`;
  - credencial `admit` caducada o revocada;
  - rol `reader` con `admit`.
- **AC-5 (CLI):**
  - controles positivos: `grant-admit` sobre un humano sale con 0 y escribe `admit: true` en su permiso de esa cúpula; `token-create --admit --expires-days 7` crea una credencial con `admit: true` y caducidad ≤ 7 días;
  - negativos con error concreto: `grant-admit` sobre `service` falla con `ADMIT_SERVICE_FORBIDDEN` y `savia-vaults.users.json` queda idéntico byte a byte; `--expires-days 8` falla con `ADMIT_TTL_EXCEEDED`;
  - `admission set` con `stdin` no TTY falla con `ADMIT_REQUIRES_TTY` y el ledger no cambia;
  - canal de la credencial: con un lector de TTY inyectado que entrega un token `admit` válido, `admission set` sale con 0 y escribe la entrada (control positivo). Si se pasa `--token`, la CLI falla con `ADMIT_CREDENTIAL_CHANNEL_FORBIDDEN` y no escribe. `SAVIA_AUTH_TOKEN` **se ignora**: la CLI nunca lee de ahí la credencial de admitir. Con esa variable definida y `stdin` no TTY, falla con `ADMIT_REQUIRES_TTY`. Todo fallo de la CLI sale con código ≠ 0, y los tests lo comprueban junto al código textual;
- **AC-6 (sin superficie de agente):**
  - un test enumera las herramientas MCP y las rutas A2A y HTTP registradas, y falla si alguna importa el módulo de escritura del ledger. Comprueba también que no acepta `admission` como entrada;
  - el recorrido de imports es **transitivo**, sobre el grafo de módulos que resuelve el compilador. Además, un test en tiempo de ejecución sustituye el módulo escritor del ledger con `vi.mock` (que también intercepta enlaces ESM), arranca el servidor MCP, invoca cada herramienta con entradas válidas y comprueba que el escritor no se llama nunca. Así se cubren los imports dinámicos y los envoltorios;
  - aserción estructural con control positivo: `path.relative(realpath(raízDeCúpula), realpath(rutaDelLedger))` empieza por `..` para cada cúpula registrada. Controles positivos:
    - una cúpula de prueba cuya raíz contiene la ruta del ledger;
    - una cúpula cuya raíz es un enlace simbólico al directorio de estado.

    En los dos, `admission set` falla con `ADMIT_LEDGER_INSIDE_DOME` y la cúpula con ledger sale degradada;
  - `vault_write` con una ruta que intenta salir hacia el directorio de estado (`../`, ruta absoluta o enlace simbólico) se rechaza y el ledger no cambia.
- **AC-7 (ledger íntegro):** en cada uno de estos casos, con `standard` y sin `includeStale`, **todos** los hits de la cúpula salen exactamente `UNREVIEWED` y `DomeOutcome.detail` contiene `admission_ledger_invalid`. Con `governed`, la cúpula devuelve 0 hits con estado degradado:
  - (a) una entrada con la firma alterada;
  - (b) una entrada intermedia borrada;
  - (c) **las últimas entradas borradas (truncado de cola)**, comprobado con el checkpoint;
  - (d) un checkpoint ausente con el ledger no vacío **y** (la cúpula marcada como inicializada **o** un ledger que no empieza en `seq` 1);
  - (e) la cúpula marcada como inicializada sin ledger ni checkpoint.

  En los cinco casos, una nota en cuarentena técnica **sigue** sin servirse, y `admission set` falla con `ADMIT_LEDGER_INVALID`.

  Casos que deben ser **válidos**:
  - (f) ledger con `seq` 1..n, cadena y firmas correctas, sin checkpoint **ni marca**: es el fallo de la primera escritura. El test de (f) y el de (d) con marca usan el **mismo ledger y difieren solo en la marca**, y deben dar resultados opuestos;
  - (g) una entrada firmada posterior al checkpoint: es el fallo entre la escritura y el checkpoint.
- **AC-8 (sin reembeber):** tras `admission set` sobre un documento indexado:
  - el hit refleja la nueva admisión **sin** sync. Esta es la aserción que falla en main;
  - el siguiente `rag sync` informa `chunks.embedded == 0` y la generación activa no cambia (invariante).
- **AC-9 (`PARTIAL` visible):** un documento de Files `PARTIAL` produce hits con `coverage` y advertencia en la salida de texto. Uno `READY` no lleva `coverage`.
- **AC-10 (servido):** `REJECTED` y `QUARANTINED` no aparecen en `vault_rag`, tampoco con `includeStale: true`, y `degradation.admission` los cuenta sin rutas.
- **AC-11 (legado):** en una cúpula sin ledger:
  - las rutas, el orden y las puntuaciones de `vault_rag` son idénticos a los de main;
  - **cada hit vigente, sin `includeStale` y sin cuarentena técnica, lleva `admission.state === 'UNREVIEWED'`**. Es una aserción que falla en main porque el campo no existe. Con `includeStale`, los hits sustituidos llevan `SUPERSEDED`;
  - el banco de recall@10 y MRR no se mueve.
- **AC-12 (perfil):** el mismo documento `RESTRICTED`:
  - en `standard` se sirve con advertencia y `scope`;
  - en `governed` no se sirve y cuenta 1 en `degradation.admission`.

  Una cúpula creada sin `governance` se comporta como `standard`.
- **AC-13 (rollback):** con `SAVIA_VAULTS_ADMISSION=off`:
  - (a) una nota `REJECTED` vuelve a servirse;
  - (b) los hits no llevan `admission`;
  - (c) una nota en cuarentena técnica (SE-481) **sigue** sin servirse;
  - (d) en una cúpula `governed`, el interruptor no tiene efecto: un `RESTRICTED` sigue sin servirse.
- **AC-15 (reparación):** sobre el caso (c) de AC-7:
  - `admission repair` vuelve a anclar en el último prefijo válido, añade `REANCHOR` firmada y deja la cúpula válida;
  - el informe de reparación da el **rango de `seq` perdido** (último válido + 1 .. `seq` del checkpoint) y declara que su contenido es irrecuperable. No dice qué decisiones eran: el test comprueba el rango, y que una decisión `REJECTED` que estaba en ese rango ya no se aplica tras la reparación;
  - sin `authorizeAdmit`, falla y no toca nada;
  - las entradas descartadas quedan archivadas, no borradas;
  - **prefijo vacío** (todas las entradas inválidas): la `REANCHOR` resultante tiene `prev` = hash cero y `seq` = `seq` del checkpoint + 1. El ledger reparado verifica como válido con ese hueco, y la cúpula queda marcada como inicializada.
- **AC-16 (requisitos sin AC hasta ahora):**
  - `admission set` sobre un objetivo con estado heredado y sin `--override-inherited` falla con `ADMIT_INHERITED_NEGATIVE`; con el flag, sale `ACCEPTED`;
  - un lote de 51 ids falla con `ADMIT_BATCH_TOO_LARGE` sin escribir nada, y `--all` no existe (error de opción);
  - en `governed`, `ACCEPTED` sobre un `PARTIAL` sin `--accept-partial` falla con `ADMIT_PARTIAL_REQUIRES_FLAG`; en `standard` no lo pide;
  - `dome create --owner <service>` falla con `ADMIT_SERVICE_FORBIDDEN` y no registra la cúpula;
  - `dome governance` deja una entrada de auditoría;
  - con el ledger inválido, `standard` e `includeStale`, un hit sustituido sale `SUPERSEDED`;
  - con un fallo simulado entre los pasos 2 y 3 de la escritura, la siguiente escritura pone la marca;
  - `--expires-days` acepta solo enteros entre 1 y 7. `0`, `-1`, `abc` y `8` fallan con `ADMIT_TTL_INVALID` o `ADMIT_TTL_EXCEEDED`;
  - `admission set ... REJECTED` sobre un objetivo cuyo digest coincide con el de otro objetivo `ACCEPTED` advierte de ese otro objetivo, que no se ve afectado (regla 3);
- **AC-17 (autorización no falsificable):**
  - `recordDecision` con un literal estructuralmente idéntico a un `AdmitAuthorization` falla con `ADMIT_FORBIDDEN` y deja el ledger intacto, byte a byte;
  - con un objeto emitido por `authorizeAdmit()`, escribe. Esa es la aserción que falla si se quita la marca;
  - un objeto emitido hace más de 5 min falla con `ADMIT_FORBIDDEN`;
- **AC-18 (cúpula legada que contiene el estado):** con una cúpula sin ledger cuya raíz es un ancestro del directorio de estado (por ejemplo `$HOME`):
  - el servidor arranca;
  - `vault_rag` de esa cúpula da los mismos resultados que main, más `admission: UNREVIEWED`;
  - `vault_health` avisa;
  - `admission set` falla con `ADMIT_LEDGER_INSIDE_DOME`;
- **AC-19 (`policyDigest`):** `DomeOutcome.policyDigest` cambia tras `admission set` y tras `dome governance`, y no cambia tras una consulta sin escrituras.

### Regla de los AC

- **AC-14:** cada AC (AC-1 a AC-13 y AC-15 a AC-19), salvo AC-6, tiene al menos una aserción **semántica** que falla contra main: un valor de estado, un código de error o un recuento. **No** cuenta como fallo que un import no compile o que un comando no exista, salvo que la aserción compruebe precisamente ese código de error. AC-6 es un invariante y se valida con **dos** mutaciones, cada una de las cuales debe hacer fallar su test: (i) colocar la ruta del ledger bajo una raíz de cúpula, que hace fallar la aserción estructural; (ii) una herramienta MCP de prueba que importa el módulo de escritura a través de un envoltorio, que hace fallar el recorrido transitivo y el espía. Las partes de regresión (la identidad de resultados de AC-11, AC-8 `embedded == 0` y AC-13c) no cuentan solas.

## Medidas que se dejan en la PR de implementación

- p95 de `vault_rag` con y sin un ledger de 10⁴ entradas. Si sube más del 5 %, la búsqueda de admisión se cachea por `policyDigest`.
- Contador `admission_invalidated_by_edit` en `vault_health`, para decidir más adelante si atar la admisión a un subconjunto de campos en lugar del digest completo.

## Riesgo residual (declarado)

- `SAVIA_VAULTS_ADMISSION=off` se lee del entorno del proceso servidor. Quien edite la configuración del cliente MCP (`env`) puede desactivar la admisión en las cúpulas `standard`. En `governed` no tiene efecto (R7).
- Durante un `admission repair`, un lector puede ver un truncado transitorio. Reintenta una vez, pero puede degradar la cúpula unos instantes (en `governed`, 0 hits).
- La marca `initialized` vive en el registro de cúpulas (`savia-vaults.domes.json` o el registro que use el servidor), que tampoco está en ninguna cúpula. Entre un fallo de los pasos 2 y 3 de la primera escritura y la siguiente escritura, borrar el checkpoint es indistinguible del caso (f).

`type: 'human'` **no es una barrera por sí solo**: `user create` y la migración v1 crean sujetos `human` por defecto, y el token que usa un agente suele ser de uno de ellos. Las barreras reales son tres: `admit` en el permiso **y** en la credencial, la TTY y la vida corta. La comprobación de tipo solo impide el caso explícito de `service`.

Un agente que se ejecuta con la misma cuenta del sistema operativo que la propietaria, que emula una TTY y lee la credencial de admitir de donde ella la guarde, puede suplantarla. Ninguna comprobación dentro del proceso lo impide. Esta spec lo mitiga con la credencial aparte, su vida corta, la ausencia de superficie MCP y la auditoría firmada. Un segundo factor queda fuera de alcance hasta que la operadora lo pida.

Por la misma razón, quien escriba en el directorio de estado del servidor puede hacer retroceder de forma coherente el ledger y el checkpoint, o provocar la admisión degradada (en `standard`, un `REJECTED` vuelve a servirse con aviso). Las superficies de agente (`vault_write`, Files, A2A, el repo de la cúpula) **no** alcanzan ese directorio. Una shell con la cuenta del SO, sí.

## Fuera de alcance

- `EvidenceRef` y conflictos (F2), ContextBundle (F3), evals de respuesta (F4), gate de primera promoción (F5), AEK (F7).
- Validación celda–encabezado de tablas y OCR: van en una spec de extracción propia.
- Interfaz web de admisión. Segundo factor.
- Admitir en bloque el contenido existente.
- Parámetro de propósito y evaluación del alcance de `RESTRICTED` contra él: F3.
- Una vía para que un escritor sin `admit` *proponga* un rechazo. Hoy solo puede editar, que devuelve el documento a `UNREVIEWED`, o marcarlo como sustituido.

## Rollback

Revert de la PR, o `SAVIA_VAULTS_ADMISSION=off` sin revertir.

- El índice no cambia: la admisión no entra en las generaciones. No hace falta reconstruir nada.
- El ledger queda en disco sin efecto y se puede borrar a mano.
- Los permisos `admit` en `savia-vaults.users.json` son campos opcionales que el código anterior ignora.
- Revertir no reabre ninguna exposición de SE-481. Sí vuelve a servir los documentos `REJECTED`, y por eso la PR debe avisarlo.

## OpenCode Implementation Plan

### Bindings touched

| Componente | Claude Code | OpenCode v1.14 |
|---|---|---|
| Servidor MCP savia-vaults (salida de `vault_rag`) | `~/.claude.json` mcpServers (stdio) | `opencode.json` mcp (stdio), mismo binario |
| CLI `savia-vaults admission`, `user grant-admit` | terminal local | terminal local (idéntica) |
| Lógica de admisión | `projects/savia-vaults/src/admission/` | idéntica (mismo servidor) |

### Verification protocol

- [ ] Funciona en runtime OpenCode (mismo servidor MCP; sin código por frontend)
- [ ] Tests vitest cubren el servidor y la CLI; los frontends solo consumen `vault_rag`
- [ ] No añade hooks
- [ ] Ningún frontend expone escritura de admisión (AC-6)

### Portability classification

- [x] **PURE_BASH** (equivalente: lógica en el servidor MCP y la CLI, independiente del frontend)
