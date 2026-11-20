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

### Aprobación de S1

S1 (recall trazado) APPROVED por la operadora el 2026-11-10 por pregunta interactiva. Respuesta literal: «Apruebo S1 (Recommended)». Esta aprobación cubre solo S1; S2–S4 siguen necesitando la suya.

## Enmienda propuesta 2026-11-10 (solape SE-516)

> Propuesta externa SE-516 del 2026-11-09, evaluada como solape. No cambia el estado de esta spec; vale cuando la operadora fusione la PR.

- **Reutilizar P10.** El resultado de la ablación recall encendido/apagado (AC-5) es también la evidencia de «con/sin lección» que S09 necesita para valorar la supervisión. Se publica en un formato que S09 pueda leer (caso, decisión con y sin recall, coste observado); no hay S5 ni informe aparte.
- **Sin comparación de modalidades de supervisión aquí.** Qué estrategia de revisión rinde más dentro de un techo de permisos no es aprendizaje exigible; lo estudia, si procede, S09. Ningún resultado de esa comparación cambia la fuerza `advisory`/`review_required`/`guarded` de una lección.
- **Dónde se anota la hipótesis.** En la sesión S09 de `docs/propuestas/planning-state.json` (fuente canónica); `docs/propuestas/ROADMAP-CURRENT.md` se regenera con `scripts/roadmap.sh render`, sin edición manual.

## Rediseño 2026-11-20 (propuesto, pendiente de la operadora)

> Estado: **propuesto**. No cambia el `status` de la spec ni desaparca nada: lo aprueba o lo rechaza la operadora. Hasta entonces S3–S4 siguen aparcadas en la cola (`parked` de S34 en `planning-state.json`). Leído en origin/main 6d42ab1bc.

### Qué dependía de SE-493 y SE-513

- **S3** no cita SE-493 en su entrada (S2 con GO y aprobación auténtica). El vínculo venía de dos sitios: la línea de Riesgos («S3 y S4 no empiezan mientras SE-493, SE-497 y SE-498 sigan PROPOSED») y la sesión S34 de la cola, que agrupa S3 y S4. La nota de retirada de SE-513 dice que «SE-515 S3 ya no puede apoyarse en la admisión de SE-513»; leída esta spec, la admisión aparece en **S2** (consulta «en la admisión de trabajo de riesgo»), no en S3.
- **S4** sí: «SE-493 y SE-498 implementadas en la ruta». SE-493 aportaba el registro del efecto (`prepare`/`dispatch`) donde el recibo de la resolución quedaba atado al efecto concreto y se comprobaba en la transacción del despacho.

### S3 rediseñado — un dominio `guarded` en `push-pr.sh`

Sin cambio de fondo. Se corrigen la entrada y el riesgo.

- **Ruta piloto (verificada).** `scripts/push-pr.sh`: sus pasos 0–5 salen con `exit 1` ante fallo (`:43-46` plan previo, `:61-64` árbol limpio, `:69` CI local, `:74` CHANGELOG, `:79` confidencialidad) y el efecto es `git push` en `:82`. El verificador de la obligación piloto va como un paso más antes de `:82`, con el mismo `exit 1`.
- **Límite declarado.** `push-pr.sh` no es la única forma de publicar: un `git push` directo lo esquiva. G4 se declara «en `push-pr.sh`», y `git push` directo queda `NOT_GUARANTEED`, como ya dice «G4 se declara por ruta».
- **Entrada corregida.** S2 con GO y una aprobación auténtica **ya implementada y fusionada** (SE-488 en estado IMPLEMENTED; SE-497 parte 2 solo cuenta cuando deje de estar PROPOSED). Un estado PROPOSED o IMPLEMENTING no vale como entrada. Sin SE-493 y sin SE-498.
- **AC-12 y AC-13**: sin cambios.

**Qué se pierde:** nada de S3. Los pasos 0–5 de `push-pr.sh` están dentro de `if ! $MERGE` (`:42`): la ruta `--merge` no ejecuta el verificador (ahí no se empuja, SE-343) y queda fuera de la garantía. Además el `git push` de `:82` va en una tubería a `tail` con `set -euo pipefail` (`:6`): un push fallido sí hace fallar la tubería y dispara el reintento, que es un `git push --force-with-lease` automático. Eso fuerza el push sin decisión humana; el verificador va antes y no lo cubre, y decidir si ese reintento debe existir es una cuestión aparte de este rediseño. Lo que S3 nunca tuvo (garantía fuera de `push-pr.sh`) sigue sin tenerlo.

### S4 rediseñado — revalidación sobre el recibo que ya existe

La revalidación no necesita un libro: compara, en el gate y justo antes del efecto, lo que valía al planificar con lo que vale ahora. Las piezas existen o las entrega S2:

| Dimensión | Fuente | Dónde | Campos |
|---|---|---|---|
| Recurso (contenido que se publica) | Recibo de revisión v2 | `scripts/receipt-v2.sh:84-85` (`output/receipts/<rama>.receipt.json`), `:170-184` | `branch`, `commit_sha`, `tree_hash`, `paths` (hash por fichero), `signed_at`; `verify` detecta contenido cambiado |
| Política (lección u obligación aplicada) | Recibo de resolución de S2 | Lo entrega S2 («recibo sin contenido sensible») | Identificador y hash de la entrada de `CRITERIO.md` o de la LP, versión, fuerza |
| STOP | Plano de control de SE-498 | `savia-control.py epoch` y `check` (SE-498 F0, aún sin implementar) | época efectiva, `stop_seq` del ámbito |
| Contrato | Kernel de SE-496 | `recheck` (solo si la ruta tiene contrato) | `state_digest` |

**Regla.** El paso nuevo de `push-pr.sh`, antes de `:82`: (1) `receipt-v2.sh verify` debe dar `RECEIPT VALID`; (2) el hash de la política en el recibo de S2 debe coincidir con el de la entrada actual; (3) la época y el `stop_seq` guardados en el recibo de S2 deben coincidir con los de `savia-control.py`. Si algo cambió, falta o no se puede leer, no se publica y se pide repetir la comprobación (fail-closed). No se reutiliza el paso `g0b` de `scripts/pr-plan-gates.sh:22-37`, que deja pasar si falta el script: aquí la ausencia bloquea.

**Rastro.** (Origen de la época y `stop_seq` de la regla (3): el recibo de S2 no los lleva hoy, así que S2 se enmienda para guardarlos en el recibo, leídos de `savia-control.py` al planificar y cubiertos por el hash del recibo. No se admite un fichero aparte junto al recibo: podría quedar obsoleto o ser manipulado sin que `receipt-v2.sh verify` lo vea.) El veredicto de cada revalidación (`PASS`, `STALE_POLICY`, `STALE_CONTENT`, `STALE_EPOCH`, `UNREADABLE`) se anota con `scripts/session-action-log.sh log` (`output/session-action-log.jsonl`, campos `ts`, `action`, `target`, `result`, `detail`), que `push-pr.sh` ya usa en `_supervisor`. No es un libro de efectos ni prueba de integridad: `output/session-action-log.jsonl` no está encadenado ni firmado, a diferencia del ledger del merge-sprint; es una pista, no una garantía.

**Entrada corregida.** S3 con GO y SE-498 F0 implementada (época y `stop_seq`). Sin SE-493.

**Criterios de aceptación rediseñados (sustituyen a AC-14; AC-15 y AC-17 sin cambios).**

- **AC-14′.** Con recibo de S2 y `receipt-v2` válidos, la publicación pasa (positivo: sin él, un gate que bloquease todo cumpliría el AC). Cambiar la entrada de política, cambiar un fichero revisado o hacer `pause` + `resume` entre el recibo y el `push` (época o `stop_seq` distintos) bloquea con su motivo y el stub de `git push` no recibe la llamada. **Negativos:** recibo de S2 ausente, `receipt-v2.sh` ausente o `savia-control.py` saliendo con 2 → bloqueo (`UNREADABLE`), nunca paso. **Mutación:** un gate que solo compare el contenido deja pasar el caso «política cambiada» y el test falla.

### Qué se pierde respecto al diseño anterior

1. **Atadura recibo–efecto duradera.** Con SE-493, cada efecto guardaba el recibo que lo autorizó y el despacho lo comprobaba en la misma transacción. Ahora la comprobación ocurre en el gate, sin registro del efecto: queda la ventana entre la revalidación y `git push` (`:82`), y la auditoría posterior es la línea de `session-action-log`, no un estado del efecto.
2. **Solo una ruta.** La revalidación vive en `push-pr.sh`. Otras rutas de efecto no la tienen; ya era así en S3–S4, pero SE-493 daba un punto común para ampliarla.
3. **Dependencia que sigue abierta.** La dimensión de STOP espera a SE-498 F0. Sin ella, S4 solo revalida contenido y política.

### Decisiones para la operadora

- **D3 — S3.** (a) Separar S3 del aparcado: no depende de SE-493 ni de SE-498; corregir su entrada y la línea de Riesgos (recomendada). (b) Mantenerla aparcada junto a S4.
- **D4 — S4.** (a) Aprobar el rediseño sobre `receipt-v2`, el recibo de S2 y SE-498 F0, con las pérdidas declaradas (recomendada). (b) Hacer S4 sin la dimensión de STOP para no esperar a SE-498 F0, y añadirla después. (c) Retirar S4: si `receipt-v2` y la entrada de S3 ya fallan cerrado, la revalidación aporta poco hasta que haya una segunda ruta.
