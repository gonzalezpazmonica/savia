---
status: PROPOSED
priority: P3
developer_type: agent-single
created: 2026-11-13
author: Savia
phase: A
risk: L3
human_surface: false
related_specs: [SE-518, SE-493, SE-433, SE-456, SE-505, SE-362, SPEC-121]
origin: "Spec pedida por la operadora el 2026-11-13 a partir de una investigación sobre orquestadores de agentes de terceros (informe en Savia Labs, privado). Es la «B» de tres specs propuestas (A hecho verificado, B ficha de harness ejecutable, C catálogo de agentes); la operadora decidió empezar por A y B y meterlas en la línea L39 (metaharness) como fase M6. Solo spec: ningún código se toca."
timeline:
  - from: "2026-11-13"
    learned: "2026-11-13"
    value: "PROPOSED"
    source: "worker autónomo; encargo de la orquestadora"
---

# SE-531 — Ficha de harness ejecutable: capacidades del runtime y supervisión del proceso hijo

> **Qué es y qué no es.** Es la declaración, comprobable por máquina, de qué sabe y qué no sabe cada programa de agente externo (Claude Code, Codex, OpenCode, Yema y los que vengan), más las reglas para supervisar al proceso que lanzamos. **No es** un enrutador que elige programa por tarea, ni un *failover* entre proveedores (la autoridad no se enruta), ni una adopción de código de otros proyectos.

## Problema (verificado en origin/main 2681e26a7, 2026-11-13)

Cada runtime se comporta distinto y hoy esa diferencia vive en parches sueltos y en texto de informes, no en un dato que algo compruebe:

