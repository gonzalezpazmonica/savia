---
status: PROPOSED
priority: P2
developer_type: agent-single
created: 2026-11-14
author: Savia
phase: A
risk: L3
human_surface: false
related_specs: [SE-270, SE-332, SE-362, SE-456, SE-496, SE-498, SE-530, SE-531, SE-532, SPEC-121]
origin: "Encargo de la orquestadora del 2026-11-14, decidido por la operadora por pregunta interactiva: redactar esta spec en estado PROPOSED. La condición que puso, medir antes, se cumple con una medición independiente del 2026-11-14 (informe privado de la línea L39, fila M6). Un estudio público previo de orquestadores de bots (2026-11-13) aporta la lección de diseño: los topes fijos de delegación se quitaron por fricción y se sustituyeron por detección de repeticiones y de fallos seguidos. Solo spec: ningún guard, agente ni script se toca todavía."
timeline:
  - from: "2026-11-14"
    learned: "2026-11-14"
    value: "PROPOSED"
    source: "worker autónomo; encargo de la orquestadora (registro de la orquestadora de la decisión de la operadora; no es texto literal)"
---

# SE-533 — Límites compartidos de delegación entre agentes (handoff)

> **Qué es y qué no es.** Es un presupuesto de delegación que cualquier cadena de agentes comparte, un permiso de quién puede pedir a quién (cerrado por defecto) y el arreglo del analizador que hoy da PASS a ciclos y atajos. **No es** un tope fijo que frena el trabajo normal: cada límite sale de una medición, empieza en modo observación y solo se hace obligatorio cuando la medición demuestra que el trabajo legítimo no lo roza. **No concede autoridad de efectos** (eso es SE-496): decidir quién puede *pedir trabajo* a quién no autoriza ningún efecto.

## Problema (verificado en origin/main fae7b0e50, 2026-11-14)

Hay cotas locales, pero ninguna cota común que sobreviva a la herramienta de delegación, a los procesos nuevos lanzados desde un agente y a los reencolados. Las pruebas son de lectura y de ejecución determinista del analizador; **no se ha provocado ninguna tormenta de agentes ni observado una cadena infinita real** (lo que sigue es apertura declarativa, no recursión demostrada).

1. **El analizador de enrutado acepta ciclos y atajos.** `scripts/agent-depth-limit.sh` (SE-270 S4) construye aristas solo desde `permission.task.allowlist` con destino existente (`:64`, `:79`, `:99`), omite autobucles (`:138`) y calcula con BFS la distancia **mínima** desde cada raíz (`:120`, `:140`), no el camino más largo ni los ciclos. Reproducido el 2026-11-14 con un directorio sintético por caso y el límite en 2:

   | Entrada | Resultado | Debería |
   |---|---|---|
   | `a→b`, `b→a` | rc 0, PASS | FAIL (ciclo) |
   | `a→a` | rc 0, PASS | FAIL (autobucle) |
   | `a→b→c→d` más `a→d` | rc 0, PASS (profundidad 2) | FAIL (hay un camino de 3 saltos oculto por el atajo) |
   | `a→b→c→d` sin atajo | rc 1, FAIL | FAIL (control de contraste: el analizador sí ve el exceso lineal) |

   El defecto es del algoritmo, no del umbral: subir o bajar el límite no lo resuelve.
