---
status: APPROVED
priority: P2
developer_type: agent-single
created: 2026-11-13
author: Savia
phase: A
risk: L2
human_surface: true
related_specs: [SE-349, SE-362, SE-433, SE-493, SE-503, SE-505, SE-507, SE-518, SE-456, SE-488]
origin: "Spec A de la línea de orquestación de compañeros (Labs L39, fase M6a). Decisión de la operadora el 2026-11-13 por pregunta interactiva (registro de la orquestadora): escribir las tres specs propuestas empezando por esta y la de ficha de harness; aplicar la regla desde ya, sin semana de medición en sombra. Inspiración pública: el principio «nada pasa a verificado por la palabra del agente» de kwant (AGPL) y la separación ejecutor/verificador de openbot (licencia no comercial). No se copia código ni texto de ninguno de los dos. Solo spec: ningún script, hook ni esquema se toca todavía."
timeline:
  - from: "2026-11-13"
    learned: "2026-11-13"
    value: "PROPOSED"
    source: "worker autónomo; encargo de la orquestadora"
  - from: "2026-11-13"
    learned: "2026-11-13"
    value: "APPROVED"
    source: "operadora, pregunta interactiva; escenas y decisiones 1-5 confirmadas «Confirmo todo como está»"
---

# SE-530 — Hecho verificado: ningún trabajo se da por bueno por su propia palabra

> **En una línea.** Un trabajo que un trabajador de la planta declara terminado sigue siendo «declarado» hasta que una comprobación que no hizo él lo confirma. La orquestadora deja de decir «terminado» de lo que solo está declarado.

## Problema (verificado en origin/main 2681e26a7, 2026-11-13)

1. **El «OK» lo escribe quien hizo el trabajo.** Los trabajadores de la planta (workers headless de `claude -p`) cierran con una marca de fin `ESTADO: OK|PARCIAL|FALLO` que escriben ellos mismos. La orquestadora la lee y la traslada a la persona. Entre «el trabajador dice que está bien» y «alguien que no es el trabajador lo ha comprobado» no hay ninguna distinción registrada. El lanzador de workers vive fuera de este repo (lo dice `docs/specs/SE-507-declared-run-heartbeat.spec.md`, Problema, punto 1), así que la marca de fin no tiene hoy un esquema versionado aquí.
2. **No se sabe qué parte de los OK tiene prueba independiente.** Hay PRs con revisión registrada (`scripts/merge-sprint.sh:74-93` exige un `VERDICT` con revisor distinto del autor y que no sea la orquestadora), CI sobre un SHA exacto y confirmaciones de la persona, pero nada las cruza con cada marca de fin. **No hay una cifra pública de cuántos OK carecen de prueba independiente**: esta spec la pide como primer entregable (S1) en vez de suponerla.
3. **Decir «listo» sin comprobar es un fallo recurrente de la propia orquestadora.** Existe una guarda para el caso de la conversación: `.claude/hooks/stop-dod-gate.sh:122-161` (DOD-004, CRIT-034) bloquea afirmar estado («en marcha», «listo», «esperando») sin una comprobación en el turno. No cubre el caso de un trabajo ajeno declarado por su ejecutor: la orquestadora puede haber comprobado «que existe la marca de fin» y aun así estar repitiendo lo que el trabajador declaró.
4. **El ledger de runs ya sabe derivar estado en lectura** (`scripts/savia-runs.sh:111-133`, `derive(r)`; el comentario de `:107` fija «ALWAYS at read time, never stored»), pero sus estados (`working`, `approved`, `merged`, …) describen el ciclo de la PR, no si alguien distinto del ejecutor confirmó el resultado. `finish` (`:324`) solo protege contra terminar un run con una PR viva.

### Qué ya existe y qué falta

