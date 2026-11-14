---
status: PROPOSED
priority: P2
developer_type: agent-single
created: 2026-11-13
author: Savia
phase: A
risk: L2
human_surface: true
related_specs: [SE-511, SE-515, SE-505, SE-456, SE-510, SE-362, SE-343]
origin: "Encargo de la operadora (2026-11-13): adoptar mejoras de compactación observadas en engram v3.7.1 (proyecto público de memoria para agentes, usado solo como referencia de inspiración; sin código ni texto copiado) y «empezar por medir». Solo spec: sin cambios de código en esta PR."
timeline:
  - from: "2026-11-13"
    learned: "2026-11-13"
    value: "PROPOSED"
    source: "worker de spec; encargo de la orquestadora"
---

# SE-529 — Compactación que conserva y reinyecta de verdad

## Problema (verificado en origin/main 16d3ffb23, 2026-11-13)

Cuando una sesión se compacta, Savia debería guardar lo que importa antes y devolverlo después. Hoy ninguna de las dos mitades está comprobada, y una de ellas, por lectura del código, no puede funcionar.

**Antes de compactar** (`.opencode/hooks/pre-compact-backup.sh`, que es un enlace a `.claude/hooks/`; registrado en `.claude/settings.json:1112-1122`):

- Lee todo stdin en una variable (`:19`) y le aplica `grep` con expresiones regulares para «decisiones» (`:35`), «correcciones» (`:36`), «estado de tarea» (`:37`), «patrones» (`:41`) y nombres de fichero (`:45`). Es decir, busca la conversación en la entrada del hook.
- Esa entrada es el JSON que Claude Code entrega a los hooks: identificador de sesión, ruta del transcript, directorio de trabajo, nombre del evento, disparador (manual o automático) e instrucciones personalizadas. Son metadatos; la conversación está en el fichero que apunta `transcript_path`, que el hook no abre. Esta forma de la carga es lo que documenta el frontend y está **sin medir** aquí (ver S0).
- Comprobado el 2026-11-13: ejecutado con una carga sintética con esa forma (HOME y proyecto temporales), el hook sale 0, no imprime la línea «Pre-compact: N items extracted», no crea `session-hot.md` y no llama al almacén. Lo único que sale es el texto genérico de `scripts/semantic-compact.sh` (rama y lista de ficheros modificados, `:92-95`).
- Cuando algo sí casara (un texto con «decid…» en un campo cualquiera), el mensaje afirma «items extracted» sin saber si lo extraído es una decisión o ruido.

**Pruebas** (`tests/test-pre-compact-backup.bats:18-65`): comprueban la sintaxis, que el hook sale 0 con entrada vacía, `{}`, `invalid` o un JSON con un campo `decisions` inventado, y que el texto del script menciona `memory-store`. Ninguna comprueba que se extraiga algo; un hook que no hiciera nada pasaría las doce. Las pruebas de la reinyección (`tests/hooks/test-hook-enhancements.bats:60-90`) sí miran el contenido, pero solo con un `session-hot.md` escrito a mano por el propio test, nunca con uno producido por el hook.

**Después de compactar** (`scripts/post-compaction.sh`, registrado como evento `PostCompact`, `.claude/settings.json:1124-1134`):

- Lee las 20 últimas líneas del almacén `output/.memory-store.jsonl` (`:41`) sin filtrar por proyecto ni por sesión: `detect_project` se calcula (`:90`) y no se usa para filtrar. Corta cada contenido a 60 caracteres (`:101`). Sin tope total de tamaño.
- Reinyecta `session-hot.md` (`:75-85`) y lo vacía al consumirlo, de modo que si la inyección no llega al modelo, la información se pierde sin rastro.
- No se sabe si el texto que imprime un hook `PostCompact` llega al contexto del modelo: Claude Code documenta que el contexto adicional entra por `SessionStart` (con origen `compact`), y en `.claude/settings.json` no hay ningún `SessionStart` con ese origen. Esta duda puede invalidar toda la reinyección; se mide en S0 con una marca.
- En OpenCode, `PreCompact` y `PostCompact` se asignan a `experimental.session.compacting` y a `event:session.compacted` (`scripts/opencode-plugin/savia-gates/lib/manifest.ts:42,47`), pero el adaptador solo registra esos eventos en auditoría (`scripts/opencode-plugin/savia-gates/lib/gates.ts:263-270`). Si el script llega a ejecutarse allí y con qué carga está **sin medir**.