2. **Su test no existe.** `tests/test-se270-agent-depth-limit.bats` tiene un único test con `skip` («pending recalibration»). Un test que no puede fallar (SE-456) protege el analizador desde SE-270. Además, `agent-depth-limit.sh` no figura en `validate-ci-local.sh` ni en `.github/workflows/`: nada lo ejecuta en cada PR (búsqueda de la cadena `agent-depth-limit` en `scripts/validate-ci-local.sh`, `.github/` y `.claude/`: sin coincidencias).
3. **Seis agentes delegadores no declaran destinos.** En `.claude/agents/` hay 8 agentes con `Task` y 6 sin `permission.task.allowlist`; en `.opencode/agents/`, 10 con `task` y las mismas 6 sin allowlist: `commit-guardian`, `court-orchestrator`, `frontend-test-runner`, `recommendation-tribunal-orchestrator`, `test-runner` y `truth-tribunal-orchestrator` (p. ej. `.claude/agents/court-orchestrator.md:7`, `.claude/agents/truth-tribunal-orchestrator.md:6`, `.claude/agents/commit-guardian.md:13`). El analizador los ignora justo por eso (punto 1): el grafo de allowlists explícitas tiene 4 aristas en Claude Code y 8 en OpenCode, sin ciclos y de profundidad 1, y **omite precisamente a los delegadores sin allowlist**. En OpenCode, `opencode.json:94` permite `task` al agente `build` sin selector de destinos y `:117` da a su Bash un permiso residual `"*": "allow"`; `plan` lo deniega (`:125`). Esto es el contrato declarativo: no se ha probado que cualquier destino sea ejecutable.
4. **El guard de profundidad no mide nada en la práctica.** `delegation-guard.sh` solo procesa `tool_name=Agent` (`:30`), sale en silencio con entrada vacía (`:26`) y bloquea si `SAVIA_DELEGATION_DEPTH` ≥ 1 (`:33`, `:35`). **Ningún fichero del repo escribe esa variable**: solo los hooks la leen y los tests la fijan a mano (búsqueda en todo el árbol, 2026-11-14). Con el valor por defecto 0 el guard no bloquea nunca. Se registra solo para `Agent` (`.claude/settings.json:380`), mientras que otros hooks usan `Agent|Task` (`:390`), y es de perfil `standard` (`:12`). La matriz de cobertura declara el guard sin portar a OpenCode (`scripts/hooks-coverage-matrix.sh:175`). Una variable autodeclarada tampoco acreditaría parentesco aunque alguien la escribiera.
5. **Otros guards miran otra cosa.** `recursion-guard.sh` solo actúa con contexto de bucle (`:14`, `:42`); `repeat-tool-guard.sh` compara llamadas idénticas dentro de una sesión (`:57`, `:66`); `agent-dispatch-validate.sh` valida contexto y modelo, sin contador de profundidad (`:20`, `:43`). Ninguno es un presupuesto acumulado de un encargo.
6. **Las entradas que lanzan procesos no comparten presupuesto.** `scripts/parallel-dispatch.sh` ejecuta un comando arbitrario con `timeout` por job (`:61`) y sin máximo de jobs ni semáforo; `scripts/fork-agents.sh` limita a 5 hijos (`:25`, `:224`) y 300 s (`:176`) pero no hereda reserva. Un agente con Bash puede relanzar un CLI de agente y volver a delegar. Los workers de la planta de trabajo reciben la prohibición de subagentes como texto del encargo, que no cierra la ruta de sesiones nuevas por Bash. **Sospechado, sin prueba de runtime**: que esas rutas permitan recursión ilimitada en los binarios instalados.
7. **La planta de trabajo (fuera de este repo) cuenta solo procesos de primer nivel y renueva reintentos entre días.** La admisión excluye descendientes y no cuenta los otros runtimes, y un trabajo cortado por cuota vuelve a la cola con freno diario pero sin máximo acumulado. Esa parte vive en la instalación privada de la operadora: esta spec fija el contrato que debe consumir y no la modifica (Fuera de alcance).

### Lo que ya está bien acotado (no se toca)

- Rondas de corrección: una por revisión en el tribunal de código (`.claude/agents/court-orchestrator.md:54`), dos intentos en `test-runner` ante fallos (`:31`) y dos ciclos en `frontend-test-runner` (`:95`).
- Abanico local de los lanzadores (5 en `fork-agents.sh`) y plazos por proceso.
- El handoff entre etapas SDD: un handoff que no termina en `completed` no activa al destino (`docs/rules/domain/agent-handoff-protocol.md:60`).

Estas cotas son **por componente**. Lo que falta es lo que las suma: profundidad, hijos activos y lanzamientos acumulados de un mismo encargo, medidos en un solo sitio.

### Límites de lo medido

- Los recuentos (8/6 y 10/6) son de cabecera parseada y de lectura el 2026-11-14; el informe de S0 fija la cifra definitiva y, si difiere, vale la de S0.
- **No se ha medido el uso real**: cuántos lanzamientos, qué profundidad ni cuántos hijos simultáneos tiene hoy un encargo normal. Por eso ningún valor de H o C de esta spec es un tope: son valores de partida para observar (D1).
- Una medición independiente del 2026-11-14 propuso H ≤ 18 (cadena SDD con una corrección) y H ≤ 32 (entradas genéricas). La primera sale de sumar etapas nominales y la segunda es una cifra de contención; ninguna se infirió del uso. Esta spec no las adopta como tope.
- El runtime no ha confirmado qué identidad del padre llega a un hook (ver Q1).

## Relación con otras specs: no se duplica