| Pieza | Dónde (verificado en main) | Qué cubre | Qué no cubre |
|---|---|---|---|
| Revisor independiente de una PR | `scripts/merge-sprint.sh:89` (`revisor no independiente`), `:29` (`is_orch`) | Un `VERDICT` solo se registra si revisor ≠ autor y el revisor no es la orquestadora | Solo existe para PRs que entran en un merge-sprint, no para cualquier trabajo |
| Estado derivado en lectura | `scripts/savia-runs.sh:111-133` | Precedencias en un solo sitio, con traza del motivo | No distingue «declarado» de «verificado» |
| Estado afirmado sin comprobar | `.claude/hooks/stop-dod-gate.sh:122-161` (DOD-004) | Bloquea la afirmación en el turno de la conversación | No sabe quién comprobó ni si era independiente |
| Aprobación por la persona | `scripts/approval-receipt.py` (SE-488) | Artefacto de aprobación que un agente no puede producir por sí mismo | No está ligado a «este trabajo concreto» |
| Verificador real por proyecto | `docs/specs/SE-503-real-verifier-per-project.spec.md` (PROPOSED) | Define cómo ejecutar una comprobación real en un proyecto | No dice quién la propone ni si cuenta como independiente |
| Ledger de efectos | `docs/specs/SE-493-effect-ledger-ambiguous-reconciliation.spec.md` | Efectos dudosos de un intento | No es una verificación del resultado |
| Pulse (SE-518) | **No está en `main` a fecha de esta spec** (APPROVED en rama) | Ledger y eventos del latido | S3 depende de que se fusione |

**Conclusión.** Las piezas para comprobar de forma independiente existen sueltas. Falta (a) **el vocabulario** (declarado / verificado / refutado), (b) **la regla de independencia** aplicada a cualquier trabajo y no solo a las PRs de un merge-sprint, y (c) **el cruce** con la marca de fin del trabajador.

## Lo que he entendido

Esta spec cambia lo que la persona ve y lo que la orquestadora le dice. Por eso lleva escenas, antes y después en lenguaje llano y la confirmación de la persona (2026-11-13).

### Qué ve la persona hoy

Un trabajador cierra con «ESTADO: OK». La orquestadora le dice a la persona «terminado» o «la PR está lista» con lo que ese trabajador escribió. Si no se abre la PR, el diff o el resultado de CI, la persona no sabe si alguien aparte del propio trabajador lo miró. Y cuando se equivoca, se entera por el fallo posterior, no por el aviso.

### Qué verá la persona con esta spec

Cada trabajo aparece con uno de tres estados y con **la razón**:

- **Declarado**: «el trabajador dice que está hecho; nadie más lo ha comprobado». La orquestadora nunca lo llama «terminado».
- **Verificado**: «lo confirmó X (una revisora distinta, pruebas que el trabajador no escribió, o tú) sobre este SHA».
- **Refutado**: «el trabajador dijo OK y una comprobación independiente falló: esto es lo que falló».

### Escenas

