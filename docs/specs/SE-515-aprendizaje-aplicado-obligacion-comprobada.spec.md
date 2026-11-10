---
status: APPROVED
priority: P1
developer_type: agent-team
created: 2026-11-09
author: Savia
phase: C
risk: L3
human_surface: false
depends_on: [SCL-001, SCL-003, SE-473]
related_specs: [SCL-006, SCL-008, SCL-011, SE-409, SE-460, SE-473, SE-488, SE-493, SE-496, SE-497, SE-498, SE-502, SE-508, SE-513, SE-514]
origin: "Tesis Savia Viva R6 «Aprendizaje exigible por dominio» (2026-11-09), candidata C3 y secuencia A0–A5. Original e informe en Savia Labs. Contrastada con main e59b795ee."
timeline:
  - from: "2026-11-09"
    learned: "2026-11-09"
    value: "PROPOSED"
  - from: "2026-11-09"
    learned: "2026-11-09"
    value: "APPROVED"
---

# SE-515 — Aprendizaje aplicado: de la lección recuperada a la obligación comprobada

## Problema (leído en main e59b795ee, 2026-11-09; lectura estática, nada ejecutado)

Matriz completa, con lo observado, lo inferido y lo no verificado: `docs/evidence/planning-repriorization-20261109.md`.

Savia guarda lecciones y las recupera. No puede demostrar que una lección validada se tuvo en cuenta antes de actuar, ni impedir un efecto que la incumple cuando el modelo la ignora.

1. **El recall efectivo existe, pero entrega un solo principio.** El hook `learning-recall-hook.sh` (UserPromptSubmit) y su par `learning-recall-guard.ts` llaman a `learning-recall.sh --mode effective` e inyectan hasta tres criterios. El filtro exige `provenance: human_authored`, y `CRITERIO.md` solo tiene uno (CRIT-001). De 725 filas de `output/learning-loop/recall.jsonl`, 487 son hits efectivos: con una sola entrada elegible, son el mismo principio repetido (inferido: el log guarda el número de hits, no cuál).
2. **No hay prueba de entrega.** El log lo escribe el script, no el hook. Si el hook vence su tope de 4 s o falla el parseo, sale con 0 sin rastro. No se sabe si el criterio llegó al contexto.
3. **El recall ocurre al escribir la persona, no al decidir.** Se dispara por prompt de usuario. No hay consulta en la admisión de un trabajo de riesgo ni antes de un efecto, y los subagentes no reciben ese evento.
4. **El orquestador mide con valores fijos.** `savia-orchestrator.sh:69` pide `--mode shadow` y cuenta hits; `:120-125` calcula `L` con `p_consistent=0.5`, `divergence=0.2`, `ignorance-resolved=0.1` si nadie pasa datos. Ese número no mide aprendizaje.
5. **Ninguna lección está enlazada a un control.** Las LP no tienen dominio, tipo de acción ni verificador (`learning-proposal.sh:158-170`). El campo `enforcement:` de `CRITERIO.md` es texto libre sin consumidor. Ningún hook de efecto consulta lecciones ni criterios.
6. **Hay rutas de efecto sin control previo.** Las llamadas `mcp__*` con escritura y `WebFetch` no tienen PreToolUse (lo cubre SE-508, PROPOSED). Los ejecutores externos corren fuera de los hooks del frontend. Varios guards de Claude Code no tienen par en OpenCode.
7. **Dos piezas previas a la acción no las invoca nadie.** `world-model-simulator.py` y `actor-pre-action-loop.py` (SPEC-165, SPEC-168) solo se ejecutan en sus tests, y sus riesgos y confianzas son constantes en código. `learning-autonomy.sh` (SCL-006) calcula un nivel que nadie aplica.

## Qué decide esta spec

- **Cinco grados, y se declara el que se alcanza.** G0 disponible, G1 recuperada, G2 evaluada, G3 incorporada a la decisión, G4 cumplida por un control externo al modelo. Ningún informe, métrica ni mensaje declara un grado superior al probado.
- **No se crea almacén, servicio ni grafo.** La vinculación de una lección a su dominio son campos en lo que ya existe: la LP (ámbito, evidencia y caducidad los define SE-473) y la entrada de `CRITERIO.md`, cuyo `enforcement:` pasa de texto libre a estructura. Si SE-496 se aprueba, el contrato de delegación es el dueño de la política y esto se reduce a una referencia.
- **Aplicar no es parecerse.** Si una lección aplica se decide con metadatos: dominio, tipo de acción, recurso, versión, punto de control y vigencia. La búsqueda léxica o semántica solo propone candidatas orientativas. El resultado es `APPLICABLE`, `NOT_APPLICABLE`, `UNKNOWN` o `CONFLICT`; `UNKNOWN` nunca vale como `NOT_APPLICABLE` ante un efecto.
- **Tres fuerzas, y el modelo no elige ninguna.** `advisory` añade contexto y nunca bloquea. `review_required` retiene la decisión hasta una revisión humana auténtica. `guarded` exige un verificador determinista, probado y conectado a un gate que ya existe. Sin aprobación verificable o sin verificador, la fuerza baja a `advisory`.
- **El aprendizaje no concede nada.** Ni `p_consistent`, ni la frecuencia de recuperación, ni la activación de una LP amplían permisos, capacidad o autonomía. El nivel de `learning-autonomy.sh` es informativo.
- **G4 se declara por ruta.** «G4 en `push-pr.sh`» es una afirmación válida; «G4» a secas no. Una ruta que esquiva el gate deja la garantía en `NOT_GUARANTEED` para esa ruta.
- **Se puede apagar.** Con el interruptor en off, Savia funciona como hoy y los gates anteriores a esta spec siguen activos.