**Lo que no se guarda:** el resumen que produce el frontend al compactar. Si la sesión muere después, ese resumen no está en ningún sitio que Savia conozca.

**Referencia pública de inspiración** (descrita con palabras propias): el proyecto engram guarda el resumen compactado una sola vez por sesión y devuelve uno de cuatro estados (confirmado, fallido, desconocido, no disponible), reinyecta solo contexto de la sesión y del proyecto con las piezas fijadas primero y un tope en bytes, y prueba sus hooks con cargas reales. Savia no necesita su motor; sí esas tres propiedades.

## Lo que he entendido

### Escenas

Antes y después, en llano.


1. **Compactación a media tarea.** *Antes:* llevas dos horas decidiendo con Savia cómo repartir un trabajo. Se compacta la sesión. Savia vuelve y te pregunta qué hacíais, o repite una pregunta que ya contestaste; o te muestra una lista de apuntes de otros proyectos cortados a mitad de frase. *Después:* tras compactar, Savia abre con un bloque corto, sin decoración y en tu idioma, con el texto confirmado de «Texto que verá la persona» (cabecera «Memoria tras compactar (proyecto: …)», línea «Fijado» y línea «Esta sesión»). Solo de este proyecto, cabe en media pantalla y lo fijado va primero. Si el almacén está vacío no se imprime nada (confirmado).
2. **No se pudo leer la conversación.** *Antes:* el aviso dice «N elementos guardados» aunque no se haya leído nada. *Después:* si Savia no pudo abrir la conversación (fichero ausente, ilegible o fuera de la carpeta del frontend), lo dice una vez: «No he podido leer la conversación antes de compactar: <motivo>. Solo uso lo que ya estaba guardado.» Nunca afirma haber guardado lo que no guardó.
3. **Compactar dos veces seguidas.** *Antes:* no se archiva nada y no hay ni duplicado ni resumen. *Después:* el resumen de la sesión se guarda una sola vez; la segunda compactación con el mismo resumen no crea otra entrada.
4. **Otro proyecto en el mismo almacén.** *Antes:* apuntes de un proyecto aparecen en la sesión de otro. *Después:* nunca cruzan.
5. **Cambia de frontend.** Lo mismo en Claude Code y en OpenCode. Si OpenCode no entrega la conversación, el aviso del punto 2 lo dice en vez de callar, y eso basta como paridad (Q2, resuelta).

### Qué SÍ será

- Una medición previa de qué entregan de verdad los eventos de compactación en los dos frontends y de cuánto se recupera hoy.
- Extracción desde el transcript real, con límites de lectura y de ruta.
- Reinyección acotada por proyecto, fijadas primero y tope en bytes.
- Tests con cargas con la forma medida; cada test falla contra el código actual.

### Qué NO será

- No cambia el resumen que genera el frontend ni usa un modelo para resumir.
- No cambia el esquema del almacén ni migra entradas antiguas.
- No toca `.claude/settings.json` salvo que S0 demuestre que el evento registrado no llega al modelo; ese cambio sería una PR aparte, tier 4, con revisión humana.
- No incluye el historial de revisiones, la caducidad por tipo, los conflictos al guardar ni la consolidación con procedencia (otras propuestas de la misma comparativa; spec propia si se aprueban).

### Palabras de la persona

