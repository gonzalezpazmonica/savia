---
status: PROPOSED
priority: P2
developer_type: agent-single
created: 2026-10-29
author: Savia
phase: D
risk: L1
related_specs: [SE-468, SE-469, SE-470]
origin: revisión de Anthropic Research en Savia Labs (privado), propuesta derivada a spec pública por encargo de la operadora 2026-10-29
timeline:
  - from: "2026-10-29"
    learned: "2026-10-29"
    value: "PROPOSED"
    source: "spec-lifecycle:auto"
---
# SE-477 — Estadística mínima en las comparativas: intervalo, diferencia pareada y censura

## Problema

Savia compara configuraciones (modelos por tier, harnesses, prompts, jueces) y decide con esas comparaciones: enrutar
trabajo, cambiar un default, aprobar una spec. Hoy una comparativa puede publicarse como «A supera a B en 3 puntos»
sin intervalo, sin emparejar por tarea y sin declarar cuántas ejecuciones se cortaron por tiempo o fallo de
infraestructura. Medido sobre `main` (7b434f9ae):

- `scripts/labs-preregister.sh` exige título, método, métrica, criterios de éxito y fracaso y muestra; no pide
  intervalo de confianza, diseño pareado ni tratamiento de ejecuciones cortadas.
- SE-469 introduce IC95 por tribunal, pero solo para la tasa de acierto de un juez, no para diferencias entre dos
  configuraciones.
- Un corte por tiempo no es aleatorio: suele caer en las ejecuciones más largas o difíciles. Tirarlas y comparar solo
  las terminadas sesga el resultado a favor de la configuración que más corta.

## Fuente

- Anthropic, «A statistical approach to model evaluations»: reportar error estándar e IC95, usar diferencias
  **pareadas** por tarea cuando ambas configuraciones resuelven las mismas tareas, y errores agrupados por cluster
  cuando las tareas no son independientes. <https://www.anthropic.com/research/statistical-approach-to-model-evals>
- Anthropic, «Infrastructure noise»: la configuración de recursos mueve varios puntos en un benchmark agéntico y los
  errores de infraestructura pueden superar el margen entre modelos.
  <https://www.anthropic.com/research/infrastructure-noise>
- Priorización: Savia Labs (privado).

## Propuesta

1. **Librería pequeña** `scripts/lib/compare-stats.py` (stdlib, sin dependencias nuevas):
   - `rate_ci(k, n)`: proporción con IC95 de Wilson.
   - `paired_diff(a[], b[])`: diferencia media pareada por tarea, error estándar e IC95; si las listas no casan por
     id de tarea, error (no se compara en no pareado en silencio).
   - `clustered_se(values, clusters)`: error estándar agrupado cuando varias medidas comparten tarea o sesión.
   - `censoring(rows)`: cuenta y tasa de ejecuciones `timeout`/`infra_error` por configuración, separadas del
     resultado.
2. **Contrato de informe.** Un informe comparativo (JSON) lleva obligatoriamente `n`, `estimate`, `ci95`,
   `design: paired|unpaired|clustered`, `censored: {timeout, infra_error}` por brazo y `censoring_policy`
   (`worst_case`, `excluded_with_bound` o `rerun`). Sin `ci95` o sin `censored`, el informe no es válido.
3. **Política de censura por defecto: `worst_case`.** Una ejecución cortada cuenta como fallo del brazo que la cortó,
   y el informe muestra además el resultado excluyéndolas como análisis de sensibilidad. Cambiar la política exige
   declararlo antes de ejecutar.
4. **Preregistro.** `labs-preregister.sh` añade `--design` y `--censoring-policy` como obligatorios y los escribe en
   el fichero de hipótesis.
5. **Lenguaje de conclusión.** Si el IC95 de la diferencia incluye 0, el informe dice «sin diferencia demostrada» y
   no «A mejor que B». Validador de texto en el generador de informes.

## Criterios de aceptación

