---
status: PROPOSED
priority: P2
developer_type: agent-single
created: 2026-11-03
author: Savia
phase: A
risk: L1
human_surface: false
human_surface_exempt: "Genera ficheros de informe con la misma presentación en lenguaje llano; no cambia ninguna pantalla ni flujo de conversación."
depends_on: [SE-449]
related_specs: [SE-449, SE-489, SE-494, SE-497, SPEC-192]
origin: "Informe de Savia Labs labs/research/20261102-conocimiento-evidencia.md, línea A (veredicto: adaptar). Solo spec."
timeline:
  - from: "2026-11-03"
    learned: "2026-11-03"
    value: "PROPOSED"
---

# SE-506 — Fichas de estudio y afirmación con atribución determinista

## Problema (verificado en origin/main 3e094038d, 2026-11-03)

Los informes de investigación de Savia (`/tech-research`, `/biblio-search`) mezclan en la misma frase lo que dice una fuente y lo que concluye Savia. No hay forma automática de comprobar que una cita sostiene la afirmación a la que se pega. La comprobación que existe es un juez LLM (Truth Tribunal, criterio `source_traceability`), y Labs midió que no basta: en F6.4b un panel de tres jueces locales aprobó por mayoría 21 de 150 falsedades plausibles.

## Discovery: qué ya existe

| Pieza | Dónde | Qué cubre | Qué no |
|---|---|---|---|
| Estado epistémico `observed/derived/inferred/unknown` | `docs/specs/SE-449-epistemic-status-in-reports.spec.md:39-45` (APPROVED) | Vocabulario y etiqueta `{e:…}` por línea | **Sin implementar**: ningún script, test ni regla en `scripts/`, `tests/`, `.claude/`, `docs/rules/` la consume (búsqueda `SE-449`/`epistemic_status`, 2026-11-03) |
| Localizador + revisión + cita literal | `projects/savia-vaults/eval/evidence-bench/validate.py` y `schema.json` (`required_evidence[]` con blob SHA-1, `section`, `quote`) | Verificación determinista de evidencia para el banco de recuperación | Solo el banco; ningún informe lo usa |
| Búsqueda académica | `scripts/web-research/search.py` (categoría `academic`), `.claude/commands/biblio-search.md` (Crossref por DOI) | Encontrar fuentes | No separa estudio y afirmación, ni deduplica estudios, ni registra contraevidencia |
| Juez de trazabilidad | `scripts/truth-tribunal.sh`, `docs/rules/domain/truth-tribunal-weights.md` | Segunda opinión | Indulgente con falsedades plausibles (F6.4b) |

Conclusión: el hueco es real y es pequeño. Falta un formato de ficha y un verificador que reutilice el modelo del banco, no un motor de búsqueda nuevo.

## Qué decide esta spec

1. **Dos fichas separadas.** `StudyRecord` (una fuente: id estable, tipo, DOI o URL, revisión o hash del texto guardado, licencia, `stored: metadata_only|abstract|full_text`) y `EvidenceClaim` (una afirmación: texto, `epistemic` de SE-449, `supports[]` y `contradicts[]` con `study_id`, `locator` y `quote` literal).
2. **Verificador determinista.** `scripts/evidence-claim-check.py` comprueba, sin LLM, que cada `quote` aparece literal en el texto guardado de su estudio en esa revisión **y dentro del tramo que delimita su `locator`** (sección o rango de líneas), no en cualquier parte del texto.
   - **Normalización antes de comparar, la misma en cita y texto:** Unicode NFC, comillas y guiones tipográficos a su forma ASCII, guion de corte de línea seguido de salto (`-\n`) eliminado, cualquier secuencia de espacios en blanco a un espacio. Sin cambio de mayúsculas ni de puntuación restante.
   - **Longitud mínima de la cita:** 8 palabras tras normalizar. Una cita más corta → `QUOTE_TOO_SHORT`, exit 1 (una palabra suelta aparece en casi cualquier texto).
   - **Códigos de salida:** 0 todo `SUPPORTED_LITERAL`; 1 al menos un hallazgo de contenido (`QUOTE_NOT_FOUND`, `QUOTE_OUTSIDE_LOCATOR`, `QUOTE_TOO_SHORT`, `REVISION_MISMATCH`, `EPISTEMIC_UNSOURCED`); 2 entrada inválida o ausente (fail-closed); 3 consulta externa denegada por nivel (`LEVEL_NOT_ALLOWED`, `LEVEL_MISSING`). El juez LLM queda como segunda opinión opcional, nunca como sustituto.
3. **Deduplicación de estudios** por DOI normalizado y, sin DOI, por hash del título normalizado más el año.
4. **Por defecto se guarda `metadata_only` o `abstract`.** El texto completo solo si su licencia lo permite y queda anotada.
5. **Solo preguntas N1** pueden consultar APIs académicas externas. El nivel no lo pone quien redacta la ficha: la ficha solo guarda la referencia a la pregunta y el nivel se toma de la clasificación de confidencialidad de esa pregunta (`docs/rules/domain/context-placement-confirmation.md`, N1–N4b), que confirma la operadora al prerregistrarla. Si la ficha declara un nivel distinto del de la pregunta, manda el más restrictivo. Una pregunta sin clasificación no consulta nada.

## Lo que esta spec NO hace