«adoptar las mejoras de engram v3.7.1 en compactación» y «empezar por medir» — 2026-11-13, encargo de la operadora transmitido por la orquestadora.

### Confirmación

- fecha: 2026-11-13
- respuesta: «Confirmo todo como está». Respuesta de la operadora, por pregunta interactiva, a las escenas y a las decisiones 10 a 12 de esta spec (Q1, Q3 y el texto del bloque de «Memoria tras compactar»), con la opción recomendada en todas. Registro de la orquestadora, sin enlace verificable todavía: para pasar a APPROVED la aprobación debe constar en la PR (comentario o review de la operadora enlazado).
- Q2 (2026-11-13, pregunta interactiva; registro de la orquestadora, no texto literal): la operadora acepta que, si OpenCode no entrega la conversación, el aviso explícito basta como paridad, por honesto: no se inventa nada y Claude Code guarda el resumen completo.

## Slice S0 — Medición y prototipo (primero, sin cambiar comportamiento)

- prototipo: el bloque «Memoria tras compactar» tal como figura en «Texto que verá la persona» (cabecera con el proyecto, línea «Fijado», línea «Esta sesión» y línea de «y N más») y el aviso de «No he podido leer la conversación antes de compactar», es decir, los textos que la operadora confirmó el 2026-11-13. Es texto, no una pantalla nueva: la persona lo ve en su conversación tras compactar.

### Confirmación del prototipo

- fecha: 2026-11-14
- respuesta: «los textos que confirmó el 2026-11-13 sean el prototipo de SE-529». Registro de la orquestadora, no texto literal de la operadora: decisión que ella tomó el 2026-11-14 por pregunta interactiva, transmitida en el encargo de esta PR, sin enlace verificable todavía. Sustituye el criterio anterior de esta spec, que pedía ver el aviso funcionando con datos reales antes de confirmar. Lo que sigue sin existir es el aviso funcionando con datos reales; eso lo producen S1 y S2, y la medición de S0 sigue siendo previa a ellos.

La spec sigue en PROPOSED: falta que la aprobación (no el prototipo) conste de forma verificable en la PR (SE-488).

El prototipo de esta spec son los textos citados arriba. S0 es la medición; su salida es `docs/evidence/SE-529-S0-forma-y-linea-base.md` más los fixtures de S3. Nada del contenido de una conversación entra en el repo.

**S0.1 Forma de las cargas.** Un colector de un solo uso, opt-in por variable de entorno y fuera de `settings.json`, registra por evento **solo la forma**: nombres de campo, tipo, longitud en bytes y presencia de ruta. Eventos: `PreCompact`, `PostCompact` y `SessionStart` con origen `compact`, en Claude Code y en OpenCode (`experimental.session.compacting`, `session.compacted`). Para cada celda (evento × frontend): «entregado / no entregado», campos, tamaño, y si hay un campo con el resumen compactado. Para `transcript_path` o equivalente: existe, ruta relativa a qué base, formato (líneas JSON), tipos de línea y tamaño típico. Cualquier valor de texto se sustituye por su longitud.

**S0.2 Canal de reinyección.** Con una marca aleatoria sin significado, escrita en `session-hot.md` y en el almacén de una sesión de prueba, compactar y comprobar en el turno siguiente si la marca está en el contexto del modelo, para cada vía: salida de `PostCompact` y salida de `SessionStart` origen `compact`. Resultado esperado de la medición: qué vía llega. Decide si hace falta la PR de `settings.json` (tier 4).

**S0.3 Línea base de extracción.** En 10 compactaciones reales de Claude Code (y todas las que haya en OpenCode, mínimo 3 o se declara la carencia): cuántos elementos extrae hoy el hook (línea «Pre-compact: N items…» y filas nuevas en `session-hot.md`), y para una muestra de 10, cuántas decisiones reales contenía la conversación según lectura humana del hueco. Se guardan los **recuentos**, no el texto.