| Pregunta | La responde | Esta spec |
|---|---|---|
| ¿Quién puede **autorizar un efecto** (grants, contratos, firma)? Subdelegar autoridad queda prohibido en v1 | SE-496 | No concede ni transmite autoridad. El permiso de aquí es «puede pedir trabajo», nunca «puede ejecutar el efecto» |
| ¿Cómo se **para** todo y se invalidan delegaciones? | SE-498 | Un STOP vigente hace que la reserva de presupuesto falle cerrada (AC-9). No define STOP |
| ¿Cómo se corta un proceso hijo, se retiran sus descendientes y se detecta la misma llamada repetida **dentro** de un hijo? | SE-531 S2 | Consume ese supervisor para la terminación (D5). SE-531 deja fuera «límites de profundidad o de abanico»: son de aquí |
| ¿Qué dice un handoff y cuándo activa al destino? | SPEC-121 (`agent-handoff-protocol.md`) | Lo usa tal cual: su `termination_reason` es la señal de fallo de D4 |
| ¿Qué hace un agente cuando se bloquea? | SE-332 (handback) | Todo límite que corta termina en handback al padre inmediato, no en un fallo mudo |
| ¿Cómo se valida la cabecera de cada agente? | SE-532 | S1 de esta spec usa el mismo parser y la clave `permission.task` que ya figura en su esquema; no define otro |
| ¿Se da un trabajo por bueno por palabra del ejecutor? | SE-530 | Independiente. Esta spec no verifica resultados, solo limita cuánto se puede delegar |

## Qué decide esta spec

### D1 — Cuatro magnitudes, un presupuesto por encargo y valores que salen de la medición

Un **encargo** es el trabajo que una persona o la planta pide en origen. Su presupuesto lo crea el lanzador raíz y **ningún hijo puede ampliarlo ni reiniciarlo**.

| Magnitud | Qué cuenta | Cómo se fija |
|---|---|---|
| **D** profundidad | Saltos de creación anidada. La sesión inicial es D=0. Lanzar un script intermediario **no** reinicia D | **Techo duro desde el principio: 2.** La cadena anidada más larga legítima del repo es sesión → orquestador → agente (tribunal, corrección, test-runner), es decir D=2; las cadenas SDD son handoffs secuenciales que procesa un supervisor y no anidan. S0 lo confirma o corrige **antes** de activarlo |
| **C** concurrencia | Hijos activos a la vez dentro del encargo, sumando todos los runtimes | Se observa en S0/S3; el techo duro se fija como **2× el máximo observado en uso normal** y nunca por debajo de 7 (los siete jueces del tribunal de veracidad) |
| **H** lanzamientos acumulados | Total de lanzamientos y handoffs del encargo | Igual que C: aviso en el **p99 observado × 1,5**, techo duro en el doble del aviso |
| **R** repeticiones | Lanzamientos del mismo destino para el mismo elemento de trabajo, aunque cambien el SHA, la sesión o el día | Aviso al tercero; ver D3 |

**Principio (la lección del estudio público):** un límite que molesta al trabajo normal se acaba quitando. Por eso:

1. **Modo observación primero.** Cada límite tiene `mode: observe | enforce` en `config/delegation-limits.yaml`. En `observe` no bloquea nada: anota «habría bloqueado» con la magnitud y el encargo.
2. **Se pasa a `enforce` por límite y con datos.** Un límite pasa a `enforce` solo si durante al menos 7 días de uso real la tasa de «habría bloqueado» sobre encargos que terminaron bien fue 0. Si no es 0, se sube el valor o se descarta el límite, y la PR lo dice. Es la prueba anti-fricción (AC-7).
3. **Solo D y el ciclo son estructurales** y entran duros desde el primer día; C y H empiezan en `observe` sin valor de bloqueo hasta que S0 aporte datos.
4. **Un límite que corta no mata el encargo.** Devuelve al padre un handback con la magnitud, el valor y qué hacer (SE-332). El resto de compañeros y el padre siguen trabajando.

### D2 — Permiso de quién puede pedir a quién, cerrado por defecto

- **Fuente única para agentes:** `permission.task.allowlist` de la cabecera del agente (mecanismo que ya existe y que SE-532 ya valida). **Ausente, vacía o inexistente = no puede delegar a nadie.** Hoy la ausencia se lee como «sin restricción» en el contrato declarativo de seis agentes (Problema 3); pasa a ser denegación.
- **Fuente para quien no es agente** (comandos, skills, scripts lanzadores, adaptadores del puente): `config/delegation-entrypoints.yaml`, una entrada por lanzador con los destinos que puede invocar. Sin entrada = denegado. Un comodín (`*`) es error del validador.
- **Sin escalada:** el destino conserva **su propio** `permission_level` y sus herramientas; ser invocado no le da los del llamante, ni el llamante hereda los del destino. La coherencia nivel/herramientas sigue siendo de `validate-agent-permissions.sh`.
- **Cierre de las seis:** cada una declara una allowlist con los destinos que **hoy** usa (tribunal de código: los cinco jueces y el desarrollador asignado; veracidad: siete jueces; recomendación: cuatro; `test-runner` y `frontend-test-runner`: desarrollador, arquitecto y analista; `commit-guardian`: el agente responsable de la corrección). El conjunto exacto se fija leyendo su texto en S2 y se prueba con la ruta legítima de cada una (AC-5). Declarar la allowlist **no cambia su comportamiento**: lo que hacían ya era esa lista.
- **Lista de excepciones congelada** (mismo patrón que SE-532 D4): en S1 las seis figuran como excepciones, con motivo y fecha, y la lista **solo puede encoger**; S2 las vacía.