1. **Un OK sin nada más.** Un trabajador deja `ESTADO: OK` y una PR en borrador. Aún no hay revisión ni CI en verde sobre el SHA final. La orquestadora te escribe: «Trabajo X: declarado, sin verificar. El trabajador dice que está hecho. Falta una revisora distinta o tus pruebas». No dice «terminado» ni «listo».
2. **Una revisora distinta lo confirma.** Una revisora que no es el trabajador ni la orquestadora registra su veredicto sobre el SHA exacto. El aviso pasa a: «Trabajo X: verificado por la revisora de corrección sobre `abc1234`». Si el trabajador sube un commit después, el veredicto ya no cuenta para el SHA nuevo y el trabajo vuelve a «declarado» con el motivo («la verificación es de un SHA anterior»).
3. **El trabajador propone su propia prueba.** El trabajador añade un test y dice «con esto se comprueba». Ese test **no cuenta**: nació de quien se juzga. El aviso dice: «El trabajador propone esta comprobación. No cuenta hasta que la apruebes». Tú la apruebas o la rechazas por una pregunta; hasta entonces el trabajo sigue declarado.
4. **Una prueba independiente falla.** El trabajador dijo OK y el CI de la base, o una revisora, dice HOLD. El aviso es: «Trabajo X: refutado. El trabajador dijo OK; falla `<comprobación>`». No se mezcla con los verificados ni se oculta entre los pendientes.
5. **El resumen de la mañana y la información que falta.**
   - **El resumen.** La tarjeta cuenta tres cifras separadas: «N verificados, M declarados sin verificar, K refutados». Un trabajo declarado no se suma a los terminados. Tú ves de un vistazo cuánto del trabajo de la noche tiene confirmación. La tarjeta depende de S3 (SE-518, aún no fusionada): hasta entonces la distinción llega solo en los mensajes de Savia.
   - **Falta información.** El recibo del trabajo está incompleto, ilegible o no dice quién lo hizo. El estado es «declarado» y el aviso dice por qué, con este texto confirmado: «Trabajo X: declarado. No se puede comprobar: el justificante no dice quién lo hizo». Nunca «verificado» por defecto.

### Palabras de la persona

«Un trabajo no pasa a hecho porque el propio trabajador lo declare. Pasa cuando lo confirma una comprobación independiente: tests que no escribió él, una revisora distinta o la persona. Si el trabajador propone su propia comprobación, no cuenta hasta que la aprueba la persona. Aplicar desde ya, sin semana de medición en sombra.» — 2026-11-13, decisión de la operadora por pregunta interactiva; registro de la orquestadora, no texto literal.

### Qué SÍ será

- Tres estados con motivo visible: declarado, verificado, refutado.
- La regla de independencia aplicada a cualquier trabajo, con la misma definición que ya usa `merge-sprint.sh` para las revisiones de PR.
- Medición y distinción en el aviso **desde el primer día** (S1): la cifra se mide mientras la regla ya se aplica.
- Fallo cerrado: ante dato ausente, ilegible o ambiguo, el estado es «declarado».

### Qué NO será

- No bloquea fusiones: la puerta de SE-433 y la de SE-362 no cambian (fuera de alcance).
- No cambia las revisoras ni la gramática del `VERDICT` (eso es el contrato de SE-518 S5c).
- No sustituye la revisión humana de tier 3/4 ni la autoridad de la persona.
- No le pide a la persona que apruebe cada trabajo: solo las comprobaciones que propone el propio trabajador, y solo si quiere que cuenten.
- No impide que un trabajo «declarado» se use: impide **llamarlo terminado**.

### Confirmación

- fecha: 2026-11-13
- respuesta: «Confirmo todo como está». Respuesta de la operadora, por pregunta interactiva, a las escenas y a las decisiones 1 a 5 de esta spec (ver «Decisiones de la operadora»), con la opción recomendada en todas. Registro de la orquestadora; el texto de las escenas confirmadas es el de esta sección. Las escenas 5 y 6 de la presentación se agrupan aquí en la 5 para cumplir el máximo de la puerta; su contenido no cambia.

## Slice S0 — Prototipo navegable

- prototipo: los avisos confirmados de las escenas 1 a 5 (declarado, verificado, refutado, aviso de comprobación propia, aviso de falta de información y las tres cifras del resumen de la mañana), escritos sobre datos de ejemplo y en el tono de Savia. Es texto, no una pantalla nueva: se enseña a la persona en una conversación o en un documento y se usa en su dispositivo. Por construir al arrancar S1; no se ha construido ni enseñado todavía.

### Confirmación del prototipo

- fecha: pendiente
- respuesta: pendiente. S1 no se pone en curso sin ella (SE-505).

## Qué decide esta spec

### D1 — Estados y precedencia