**S0.4 Línea base de reinyección.** En el almacén real: número de entradas, reparto por valor de `project` (incluida la proporción de `"project":"null"`), reparto por `importance_tier`, bytes que imprime hoy `post-compaction.sh` y qué fracción pertenece al proyecto activo.

**S0.5 Decisiones que la medición fija antes de S1/S2** (se escriben en el informe antes de ver el resultado de S1/S2, y no se cambian después sin spec ni Causal-Evidence):

| Parámetro | Hipótesis previa | Regla para fijarlo |
|---|---|---|
| Tope de reinyección (bytes) | 4096 | El mayor valor ≤ 6144 con el que S0.2 muestre que el bloque no desplaza al resumen del frontend |
| Lectura máxima del transcript (bytes, desde el final) | 262144 | Mínimo que contenga el P90 de las últimas 30 vueltas medidas en S0.1 |
| Qué cuenta como «fijada» | `importance_tier` A | Si S0.4 muestra que A es > 30 % del almacén, no selecciona: pregunta Q1 |

## Slices de implementación

Orden de entrega: S0 → S5 → S1 → S2 → S4; S3 (tests) acompaña a cada slice y se cierra con la prueba de paridad. Cada slice es una PR, con su aprobación, y las que cambian hooks o scripts son tier 2 por `scripts/risk-tier.py`.

### S5 — Redacción de privados robusta (precondición de S1)

`redact_private` (`scripts/memory-store.sh:62`) es un `sed` de una línea y voraz. Comprobado el 2026-11-13: `x <private>l1⏎l2 secreto</private> y` sale **intacto** (el bloque ocupa dos líneas); con dos bloques en una línea, `.*` borra también el texto que hay entre ambos. S1 guardaría fragmentos de conversación, donde los bloques privados son habituales; sin este arreglo S1 puede persistir lo que la persona marcó como privado.

- Redacción multilínea, no voraz, sin distinguir mayúsculas. Bloque sin cierre: se redacta hasta el final de la entrada (se declara así; no se rechaza).
- Todas las rutas que escriben contenido derivado pasan por la misma función: `session-summary`, el guardado de S1 y el de S4.

### S1 — Extracción desde el transcript real

- El hook toma `transcript_path` de la carga medida en S0, lo resuelve con `realpath` y lo abre **solo si** es un fichero regular, propiedad de la persona y dentro de la carpeta de datos del frontend; en cualquier otro caso no lo abre y lo dice. (La ruta llega por stdin y no es de fiar: sin esta comprobación el hook leería cualquier fichero.)
- Lee como máximo el tope de S0.5 desde el final, parsea líneas JSON, descarta las que no son JSON, y considera **solo** turnos de la persona y del asistente en texto; no resultados de herramientas (pueden contener contenido de ficheros).
- Extrae decisiones, correcciones y estado de tarea de esas vueltas (las mismas categorías que el hook actual, ahora sobre texto de conversación) y las pasa por S5 antes de escribir en `session-hot.md` (Tier B) o en el almacén (Tier C).
- El aviso dice la verdad: «N elementos guardados» solo si N > 0 y se escribieron; si no se pudo leer o no había nada: el mensaje de la escena 2. Si OpenCode no entrega la conversación, ese aviso es el comportamiento esperado y suficiente (Q2, resuelta): no se busca una fuente alternativa ni se bloquea S1 por ello. Siempre exit 0 y dentro del timeout actual del hook (10 s).

### S2 — Reinyección acotada

- Solo entradas del proyecto activo. Proyecto no determinable: no se inyecta nada del almacén, se dice, y sí se inyecta `session-hot.md`. Entradas sin proyecto (`"project":"null"`): solo si son fijadas, según lo que decida S0.4/Q1.
- Orden: fijadas primero, luego las más recientes; titulares compactos; tope en bytes de S0.5; si hay más de las que caben, una línea «y N más (consulta con memory-store recall)».
- `memory-store.sh context` y `search` ganan `--max-bytes N`: corta en frontera de línea y de carácter, nunca a mitad de un carácter UTF-8; sin la opción, la salida es idéntica a la actual.
- `session-hot.md` se vacía **solo después** de emitir el bloque (no antes) y solo si la emisión terminó bien.
- Canal: el que fije S0.2. Si es `SessionStart` origen `compact` y exige tocar `settings.json`, esa parte es una PR aparte de tier 4.

