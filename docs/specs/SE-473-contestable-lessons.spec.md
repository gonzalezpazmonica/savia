---
status: APPROVED
approved_at: 2026-10-27
approved_by: "operadora, AskUserQuestion 2026-10-27 (alcance aprobado: solo S0 (medición; puede cerrar la spec))"
priority: P2
developer_type: agent-single
created: 2026-10-26
author: Savia
phase: D
risk: L2
related_specs: [SCL-001, SCL-003, SCL-010, SE-352, SE-366, SE-409, SE-454, SE-456, SE-449]
origin: síntesis de una tesis sobre arquitectura neuro-simbólica; diseño en el repo de investigación privado
---

# SE-473 — Lecciones contrastables: ámbito, evidencia, revalidación y refutación

## Problema

Savia captura lecciones y las promueve con revisión humana (SCL-001: capturar → `INFERRED` → canary →
`human_authored`). Eso impide que el aprendizaje se autoautorice, pero no impide que una lección **deje de ser cierta** y
siga influyendo:

- Ninguna lección declara **dónde vale** (dominio, proyecto, frontend, versión de herramientas, periodo). Una lección
  aprendida con un frontend se aplica igual a otro.
- Ninguna declara **qué la refutaría** ni enlaza los casos que la sostienen.
- La caducidad está anunciada y no aplicada: `scripts/lesson-pipeline.sh:20` declara `MAX_LESSON_AGE_DAYS=90` y la
  variable no se usa en ningún otro sitio de `scripts/`.
- La retirada que existe es por desuso (SE-409) o por conflicto entre instancias (SCL-010), no por refutación.

Memoria (registrar y recuperar) no es aprendizaje (generalización contrastada, con ámbito y revocable).

## Valor y evidencia

- Evidencia propia: la de arriba (lectura de specs y script, 2026-10-26). **No medido todavía** cuántas lecciones activas
  son falsas o están fuera de ámbito: eso es S0, y S0 puede cerrar la spec.
- Evidencia externa de que las reglas inducidas no garantizan robustez fuera de muestra: DFORL (Gao et al., *Artificial
  Intelligence* 2024; reprint IJCAI 2024) y Propper (TPLP 2024) motivan su trabajo en la fragilidad de la inducción ante
  ruido. La misma fragilidad aplica a lecciones escritas por un LLM a partir de un solo episodio.
- Coste bajo: campos opcionales y un verificador; sin motor lógico nuevo.

## Alcance

| Slice | Tamaño | Entrega |
|---|---|---|
| S0 — medición | S | Inventario de almacenes de lecciones (lesson-pipeline, instintos, cúpula de lecciones, entradas `INFERRED`). Script de solo lectura que cuenta, por almacén, lecciones activas con y sin ámbito, evidencia enlazada y fecha. Muestra de 10 al azar con búsqueda manual de un contraejemplo en el historial. Informe sin datos personales. |
| S1 — esquema y verificador | S | Campos opcionales: `scope` (mapa de dimensiones), `evidence_refs` (≥ 1 enlace a caso), `review_by` (fecha), `refuted_by` (refs a contraejemplos). Verificador que **informa** (no bloquea) lecciones activas sin `scope`/`evidence_refs` o con `review_by` vencido. La caducidad de `lesson-pipeline.sh` se aplica con test o se elimina la variable: no queda configuración muerta. |
| S2 — refutación | M | Registrar un contraejemplo (`refuted_by`) degrada la lección a `INFERRED` y la excluye del recall operativo (SCL-003) hasta revisión humana. Nunca borra: deja rastro compatible con `supersedes` de SE-366. |

## Fuera de alcance

- Inducción automática de lecciones (ILP, Popper): sin negativos fiables en volumen no hay sobre qué trabajar.
- Calibrar la `confidence` de los instintos.
- Migración retroactiva obligatoria: los campos son opcionales.
- Cambiar la semántica `INFERRED`/`human_authored`.

## Criterios de aceptación

| AC | Verificación |
|---|---|
| AC1 (S0) | El script de medición es reproducible (misma entrada, misma salida) y da por almacén el % de lecciones activas sin `scope`, sin evidencia y sin fecha. |
| AC2 (S0, kill) | Si ≥ 80 % de las lecciones activas ya tiene ámbito y evidencia **y** 0 de 10 de la muestra tiene contraejemplo, S1–S2 no se hacen y se registra el descarte. |
| AC3 (S1) | Test que falla antes: una lección activa con `review_by` vencido aparece en el informe del verificador; negativo: una con `review_by` futuro no aparece. |
| AC4 (S1) | La caducidad de `lesson-pipeline.sh` aplicada con test, o la variable eliminada. |
| AC5 (S2) | Test: añadir `refuted_by` a una lección `human_authored` la devuelve a `INFERRED` y deja de salir en recall; negativo: una sin `refuted_by` sigue saliendo. |
| AC6 (S2, frontera de autoridad) | Test negativo de que ninguna operación de este flujo escribe en contratos, grants, capabilities ni reglas canónicas (línea de SE-454). Un contraejemplo nunca promueve: solo degrada. |
| AC7 | `capability-entropy.py --check` PASS: se extienden scripts existentes, sin skills ni comandos nuevos. |

## Riesgos

- Burocracia: campos que nadie rellena. Mitigación: opcionales, el verificador informa sin bloquear y AC2 permite matar
  la spec.
- Un contraejemplo falso degrada una lección buena. Mitigación: la degradación vuelve a revisión humana y no borra.

## Esfuerzo

S0 S, S1 S, S2 M.

## Decisiones pendientes de la operadora

- **D1**: aplicar la caducidad por edad de `lesson-pipeline.sh` o eliminar la variable (propuesta: decidir con el dato de
  S0).
- **D2**: si `refuted_by` admite referencias a informes con estado epistémico `rejected` (delta de SE-449) (propuesta: sí,
  cuando SE-449 lo incorpore).

## Referencias cruzadas

SCL-001 (bucle de aprendizaje), SCL-003 (recall operativo), SCL-010 (reconciliación), SE-352 (procedencia), SE-366
(bitemporal, `supersedes`), SE-409 (retirada por desuso), SE-454 (invariantes negativos), SE-456 (tests no vacuos),
SE-449 (estado epistémico).

## OpenCode Implementation Plan

### Bindings touched

| Componente | Claude Code | OpenCode v1.14 |
|---|---|---|
| `scripts/lesson-pipeline.sh` y verificador | scripts invocados por skills de memoria | los mismos |
| Recall operativo (SCL-003) | lectura de almacenes desde el script | la misma |

### Verification protocol

- [ ] Los tests corren sin frontend.
- [ ] Sin hooks nuevos.
- [ ] El recall filtrado se comprueba desde los dos frontends con la misma lección de fixture.

### Portability classification

- [x] **PURE_BASH**: scripts y ficheros de lecciones; ningún binding de frontend.