| Estado | Condición |
|---|---|
| `refutado` | Existe al menos una comprobación independiente, ligada al SHA vigente, con resultado negativo (CI en rojo sobre ese SHA, `VERDICT: HOLD` de una revisora distinta, rechazo de la persona). |
| `verificado` | No hay refutación y existe al menos una comprobación **independiente** (D2), **aprobada** (D3), **superada** y **ligada al SHA vigente** del trabajo (D4). |
| `declarado` | Todo lo demás, incluido: sin recibo, recibo ilegible, campo ausente, identidad del ejecutor desconocida, comprobación solo del ejecutor, comprobación de un SHA anterior. |

Precedencia: `refutado` > `verificado` > `declarado`. Evidencia propia negativa: un test o CI del propio ejecutor en rojo no refuta (no es independiente), pero tampoco se calla: el trabajo sigue `declarado` y el aviso añade «la comprobación propia del ejecutor falla». Una comprobación que falla pesa más que cien que pasan: un trabajo con una revisora que aprueba y un CI de la base en rojo es `refutado`. **El estado se deriva siempre en lectura y nunca lo escribe el ejecutor** (mismo principio que `scripts/savia-runs.sh:107`): un recibo que traiga un campo de estado escrito por el trabajador se ignora y se anota como anomalía.

### D2 — Qué es independiente

Una comprobación es independiente si cumple las tres:

1. **El verificador no es el ejecutor** (identidad distinta, comparada con el id del trabajador del recibo).
2. **El verificador no es la orquestadora que despachó el trabajo**, salvo que la comprobación sea mecánica y no la haya escrito ella (CI, postcondición fijada antes del trabajo). Es la regla que ya aplica `scripts/merge-sprint.sh:89` a los revisores de PR.
3. **Lo comprobado no lo escribió el ejecutor.** Un test añadido por el propio trabajador en el mismo diff no es independiente respecto a lo que ese diff implementa. Sí lo es un test que ya estaba en la base (`origin/main` antes del trabajo) y sigue en verde.

Clases de evidencia que S1 mide por separado:

| Clase | Qué es | Cuenta como independiente |
|---|---|---|
| `revision` | `VERDICT` de una revisora distinta del ejecutor y de la orquestadora, sobre el SHA vigente | Sí |
| `persona` | Confirmación registrada de la persona sobre este trabajo y SHA | Sí |
| `ci_base` | CI en verde sobre el SHA exacto, con pruebas que existían en la base | Sí, y verifica «no rompe lo existente» |
| `postcondicion` | Comprobación mecánica definida **antes** del trabajo por alguien distinto del ejecutor (por ejemplo, la del encargo) | Sí |
| `ci_propio` | CI en verde cuyas únicas pruebas relevantes las añadió el propio ejecutor | **No**: cuenta como `declarado` y se informa aparte |
| `autodeclaracion` | La propia marca de fin, un fichero que creó el ejecutor, su resumen | **No** |

El criterio de `ci_base` y `ci_propio` (qué pruebas son «de la base») se fija en el prerregistro de S1 y no se cambia después de medir (D6).

### D3 — Comprobaciones propuestas por el ejecutor

Si el ejecutor propone su propia comprobación (un test que añade, una postcondición que escribe en su recibo), nace `propuesta_por: ejecutor` y `aprobada_por: ninguno`. **No cuenta hasta que la aprueba la persona**, y esa aprobación solo es válida si la registra una acción que el ejecutor no puede producir: un artefacto del tipo de `scripts/approval-receipt.py`, o la respuesta a una pregunta interactiva registrada. Aprobarla un agente, incluida la orquestadora, no vale. La aprobación va ligada a la comprobación concreta (hash de su contenido), no al trabajo en general: si el ejecutor la cambia después, vuelve a no estar aprobada.

### D4 — Ligadura al SHA

Toda comprobación lleva el SHA (o el hash del resultado, para trabajos sin commit) sobre el que se hizo. Si el SHA vigente del trabajo cambia, la comprobación deja de contar, el trabajo vuelve a `declarado` y el aviso dice por qué. Es la misma disciplina que el registro de revisiones de `merge-sprint.sh` (revisión ligada a `pr` y `sha`).