- **El código de salida no siempre dice la verdad.** El ejemplo conocido: OpenCode sale con 0 tras un error de la API. El invocador de la línea L39 en Savia Labs (privado, no versionado en este repo) lo corrige a mano forzando el código a 1 solo para ese runtime. Ese fichero no es verificable desde `main`; el primer AC de S1 es volver a leerlo y citarlo con fichero y línea antes de tocar nada.
- **La cuota se avisa de formas distintas** (código de salida, campo del flujo JSON o solo texto libre) y la spec de Pulse (SE-518, PR #1535 abierta; su S3 exige «señal tipada, nunca texto libre») necesita saber de cuál se trata para cada runtime. Hoy ese dato no está escrito en ningún sitio que se pueda consultar.
- **Matar al hijo no mata a sus descendientes.** Medición hecha para esta spec el 2026-11-13 (Linux, Python 3.14.4, `timeout` de uutils coreutils 0.10.0), con un hijo `bash` que lanza un `sleep` largo como nieto y un *timeout* de 1 s; se contó el `sleep` vivo después:

  | Mecanismo de corte | Nietos vivos tras el *timeout* |
  |---|---|
  | `subprocess.run(..., timeout=)` de Python (mata solo al hijo directo) | **1** |
  | `timeout N cmd` de la línea de órdenes | 0 |
  | `timeout N cmd`, con un nieto que se separó con `setsid` | **1** |
  | Hijo en sesión propia + `os.killpg` | 0 |

  Lectura: el resultado depende del mecanismo, y ninguno cubre a un descendiente que se separa del grupo. **Esta medición prueba el mecanismo, no el invocador real**, que no está en este repo; por eso S2 empieza repitiéndola contra él (AC-S2a). En el repo público ya hay dos formas distintas de cortar: `scripts/agent-hook-runner.sh:233-236` y `scripts/parallel-dispatch.sh:61` usan `timeout`, y `scripts/automations/runner.py:104-124` abre sesión propia y envía `SIGKILL` al grupo (sin `SIGTERM` previo ni plazo de gracia).
- **El fail-safe de Savia está escrito en prosa y nada lo aplica al lanzar a un hijo.** `docs/rules/domain/savia-core.md` (sección «Fail-safe») dice «abortar tras 3 fallos consecutivos o misma acción 3+ veces»; ningún invocador corta a un hijo que repite la misma llamada fallida dentro de su turno.
- **Se relanza sin saber si el trabajo hizo algo.** SE-493 (APPROVED) ya establece, para los efectos de fusión, que un efecto de resultado incierto es `ambiguous` y no se repite. No existe esa regla para relanzar un trabajo entero.

## Qué decide esta spec

### D1 — La ficha es un dato con campos obligatorios y valores cerrados

Cada runtime tiene un bloque `runtime` en su ficha. Falta un campo, o su valor no es uno de los permitidos, y el validador falla (error, no aviso). `no_medido` es un valor permitido para dejar constancia de que no se sabe, pero **los consumidores lo tratan como la opción más desconfiada** (D3), así que no es una vía de escape.

| Campo | Valores permitidos | Qué responde |
|---|---|---|
| `aislamiento` | `ninguno` · `sandbox_de_ordenes` · `proceso_confinado` · `no_medido` | Cómo se encierra al programa |
| `rc_en_error` | `fiable` · `no_fiable` · `no_medido` | Si un fallo real se traduce en código de salida distinto de 0 |
| `rc_deteccion` | texto corto con la regla; **obligatorio si `rc_en_error` es `no_fiable`**, prohibido si es `fiable` | Cómo se detecta el fallo cuando el código no sirve |
| `senal_cuota` | `codigo_de_salida` · `campo_del_flujo` · `ninguna` · `no_medido` | Cómo avisa de que se acabó la cuota |
| `informa_uso` | `si` · `no` · `no_medido` | Si informa de lo que gasta |
| `reanudacion` | `por_sesion` · `no_soportada` · `no_medido` | Si se le puede preguntar en qué estado quedó una ejecución |
| `limpieza` | `grupo_de_procesos` · `ninguna` · `no_medido` | Cómo se retira a sus descendientes al cortarlo |
| `flujo_llamadas` | `json` · `ninguno` · `no_medido` | Si emite las llamadas a herramientas como eventos que se pueden vigilar |
| `fuente` y `version_cli` | texto; **obligatorios por cada campo no `no_medido`** | De dónde sale el dato y con qué versión del programa se midió |

Las reglas «si X entonces Y» (`rc_deteccion` solo con `no_fiable`; `fuente` y `version_cli` con cada dato medido) son de la misma familia que las del esquema de harness de kagent 1.0 (proyecto público, citado como inspiración; no se copia su esquema ni su texto).

Cobertura: **un runtime que alguna ficha usa y que no tiene bloque `runtime` es un error**, igual que un campo ausente. Es la comprobación equivalente a la «fila obligatoria por proveedor» de openbot (proyecto público con licencia no comercial, citado como inspiración; no se usa ni se copia su código).

### D2 — Los parches por runtime se derivan de la ficha, no al revés

El ajuste «OpenCode sale con 0 pero falló» pasa a ser `rc_en_error: no_fiable` más su `rc_deteccion`, y el invocador **lee** la ficha. Si un runtime tiene `no_fiable` sin regla de detección, el validador falla; si tiene `no_medido`, el invocador no acepta un código 0 sin la postcondición del trabajo (fail-closed). No se conserva ningún parche con el nombre de un runtime dentro del código del invocador.

### D3 — Qué hace el supervisor con cada valor (S2)

| Situación | Regla |
|---|---|
| Al vencer el tiempo | El hijo arranca en sesión propia. Se envía `SIGTERM` al grupo, se espera un plazo de gracia (por defecto 5 s, ajustable por ficha) y se envía `SIGKILL` al grupo. Con `limpieza: ninguna` o `no_medido` el supervisor lo registra en el recibo como «descendientes sin garantía» y **no** declara el trabajo limpio. |
| Misma llamada fallida repetida | Si `flujo_llamadas` es `json`: la misma herramienta con los mismos argumentos normalizados y el mismo error, N veces seguidas (por defecto N = 3, el umbral ya escrito en el fail-safe de Savia) cortan el turno con clase `limite_de_turno`. Un éxito entre medias, o argumentos distintos, reinician la cuenta. Si es `ninguno` o `no_medido`: el recibo dice «bucle no vigilado»; no se finge vigilancia. |
| Relanzar | Solo si el recibo registra **cero efectos** y ningún efecto `ambiguous` (estados de SE-493), y como máximo una vez. Sin recibo, o con un campo ilegible: no se relanza. Un corte por `limite_de_turno` **nunca** se relanza ni se anota como fallo del proveedor. |
| Reiniciar tras una caída | Con `reanudacion: por_sesion` se pregunta al programa qué pasó con la ejecución y se registra su respuesta. Con `no_soportada` o `no_medido` el estado es `ambiguous` y lo resuelve la reconciliación de SE-493 o la persona; **no se supone**. |

### D4 — Qué no se promete

- Un descendiente que se separa del grupo (`setsid`, daemonización) **escapa** a la limpieza por grupo (lo muestra la tercera fila de la medición). S2 lo mide y lo declara como límite; cerrarlo (cgroups, `pidfd`) queda fuera de alcance.
- Los campos de la ficha **envejecen**: los programas cambian su comportamiento con frecuencia. Por eso cada dato lleva `fuente` y `version_cli`, y el validador avisa (no falla) cuando la versión instalada del programa difiere de la medida.
- La ficha describe el runtime; **no concede permisos**. Qué puede hacer un trabajo sigue decidiéndolo el gobierno (Regla 8, `autonomous-safety`, grants), que ninguna ficha edita.

## Slices

| Slice | Qué entrega | Dónde | Tier | Depende de |
|---|---|---|---|---|
| S1 | Esquema del bloque `runtime`, validador con cobertura y migración de las fichas actuales (derivando el parche de OpenCode) | Savia Labs (L39) | **2** | — |
| S2 | Supervisor: grupo de procesos, corte por llamada repetida, relanzar solo sin efectos, preguntar al reiniciar | Savia Labs (L39) y, si el invocador pasa a producto, `scripts/` | **2–3** | S1 |
| S3 | Catálogo de estaciones en el repo público: esquema publicado y cuatro fichas (worker, revisora, Yema y refutadora opcional) | Este repo | **3** | S1, S2 |

El tier de cada PR se calcula con `scripts/risk-tier.py` sobre su diff final; S2 es 3 si toca `scripts/` de producción y 2 si queda dentro de Labs.

### S1 — La ficha y su validador, con las fichas actuales

1. Releer el invocador y las fichas de Labs y citar fichero y línea de cada parche por runtime que existe (OpenCode rc 0; contención; cuota sin texto en Claude).
2. Esquema (D1) y validador que lo aplica, con salida legible: nombra la ficha y el campo.
3. Migrar las fichas actuales sin perder información: lo que hoy está en texto de informes pasa a los campos con su `fuente` y `version_cli`. Lo que no se ha medido se declara `no_medido`; no se inventa.
4. El invocador deriva el ajuste del código de salida de la ficha (D2).

### S2 — Supervisión del proceso y del bucle

1. **Medir primero** (AC-S2a): repetir la tabla del «Problema» contra el invocador real y contra cada runtime real, y guardar el resultado en la PR. Regla de decisión escrita antes de medir: si con 3 cortes reales por runtime no queda ningún descendiente vivo, el corte por grupo se entrega igual como invariante con test (cuesta poco), pero la PR **no** declara beneficio medido.
2. Supervisor según D3. Aplica a cualquier lanzador que adopte la ficha; en S2 solo el invocador de Labs.
3. Los casos de aborto se registran con el motivo exacto, para que Pulse (SE-518 S3) los lea como señal tipada y no tenga que interpretar texto.

### S3 — El catálogo de estaciones en el producto

1. Una **estación** es el puesto que ocupa un harness (worker, revisora, Yema, refutadora opcional): referencia a una ficha de runtime más su gobierno. La ficha de runtime describe al programa; la estación, qué papel le damos.
2. Esquema y las cuatro fichas bajo `contracts/harness/` (ruta propuesta; `contracts/` ya existe con `capabilities/` y `ontology/`). El validador corre en CI.
3. La publicación pasa la prueba de confidencialidad: sin rutas ni nombres de instalación, sin datos de personas.
4. Antes de abrir S3 se comprueba que S1 y S2 han estado en uso real al menos una semana: no se publica un esquema que no ha sobrevivido a un cambio de versión de algún programa.

## Criterios de aceptación

| AC | Criterio | Tipo |
|---|---|---|
| AC-S1a | La PR de S1 cita fichero y línea del invocador y de cada parche por runtime que sustituye, leídos en esa PR. | positivo |
| AC-S1b | El validador falla si una ficha usa un runtime sin bloque `runtime`. | negativo |
| AC-S1c | El validador falla por cada campo obligatorio ausente: un test por campo (los siete campos obligatorios de D1, más `fuente` y `version_cli`), cada uno sobre una copia con solo ese campo quitado. | negativo |
| AC-S1d | El validador falla con un valor fuera del conjunto permitido (p. ej. `aislamiento: casi`) y con `rc_en_error: no_fiable` sin `rc_deteccion`; también con `rc_deteccion` presente si `rc_en_error` es `fiable`. | negativo |
| AC-S1e | Un dato distinto de `no_medido` sin `fuente` o sin `version_cli` falla. Con `no_medido` pasa y el validador lo cuenta en su resumen. | negativo / límite |
| AC-S1f | Las fichas actuales migradas pasan el validador y cada hecho que estaba en texto de informe está en un campo (revisión con lista de «antes → después» en la PR). | positivo |
| AC-S1g | El ajuste de OpenCode ya no está en el código con el nombre del runtime: el test lo prueba con un runtime ficticio `no_fiable`, y con el mismo runtime en `fiable` el invocador **no** fuerza el código (caso inverso). | negativo |
| AC-S2a | La PR de S2 trae la medición de huérfanos contra el invocador real y cada runtime real, con la regla de decisión de S2.1 escrita antes. | positivo |
| AC-S2b | Un hijo que lanza un nieto dormido: tras el *timeout* no queda ningún proceso del grupo. Negativo: con `limpieza: ninguna` el test detecta el nieto vivo (y lo retira en el *teardown*). Con un nieto en sesión propia, el test confirma que escapa y el recibo lo dice (D4). | negativo |
| AC-S2c | Un hijo que ignora `SIGTERM` muere por `SIGKILL` tras el plazo de gracia; el plazo es el configurado, con tolerancia declarada. | negativo / límite |
| AC-S2d | La misma llamada con el mismo error N veces seguidas corta con `limite_de_turno`; N−1 veces no corta; el mismo error con argumentos distintos no corta; un éxito intercalado reinicia la cuenta. | límite |
| AC-S2e | Un corte por `limite_de_turno` no se relanza ni se cuenta como fallo del proveedor. Con `flujo_llamadas: ninguno`, el recibo dice «bucle no vigilado». | negativo |
| AC-S2f | Un trabajo con cero efectos se relanza una vez; con un efecto registrado, con un efecto `ambiguous`, con recibo ausente o ilegible, o ya relanzado una vez, no se relanza. | negativo |
| AC-S2g | Con `reanudacion: por_sesion` la respuesta del programa queda en el recibo; con `no_soportada` o `no_medido` el estado es `ambiguous` y no hay relanzamiento automático. | negativo |
| AC-S3a | El esquema publicado es idéntico al de Labs (comprobado por huella) y el validador corre en CI. | positivo |
| AC-S3b | El escaneo de confidencialidad del repo no encuentra rutas de instalación ni datos de personas en el catálogo; una ficha con una ruta personal lo hace fallar. | negativo |
| AC-S3c | Las cuatro fichas pasan el validador y un runtime sin ficha publicada hace fallar el CI. | negativo |
| AC-X1 | Cada PR trae su tier calculado con `scripts/risk-tier.py` y la cifra antes/después de lo que mide (huérfanos, parches por runtime). Nada se declara «verificado» por la palabra del propio worker. | positivo |
| AC-X2 | Reversión probada: `git revert --no-commit` de cada merge deja en verde los tests de la estructura. | positivo |

## Puerta de comprensión

**No hay interfaz humana nueva**: `human_surface: false`, sin escenas ni prototipo S0 (SE-505). Cambia, eso sí, lo que la persona lee en los recibos y en los informes de las rondas:

- **Antes:** un trabajo que se pasa de tiempo figura como «timeout» y puede dejar procesos vivos sin que nadie lo sepa; un runtime que sale con 0 aunque haya fallado se corrige con un parche que nadie ve; un trabajo que repite la misma llamada fallida consume su tiempo entero y se relanza como si fuera un fallo del proveedor.
- **Después:** el recibo dice qué se cortó, si quedaron descendientes, si el bucle estaba vigilado y por qué no se relanzó (o por qué sí). Un trabajo cortado por repetición figura como «límite de turno», no como fallo del proveedor. Lo que no se sabe se lee como «no medido» o «bucle no vigilado».

Lo que sí requiere a una persona es revisar cada PR de slice (S3 es tier 3: revisión humana explícita del PR concreto, SE-362) y aprobar esta spec.

## Fuera de alcance

- Kubernetes, imágenes de contenedor, enrutador aprendido y *failover* entre proveedores: la autoridad no se enruta.
- Instalar, ejecutar o copiar código de openbot (licencia no comercial), kwant (AGPL), CopilotKit o kagent. Se citan como inspiración pública; el diseño y los textos son propios.
- La verificación independiente del «hecho» (spec A) y el catálogo de agentes con esquema y retirada (spec C): son otras specs.
- Límites de profundidad o de abanico al pasarse trabajo entre agentes: hoy la línea no encadena agentes y primero hay que medir si existe alguna cadena sin cota.
- `concurrencia` y la inyección de mensajes en un turno en curso: no hay consumidor todavía; se añaden cuando lo haya.
- Cerrar la fuga por descendientes que se separan del grupo (D4).
- Cambiar permisos, gobierno, umbrales de los gates o la política de grants.

## Riesgos

- **Fijar campos que el programa cambia a menudo.** Mitigación: `fuente` y `version_cli` por dato, aviso (no fallo) cuando difiere la versión instalada, y `no_medido` como valor honesto.
- **`no_medido` como escape.** Mitigación: D2 y D3 lo tratan como la opción más desconfiada y el validador lo cuenta en su resumen.
- **Medición de huérfanos no representativa.** La tabla del «Problema» prueba mecanismos, no el invocador real. Mitigación: AC-S2a, con regla de decisión previa.
- **Cortar un trabajo legítimo que repite una llamada** (p. ej. un sondeo que falla por red y se recupera). Mitigación: un éxito intercalado reinicia la cuenta, N es configurable por ficha y el corte se registra con su motivo, no se oculta.
- **Relanzar con efectos no registrados.** Mitigación: fail-closed; si el recibo no dice «cero efectos» de forma explícita, no se relanza.
- **Duplicar superficie.** Hay tres formas de cortar procesos en el repo público. S2 las nombra; unificarlas es una decisión posterior de la persona, no se hace aquí.

## OpenCode Implementation Plan

### Bindings touched

| Componente | Claude Code | OpenCode v1.14 |
|---|---|---|
| Ficha de runtime | Un bloque `runtime` para `claude -p` | Un bloque `runtime` para `opencode run` (`rc_en_error` y su regla de detección) |
| Supervisor del hijo | El mismo para los dos lanzadores | El mismo para los dos lanzadores |
| Catálogo público (S3) | `contracts/harness/` (ruta propuesta) | El mismo directorio |
| Lanzadores públicos hoy | `scripts/agent-hook-runner.sh`, `scripts/parallel-dispatch.sh`, `scripts/automations/runner.py` | Los mismos scripts |

### Verification protocol

- [ ] Funciona en runtime OpenCode: la ficha de `opencode run` deriva el ajuste del código de salida y el test lo prueba con un runtime ficticio
- [ ] Tests BATS y pytest cubren cada slice con su caso negativo y su límite (AC-S1a a AC-S3c)
- [ ] No se registra ningún hook nuevo; los cambios en hooks o `settings.json` quedan fuera de esta spec

### Portability classification

- [x] **DUAL_BINDING**: el esquema y el supervisor no dependen del frontend; cada runtime declara su propio bloque.

## Aprobación

**Pendiente de la operadora.** El estado pasa a APPROVED solo cuando la operadora lo confirme en esta PR; hasta entonces la spec es PROPOSED y no desbloquea ningún slice. S1 y S2 pueden empezar en paralelo con la spec A una vez aprobada; S3 espera a S1 y S2 y a una semana de uso real. Cada slice se fusiona con revisión humana de su PR.