- No implementa SE-449: depende de ella y no empieza S1 sin ella en main.
- No adopta un «medidor de consenso». La propia herramienta de referencia lo limita a preguntas sí/no con al menos cinco artículos.
- No añade dependencias ni servicios de terceros.

## Criterios de aceptación

| AC | Criterio | Tipo | Test |
|---|---|---|---|
| AC-1 | Una `EvidenceClaim` cuya `quote` aparece literal en el texto guardado del estudio en la revisión declarada → `SUPPORTED_LITERAL` | estática | `tests/test-se506-evidence-claim.bats` |
| AC-2 | **Negativo:** la misma `quote` con una palabra cambiada → `QUOTE_NOT_FOUND`, exit 1; la misma `quote` con comillas tipográficas, doble espacio o partida por `-\n` → `SUPPORTED_LITERAL` | estática | ídem |
| AC-2b | **Negativo:** cita literal que existe en el estudio pero fuera de la sección de su `locator` → `QUOTE_OUTSIDE_LOCATOR`, exit 1; **límite:** cita de 7 palabras → `QUOTE_TOO_SHORT`, exit 1; de 8 → se verifica | estática | ídem |
| AC-3 | **Negativo:** revisión declarada distinta del hash del texto guardado → `REVISION_MISMATCH`, exit 1 (la cita podría existir en otra versión) | estática | ídem |
| AC-4 | **Negativo:** `epistemic: observed` sin ningún `supports[]` → `EPISTEMIC_UNSOURCED` (mismo código que SE-449 AC2), exit 1 | estática | ídem |
| AC-5 | **Negativo:** pregunta sin clasificación → `LEVEL_MISSING`, exit 3; pregunta N2 o superior → `LEVEL_NOT_ALLOWED`, exit 3; ficha que declara N1 sobre una pregunta clasificada N2 → `LEVEL_NOT_ALLOWED`; en los tres casos no se hace ninguna consulta externa (se comprueba con un stub de red que falla si se le llama) | estática | ídem |
| AC-6 | Dos estudios con el mismo DOI escrito de forma distinta (mayúsculas, prefijo `https://doi.org/`) → un solo `StudyRecord` | estática | ídem |
| AC-7 | **Fail-closed:** JSON malformado, estudio citado inexistente o texto guardado ausente → exit 2, nunca `SUPPORTED_LITERAL` | estática | ídem |
| AC-8 | Una afirmación con `contradicts[]` válido se lista en el informe en una sección «Contraevidencia», no se descarta | estática | ídem |
| AC-9 | S0 (piloto PA) prerregistrado antes de medir: 3 preguntas N1, ≥30 afirmaciones, baseline `/tech-research` actual, métrica `claim_supported_precision` y tiempo de revisión humana | experimento | prerregistro en Savia Labs |
| AC-10 | S1 solo arranca si el piloto mejora `claim_supported_precision` con un IC al 95 % que excluye 0 y el tiempo de revisión humana no sube más de un 50 %. El método del IC (bootstrap pareado por afirmación, 10 000 remuestreos) y el tamaño se fijan en el prerregistro; si con ≥30 afirmaciones el IC no puede excluir 0 por potencia, el prerregistro amplía la muestra antes de medir, no después. Si no se cumple, la spec pasa a `REJECTED` con el resultado publicado | gate | informe del piloto |
| AC-11 | `capability-entropy.py --check` PASS | CI | — |

## Plan por slices

| Slice | Entrega | Condición |
|---|---|---|
| S0 | Piloto PA en Savia Labs con fichas escritas a mano y verificador mínimo | SE-449 S1 en main; operadora autoriza consultas a APIs académicas con preguntas N1 |
| S1 | `scripts/evidence-claim-check.py` (stdlib), esquema `docs/schemas/evidence-claim.schema.json`, tests AC-1..8 | AC-10 en verde |
| S2 | `/tech-research` emite fichas además del informe en prosa; el Truth Tribunal lee el resultado del verificador como hallazgo de trazabilidad | S1 fusionado |

## Riesgos

- **Coste de revisión:** las fichas añaden trabajo. AC-10 lo limita y el piloto lo mide antes de construir.
- **Licencias del texto completo:** por eso el valor por defecto es `metadata_only/abstract`.
- **Cita literal ≠ apoyo lógico:** el verificador demuestra que la cita existe, no que sostiene la afirmación. Eso sigue siendo revisión humana; el informe lo dice así.

## OpenCode Implementation Plan

### Bindings touched

| Componente | Claude Code | OpenCode v1.14 |
|---|---|---|
| `scripts/evidence-claim-check.py` | Python stdlib desde la sesión | El mismo |
| `docs/schemas/evidence-claim.schema.json` | Fichero | El mismo |
| `.claude/commands/tech-research.md` (S2) | Comando | Comando espejo en `.opencode/commands/` si existe |

### Verification protocol

- [ ] Funciona en runtime OpenCode: el verificador no depende del frontend
- [ ] Tests BATS cubren AC-1..8, con los negativos
- [ ] No añade hooks

### Portability classification

- [x] **PURE_BASH**: Python stdlib y BATS; sin red en el verificador.

## Aprobación

Spec PROPOSED. La aprueba la operadora o la orquestadora con autoridad delegada en su PR. Esta PR solo añade documentación; ningún agente la fusiona sin grant.