### D5 — Qué dice la orquestadora

La orquestadora **no usa «terminado», «listo» ni «hecho»** para un trabajo `declarado`. Usa «declarado, sin verificar» y la razón. Para `verificado` dice quién lo verificó y sobre qué SHA. Para `refutado` dice qué comprobación falló. La regla se escribe en `docs/rules/domain/hecho-verificado.md` (carga bajo demanda, no `@import`, para no tocar el contexto fijo por turno de SE-511). No se extiende DOD-004: ampliar un hook es otra spec y otro tier.

### D6 — Prerregistro de H9 y de las clases de evidencia

Antes de ejecutar la primera medición, S1 commitea `docs/evidence/SE-530-S1-prerregistro.md` con:

- **Hipótesis H9**: «En una ventana de 14 días, al menos el 10 % de las marcas `ESTADO: OK` de la línea de producción no tienen evidencia independiente registrada.»
- **Refutación**: H9 se refuta si la cifra es **inferior al 10 %** con **n ≥ 200** marcas OK en la ventana. Con n < 200 el resultado es «no concluyente» y se amplía la ventana sin cambiar el umbral.
- **Definición congelada** de cada clase de la tabla D2, incluida la de «prueba de la base» y la de «orquestadora que despachó».
- **Qué cambia según el resultado.** Si H9 se confirma, la regla de S2 se mantiene y se vigila el ruido. **Si se refuta, la regla de S2 se mantiene igual** (la operadora decidió aplicarla desde ya), y lo que se replantea es S3 y el tamaño del aviso, no el umbral.
- **Desviaciones**: lo que se vea después de la primera medición va a una sección «Desviaciones», no reescribe el prerregistro. El umbral del 10 % no se rebaja para que la hipótesis salga (causa raíz, SE-456).

Un test comprueba que el commit del prerregistro es ancestro del commit del informe de medición.

### D7 — Reversión

S1 es de solo lectura sobre los registros: se revierte con `git revert`. S2 añade campos opcionales a un recibo y una derivación en lectura: un recibo antiguo sin los campos queda en `declarado` (D1), que es el estado conservador, así que volver atrás no corrompe ningún dato. S3 se revierte quitando el evento; los eventos ya emitidos quedan como historia.

## Slices

| Slice | Qué | Tier (`scripts/risk-tier.py`) | Depende de |
|---|---|---|---|
| S1 | Medición y distinción en el recibo, con los estados declarado / verificado / refutado, aplicados desde el primer día | **1-2** | Confirmación de las escenas |
| S2 | Regla en el recibo del trabajador, con fallo cerrado | **2** | S1 fusionada y prerregistro commiteado |
| S3 | Evento `job_verified` en Pulse | **3** | S2 y SE-518 fusionada (S1 del latido) |

Tiers: S1 y S2 salen de `python3 scripts/risk-tier.py --diff` sobre sus ficheros previstos (guion, regla, esquema, tests y `scripts/savia-runs.sh`): **tier 2** en las dos muestras; S1 baja a 1 si solo entrega el prerregistro y el informe. S3 es **tier 3** por declaración, porque toca el latido de SE-518 (gobernanza del ledger) y SE-518 no está en `main`: no se puede calcular con un diff que todavía no existe. Cada PR vuelve a calcularlo con su diff final y lo escribe en su body.

### S1 — Medición y distinción desde el primer día (tier 1-2)

La decisión de la operadora fue **aplicar desde ya**, así que S1 mide y aplica a la vez. No hay fase en sombra.