### D3 — Repetición y compañeros que fallan: detectar y cortar lo que ya no aporta

**Repetición literal.** Antes de lanzar, el mediador calcula la clave `(destino, huella del encargo normalizado)`: se normalizan espacios y se descartan los campos volátiles declarados (hora, id de sesión). Si el mismo encargo al mismo destino **ya está en curso o ya terminó bien en este encargo**, no se lanza otro: se devuelve la referencia al resultado anterior y se anota. Si terminó mal, se deja pasar (reintento legítimo) y cuenta para R.

- Un reintento con entrada distinta (por ejemplo, el tribunal de código tras una corrección: cambia el SHA del candidato) tiene otra clave y **pasa**.
- **Límite honesto:** una repetición parafraseada tiene otra huella y no se detecta aquí. Es lo que cubren R y H: R cuenta lanzamientos del mismo destino para el mismo elemento de trabajo con independencia de la huella.

**Compañero que falla N veces seguidas.** Un fallo es un destino que termina con `termination_reason` distinto de `completed` (SPEC-121), agota su plazo o sale con error. N=3, igual que `AGENT_MAX_CONSECUTIVE_FAILURES` de las reglas de seguridad autónoma, para no inventar otro número. Un éxito pone el contador a cero. Al tercero seguido el compañero queda **suspendido para ese encargo** y el padre recibe un handback («el compañero X falló 3 veces seguidas, motivo, qué hacer»); se reanuda cuando el padre o la persona lo reactiva.

- **No cuentan como fallo del compañero:** cuota agotada del proveedor y corte por STOP (SE-498). Esperar por cuota **no** consume intento; arrancar sí.
- **Efecto acotado:** suspende a ese compañero, no al encargo ni a los demás.

**R acumulado.** Tres lanzamientos del mismo destino para el mismo elemento de trabajo dentro de un encargo, contando los arranques fallidos y el fallback. Las fases distintas (revisar, corregir, probar) no son reintentos. El cambio de SHA o de día **no** renueva R; solo lo renueva una orden explícita de la persona (queda registrada).

### D4 — El mediador y su identidad

Un único punto de admisión, `scripts/delegation-budget.py`, que **reserva de forma atómica** antes de lanzar y libera al terminar. Lo llaman el hook de delegación (la herramienta de subagentes), los lanzadores (`parallel-dispatch.sh`, `fork-agents.sh`, los adaptadores del puente) y el invocador de harnesses. Estado en un directorio local fuera del repo, con candado de fichero y una línea por reserva.

- **Fail-closed.** Presupuesto ausente o ilegible, herramienta ausente, entrada vacía o malformada, STOP vigente, destino no permitido o identidad no resoluble: **no se lanza** y el mensaje dice cuál. Esto invierte el guard actual, que ante entrada vacía o error de `jq` sale con 0 (`delegation-guard.sh:26`, `:29`).
- **Entrada por stdin.** Los hooks reciben JSON por stdin, incluida la identidad que el runtime observa; ninguna decisión depende de una variable de entorno autodeclarada. Una variable puede ayudar a localizar el presupuesto, pero no acredita parentesco por sí sola (Q1).
- **Un hijo no puede crear un presupuesto raíz propio** para esquivar los contadores. Cómo se prueba el parentesco (identidad del runtime, ascendencia de procesos o ambas) lo decide S0 con medición, y hasta entonces el mediador solo corre en observación.
- **Cobertura por runtime.** El mismo mediador sirve a Claude Code y a OpenCode; donde un runtime no pueda llamarlo desde un hook, el lanzador intermedio lo llama y la ficha de harness (SE-531) declara la limitación. Lo no cubierto se dice cubierto-no-probado, no cubierto.

### D5 — Terminar a los descendientes

Cuando se agota un plazo o se suspende un compañero, los descendientes del hijo deben terminar. Eso lo hace el supervisor de SE-531 S2 (grupo de procesos, con el límite declarado de descendientes que se separan del grupo). Esta spec no lo reimplementa: exige que el mediador, al liberar una reserva por corte, **verifique** que no queda ningún proceso del encargo vivo y, si queda, lo anote como «descendientes sin garantía» en el recibo. Hasta que SE-531 S2 esté en uso, ese campo dice «no verificado».

### D6 — El analizador, arreglado (S1)

`scripts/agent-depth-limit.sh` mantiene nombre, opciones y salida, y su cálculo pasa a un módulo Python invocado por él (sin añadir una superficie nueva, para respetar la entropía de capacidades):