| AC | Verificación |
|---|---|
| AC1 | `pytest tests/python/test_compare_stats.py`: `rate_ci(30, 50)` coincide con Wilson de referencia a 3 decimales; `paired_diff` con listas de ids distintos lanza error; una diferencia pareada con varianza nula da IC de ancho 0; un caso con correlación por tarea da IC pareado más estrecho que el no pareado (prueba de que el emparejamiento se usa). |
| AC2 | `censoring`: con 4 terminadas y 2 `timeout` en un brazo, `worst_case` cuenta 2 fallos más; la sensibilidad excluyendo cortes se reporta aparte; ninguna política descarta cortes sin dejarlos en `censored`. |
| AC3 | Validador de informe: rechaza JSON sin `ci95`, sin `design` o sin `censored`; acepta uno completo. |
| AC4 | Texto de conclusión: con IC que incluye 0 el generador emite «sin diferencia demostrada» y un test negativo comprueba que no emite «mejor». |
| AC5 | `bats tests/test-labs-preregister.bats`. Inventario de llamadores a fecha de la spec: `grep -rn labs-preregister scripts tests docs` solo encuentra el propio script y esta spec, sin invocaciones ni tests previos, así que no hay llamadores existentes que romper (se revalida al implementar). Periodo de aviso: durante 2 semanas desde el merge, la ausencia de `--design` o `--censoring-policy` emite aviso por stderr y sale 0; pasado ese plazo sale con error. Con ambos presentes, el fichero de hipótesis los contiene. Test negativo en cada fase. |

## Riesgos

- **Burocracia**: dos campos más en cada preregistro. Bajo.
- **Falsa precisión**: un IC de Wilson con n=5 sigue siendo inútil; el informe muestra n y el ancho, que es la
  señal honesta.
- **`worst_case` penaliza al brazo con más cortes aunque el corte sea de infraestructura**: por eso la tasa de
  `infra_error` se reporta separada y el informe permite `rerun` declarado de antemano.

## Alternativas

- **Dependencia estadística externa (scipy, statsmodels)**: instala dependencias nuevas; para estos cuatro cálculos
  basta la stdlib.
- **Solo una nota en la regla**: ya hay reglas de evaluación honesta (SE-468) y el problema persiste; hace falta un
  validador.
- **No hacer nada**: decisiones de enrutado y defaults apoyadas en diferencias que pueden ser ruido.

## Lo que no se hace

- No re-analiza comparativas antiguas: aplica a informes nuevos.
- No impone tamaños de muestra mínimos: el IC ya muestra si la muestra alcanza.
- No sustituye a SE-469 (acierto de cada tribunal); la complementa para comparar configuraciones.

## Alcance

| Slice | Entrega |
|---|---|
| S1 | `compare-stats.py` y tests AC1-AC2. |
| S2 | Contrato y validador de informe, texto de conclusión; AC3-AC4. |
| S3 | Campos nuevos en `labs-preregister.sh`; AC5. |

## Esfuerzo

S1 S, S2 S, S3 S.

## Decisiones pendientes de la operadora

- **D1**: política de censura por defecto (propuesta: `worst_case` + sensibilidad).
- **D2**: ¿el validador bloquea en CI los informes comparativos nuevos o solo avisa al principio? (propuesta: aviso
  durante 2 semanas, luego bloqueo).

## OpenCode Implementation Plan

### Bindings touched

| Componente | Claude Code | OpenCode v1.14 |
|---|---|---|
| `scripts/lib/compare-stats.py` | invocado por scripts de evaluación | el mismo |
| `scripts/labs-preregister.sh` | script bash | el mismo |
| Validador de informe | script Python | el mismo |

### Verification protocol

- [ ] Funciona en runtime OpenCode: sin dependencia de frontend.
- [ ] Tests cubren ambos paths: un único path (pytest + BATS), sin bindings.
- [ ] Sin hooks nuevos.

### Portability classification

- [x] **PURE_BASH**: bash y Python stdlib, sin bindings de frontend.