### S4 — Resumen compactado guardado una sola vez (condicionado a S0.1)

- Solo si la carga de `PostCompact`/`SessionStart` trae el resumen del frontend. Si no lo trae: S4 se cierra como **no aplicable** y la spec lo dice; no se inventa una fuente.
- Clave de idempotencia: identificador de sesión + huella sha-256 del resumen normalizado. Misma clave, ya guardada: no escribe.
- Estado explícito de cada intento: confirmado, fallido, desconocido, no disponible. Con «fallido» o «desconocido», el aviso al agente dice «no confirmado» y no «guardado», y manda comprobar antes de reintentar. El contenido pasa por S5.

### S3 — Tests con casos reales

- Fixtures **sintéticos** con la forma medida en S0 (campos, tipos, tamaños, formato de líneas), generados por un script versionado; ningún fragmento de conversación real.
- Cada test nuevo se ejecuta antes contra el hook/script actual y debe fallar (SE-456); el informe de la PR guarda esa ejecución.
- Los bats actuales de `pre-compact-backup` se mantienen, pero se completan: ya no se aceptan solo con códigos de salida para ninguna ruta nueva.
- Paridad (Q2, resuelta): la misma entrada normalizada pasa por la ruta Claude Code y por la de OpenCode y da el mismo resultado; donde OpenCode no entrega la conversación, el resultado esperado es el aviso explícito, no silencio, y eso cuenta como paridad.

## Criterios de aceptación