- **Ciclos y autobucles** por componentes fuertemente conexas: un ciclo o autobucle es FAIL, siempre, sea cual sea el límite.
- **Camino más largo en el grafo acíclico**, no BFS de distancia mínima: el atajo `a→d` ya no oculta `a→b→c→d`.
- **Destino ausente o inexistente en una allowlist = error**, no arista omitida.
- **Delegador sin allowlist** (con `Task`/`task` habilitado) = error, salvo que figure en la lista de excepciones congelada (D2). Es lo que hoy el analizador no ve.
- **Cabecera ilegible o con YAML inválido = error** (no «agente sin allowlist»); parseo YAML real, no `awk`.
- Un test BATS real (no `skip`) y un paso en `scripts/validate-ci-local.sh`, **sin tocar `.github/workflows/ci.yml`**: si `ci-select-bats` no lo elige cuando cambia un agente, la PR lo declara y el paso en CI pasa a decisión de la operadora, como en SE-532 S1.

## Slices (en serie)

Orden: **S0 → S1 → S2 → S3 → S4 → S5.** Cada una con su PR y revisión humana de esa PR (SE-362). Tier calculado con `python3 scripts/risk-tier.py --diff <ficheros>` sobre muestras de cada slice; cada PR lo recalcula con su diff final.

| Slice | Qué | Tier pedido | Tier calculado |
|---|---|---|---|
| S0 | Medir D, C, H, R y la identidad del padre. Sin cambio de comportamiento | 2 | **2** |
| S1 | Arreglo del analizador, test real y paso en validate-ci-local; excepciones congeladas | 2 | **2** |
| S2 | Allowlist en los seis delegadores y `delegation-entrypoints.yaml`; las excepciones se vacían | 3 | **4** |
| S3 | Mediador en modo observación: reserva, repetición, fallos seguidos y recibo | 2 | **2** |
| S4 | Paso a `enforce` límite a límite, con los valores de S0 | 3 | **3** |
| S5 | Los lanzadores toman reserva del mediador; contrato para la planta privada | 2 | **2** |

**Notas de tier, medidas el 2026-11-14.** S2 toca `.opencode/agents/` y `.claude/agents/`: `risk-tier.py` da tier 4 («path de gobernanza»), no el 3 pedido; no entra en un lote de tier 1/2. S3 y S5 salen tier 2 solo si no editan `.claude/settings.json`. **Registrar el hook de delegación también para la herramienta `Task`, o cambiar el perfil de `standard` a otro, exige editar `.claude/settings.json` (tier 4, decisión de la operadora)**: esta spec no lo hace; S3 deja la orden exacta en su PR. S4 son valores en `config/delegation-limits.yaml`: un fichero YAML de `config/` sin categoría sube a tier 3 por fail-closed (`risk-tier.py`).

### S0 — Medir antes de limitar (tier 2)

- **Entrega.** Un script de solo lectura que reconstruye, de los registros de ejecución de agentes y del hook de ciclo de vida de subagentes que existen hoy, la distribución por encargo de D, C, H y R; un informe en `docs/evidence/` con p50/p90/p99/máximo y los encargos más profundos; y la prueba de qué identidad del padre llega por stdin a un hook en cada runtime (Q1).
- **Regla de decisión escrita antes de medir:** el valor de partida de C y H es el descrito en D1; si el máximo observado de D en un encargo que terminó bien es 3 o más, **D no entra duro** y la PR lo dice. Si no hay registros suficientes (menos de 50 encargos en la ventana), S0 lo declara y los valores de C y H quedan sin fijar: no se inventan.
- **Pruebas (BATS).** Sobre registros sintéticos con distribución conocida el script devuelve exactamente esos percentiles; un registro corrupto o fuera de orden se cuenta y se informa, no se ignora; registros vacíos dan «sin datos», no ceros; un encargo sin padre identificable se clasifica aparte.
- **Reversión.** `git revert`; no hay estado fuera del repo salvo el informe.

### S1 — Arreglar el analizador (tier 2)

- **Entrega.** D6 completo, incluida la lista de excepciones congelada de las seis (`docs/agent-delegation-exceptions.txt`, solo encoge) y la sustitución del test con `skip` por tests reales.
- **No toca** `.opencode/agents/`, `.claude/agents/`, `.claude/settings.json`, `opencode.json` ni `.github/workflows/ci.yml`.
- **Pruebas (BATS), cada una falla contra el script actual y pasa con el nuevo:** ciclo de dos nodos, autobucle y atajo con límite 2 fallan (los tres falsos verdes); la cadena lineal de tres saltos falla (control); el grafo real de los catálogos pasa con exactamente las excepciones congeladas; destino inexistente falla; cabecera con YAML inválido falla; delegador sin allowlist fuera de la lista falla; una excepción obsoleta (el agente ya declara allowlist) falla; una excepción nueva respecto a la base falla; sin PyYAML sale 2, no 0; directorio de agentes ausente sale 2. Caso límite: profundidad igual al límite pasa, límite + 1 falla.
- **Reversión.** `git revert`; el script vuelve a su versión anterior.