## Slices

| Slice | Entrega | Entrada |
|---|---|---|
| S0 | Auditoría y línea base, solo lectura: matriz de cobertura por clase de efecto y por frontend; desglose del recall por criterio; estado de cada LP; diseño y fixtures de P10–P15 con sus condiciones de NO-GO; elección del dominio piloto con tres casos útiles y tres contraejemplos; decisión sobre retirar o etiquetar las dos piezas sin llamador. Commit y hashes congelados | Aprobación de S0 |
| S1 | Recall trazado: el hook y el guard registran qué criterios emitieron y si la emisión terminó; el orquestador usa el recall efectivo o declara `shadow`; una métrica calculada con valores por defecto sale marcada `no medido`. Ablación con recall encendido y apagado (P10) | S0 publicada |
| S2 | Vinculación `advisory` en sombra: campos de aplicabilidad, resolvedor determinista en `learning-recall.sh`, consulta en dos puntos (admisión de trabajo de riesgo y preparación de efecto), recibo sin contenido sensible. Evaluación en casos no usados para ajustar (P11, P13, P15) | S1; SE-473 S1 aprobada |
| S3 | Un dominio `guarded` con verificador real en un gate existente. Candidato a confirmar en S0: publicación del repositorio (`push-pr.sh`), la única ruta con un punto de control único que falla cerrado (P12) | S2 con resultado GO; aprobación auténtica (SE-497 parte 2 o SE-488) |
| S4 | Revalidación justo antes del efecto si cambian política, recurso, entorno, contrato o época de STOP; canario acotado con retirada (P14) | S3; SE-493 y SE-498 implementadas en la ruta |

Cada slice necesita su propia aprobación. Aprobar S0 no aprueba S1.

## Criterios de aceptación

| AC | Criterio | Slice |
|---|---|---|
| AC-1 | La matriz de cobertura lista cada clase de efecto, su control, si falla cerrado y las rutas que lo esquivan, en Claude Code y en OpenCode, con ruta y línea | S0 |
| AC-2 | El informe de S0 separa observado, inferido y no verificado, y fija commit y hash de cada fixture | S0 |
| AC-3 | Cada inyección de recall deja una fila con los identificadores de criterio emitidos y un indicador de emisión completada. **Negativo:** hook que vence su tope → fila con `emitted: false`, nunca ausencia de fila | S1 |
| AC-4 | **Negativo:** `learning-metric.sh` invocado con valores por defecto → salida marcada `no medido`; el orquestador no imprime «aprendió» con ella | S1 |
| AC-5 | P10: con el recall apagado y encendido sobre los mismos casos, el informe dice en cuántos cambió la decisión. Cero cambios es un resultado válido y se publica | S1 |
| AC-6 | El resolvedor devuelve los cuatro valores sobre una matriz de dominio, acción, versión y ámbito con positivos y negativos. **Negativo:** caso parecido de otro dominio o versión → `NOT_APPLICABLE`, sin bloqueo | S2 |
| AC-7 | **Negativo:** índice ilegible, verificador ausente o metadatos incompletos ante una obligación → `UNKNOWN` y decisión `BLOCK`, `REVIEW` o `DEFER` según la fuerza; nunca `PASS` por tiempo agotado | S2 |
| AC-8 | **Negativo:** una LP sin origen, versión o ciclo de vida válido, o con una cadena `human_trailer` no verificable, nunca se resuelve como `review_required` ni `guarded` | S2 |
| AC-9 | **Negativo:** dos obligaciones activas incompatibles → `CONFLICT` y escalado; no se elige por fecha ni por frecuencia | S2 |
| AC-10 | **Negativo:** el recibo de resolución no contiene prompts ni secretos, y un principal sin acceso a una lección no distingue «no aplica» de «no existe» | S2 |
| AC-11 | **Negativo:** `p_consistent` alto con mandato limitado → ninguna ruta amplía permisos; `learning-autonomy.sh` no tiene consumidor que conceda | S2 |
| AC-12 | P12: con el modelo instruido para ignorar la obligación, con texto inyectado que pide saltarla y con invocación directa de la herramienta, el efecto inválido se bloquea en la ruta cubierta. Una ruta que lo ejecuta deja el resultado en NO-GO para `guarded` | S3 |
| AC-13 | **Negativo:** verificador que no ejecuta ninguna comprobación → un control negativo lo detecta; retirar la lección cambia el resultado del caso de prueba | S3 |
| AC-14 | P14: cambio de política, de recurso o de época de STOP entre el plan y el efecto invalida el recibo y obliga a repetir la comprobación. **Negativo:** efecto comprometido con un recibo anterior → fallo | S4 |
| AC-15 | **Negativo:** lección caducada o refutada → no bloquea; se conserva en el histórico | S4 |
| AC-16 | Interruptor en off → suites actuales sin cambios y gates previos activos | S1–S4 |
| AC-17 | P13 y P15 en casos y versiones no usados para ajustar. Sin mejora neta o con falsos bloqueos relevantes, la vinculación se retira y el resultado se guarda | S2, S4 |