- [ ] **AC-1 (S0 forma):** el informe `docs/evidence/SE-529-S0-forma-y-linea-base.md` tiene una fila por evento × frontend (6 filas) con «entregado / no entregado», campos, tamaño y si trae resumen. Una fila vacía o sin «no entregado» explícito hará fallar el comprobador del informe (se escribe en S0; el actual comprueba solo esta spec). Caso negativo: una copia con una fila borrada falla.
- [ ] **AC-2 (S0 canal):** el informe declara qué vía (PostCompact, SessionStart origen compact, o ninguna) hace llegar la marca al modelo, con el recuento de pruebas. Si ninguna, S2 queda bloqueado hasta la PR de `settings.json` (tier 4).
- [ ] **AC-3 (S0 línea base):** ≥ 10 compactaciones de Claude Code contadas y, para OpenCode, ≥ 3 o la carencia declarada. Recuentos, nunca texto. El informe fija los tres parámetros de S0.5 antes de que exista código de S1/S2 (el comprobador del informe, que se escribe en S0, verificará que la fecha del informe es anterior a la del primer commit de S1/S2; el actual no lo hace).
- [ ] **AC-4 (S5):** entradas con bloque multilínea, dos bloques en una línea, mayúsculas mixtas y bloque sin cierre: ninguna deja contenido privado en el JSONL, en `session-hot.md` ni en la salida. Caso límite: bloque vacío. El test falla contra `scripts/memory-store.sh:62` actual.
- [ ] **AC-5 (S1 positivo):** con un transcript sintético de 30 vueltas y 2 decisiones, `session-hot.md` contiene ambas y el aviso dice «2 elementos guardados» (o el N medido). Falla contra el hook actual (0 elementos).
- [ ] **AC-6 (S1 negativos):** transcript ausente, vacío, ilegible, no JSON, o con `transcript_path` fuera de la carpeta del frontend (incluido un enlace simbólico que sale de ella): no escribe nada, no abre el fichero, sale 0, y el aviso explica el motivo. Las decisiones que solo aparecen en resultados de herramientas no se extraen.
- [ ] **AC-7 (S1 límite):** transcript mayor que el tope de lectura: solo se lee el final y el hook termina en < 10 s; las decisiones anteriores al corte no aparecen y el aviso no dice haber leído todo.
- [ ] **AC-8 (S2 positivo):** con un almacén de 500 entradas de 3 proyectos, la salida ≤ el tope de S0.5 en bytes, solo trae entradas del proyecto activo e incluye las fijadas antes que las demás. Si las fijadas no caben, dice cuántas faltan.
- [ ] **AC-9 (S2 negativos):** almacén vacío o ausente: sale 0 sin texto de memoria; proyecto no determinable: ninguna entrada del almacén y aviso; ninguna entrada de otro proyecto en ningún caso (una entrada `"project":"null"` fijada no cuenta como de otro proyecto, ver Q1); `session-hot.md` no se vacía si la emisión falla.
- [ ] **AC-10 (`--max-bytes`):** `--max-bytes N` devuelve ≤ N bytes, corta en frontera de línea y de carácter UTF-8; con N menor que la primera línea devuelve vacío, sale 0 y avisa por stderr; sin la opción la salida es byte a byte la actual (comparación con salida guardada).
- [ ] **AC-11 (S4):** dos compactaciones de la misma sesión con el mismo resumen producen una entrada; con resumen distinto, dos; guardado fallido: el aviso dice «no confirmado». Si S0.1 muestra que la carga no trae el resumen, este AC se marca «no aplicable» en la spec y en la PR, con la evidencia, y no se da por cumplido.
- [ ] **AC-12 (paridad):** la misma batería de fixtures pasa por la ruta de Claude Code y por la de OpenCode con resultado normalizado igual, o con el aviso explícito declarado en S0.1 para la celda no entregada; ese aviso se acepta como paridad (Q2, resuelta) y no se exige fuente alternativa.
- [ ] **AC-13 (no bloquea):** ante cualquier entrada (vacía, basura, enorme, binaria) los hooks de compactación salen 0 y no escriben fuera de `session-hot.md` y del almacén.
- [ ] **AC-14 (honestidad):** el aviso «guardado/extraído» no aparece nunca con 0 elementos ni con un guardado no confirmado (test por cada rama).
- [ ] **AC-15 (reversión):** cada slice se revierte con `git revert` de su PR sin migración de datos: el formato del almacén y de `session-hot.md` no cambia. Comprobado en cada PR aplicando el revert en un clon limpio y pasando los bats anteriores.
- [ ] **AC-16 (tier):** `python3 scripts/risk-tier.py --diff <ficheros>` de cada PR de slice da tier 2; si una PR toca `.claude/settings.json` da tier 4 y no se mezcla con otras.

## Texto que verá la persona (Slice S1/S2)

Tras compactar, un único bloque, en el idioma del perfil, sin decoración:

```
Memoria tras compactar (proyecto: <nombre>)
Fijado: <titular> · <titular> …
Esta sesión: <decisión> · <corrección> · <estado de la tarea>
(y N más; consulta con memory-store recall)
```

Si no pudo leer la conversación: `No he podido leer la conversación antes de compactar: <motivo>. Solo uso lo que ya estaba guardado.` Si el almacén está vacío: no se imprime nada.

## Fuera de alcance

- Resumir con modelo, o cambiar el resumen del frontend.
- Cambiar el almacén (JSONL), el ranking híbrido o la migración a otra base.
- Historial de revisiones por clave, caducidad por tipo, conflictos al guardar y consolidación con procedencia.
- Cablear o archivar los scripts de SE-256 (se trata aparte).
- Recorte del contexto fijo de cada turno (SE-511).

## Preguntas abiertas para la operadora

Cerradas por la operadora el 2026-11-13 (pregunta interactiva, «Confirmo todo como está»), con la opción recomendada. Registro de la orquestadora.