### S2 — Cerrar la delegación por defecto (tier 4 calculado)

- **Entrega.** La allowlist de los seis delegadores en los dos lados (D2), `config/delegation-entrypoints.yaml` con los lanzadores actuales y la regla correspondiente en el validador. La lista de excepciones de S1 queda vacía y el validador pasa a rechazar cualquier excepción.
- **Pruebas.** La ruta legítima de cada una de las seis sigue siendo posible: tribunal de veracidad con sus siete jueces, tribunal de recomendación con sus cuatro, tribunal de código con cinco jueces y corrección, `test-runner` y `frontend-test-runner` con desarrollador, arquitecto y analista, `commit-guardian` con el agente responsable (el validador acepta cada arista). Un destino fuera de la lista falla. Una entrada de lanzador con comodín falla. Un lanzador sin entrada falla. Un diff de `permission_level`, `permissionMode` y `tools` de todos los agentes antes y después sale vacío; si no lo es, la PR no sale de borrador.
- **Reversión.** `git revert`; vuelve la apertura declarativa anterior.

### S3 — Mediador en observación (tier 2)

- **Entrega.** `scripts/delegation-budget.py` (reserva atómica, liberación, repetición, fallos seguidos, R), `config/delegation-limits.yaml` con todos los límites en `observe`, recibo por encargo, y la adaptación de `delegation-guard.sh` para llamarlo **en modo observación y sin dejar de bloquear lo que bloquea hoy**. El texto del mensaje de handback se define aquí.
- **Pruebas.** Dos reservas simultáneas contra un techo de 1 (carrera real con dos procesos) dejan exactamente una. Repetición literal: la segunda no se lanza y devuelve la referencia; con entrada distinta pasa. Tres fallos seguidos suspenden al compañero; un éxito intermedio reinicia el contador; la cuota agotada no cuenta. R: tres lanzamientos con SHA distintos cuentan juntos. Presupuesto ausente, JSON vacío o malformado, herramienta auxiliar ausente y STOP vigente **no lanzan**. Un hijo que intenta crear su propio presupuesto raíz no obtiene uno nuevo. Con `observe`, un exceso no bloquea y deja la línea «habría bloqueado».
- **Reversión.** `git revert` y borrar el directorio de estado local; el guard anterior vuelve tal cual.

### S4 — Pasar a obligatorio, límite a límite (tier 3)

- **Entrega.** Valores y `mode: enforce` en `config/delegation-limits.yaml`, uno por límite y con la medición de la ventana de 7 días adjunta.
- **Pruebas.** Un exceso real en `enforce` bloquea con handback; el mismo exceso en `observe` no. La prueba anti-fricción (AC-7): la ventana de 7 días con encargos reales terminados bien no tiene ningún «habría bloqueado» antes de activar el límite; si lo tiene, la PR no activa ese límite.
- **Reversión.** Volver `mode` a `observe` por PR o, en una emergencia, con la variable de desactivación del mediador, que queda registrada en el recibo.

### S5 — Los lanzadores toman reserva (tier 2)

- **Entrega.** `parallel-dispatch.sh`, `fork-agents.sh`, los adaptadores del puente y el invocador de harnesses reservan antes de lanzar y liberan al terminar, descontando de la misma reserva (el techo local de 5 de `fork-agents.sh` se conserva). El contrato de admisión para la planta privada queda documentado en `docs/rules/domain/`; adoptarlo allí es trabajo de la instalación, fuera de este repo.
- **Pruebas.** Un lanzador sin presupuesto no lanza; dos lanzadores distintos comparten el mismo techo C; el techo local de 5 sigue vigente; un hijo lanzado por Bash dentro de un encargo descuenta del padre.
- **Reversión.** `git revert` por lanzador.

## Criterios de aceptación