- **Entregables.**
  1. `docs/evidence/SE-530-S1-prerregistro.md` (D6), commiteado antes de medir.
  2. `scripts/hecho-verificado.py` con dos subcomandos de **solo lectura**: `classify <marca-de-fin>` (da el estado y el motivo de un trabajo) y `measure --window 14 --done-dir <dir>` (cruza cada marca OK de la ventana con las clases de D2 y da la cifra por clase). El directorio de marcas de fin y el repo se pasan por argumento: el lanzador está fuera de este repo y el script no asume su ruta.
  3. `docs/rules/domain/hecho-verificado.md` con D1 a D5: vocabulario y frases de la orquestadora. Desde su fusión, los avisos distinguen declarado de verificado.
  4. `docs/evidence/SE-530-S1-medicion.md` con la cifra, el n, el veredicto de H9 y la tabla por clase.
- **Qué no hace S1.** No escribe en ningún recibo, ledger ni marca de fin. No bloquea nada.
- **AC.**
  - **AC-1.1** La medición es reproducible: dos ejecuciones sobre los mismos ficheros dan la misma salida byte a byte.
  - **AC-1.2** Da la cifra **por clase de evidencia**, no solo un total.
  - **AC-1.3 (negativo)** Una marca `ESTADO: OK` sin PR, sin `VERDICT` y sin nada más cuenta como «declarado, sin verificar».
  - **AC-1.4 (negativo)** Un OK cuya única evidencia es un fichero que creó el propio trabajador cuenta como «declarado».
  - **AC-1.5 (negativo)** Un test añadido por el trabajador en su diff y en verde (`ci_propio`) **no** sube el trabajo a `verificado`.
  - **AC-1.6 (límite)** Con n = 199 OK en la ventana el veredicto de H9 es «no concluyente»; con n = 200 y 19 marcas sin evidencia independiente (9,5 %) se refuta; con n = 200 y 20 marcas (10,0 %, justo en el umbral) se confirma.
  - **AC-1.7 (fallo cerrado)** Marca de fin ilegible, vacía o sin `ESTADO:` da «declarado» con motivo y salida distinta de 0 de `classify`; nunca «verificado».
  - **AC-1.7b (contrato de salida)** `classify` devuelve 0 para `verificado` y para `declarado` con recibo legible, 1 para `refutado` y 2 para recibo ilegible, vacío o sin `ESTADO:` (declarado por fallo cerrado). El estado se lee siempre de la salida estándar, no solo del código.
  - **AC-1.8** El prerregistro es ancestro del informe de medición (D6).

### S2 — Regla en el recibo del trabajador (tier 2)

- **Qué cambia.** El recibo de un trabajo (el registro que une la marca de fin con las comprobaciones) añade `ejecutor`, `sha`, y una lista `verificaciones[]` con `{clase, ref, sha, verificador, propuesta_por, aprobada_por, resultado}`. El estado efectivo se **deriva** en lectura con D1; el ledger de runs (`scripts/savia-runs.sh`, `derive`) lo expone junto al estado de la PR sin guardarlo. Las verificaciones las añaden quienes verifican (revisora, CI, persona), nunca el ejecutor sobre su propio recibo.
- **Esquema.** Un esquema versionado en `schemas/` para el recibo, validado con el patrón de los demás esquemas del repo.
- **AC.**
  - **AC-2.1** Un test con el mismo id de ejecutor y de verificador da «declarado».
  - **AC-2.2** Un verificador distinto con su comprobación superada y ligada al SHA vigente da «verificado».
  - **AC-2.3 (fallo cerrado)** Si falta el campo `verificado_por`/`verificaciones` o el recibo no valida contra el esquema, el estado es «declarado», nunca «verificado».
  - **AC-2.4 (negativo)** Una comprobación con `propuesta_por: ejecutor` y sin `aprobada_por` de la persona no cuenta; con `aprobada_por` igual al ejecutor o a la orquestadora, tampoco.
  - **AC-2.5 (negativo)** Una verificación de un SHA anterior al vigente no cuenta (D4).
  - **AC-2.6 (negativo)** Una verificación `superada` más otra `fallida` dan «refutado».
  - **AC-2.7 (negativo)** Un recibo con un campo de estado escrito por el ejecutor se ignora y se anota como anomalía.
  - **AC-2.8** Los recibos anteriores a S2, sin los campos nuevos, siguen leyéndose y dan «declarado» (reversión segura, D7).
  - **AC-2.9** Cada test nuevo falla contra el código anterior o con la aserción mutada (SE-456).

