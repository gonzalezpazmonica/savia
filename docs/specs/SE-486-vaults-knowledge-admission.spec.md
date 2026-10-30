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
- **La admisión vive fuera del contenido.** Hay un ledger de admisión por cúpula, append-only y firmado, atado al **digest de contenido** que ya existe. Las decisiones positivas (`ACCEPTED`, `RESTRICTED`) caducan con cualquier edición: el documento vuelve a `UNREVIEWED`. Las negativas (`REJECTED`, `QUARANTINED`) **no** caducan al editar, porque si no, un escritor levantaría un rechazo cambiando un byte. Un escritor sin `admit` no escribe decisiones. Solo puede bajar la admisión indirectamente: editando, o marcando el documento como sustituido con los campos de vigencia.
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
  superseded: boolean;                        // derivado: excludedReason(...) !== undefined o superseded_by
}): { state: AdmissionState; scope?: string }
```

Las reglas se aplican en orden y gana la primera que se cumple:

1. cuarentena técnica → `QUARANTINED`;
2. decisión `REJECTED`, **con cualquier digest** → `REJECTED`;
3. decisión `QUARANTINED`, **con cualquier digest** → `QUARANTINED`;
4. `superseded` → `SUPERSEDED`;
5. decisión `ACCEPTED` o `RESTRICTED` con digest igual al actual → esa decisión;
6. en cualquier otro caso → `UNREVIEWED`.

`RESTRICTED` exige `scope` no vacío.

Semántica de varias entradas:

- La decisión vigente de un objetivo es su entrada de **mayor `seq`**.
- Un rechazo solo se levanta con una decisión nueva de alguien con `admit`.
- Si el fichero se edita y luego se revierte a los mismos bytes, el `ACCEPTED` previo vuelve a aplicarse, siempre que siga siendo la última entrada. Es intencionado: son exactamente los bytes revisados (caso ABA).

### R2 — Ledger de admisión

`<cúpula>/.savia-vaults/admission/` guarda un JSON canónico por entrada con estos campos:

- `seq`, `target` (`notes/<ruta>` o `files/<docId>`);
- `digest`, `admission`, `scope?`, `reason` (≤ 200 caracteres);
- `subject`, `credential`, `at`;
- `prev`: sha256 de la entrada anterior;
- `sig`: Ed25519 con el firmante de recibos de Files (`files/receipts.ts`).

Reglas del ledger:

- Nunca contiene texto del documento.
- El digest de una nota es `DocEntry.hash` (sha256 de los bytes del fichero). El de Files es `sha256(rev.sha256 + "\n" + (extraction.digest ?? ""))`.
- **Ancla de cabeza contra el truncado o la vuelta atrás.** Cada escritura actualiza, además del ledger, un checkpoint firmado `{dome, seq, head}`. El checkpoint está en el directorio de estado del servidor, **fuera** de la cúpula (junto a `users.json`). Al cargar:
  - si el `seq` del checkpoint es mayor que el último `seq` del ledger, o su `head` no coincide con el hash de la entrada con ese `seq`, el ledger es inválido;
  - si falta el checkpoint y el ledger tiene entradas, el ledger es inválido;
  - si los dos faltan, el ledger está vacío y es válido.
- Si una firma, la cadena `prev` o el ancla no cuadran, o el ledger no se puede leer, **todos** los documentos de la cúpula son `UNREVIEWED` (fail-closed) y `vault_health` lo reporta como `admission_ledger_invalid`.
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
  - N ≤ 7, por defecto 1;
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
- Cómo se usa:
  - La credencial de admitir se pide por prompt en la TTY, nunca por argv ni por variable de entorno.
  - Hay que confirmar tecleando el id corto del objetivo.
  - El lote son ids explícitos, **≤ 50** por llamada. No existe `--all`.
- **No** se añade ninguna herramienta MCP ni ruta A2A ni HTTP para escribir admisión. La lectura de la admisión efectiva sí aparece en los hits (R5).
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
- `DomeOutcome.policyDigest = sha256(cabeza del ledger + excludeStatuses + perfil)`.
- El hash de la fuente virtual de Files **no** incluye la admisión.

### R6 — Perfil `governed`

- `domes.<n>.governance.profile: 'standard' | 'governed'`. Por defecto `standard`.
- Se cambia solo por CLI local (`dome governance <n> <perfil>`), con auditoría.
- Las únicas diferencias de `governed` en F1 son dos:
  - `RESTRICTED` no se sirve en `vault_rag` (R5);
  - aceptar un `PARTIAL` exige `--accept-partial` (R4).
- Lo que el perfil haga en F3 y F5 se especifica allí.

### R7 — Interruptor de rollback

- `SAVIA_VAULTS_ADMISSION=off` hace que el retriever ignore el ledger: no hay campo `admission` y `REJECTED` vuelve a servirse.
- **La cuarentena técnica sigue aplicándose.**
- El ledger no se borra.

## Criterios de aceptación

- **AC-1 (función pura):** test de tabla que recorre las 6 reglas de R1 y el orden entre ellas (p. ej. `REJECTED` + `superseded` ⇒ `REJECTED`; `ACCEPTED` + `superseded` ⇒ `SUPERSEDED`; `ACCEPTED` con digest distinto ⇒ `UNREVIEWED`; **`REJECTED` con digest distinto ⇒ `REJECTED`**; con dos entradas para el mismo objetivo, gana la de mayor `seq`). `RESTRICTED` sin `scope` lanza un error.
- **AC-2 (autoadmisión por frontmatter):** una nota con `admission: accepted` y `status: approved` se sirve como `UNREVIEWED`, y `vault_health` cuenta 1 en `admission_claim_ignored`.
- **AC-3 (edición invalida):** una nota `ACCEPTED` cuyo cuerpo se edita pasa a `UNREVIEWED` en la siguiente consulta. Lo mismo si solo se edita `valid_until`. Una nota `REJECTED` cuyo cuerpo se edita **sigue** `REJECTED` y no se sirve (caso negativo).
- **AC-4 (permiso ortogonal):** `authorizeAdmit()` devuelve `forbidden` en cada uno de estos casos, y `allowed` solo cuando se cumplen las cuatro condiciones:
  - `admin` sin `admit`;
  - humano con `admit` pero con una credencial sin `admit`;
  - usuario `service` con `admit:true` metido a mano en `users.json`;
  - credencial `admit` sobre una cúpula sin `admit`.
- **AC-5 (CLI):** `grant-admit` sobre un usuario `service` termina con código ≠ 0 y no modifica `users.json`. `token-create --admit --expires-days 8` se rechaza.
- **AC-6 (sin superficie de agente):** ninguna herramienta MCP ni ruta A2A o HTTP escribe en el ledger. Un test enumera las herramientas registradas y las rutas y falla si alguna acepta `admission` como entrada.
- **AC-7 (ledger íntegro):** en todos estos casos, todos los hits de la cúpula salen `UNREVIEWED` o descartados, ninguno `ACCEPTED`, y `vault_health` reporta `admission_ledger_invalid`:
  - (a) una entrada con la firma alterada;
  - (b) una entrada intermedia borrada;
  - (c) **las últimas entradas borradas (truncado de cola)**, comprobado con el checkpoint;
  - (d) un checkpoint ausente con el ledger no vacío.

  Un `REJECTED` truncado no vuelve a servirse sin la alerta.
- **AC-8 (sin reembeber):** tras `admission set` sobre un documento indexado, el siguiente `rag sync` informa `chunks.embedded == 0`, la generación activa no cambia y el hit refleja la nueva admisión **sin** sync.
- **AC-9 (`PARTIAL` visible):** un documento de Files `PARTIAL` produce hits con `coverage` y advertencia en la salida de texto. Uno `READY` no lleva `coverage`.
- **AC-10 (servido):** `REJECTED` y `QUARANTINED` no aparecen en `vault_rag`, tampoco con `includeStale: true`, y `degradation.admission` los cuenta sin rutas.
- **AC-11 (legado):** en una cúpula sin ledger:
  - las rutas, el orden y las puntuaciones de `vault_rag` son idénticos a los de main;
  - **cada hit lleva `admission.state === 'UNREVIEWED'`**, una aserción que falla en main porque el campo no existe;
  - el banco de recall@10 y MRR no se mueve.
- **AC-12 (perfil):** el mismo documento `RESTRICTED`:
  - en `standard` se sirve con advertencia y `scope`;
  - en `governed` no se sirve y cuenta 1 en `degradation.admission`.

  Una cúpula creada sin `governance` se comporta como `standard`.
- **AC-13 (rollback):** con `SAVIA_VAULTS_ADMISSION=off`:
  - (a) una nota `REJECTED` vuelve a servirse;
  - (b) los hits no llevan `admission`;
  - (c) una nota en cuarentena técnica (SE-481) **sigue** sin servirse.
- **AC-14:** cada AC tiene al menos una aserción que falla contra main, o con la aserción mutada si la función no existe en main. Las partes de regresión (AC-11 identidad de resultados, AC-13c) se apoyan en esa aserción y no cuentan solas.

## Medidas que se dejan en la PR de implementación

- p95 de `vault_rag` con y sin un ledger de 10⁴ entradas. Si sube más del 5 %, la búsqueda de admisión se cachea por `policyDigest`.
- Contador `admission_invalidated_by_edit` en `vault_health`, para decidir más adelante si atar la admisión a un subconjunto de campos en lugar del digest completo.

## Riesgo residual (declarado)

Un agente que se ejecuta con la misma cuenta del sistema operativo que la propietaria, que emula una TTY y lee la credencial de admitir de donde ella la guarde, puede suplantarla. Ninguna comprobación dentro del proceso lo impide. Esta spec lo mitiga con la credencial aparte, su vida corta, la ausencia de superficie MCP y la auditoría firmada. Un segundo factor queda fuera de alcance hasta que la operadora lo pida.

Por la misma razón, quien pueda escribir a la vez en la cúpula y en el directorio de estado del servidor puede hacer retroceder de forma coherente el ledger y el checkpoint. El ancla cubre el truncado accidental y el de quien solo tiene acceso a la cúpula (por ejemplo, un agente con `vault_write` o con acceso al repo sincronizado), no a la cuenta del SO.

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
- Los permisos `admit` en `users.json` son campos opcionales que el código anterior ignora.
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
