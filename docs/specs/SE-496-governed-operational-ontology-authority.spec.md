---
status: APPROVED
priority: P1
developer_type: agent-single
created: 2026-11-01
author: Savia
phase: B
risk: L4
human_surface: true
related_specs: [SE-343, SE-362, SE-386, SE-387, SE-401, SE-488, SE-491]
origin: "Iniciativa SAVIA-RESEARCH-03 / validación V4 del análisis de repositorios difundidos por André Lindenberg (2026-11-01): AWS context-ontology-accelerator y operational-ontology. Solo spec."
timeline:
  - from: "2026-11-01"
    learned: "2026-11-01"
    value: "PROPOSED"
    source: "spec-lifecycle:auto"
  - from: "2026-11-09"
    learned: "2026-11-09"
    value: "APPROVED"
---
# SE-496 — Ontología operativa gobernada: la autoridad vive fuera del modelo

## Problema (verificado en origin/main 6b0658b28)

Savia ya separa razonar de autorizar en el papel. SE-401 lo declara («una decisión no es un permiso», «la confianza no es autoridad») y define un `AuthorityEngine` abstracto, pero solo tiene aprobada la F0 de solo lectura y deja abierta la frontera con AEK (§21). En el código, la autoridad está repartida en piezas que no comparten contrato:

1. **Niveles L0–L4** (`agent-permission-levels.md`): techo estático por herramientas. No dicen sobre qué recurso ni con qué efecto.
2. **Tiers de riesgo** (SE-362): clasifican el PR, no la delegación.
3. **Grants de la operadora** (SE-343, `scripts/operator-grant.sh`): ámbito `scope` + `resource`, TTL y consumo único. El grant de merge va firmado con ed25519 contra `config/operator-grant-signers` de `origin/main`; los `autonomy:*` no van firmados (`source express-request`). Ningún grant declara precondiciones sobre el estado ni los efectos que autoriza.
4. **Autorizaciones de publicación** (SE-491, PR #1446 abierta): firma con namespace propio, solo para `project.publish`.
5. **Descriptores de capacidad** (SE-386, `contracts/capabilities/*.yaml`): declaran `safety.effect`, `reversibility` y `human_gate`, pero solo los valida en estático `scripts/contract-check.sh`; nada los evalúa en el momento de ejecutar.
6. **Reservas de efecto** (SE-387, `scripts/effect-reservation.sh`): idempotencia por clave, sin vínculo con quién autorizó.

Consecuencias concretas:

- No hay forma de expresar «la operadora delega en Yema abrir PRs Draft en el repo X, solo si la rama es `agent/*` y la CI no está roja, hasta el viernes». Hoy eso es prosa en un encargo, y lo que vigila su cumplimiento son hooks sueltos.
- Cada pieza nueva inventa su formato de autorización (SE-343, SE-491). Es la «segunda verdad de autoridad» que SE-401 §20 manda parar.
- El grafo de conocimiento (SE-162/213) y las cúpulas (SaviaVaults) ya infieren relaciones como «este recurso pertenece al proyecto Y». Hoy ningún gate las usa para autorizar. **No hay incidente**: el riesgo es que, al conectar el grafo a la ejecución, una inferencia acabe concediendo un permiso. Esta spec lo prohíbe antes de que ocurra.

## Qué aporta lo estudiado (lectura sin ejecución, 2026-11-01)

- **AWS context-ontology-accelerator** (Apache-2.0): separa la capa semántica (grafo, ontologías, MCP) de la autorización, que evalúa **Cedar** en el autorizador de API con *deny* por defecto (`denyAll` cuando nada aplica) y políticas `forbid` que ganan a cualquier `permit`. Tiene dos capas: acción (Cedar) y datos (cortafuegos SQL con listas de tablas y columnas en el propio grant). Su punto débil para nosotros: el autorizador **cachea la decisión ~60 s por token**, así que una revocación tarda en surtir efecto. Savia no cachea decisiones.
- **operational-ontology** (MIT): las escrituras solo pasan por **acciones con nombre** que llevan sus **precondiciones de negocio**. Las violaciones devuelven rechazos legibles por máquina, y se auditan tanto los intentos aplicados como los rechazados. Cada dato declara su dueño (`source-backed`, `ontology-owned` o `derived`) y está prohibido el estado sin dueño. Separa expresamente «las precondiciones dicen si la acción es válida» de «las políticas de acceso dicen quién puede actuar».

Se toman los patrones, no el código: sin dependencias nuevas (ni Cedar, ni Node, ni AWS).

## Qué decide esta spec

1. **Un único contrato de delegación** (*Principal / Capability / Authority / Effect*) para toda autoridad delegada. Los grants de SE-343 y las autorizaciones de SE-491 se proyectan a él mediante adaptadores; no se crea un tercer formato.
2. **Un kernel de autoridad determinista**, fuera del LLM, que es el único que devuelve `ALLOW`. El grafo, las cúpulas y el modelo pueden **sugerir**; nunca autorizan.
3. **Una ontología operativa mínima**: tipos de objeto con dueño declarado y acciones tipadas con precondiciones y efectos declarados, construida sobre los descriptores de SE-386.
4. **Una batería de 15 denegaciones obligatorias** (§ R5), con revocación y datos ambiguos.

Frontera con AEK (SE-401 §21): esta spec define el **delta del lado Savia** con el prefijo `AEK-` ya reservado. Si el repositorio canónico de AEK publica antes estas primitivas, mandan las suyas y este contrato se convierte en adaptador. Sin esa decisión de la operadora, la implementación no sale del modo sombra (F1).

## Alternativas para evaluar la política

Las tres son viables; la tabla las pone en paralelo.

| | A. Evaluador propio en Python stdlib | B. Cedar (`cedarpy`/CLI) | C. OPA / Rego |
|---|---|---|---|
| Dependencias | Ninguna (`python3 -I`, PATH fijo, como `operator-grant.sh`) | Binario Rust o rueda nativa | Binario Go |
| Semántica | La definimos: *deny* por defecto, `forbid` gana, sin comodines | Formal, verificada, la misma que usa AWS | Muy expresiva, Datalog |
| Riesgo de error propio | Mayor: lo escribimos nosotras | Menor en el motor | Menor en el motor |
| Portabilidad (Windows sin admin, portátil corporativo) | Total | Depende de instalar el binario | Depende de instalar el binario |
| Auditabilidad por diff | Reglas en YAML legible | Políticas `.cedar` legibles | Rego, menos legible para no programadoras |
| Coste de cambiar después | Medio: el contrato no depende del motor | Medio | Medio |

**Recomendación: A en F1–F2**, con una regla de diseño que deja abierta B: el contrato y la batería de denegaciones no dependen del motor, y la política se escribe en un subconjunto que se traduce 1:1 a Cedar (`permit`/`forbid` sobre principal, acción y recurso, con `when` sobre atributos). Si el ensayo de F3 muestra que el evaluador propio falla casos que Cedar resuelve, se cambia el motor sin tocar contratos ni tests. La regla de no instalar dependencias del sistema pesa más que la madurez del motor mientras no haya medición.

## Requisitos

### R1 — Ontología operativa mínima

`contracts/ontology/savia-operational.yaml` declara:

- **Tipos de objeto**: `Principal` (persona que delega), `Delegate` (agente, harness o proveedor externo), `Repo`, `Branch`, `PullRequest`, `Project`, `VaultNote`, `ExternalSystem`. Cada atributo declara su **dueño**:
  - `source-backed`: lo dice un sistema de registro mediante un lector determinista (`git`, `gh`, fichero de firmantes de `origin/main`);
  - `contract-owned`: lo dice un contrato firmado;
  - `derived`: se calcula al evaluar y nunca se escribe;
  - `inferred`: viene del grafo, las cúpulas o un modelo. **Ningún atributo `inferred` puede aparecer en una condición de autorización** (lo comprueba el validador de la ontología, R6).
- **Acciones**: cada una es un descriptor de SE-386 (`contracts/capabilities/<id>.yaml`) ampliado con `preconditions` (predicados tipados sobre atributos `source-backed` o `contract-owned`) y `declared_effects` (lista de `EffectDescriptor` de SE-401 §5.3). Primera tanda, solo para la batería: `pr.create-draft`, `pr.merge`, `project.publish`, `vault.note-write`.
- Atributos con validez temporal: `valid_from` / `valid_to`, intervalo semiabierto `[from, to)`.

### R2 — Contrato de delegación

Fichero JSON canónico (claves ordenadas, UTF-8 NFC, sin espacios) con firma `ssh-keygen -Y` ed25519, namespace `savia-delegation`, verificada contra `config/operator-grant-signers` **de `origin/main`**, como SE-343. Campos:

| Campo | Contenido |
|---|---|
| `schema` | `delegation-contract/1` |
| `id`, `nonce` | Identificador y 16 hex aleatorios |
| `principal` | Identidad del firmante en el fichero de firmantes. Nunca `self` ni un agente |
| `delegate` | Agente o harness concreto (`yema`, `codex`, `savia-worker:<id>`) |
| `capability` | `id`, `version` y `sha256` del descriptor de SE-386; si el descriptor cambia, el contrato deja de valer |
| `authority` | Techo: nivel L0–L4 y tier SE-362 máximos. La autoridad efectiva es el **mínimo** entre el contrato, el nivel del agente y el gate del tier |
| `scope` | Lista cerrada de selectores de recurso exactos: `repo`, ramas por patrón anclado (`agent/*`), número de PR o proyecto. Sin comodines globales. Semántica de selectores en «Comparación de selectores», abajo |
| `preconditions` | Predicados adicionales del principal (por ejemplo, `ci_status == success`; una CI pendiente o cancelada no cumple) |
| `declared_effects` | Efectos que el principal acepta. Un efecto no listado se deniega aunque la capacidad lo permita |
| `not_before`, `expires_at` | Obligatorios. Vida máxima 7 días; la del grant de merge sigue siendo la de SE-343 |
| `max_uses` | Opcional; `1` para efectos irreversibles (`reversibility: irreversible`). Mecanismo de consumo en R4 «Ledger de usos» |
| `installation` | Remoto `origin` normalizado a `host/propietario/repo`, para que el contrato no valga en otro repo |

El contrato no lleva secretos ni datos personales más allá del identificador del firmante, que ya es público en el fichero de firmantes. Se versiona en `config/delegations/<id>.json` + `.sig` cuando el principal quiere que la CI lo vea, o en `~/.savia/delegations/` cuando es local.

**Comparación de selectores** (cierra el prefijo engañoso de D10 y D14):

- Antes de comparar, selector y recurso se normalizan a NFC. Si el recurso cambia al normalizarlo, o contiene caracteres de control o de confusión (tabla de confusables de Unicode TR39), la decisión es `AMBIGUOUS`; no se «arregla» en silencio.
- La comparación distingue mayúsculas. Dos recursos existentes que solo difieren en mayúsculas o normalización dan `AMBIGUOUS`.
- Los patrones de rama son glob por segmentos: `*` casa con uno o más caracteres de **un solo** segmento y nunca cruza `/`; no hay `**`, `?` ni clases. `agent/*` cubre `agent/x` pero no `agent/x/y`.
- Se rechazan con `OUT_OF_SCOPE` los recursos con segmentos `..`, `.` o vacíos, o con `/` inicial. Las rutas de proyecto se comparan por segmento completo: `projects/alpha` no cubre `projects/alpha-x`.
- Cada regla tiene fixture propio dentro de D10 o D14 (`agent/../main`, `agent/x/y`, `projects/alpha-x`, homoglifo, NFD).

**Revocación**: el `nonce` en `config/delegations/REVOKED` (en `origin/main` o en la copia de trabajo) o en `~/.savia/delegations/REVOKED`. Basta con que aparezca en cualquiera de los tres. La revocación local es inmediata y no espera a ninguna fusión, pero **no resiste a un agente comprometido**: los ficheros locales los puede escribir el mismo usuario que ejecuta al agente, así que un agente puede borrar una línea que aún no esté en `origin/main`. Contra un agente comprometido, la única revocación autoritativa es la de `origin/main`; la local protege frente a errores y carreras, no frente a sabotaje. La misma limitación aplica al ledger de usos (R4) y al audit (R3).

### R3 — Kernel de autoridad

`scripts/lib/authority_kernel.py evaluate`, con `python3 -I` y PATH fijo de sistema. Lee por stdin una petición JSON (`delegate`, `capability`, `action` con parámetros, `target`) y devuelve por stdout:

```json
{"decision": "ALLOW|DENY|REQUIRES_APPROVAL", "reason": "<código>", "contract_id": "...",
 "contract_sha256": "...", "capability_sha256": "...", "action_sha256": "...",
 "state_digest": "...", "policy_sha256": "...", "evaluated_at": "...", "suggestions": []}
```

Reglas:

- *Deny* por defecto. Las reglas `forbid` ganan a cualquier `permit`. Sin contrato aplicable, `DENY`.
- El estado se lee en el momento de evaluar y solo de los lectores `source-backed`. **No hay caché de decisiones** entre evaluaciones.
- Los hechos `inferred` que lleguen en la petición se descartan para decidir y se devuelven en `suggestions` con la acción que haría falta (por ejemplo, «pedir un contrato para `projects/alpha`»). Una sugerencia nunca cambia `decision`.
- Fail-closed: herramienta ausente, `origin/main` ilegible o lector que no responde → `DENY UNKNOWN_STATE` (exit 1) en la posición del paso que lee esa fuente. Petición mal formada o fallo interno del propio kernel → exit 2 sin decisión. Nunca exit 0 salvo con `ALLOW`. La tabla «Códigos de salida» es la única referencia.
- `evaluate` es de solo lectura: **nunca consume** `max_uses` ni escribe estado salvo el audit. El consumo lo hace `recheck` (R4).
- Cada evaluación, permitida o denegada, se añade a `~/.savia/authority/audit.jsonl` con los hashes. Los parámetros de la acción se guardan **todos como hash** salvo los que el descriptor de la capacidad declare en una lista blanca `audit_plain` (por ejemplo, el número de PR); un parámetro sin declarar nunca va en claro. Cada línea lleva `prev_sha256` (hash de la línea anterior; la primera, 64 ceros), y `authority_kernel.py verify-audit` detecta una línea editada, borrada o reordenada. Como el agente puede reescribir el fichero entero con el mismo usuario, la cadena detecta ediciones parciales y errores, **no es prueba frente al agente**; el recibo con valor de prueba es la PR revisada.

**Orden de evaluación y precedencia de códigos.** Todas las comprobaciones son `forbid`; el kernel las aplica en este orden fijo y devuelve el código de la **primera** que falla, sin evaluar las siguientes. Así, una entrada que cumple dos casos tiene un único código esperado, y dos implementaciones correctas no divergen:

| Orden | Comprobación | Código | Fuente que lee (si falla: `UNKNOWN_STATE` en este paso) |
|---|---|---|---|
| 0 | Petición JSON bien formada y con campos obligatorios | exit 2, sin decisión | stdin |
| 1 | Hay contrato para `delegate` + `capability` | `NO_CONTRACT` | `config/delegations/`, `~/.savia/delegations/` |
| 2 | Firma presente; `principal` no es `self` ni un agente | `SELF_ISSUED` | el contrato |
| 3 | Firma válida, namespace `savia-delegation`, firmante en el fichero de `origin/main` | `BAD_SIGNATURE` | `origin/main`, `ssh-keygen` |
| 4 | Firmante verificado = principal seleccionado por el perfil activo | `PRINCIPAL_MISMATCH` | perfil activo |
| 5 | `nonce` en alguna lista `REVOKED` | `REVOKED` | `origin/main`, copia de trabajo, `~/.savia` |
| 6 | `not_before` ≤ now < `expires_at` | `NOT_YET_VALID` / `EXPIRED` | reloj |
| 7 | `capability` (id, versión, `sha256`) coincide | `CAPABILITY_MISMATCH` | `contracts/capabilities/` |
| 8 | El objetivo se normaliza a un único recurso | `AMBIGUOUS` | `git`, `gh` |
| 9 | La pertenencia del recurso al ámbito no descansa solo en hechos `inferred` | `INFERRED_NOT_AUTHORITY` | — |
| 10 | El recurso está cubierto por `scope` e `installation` | `OUT_OF_SCOPE` | `git remote` |
| 11 | Los usos registrados son < `max_uses` | `MAX_USES_EXHAUSTED` | `~/.savia/authority/uses/` |
| 12 | Los lectores `source-backed` de las precondiciones responden | `UNKNOWN_STATE` | `git`, `gh` |
| 13 | Precondiciones del descriptor y del contrato | `PRECONDITION_FAILED:<id>` | — (ya leído en 12) |
| 14 | Efectos de la acción ⊆ `declared_effects` | `UNDECLARED_EFFECT` | — |
| 15 | Techo: nivel del agente | `LEVEL_EXCEEDED` | `agent-permission-levels.md` |
| 16 | Techo: tier 3/4 sin revisión humana del PR | `REQUIRES_APPROVAL` con `REVIEW_REQUIRED` | `gh` |
| 17 | Solo `recheck`: `action_sha256` igual al del recibo previo | `ACTION_MISMATCH` | el recibo |
| 18 | Solo `recheck`: `state_digest` igual al del recibo previo | `STATE_CHANGED` | el recibo |

Si una comprobación no puede leer su fuente (por ejemplo, el paso 3 sin `origin/main` o sin `ssh-keygen`, el 10 sin `git remote`, el 11 sin acceso al ledger), devuelve `DENY UNKNOWN_STATE` **en su posición**, no la del paso 12. Ejemplos de precedencia que la batería fija con fixture propio: contrato sin firma → `SELF_ISSUED` (no `BAD_SIGNATURE`); homoglifo de un proyecto del ámbito → `AMBIGUOUS` (no `OUT_OF_SCOPE`). En `recheck`, un estado que ya viola una precondición da `PRECONDITION_FAILED` (paso 13) antes que `STATE_CHANGED` (paso 18); este solo aparece cuando el cambio no rompe ninguna precondición pero sí el digest (por ejemplo, un `head_sha` nuevo). El consumo del ledger (R4) ocurre después del paso 18.

**Códigos de salida.** Cada caso tiene una única decisión y un único exit:

| Caso | Decisión | Exit |
|---|---|---|
| Todas las comprobaciones pasan | `ALLOW` | 0 |
| Falla una comprobación de los pasos 1–15, 17 o 18 | `DENY` | 1 |
| Una fuente no se puede leer (cualquier paso) | `DENY` | 1 |
| Paso 16: tier 3/4 sin revisión humana | `REQUIRES_APPROVAL` | 4 |
| Petición mal formada (paso 0) | sin decisión | 2 |
| Fallo interno del kernel (excepción no controlada) | sin decisión | 2 |

**`state_digest`.** SHA-256 del JSON canónico con exactamente estos campos, y ningún otro:

- `contract_sha256` y `capability_sha256`;
- `signers_blob`: id del blob de `config/operator-grant-signers` en `origin/main`;
- `revoked`: booleano de presencia del `nonce` en cada una de las tres listas;
- `target`: identidad resuelta del recurso (`host/propietario/repo`, rama, número de PR y `head_sha` si aplica);
- `facts`: valor de cada atributo `source-backed` que **una precondición aplicable referencia**, por nombre.

El estado que ninguna precondición referencia no entra, de modo que un cambio irrelevante entre las dos llamadas (otra PR, un check no exigido) no produce denegaciones espurias. Un cambio en algo que sí se referencia (la CI pasa a rojo, la PR deja de ser Draft) cambia el digest y bloquea la ejecución, que es lo que se quiere. Los usos del ledger **no** entran en el digest: con `max_uses > 1`, el `recheck` de una orden consumiría un uso y haría fallar por digest el `recheck` de otra orden concurrente aunque quedaran usos. El límite de usos lo garantiza el paso 11 y la creación exclusiva de R4.

### R4 — Punto de ejecución (EEP)

La prueba de autorización **no es un token al portador**: el kernel corre en el mismo equipo y con el mismo usuario que el agente, así que una firma local no distinguiría a la persona del agente (el mismo motivo por el que SE-491 descarta el HMAC local). La garantía contra la falsificación está en la firma del principal, cuya clave privada no está en el equipo. Por eso el punto de ejecución **vuelve a llamar al kernel** inmediatamente antes del efecto, con `authority_kernel.py recheck --prior <recibo>`, que repite la evaluación completa y compara `action_sha256` y `state_digest` con los del recibo previo (pasos 17 y 18 de R3). Si la nueva evaluación no es `ALLOW`, devuelve su código; si `action_sha256` difiere, `DENY ACTION_MISMATCH`; si `state_digest` difiere, `DENY STATE_CHANGED`. En cualquiera de esos casos no ejecuta. La salida del kernel queda como recibo de auditoría, enlazado con la clave de `effect-reservation.sh`.

**`recheck` es F0; el envoltorio es F2.** `recheck` forma parte del kernel desde F0. En F0 lo ejercita un arnés de pruebas (`tests/helpers/se496-eep-harness.sh`, solo en `tests/`, no lo invoca ningún hook) que hace `evaluate`, ejecuta un gancho entre medias (por ejemplo, revocar), llama a `recheck` y solo si sale `ALLOW` crea un fichero marcador en lugar de la orden real. Así D04 y AC-5 se prueban en F0 sin que el EEP decida nada sobre efectos reales.

**Ledger de usos (`max_uses`).** El contador vive en `~/.savia/authority/uses/<contract_id>/<n>`, un fichero por uso, `n` de 1 a `max_uses`.

- `evaluate` cuenta los ficheros y da `MAX_USES_EXHAUSTED` si hay `max_uses` o más; **no consume**. Por eso el caso feliz de un contrato `max_uses: 1` es `evaluate` → `ALLOW` y `recheck` → `ALLOW`.
- `recheck`, si todo lo demás da `ALLOW`, consume un uso **antes** de devolver `ALLOW`: crea el primer `<n>` libre con creación exclusiva (`O_CREAT|O_EXCL`), que contiene la clave de reserva SE-387 de la orden. Si la creación exclusiva falla para todos los `n` ≤ `max_uses`, devuelve `DENY MAX_USES_EXHAUSTED`. Dos `recheck` concurrentes sobre un contrato `max_uses: 1` dan un `ALLOW` y un `DENY`, nunca dos `ALLOW`.
- El uso se consume aunque la orden falle después: para efectos irreversibles es preferible pedir otro contrato que arriesgar una segunda ejecución. Un reintento de la **misma** orden tras una caída se resuelve con la reserva de SE-387 (misma clave, `resume`), no con otro uso.
- `effect-reservation.sh` no sirve como contador: su `reserve` sobre una clave abierta devuelve `resume` con exit 0, que es la semántica correcta para reanudar, no para limitar usos. Por eso el ledger es propio y solo guarda la clave para enlazarlos.

En F2 el primer EEP es un envoltorio (`scripts/authority-exec.sh <capability> -- <orden>`) que llama a `recheck`. Los hooks de Claude Code y un guard nuevo del plugin `savia-foundation` de OpenCode (`.opencode/plugins/guards/`) lo invocan para las capacidades con contrato; no reimplementan la lógica en TS (lección de la PR #1237: los ports TS divergen).

### R5 — Batería de 15 denegaciones obligatorias

Cada caso tiene un fixture en `tests/fixtures/se496/`, código de motivo estable y **un caso positivo gemelo** que difiere en un solo dato y da `ALLOW`. Así, si el control se desactiva, el test falla.

| # | Caso | Entrada | Motivo |
|---|---|---|---|
| D01 | Sin contrato | Delegado sin contrato para la capacidad | `NO_CONTRACT` |
| D02 | Revocado en main | `nonce` en `config/delegations/REVOKED` de `origin/main` | `REVOKED` |
| D03 | Revocado solo en local | `nonce` solo en `~/.savia/delegations/REVOKED`, aún sin fusionar | `REVOKED` |
| D04 | Revocado entre evaluar y ejecutar | `ALLOW` en `evaluate`; revocación; `recheck` (arnés de F0, R4) | `REVOKED` en `recheck`; el marcador no se crea |
| D05 | Fuera de vigencia | `expires_at` pasado; caso límite `now == expires_at`; `now < not_before` | `EXPIRED` / `NOT_YET_VALID` |
| D06 | Firma no válida | Firma alterada, firmante ausente del fichero de `origin/main` (aunque esté en la rama) o namespace de otro uso (`savia-operator-grant`, `savia-project-publish`) | `BAD_SIGNATURE` |
| D07 | Autoemisión | Contrato sin firma, con `principal: self` o con un agente como principal | `SELF_ISSUED` |
| D08 | Otro operador | Contrato firmado por el operador A mientras el perfil activo es el del operador B; también un perfil activo editado para decir A cuando la firma es de B | `PRINCIPAL_MISMATCH` |
| D09 | Capacidad distinta | Otra capacidad, otra versión o descriptor con `sha256` cambiado tras firmar | `CAPABILITY_MISMATCH` |
| D10 | Fuera de ámbito | Recurso no cubierto, prefijo engañoso (`projects/alpha-x` frente a `projects/alpha`), `..`, otro repo | `OUT_OF_SCOPE` |
| D11 | Efecto no declarado | La acción produciría un efecto que no figura en `declared_effects` (push además de commit) | `UNDECLARED_EFFECT` |
| D12 | Precondición falsa | Estado conocido que la viola (PR no Draft, CI en rojo, rama humana) | `PRECONDITION_FAILED:<id>` |
| D13 | Estado desconocido | El lector no responde, `gh` ausente o `origin/main` ilegible | `UNKNOWN_STATE` |
| D14 | Dato ambiguo | El selector resuelve a 2+ recursos, nombres que difieren solo en mayúsculas o normalización Unicode, homoglifos, alias sin dueño declarado | `AMBIGUOUS` |
| D15 | Autoridad inferida | La única prueba de pertenencia o permiso viene del grafo, de las cúpulas o del modelo (`provenance: inferred`) | `INFERRED_NOT_AUTHORITY` + sugerencia |

Las 15 denegaciones de la batería dan todas `DENY`; ninguna da `REQUIRES_APPROVAL`. Cuando un caso cumple dos filas, el código esperado es el que fija el orden de R3.

Casos técnicos además de la batería, cada uno con su gemelo positivo:

| Caso | Resultado |
|---|---|
| Entrada malformada | exit 2, sin decisión |
| Kernel ausente | el EEP no ejecuta (exit ≠ 0) |
| `max_uses` consumido (repetición) y dos `recheck` concurrentes con `max_uses: 1` | `DENY MAX_USES_EXHAUSTED`; exactamente un `ALLOW` en la carrera |
| Contrato que supera el nivel del agente | `DENY LEVEL_EXCEEDED` |
| `recheck` con una orden distinta de la evaluada | `DENY ACTION_MISMATCH`; el marcador no se crea |
| `recheck` tras un cambio en un hecho referenciado que no viola ninguna precondición (`head_sha` nuevo) | `DENY STATE_CHANGED`; el marcador no se crea |
| Tier 3/4 sin revisión humana del PR | `REQUIRES_APPROVAL` con `REVIEW_REQUIRED`, nunca `ALLOW` |

### R6 — Validadores

- `authority_kernel.py check-ontology`: falla si algún atributo `inferred` aparece en una precondición o regla, si hay estado sin dueño o si una acción no declara efectos.
- `authority_kernel.py check-contract <fichero>`: forma canónica, campos obligatorios, vida ≤ 7 días, `max_uses: 1` en irreversibles.

### R7 — Adaptadores sin segunda verdad

- **SE-343**: `operator-grant.sh` no cambia en esta spec. En F1, un adaptador proyecta cada grant vigente a un contrato equivalente y el kernel evalúa en **sombra**: registra cuándo discrepa del grant, pero no decide nada.
- **SE-491**: el verificador `project_authz.py` sigue siendo la fuente para `project.publish`; el kernel lo consulta como lector `contract-owned`. Si la PR #1446 cambia el formato antes de fusionarse, se ajusta el adaptador, no el contrato.
- **L0–L4 y SE-362**: el kernel los lee como techo. No los sustituye.

### R8 — Multioperador

Nada depende de una persona concreta. El perfil activo solo **selecciona** qué principal se espera; no concede nada. El principal efectivo es **siempre** el firmante verificado contra el fichero de firmantes de `origin/main` (paso 3 de R3), y el paso 4 exige que coincida con el seleccionado. Editar el perfil puede, como mucho, provocar `PRINCIPAL_MISMATCH`; nunca convierte una firma de otra persona en autoridad propia. Con el fichero vacío o sin clave registrada, todas las delegaciones dan `DENY` con un mensaje que enlaza el alta de la clave. El suelo es el de hoy: acción humana manual y PR revisada. Los tests usan dos operadores ficticios con claves generadas en el propio test.

## Criterios de aceptación

- **AC-1** `contracts/ontology/savia-operational.yaml` existe con los tipos y las cuatro acciones de R1, y `check-ontology` da PASS. Un fixture con un atributo `inferred` en una precondición da FAIL.
- **AC-2** `check-contract` acepta un contrato válido y rechaza, cada uno con su código: falta un campo obligatorio, vida > 7 días, forma no canónica e irreversible sin `max_uses: 1`.
- **AC-3** Las 15 denegaciones de R5 dan `DENY` con su código exacto, y sus 15 gemelos positivos dan `ALLOW`. Los casos técnicos de R5 dan el resultado de su tabla (`REQUIRES_APPROVAL REVIEW_REQUIRED` solo en el de tier 3/4). Los dos ejemplos de precedencia de R3 tienen fixture y dan el código del primer paso que falla. Lo comprueba `tests/test-se496-authority-kernel.bats`.
- **AC-4** Mutación: con cada comprobación del kernel desactivada por turnos (parche de prueba), falla al menos su caso de R5. Lo informa `tests/test-se496-mutation.bats`.
- **AC-5** D04 (F0, con el arnés de R4): con la orden real sustituida por un marcador, revocar entre `evaluate` y `recheck` deja el marcador sin crear; sin la revocación, el marcador se crea.
- **AC-5b** Ledger de usos: con `max_uses: 1`, `evaluate` → `ALLOW`, `recheck` → `ALLOW` y un segundo `recheck` → `DENY MAX_USES_EXHAUSTED`; dos `recheck` concurrentes producen exactamente un `ALLOW`; `evaluate` repetido no consume usos.
- **AC-5c** `state_digest`: un cambio en un atributo que ninguna precondición referencia no altera el digest; un cambio en uno referenciado sí, y `recheck` deniega con `STATE_CHANGED`; una orden distinta de la evaluada da `ACTION_MISMATCH`. Con `max_uses: 2`, dos órdenes evaluadas a la vez dan dos `ALLOW` en `recheck` (los usos no entran en el digest).
- **AC-6b** Códigos de salida: cada fila de la tabla «Códigos de salida» de R3 tiene un caso que comprueba a la vez la decisión y el exit; una fuente ilegible da `DENY UNKNOWN_STATE` con exit 1. La entrada malformada da exit 2.
- **AC-6** Fail-closed: sin `ssh-keygen`, sin `git`, sin `origin/main` o con entrada malformada, el kernel nunca sale con 0.
- **AC-7** Sin caché: dos evaluaciones seguidas con una revocación en medio dan `ALLOW` y luego `DENY`, sin esperas.
- **AC-8** Las sugerencias del grafo aparecen en `suggestions` y no cambian `decision` (D15 y su gemelo con contrato firmado).
- **AC-9** Multioperador: los tests pasan con dos operadores ficticios y con el fichero de firmantes vacío (todo `DENY`). Ningún test lee el perfil real ni `~/.savia` real (`HOME` temporal).
- **AC-10** Sombra (F1): el adaptador de SE-343 evalúa todos los grants vigentes de un ledger de prueba y escribe las discrepancias en el audit; `operator-grant.sh` sigue dando los mismos códigos de salida que antes (sus tests en verde sin cambios).
- **AC-11** Mismo resultado en Claude Code y OpenCode: el guard de OpenCode llama al mismo `authority-exec.sh` y un test lo ejecuta por las dos vías con la misma entrada.
- **AC-12** El audit registra intentos permitidos y denegados con hashes; un test verifica que solo los parámetros de la lista blanca `audit_plain` aparecen en claro (un parámetro no declarado va como hash), y que `verify-audit` falla si se edita, borra o reordena una línea intermedia.
- **AC-13** Selectores: `agent/*` no cubre `agent/x/y` ni `agent/../main`; `projects/alpha` no cubre `projects/alpha-x`; un recurso en NFD o con homoglifo da `AMBIGUOUS`. Cada uno con gemelo positivo.

## Fases

| Fase | Entrega | Decide algo |
|---|---|---|
| F0 | Ontología, contrato, validadores, kernel (`evaluate`, `recheck`, ledger de usos, `verify-audit`) y arnés EEP de pruebas, con la batería (AC-1..AC-9, AC-5b, AC-5c, AC-6b, AC-12, AC-13) | No: solo tests |
| F1 | Adaptadores SE-343/SE-491 en sombra durante 14 días; informe de discrepancias (AC-10) | No |
| F2 | `authority-exec.sh` (envoltorio sobre `recheck`) como EEP de `pr.create-draft` y `vault.note-write` (AC-11) | Sí, solo esas dos y solo si la operadora lo aprueba tras ver el informe de F1 |
| F3 | Ensayo Cedar frente al evaluador propio con la misma batería | Decisión de motor |

`pr.merge` y `project.publish` no pasan a decidir por el kernel en esta spec: siguen en SE-343 y SE-491.

## Fuera de alcance

- Sustituir `operator-grant.sh`, el verificador de SE-491 o los hooks actuales.
- Reconciliar efectos de resultado incierto (SAVIA-RESEARCH-01, OpenRath): aquí solo se enlaza la clave de reserva.
- Instalar Cedar, OPA o cualquier dependencia del sistema.
- Conectar el grafo de conocimiento a la ejecución más allá de las sugerencias.
- Delegación en cadena (un delegado que subdelega). Queda prohibida en v1: `delegate` no puede firmar contratos.

## Riesgos

- **El evaluador propio tiene errores que Cedar no tendría.** Mitigación: batería con gemelos, mutación (AC-4) y F3.
- **Coste de fricción.** Un contrato más que firmar desde el móvil. Mitigación: F2 solo cubre capacidades reversibles y contratos de hasta 7 días.
- **Carrera entre la evaluación y el efecto.** La reevaluación del EEP la reduce a la ventana entre la llamada y la orden; no la elimina para efectos externos lentos.
- **Estado local escribible por el agente.** Revocación local, ledger de usos y audit viven en `~/.savia` con el mismo usuario que el agente. Mitigación declarada, no resuelta: la autoridad contra un agente comprometido es `origin/main` más la PR revisada; lo local cubre errores y carreras.
- **`origin/main` es una ref local.** `refs/remotes/origin/main` y la URL de `origin` (de la que sale `installation`) también las puede mover el mismo usuario (`git update-ref`, un `fetch` desde un remoto falso), y con ello cambiar el fichero de firmantes o la lista `REVOKED` que «manda». Es la misma debilidad que tiene hoy SE-343 (`operator-grant.sh` lee `refs/remotes/origin/main` sin verificarla). No afecta a F0/F1, que no deciden nada. **Condición para pedir F2**: el kernel comprueba el blob de firmantes y el de `REVOKED` contra el remoto real (`git ls-remote` o `gh api`), y si el remoto no responde da `DENY UNKNOWN_STATE`.
- **Frontera con AEK sin decidir.** Si AEK define otras primitivas, F0 se rehace como adaptador; la batería se conserva.

## OpenCode Implementation Plan

### Bindings touched

| Componente | Claude Code | OpenCode v1.14 |
|---|---|---|
| Kernel `scripts/lib/authority_kernel.py` | Invocado por `authority-exec.sh` | Mismo binario vía `execFile` desde un guard de `.opencode/plugins/guards/` |
| EEP `scripts/authority-exec.sh` | Hook PreToolUse (entrada JSON por stdin) para capacidades con contrato | Guard `authority-exec.ts` cargado por `savia-foundation.ts` (`tool.execute.before`) que llama al mismo script |
| Ontología y contratos | Ficheros en `contracts/` y `config/delegations/` | Los mismos ficheros |

### Verification protocol

- [ ] Funciona en runtime OpenCode (AC-11)
- [ ] Tests cubren ambos paths con la misma entrada
- [ ] El guard nuevo queda cargado por `savia-foundation.ts` (el plugin de gates de OpenCode)

### Portability classification

- [x] **DUAL_BINDING**: la lógica está en Python stdlib y bash; los dos frontends solo la invocan, sin port TS de la lógica.

## Lo que he entendido

### Escenas
1. Quieres que Yema abra PRs en borrador en un repo hasta el viernes, solo desde ramas agent/* y con la CI verde. Te llega al móvil una PR de autorización con eso en lenguaje llano; la fusionas y vale hasta el viernes.
2. El jueves Yema intenta abrir un PR con la CI roja. Se rechaza con el motivo: «precondición: CI verde». No te despierta; lo ves en el resumen.
3. El grafo de conocimiento cree que un repo es de tu proyecto. Eso no da permiso a nadie: solo vale lo que firmaste.

### Palabras de la persona
«Savia Viva + tokens y efectos» — 2026-11-09, respuesta de la operadora a la pregunta interactiva sobre qué specs aprobar.

### Qué SÍ será
- Un solo contrato para delegar, con ámbito, precondiciones y caducidad.
- Rechazos con motivo legible.

### Qué NO será
- Permisos deducidos por el modelo o por el grafo.
- Un tercer formato de firma: los permisos de merge y de publicación pasan a este contrato.

### Confirmación
- fecha: 2026-11-09
- respuesta: «Confirmo las escenas». Opción elegida por la operadora en la pregunta interactiva del 2026-11-09 en la que se le enseñaron estas escenas literalmente.

## Slice S0 — Prototipo navegable
- prototipo: [docs/specs/assets/SE-496-prototipo.html](assets/SE-496-prototipo.html) — la PR de autorización de la escena 1 tal como llega al móvil y el texto exacto del rechazo de la escena 2 (simulado, con datos de ejemplo).

### Confirmación del prototipo
- fecha: pendiente (obligatoria antes de poner S1 en curso)
- respuesta: pendiente

## Aprobación

APPROVED por la operadora el 2026-11-09 por pregunta interactiva («Savia Viva + tokens y efectos»), tras confirmar las escenas cuando la spec las exige. Se formaliza al fusionar la PR (SE-488). 