| AC | Criterio | Tipo |
|---|---|---|
| AC-1 | Ciclo de dos nodos, autobucle y atajo con límite 2 fallan en el analizador; los tres pasaban antes de S1. La cadena lineal de tres saltos sigue fallando. | negativo |
| AC-2 | El analizador falla ante destino inexistente, YAML inválido, delegador sin allowlist fuera de la lista congelada y excepción obsoleta o nueva; falta de PyYAML o del directorio da error de entorno (2), nunca PASS. | negativo |
| AC-3 | El test del analizador no usa `skip` y cada comprobación falla sobre una copia mutada (SE-456); el analizador corre en `validate-ci-local.sh`. | negativo |
| AC-4 | S2 no cambia el diff de `permission_level`, `permissionMode` ni `tools` de ningún agente. | negativo |
| AC-5 | Tras S2, cada ruta legítima de los seis delegadores sigue siendo una arista permitida; un destino fuera de la lista falla. Los siete jueces de veracidad no se frenan. | positivo / negativo |
| AC-6 | Sin entrada en la lista de lanzadores o con comodín, el validador falla: denegado por defecto. | negativo |
| AC-7 | Ningún límite pasa a `enforce` si en la ventana de 7 días hay un «habría bloqueado» sobre un encargo que terminó bien. Un límite sin ventana medida no pasa a `enforce`. | negativo |
| AC-8 | Repetición literal en el mismo encargo no lanza un segundo hijo; la misma petición con SHA distinto sí pasa; tres lanzamientos del mismo destino para el mismo elemento cuentan juntos aunque cambie el SHA o el día. | negativo / positivo |
| AC-9 | Entrada vacía, JSON malformado, presupuesto ausente o ilegible, herramienta auxiliar ausente, destino no permitido, STOP vigente o identidad no resoluble: no se lanza, con mensaje que dice cuál. | negativo |
| AC-10 | Tres fallos seguidos suspenden al compañero; un éxito intermedio reinicia; cuota agotada y corte por STOP no cuentan; los demás compañeros siguen. | negativo / positivo |
| AC-11 | Dos reservas simultáneas contra un techo de 1 dejan una; un hijo no obtiene presupuesto raíz propio; el reinicio de R solo con orden explícita registrada. | negativo |
| AC-12 | Un corte por plazo anota en el recibo si quedó algún descendiente vivo; sin SE-531 S2 en uso, dice «no verificado». | negativo |
| AC-13 | S0: el valor de C y H viene de la medición; sin datos suficientes (menos de 50 encargos), queda sin fijar y el informe lo dice. | negativo |
| AC-14 | Esta spec: `tests/bats/se533-spec-coherence.bats` pasa y cada comprobación falla sobre una copia mutada. | negativo |

## Puerta de comprensión

**Probablemente sin interfaz humana nueva, y esta spec lo declara así (`human_surface: false`).** Ninguna slice añade pantalla, botón, pregunta ni mensaje a la persona: quien pide cosas a Savia las sigue pidiendo igual.

- **Antes, en lenguaje llano.** Si un agente le pide trabajo a otro, que a su vez se lo pide a otro, y así sin fin, o si dos agentes se devuelven la tarea o uno falla una y otra vez, nadie corta la cadena: cada pieza tiene su tope pero nadie suma el total. Y la revisión que debería avisar de un ciclo da el visto bueno.
- **Después.** Cada encargo tiene un presupuesto único. Si una cadena se pasa, se repite lo mismo o un compañero falla tres veces seguidas, el padre recibe un aviso con el motivo y qué hacer, y el resto del trabajo sigue. La revisión automática de cada PR rechaza ciclos y atajos.
- **Dónde podría verlo una persona:** el aviso de corte aparece en la salida del agente padre y en el resumen de la PR cuando un trabajo autónomo se corta; no hay superficie propia. Si S3 llevara ese texto a algo que la persona ve fuera de los registros (por ejemplo, el resumen de Savia), **no se pone en curso sin que la operadora confirme el texto por pregunta interactiva** (SE-505). Hasta entonces no hay escenas que confirmar y esta spec no inventa el texto.

## Fuera de alcance

- Concesión de autoridad de efectos o subdelegación de autoridad (SE-496), parada y revocación (SE-498), supervisión del proceso y de sus descendientes (SE-531 S2), verificación de resultados (SE-530) y validación de cabecera (SE-532).
- **Modificar la planta de trabajo privada** (admisión, cola, reencolado, planificación). S5 deja el contrato; adoptarlo es de la instalación. Las cifras de esa parte vienen de una lectura, no de este repo.
- Quitar el límite por proceso de los lanzadores, o los topes locales que ya funcionan (rondas del tribunal, ciclos de `test-runner`).
- Limitar el uso de herramientas que no delegan, o el gasto de tokens (eso es consumo, no delegación).
- Cambiar el perfil de ejecución del guard o su registro para `Task` en `.claude/settings.json`: tier 4, decisión de la operadora.
- Un contrato de delegación entre personas.

## Preguntas abiertas (con recomendación)