### S3 — Evento en Pulse (tier 3)

- **Depende de** SE-518 fusionada. A fecha de esta spec SE-518 está APPROVED en rama y **no en `main`**; S3 no arranca hasta que lo esté, y su contrato de evento se escribe contra el ledger tal como quede fusionado, no contra la rama. No modifica la spec de SE-518: va como spec propia que Pulse consume.
- **Qué hace.** Emite `job_verified` con el verificador y el SHA. Las dos vistas de Pulse que hoy distinguen «en marcha» de «terminó» pasan a distinguir también «verificado». Cuáles son exactamente se fija al arrancar S3, leyendo SE-518 ya fusionada; aquí no se citan por nombre porque no se han podido verificar en `main`.
- **AC.**
  - **AC-3.1 (negativo)** Un trabajo con `done` OK y sin evidencia independiente **no** genera `job_verified`.
  - **AC-3.2** La tarjeta de la mañana cuenta verificados, declarados sin verificar y refutados por separado (escena 5).
  - **AC-3.3 (negativo)** Un `job_verified` cuyo verificador coincide con el ejecutor se rechaza y se registra como anomalía.
  - **AC-3.4** Tier 3: revisión humana explícita de esa PR (SE-362).

## Criterios de aceptación transversales

| AC | Criterio | Tipo |
|---|---|---|
| AC-T1 | `tests/bats/se530-spec-coherence.bats` pasa sobre la spec y falla con cada mutación (estado, slice, tier, escenas, prerregistro, orden S1-S2-S3). | positivo / negativo |
| AC-T2 | Ningún slice cambia la gramática del `VERDICT`, las revisoras ni la puerta de merge (SE-433, SE-362). | negativo |
| AC-T3 | Lo no verificado jamás se informa como «terminado» desde la fusión de S1 (regla D5). | negativo |
| AC-T4 | La medición de S1 y la regla corren a la vez: no hay modo «sombra». | negativo |

## OpenCode Implementation Plan

### Bindings touched

| Componente | Claude Code | OpenCode v1.14 |
|---|---|---|
| Medición y clasificación (S1) | `scripts/hecho-verificado.py` (Python, solo lectura) | El mismo script |
| Regla de la orquestadora (S1) | `docs/rules/domain/hecho-verificado.md`, carga bajo demanda | La misma regla, mismo path |
| Recibo y derivación (S2) | `scripts/savia-runs.sh` y un esquema en `schemas/` | Los mismos ficheros |
| Evento de Pulse (S3) | Según SE-518 fusionada | Según SE-518 fusionada |
| Hooks | Ninguno nuevo. DOD-004 no se toca | Ninguno nuevo |

### Verification protocol

- [ ] Funciona en runtime OpenCode: `classify` y `measure` se ejecutan igual desde una sesión de OpenCode y dan la misma salida
- [ ] Tests BATS y pytest cubren cada slice, su caso negativo y su caso límite (AC-1.x, AC-2.x, AC-3.x)
- [ ] No se registra ningún hook nuevo; los cambios en hooks o `settings.json` quedan fuera de esta spec

### Portability classification

- [x] **PURE_BASH / PURE_PYTHON**: scripts y reglas sin dependencia de un frontend; el único acoplamiento es el formato del recibo, que es común.

## Fuera de alcance