## Criterios de decisión

- **NO-GO inmediato:** una violación de autorización, STOP, privacidad, aislamiento entre ámbitos, o un consentimiento falsificado aceptado.
- **NO-GO para `guarded`:** la ruta no puede pasar por un gate externo fiable. Se usa `review_required` y se documenta la cobertura parcial.
- **GO provisional para `advisory`:** mejora resultados o reduce coste en casos no vistos sin transferencia negativa sistemática.
- **Más evidencia:** pocos casos, etiquetas contradictorias o líneas base no comparables.

Los umbrales se fijan después de la línea base y antes de abrir los casos reservados. Tamaño de cribado propuesto por la tesis: tres dominios con al menos veinte casos cada uno. No da potencia estadística; S0 decide el tamaño.

## No cuenta como éxito

Número de lecciones, veces recuperada, porcentaje de respuestas que citan una lección, aumento de `L` con valores fijos, o acuerdo entre dos modelos sin evidencia externa.

## Fuera de alcance

- Los campos de ámbito, evidencia, caducidad y refutación de las LP (SE-473).
- Aprobación humana auténtica y arreglos del ciclo de vida (SE-497 parte 2, SE-488).
- Ledger de efectos, STOP global y guard de MCP y WebFetch (SE-493, SE-498, SE-508). Esta spec los consume.
- Transferir lecciones entre organizaciones. Una lección ajena entra como propuesta en sombra y se revalida.
- Exploración autónoma con efectos.

## Riesgos

- **Un motor de políticas duplicado.** Si los campos de SE-473 y el contrato de SE-496 ya expresan la vinculación, S2 se reduce a un resolvedor de lectura y esta spec no añade esquema.
- **Bloqueos falsos.** Una lección demasiado general puede parar un dominio entero. Por eso `guarded` empieza con un dominio y con contraejemplos.
- **Una sola entrada elegible.** Con un criterio humano, P10 puede no tener muestra. S0 lo dice antes de gastar en S1.
- **Dependencias sin aprobar.** S3 y S4 no empiezan mientras SE-493, SE-497 y SE-498 sigan PROPOSED.

## OpenCode Implementation Plan

### Bindings touched

| Componente | Claude Code | OpenCode v1.14 |
|---|---|---|
| Recall trazado | `.claude/hooks/learning-recall-hook.sh` | `.opencode/plugins/guards/learning-recall-guard.ts`, misma batería de entradas |
| Resolvedor de aplicabilidad | `scripts/learning-recall.sh` (bash + Python stdlib) | El mismo |
| Verificador `guarded` | Dentro del gate existente de la ruta piloto | El mismo script |

### Verification protocol

- [ ] El guard TS registra la misma fila que el hook ante la misma entrada
- [ ] Tests con caso negativo por AC en los dos frontends
- [ ] Interruptor en off sin regresión

### Portability classification

- [x] **DUAL_BINDING**: el recall tiene binding por frontend; resolvedor y verificador son bash y Python stdlib.

## Aprobación

APPROVED por la operadora el 2026-11-09 por pregunta interactiva («Savia Viva + tokens y efectos»), tras confirmar las escenas cuando la spec las exige. Se formaliza al fusionar la PR (SE-488). Cada slice sigue necesitando su propia aprobación según «Slices»; esta aprobación cubre la spec y S0.

## Enmienda propuesta 2026-11-10 (solape SE-516)

> Propuesta externa SE-516 del 2026-11-09, evaluada como solape. No cambia el estado de esta spec; vale cuando la operadora fusione la PR.

- **Reutilizar P10.** El resultado de la ablación recall encendido/apagado (AC-5) es también la evidencia de «con/sin lección» que S09 necesita para valorar la supervisión. Se publica en un formato que S09 pueda leer (caso, decisión con y sin recall, coste observado); no hay S5 ni informe aparte.
- **Sin comparación de modalidades de supervisión aquí.** Qué estrategia de revisión rinde más dentro de un techo de permisos no es aprendizaje exigible; lo estudia, si procede, S09. Ningún resultado de esa comparación cambia la fuerza `advisory`/`review_required`/`guarded` de una lección.
- **Dónde se anota la hipótesis.** En la sesión S09 de `docs/propuestas/planning-state.json` (fuente canónica); `docs/propuestas/ROADMAP-CURRENT.md` se regenera con `scripts/roadmap.sh render`, sin edición manual.