- **Q1 — ¿Cómo se acredita que un hijo es hijo?** Hipótesis: la identidad de sesión que el runtime pasa por stdin al hook, más la ascendencia de procesos como segunda comprobación. **No está medido** que ambos runtimes la entreguen. Recomendación: S0 lo mide con una cadena real de dos saltos en cada runtime; si ninguno de los dos mecanismos sirve en uno, el mediador en ese runtime corre solo en observación y la ficha de harness lo declara. No se activa `enforce` sin parentesco acreditado.
- **Q2 — ¿Valor de D=2 duro desde el principio?** Recomendación: sí, y S0 lo valida antes de activarlo; si la medición encuentra D=3 legítimo, no entra duro.
- **Q3 — ¿Qué hace el encargo cuando un compañero queda suspendido?** Recomendación: handback al padre inmediato (SE-332) y, si el padre es la sesión de la persona, un mensaje; nunca reintento automático con otro destino.

## Riesgos

- **Frenar el trabajo normal.** Mitigación: observación primero, ventana de 7 días con cero «habría bloqueado» (AC-7), techo de C de al menos 7 y D como único duro inicial; un límite que no demuestra no molestar no se activa.
- **Cerrar por defecto rompe un tribunal.** Mitigación: S2 declara en cada allowlist lo que hoy usan y AC-5 prueba cada ruta legítima, incluidos los siete jueces.
- **Identidad del padre sin acreditar.** Mitigación: Q1; sin parentesco, solo observación y se declara.
- **Falso positivo de repetición.** Mitigación: la clave descarta campos volátiles y un reintento con entrada distinta pasa; una repetición que falló se deja pasar.
- **Paráfrasis no detectada.** Mitigación honesta: la detección literal no la ve; R y H son la red de seguridad, y esta spec no promete más.
- **Estado local corrupto.** Mitigación: fail-closed (AC-9); borrar el estado local reinicia el presupuesto solo por orden explícita registrada.
- **El analizador pasa a rechazar lo que antes pasaba.** Mitigación: la lista de excepciones congelada, que solo encoge, mantiene verde el catálogo actual en S1 y S2 la vacía con la ruta legítima probada.
- **Interacción con SE-532 S1 (PR abierta al redactar esto).** El esquema de cabecera ya acepta `permission.task`; S1 de esta spec reutiliza su parser cuando esté fusionada y, si no lo está, no la apila (rama desde `main`) y declara la dependencia.

## OpenCode Implementation Plan

### Bindings touched

| Componente | Claude Code | OpenCode v1.14 |
|---|---|---|
| Guard de delegación | `.claude/hooks/delegation-guard.sh`, registrado para `Agent` en `.claude/settings.json` (registrar también `Task`: tier 4, decisión de la operadora) | Hoy sin portar (`hooks-coverage-matrix.sh:175`): el mediador lo llama el lanzador y la ficha de harness lo declara |
| Permiso por agente | `permission.task.allowlist` en `.claude/agents/<x>.md` | La misma clave en `.opencode/agents/<x>.md` (fuente de verdad) y `task` por agente en `opencode.json` |
| Analizador | `scripts/agent-depth-limit.sh` y su módulo Python (común) | El mismo, sobre `.opencode/agents/` |
| Mediador de presupuesto | `scripts/delegation-budget.py` (común) | El mismo |
| Límites y lanzadores | `config/delegation-limits.yaml`, `config/delegation-entrypoints.yaml` (comunes) | Los mismos |

### Verification protocol

- [ ] Funciona en runtime OpenCode: el analizador y el mediador dan el mismo resultado desde ambos frontends
- [ ] Tests BATS cubren cada slice, con su caso negativo y su reversión (AC-1 a AC-14)
- [ ] Ningún hook nuevo se registra y `settings.json` no cambia en estas slices; el registro para `Task` queda como decisión de la operadora
- [ ] Un runtime que no pueda llamar al mediador desde un hook queda declarado, no dado por cubierto

### Portability classification

- [x] **DUAL_BINDING**: analizador, mediador y configuración son comunes; el cableado del guard difiere por runtime y la cobertura en OpenCode depende de que el lanzador llame al mediador.

## Encaje en la línea de metaharness (L39, fila M6)

Esta spec es el contenido de la fila M6 («límites y permisos de delegación entre harnesses»): D, C, H y R son la cota común que falta entre sesiones, procesos nuevos y reencolados. Se apoya en la ficha de harness y en la supervisión de procesos de SE-531, y en el handback de SE-332 para terminar bien un corte.

## Aprobación

**PROPOSED.** Redactada el 2026-11-14 por encargo de la orquestadora, decidido por la operadora por pregunta interactiva; la condición que puso, medir antes, se cumple con la medición independiente de ese día. **No está aprobada**: la operadora decide el paso a APPROVED, el orden de las slices y las preguntas Q1 a Q3. Cada slice se fusiona con revisión humana de su PR concreta (SE-362); S2 es tier 4 y no entra en un lote de fusiones.