- Cambiar las revisoras o el contrato `VERDICT` (SE-518 S5c).
- Bloquear fusiones o cambiar la puerta de SE-433 y la clasificación de SE-362.
- Ampliar el hook DOD-004 o cualquier otro hook.
- Decidir qué comprobación real corresponde a cada proyecto (SE-503).
- Medir o limitar las cadenas de delegación entre agentes.
- Cualquier cambio en la ficha de harness o en el catálogo de agentes: son las otras dos specs de la fase M6.
- Reescribir la marca de fin del lanzador, que vive fuera del repo.

## Preguntas abiertas

Las tres quedan cerradas con la opción recomendada, confirmada por la operadora el 2026-11-13 (pregunta interactiva).

1. **¿`ci_propio` cuenta como verificación?** Cerrada: **no**. Un test que añade el trabajador mide lo que el trabajador entendió, no lo que se pidió. Solo cuenta si una revisora distinta lo aprobó, que ya es la clase `revision`.
2. **¿La confirmación de la persona se registra con la misma pregunta interactiva de siempre o con un artefacto aparte?** Cerrada: **la pregunta interactiva**; el artefacto de `scripts/approval-receipt.py` solo se usa cuando la aprobación amplíe autoridad.
3. **¿Qué pasa con los trabajos sin PR (informes, investigación)?** Cerrada: la persona o una revisora distinta son las únicas clases posibles; si ninguna actúa, el trabajo queda «declarado» y el aviso lo dice sin dramatizar.

## Decisiones de la operadora (2026-11-13)

Registro de la orquestadora de las respuestas a preguntas interactivas; no es texto literal.

- Escribir las tres specs propuestas (A, B y C), empezando por esta (A) y por la de la ficha de harness (B). Entran en Labs L39 como fase M6.
- **Aplicar desde ya.** No hay semana de medición en sombra antes de la regla. Por eso S1 mide y aplica a la vez.
- Prerregistrar la hipótesis H9 en S1, antes de medir.

Confirmadas el 2026-11-13 por pregunta interactiva («Confirmo todo como está»), con la opción recomendada en todas:

1. **Texto de los avisos** de declarado, verificado y refutado (escenas 1 a 4): tal cual.
2. **Aprobación de las pruebas que propone la trabajadora** (escena 3): pregunta interactiva, no justificante aparte.
3. **Una prueba que añade la propia trabajadora no cuenta como verificación**; solo cuenta si la aprueba una revisora distinta (clase `revision`).
4. **Trabajos sin propuesta de cambio** (informes, investigación): solo la persona o una revisora distinta pueden verificarlos; si ninguna actúa, quedan declarados.
5. **Texto del aviso de «falta información»**: «Trabajo X: declarado. No se puede comprobar: el justificante no dice quién lo hizo».

## Riesgos

- **Más ruido si la evidencia está dispersa.** Muchos trabajos saldrán «declarados» el primer día aunque estén bien, porque la verificación aún no se ha registrado. Mitigación: el aviso dice qué falta, no acusa, y S1 mide la cifra real en paralelo.
- **Una verificación «de compromiso».** Una revisora que aprueba por inercia vuelve a la regla papel mojado. Mitigación: la regla garantiza independencia, no calidad; la calidad de la revisión es de SE-518 S5c.
- **Aplicar sin medir.** Se acepta por decisión de la operadora; la medición corre en paralelo y el prerregistro fija cómo se lee.
- **Identidad del ejecutor mal registrada.** Si el recibo no la trae, el estado es `declarado` (D1). Se paga en ruido, no en falsa confianza.
- **Marca de fin fuera del repo.** El formato lo fija un lanzador ajeno a este repo; S1 no lo reescribe y `classify` falla cerrado ante lo que no entienda.

## Aprobación

**Aprobada por la operadora el 2026-11-13** por pregunta interactiva («Confirmo todo como está»), con las escenas y las decisiones 1 a 5. Falta la confirmación del prototipo (S0): S1 no se pone en curso sin ella (SE-505). S3 espera además a SE-518 en `main`. Se formaliza al fusionar (SE-488).