- **Q1 (resuelta, 2026-11-13).** «Fijada» es `importance_tier` A mientras S0.4 muestre que A es ≤ 30 % del almacén; si no, se usa un umbral más estricto en lugar de un campo nuevo, para no tocar el esquema del almacén. Descartada la alternativa de un campo explícito nuevo.
- **Q2 (resuelta, 2026-11-13).** Si OpenCode no entrega la conversación, el aviso explícito basta como paridad; no se exige fuente alternativa para aprobar S1. Registro de la orquestadora a partir de la respuesta interactiva de la operadora.
- **Q3 (resuelta, 2026-11-13).** Si S0.2 demuestra que `PostCompact` no llega al modelo, se aprueba la PR de `settings.json` (tier 4) para pasar la reinyección a `SessionStart` origen `compact`. Solo si la medición lo demuestra: si llega, no se toca nada. Esa PR es aparte, tier 4, con revisión humana y sin fusión en lote.
- **Texto del bloque «Memoria tras compactar» (resuelta, 2026-11-13).** Tal cual figura en «Texto que verá la persona».

## Riesgos

| Riesgo | Mitigación |
|---|---|
| Leer una ruta controlada por la entrada | `realpath`, fichero regular, dueño, carpeta del frontend, límite de bytes (AC-6, AC-7) |
| Persistir contenido marcado como privado | S5 antes de S1; AC-4 |
| Reinyección sin efecto porque el evento no llega al modelo | S0.2 antes de escribir S2; AC-2 |
| Heurística de regex sobre texto libre da falsos positivos | Aviso con N real y sin afirmar calidad; la tasa de falsos positivos se mide en la muestra de S0.3 y se declara; no se promete más que «lo detectado» |
| Los fixtures divergen de la realidad | Se generan con la forma medida; la PR de S3 repite la captura de forma y compara |
| Interferencia con SE-510 (un despachador por evento) | Si SE-510 mueve `PreCompact`/`PostCompact` a un despachador, los slices adoptan su registro; no se añade un hook suelto |

## OpenCode Implementation Plan

### Bindings touched

| Componente | Claude Code | OpenCode |
|---|---|---|
| Antes de compactar | `PreCompact` → `.opencode/hooks/pre-compact-backup.sh` (`.claude/settings.json:1112`) | `experimental.session.compacting` (`scripts/opencode-plugin/savia-gates/lib/manifest.ts:47`); hoy el adaptador solo audita (`scripts/opencode-plugin/savia-gates/lib/gates.ts:268`); si ejecuta el script es medición de S0.1 |
| Después de compactar | `PostCompact` → `scripts/post-compaction.sh` (`.claude/settings.json:1124`) | `event:session.compacted` + `experimental.compaction.autocontinue` (`scripts/opencode-plugin/savia-gates/lib/manifest.ts:42`) |
| Almacén y tope | `scripts/memory-store.sh` (`context`, `search`, `--max-bytes`) | El mismo script |

### Verification protocol

- [ ] Funciona en runtime OpenCode, o el aviso explícito de «no entregado» está probado (AC-12)
- [ ] Tests BATS cubren cada AC con caso negativo y fallan contra el código actual
- [ ] Hooks cambiados registrados en el plugin `savia-gates` (sin hook suelto nuevo)

### Portability classification

- [x] **DUAL_BINDING**: misma lógica en scripts compartidos; adaptador por frontend solo para obtener la conversación; paridad por AC-12.

## Aprobación

En PROPOSED. La operadora confirmó escenas y decisiones 10 a 12 el 2026-11-13 y, el 2026-11-14, que esos mismos textos son el prototipo de S0 (ambos registros de la orquestadora, sin enlace verificable). Pasa a APPROVED cuando la aprobación conste en la PR por una vía verificable (SE-488). Ningún slice empieza sin aprobación; S0 puede aprobarse sola (no cambia comportamiento).
