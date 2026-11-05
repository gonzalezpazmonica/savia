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
   - **Normalización antes de comparar, la misma en cita y texto:** Unicode NFC, comillas y guiones tipográficos a su forma ASCII, cualquier secuencia de espacios en blanco a un espacio. Sin cambio de mayúsculas ni de puntuación restante.
   - **Guion de corte de línea (`-\n`):** no se puede saber si es un corte («infor-\nmación») o un guion real partido por el salto («well-\nknown»). El texto se normaliza de las dos formas, sustituyendo cada coincidencia de `-[ \t]*\n\s*` (guion, espacios opcionales, salto y la sangría de la línea siguiente) por la cadena vacía («información») y por `-` («well-known»), y solo después se colapsan los espacios. La cita vale si aparece literal en cualquiera de las dos. Así ninguna de las dos lecturas produce un rechazo espurio.
   - **Longitud mínima de la cita:** 8 palabras tras normalizar. Una cita más corta → `QUOTE_TOO_SHORT`, exit 1 (una palabra suelta aparece en casi cualquier texto).
   - **Códigos de salida de `check`:** 0 todo `SUPPORTED_LITERAL`; 1 al menos un hallazgo de contenido (`QUOTE_NOT_FOUND`, `QUOTE_OUTSIDE_LOCATOR`, `QUOTE_TOO_SHORT`, `REVISION_MISMATCH`, `EPISTEMIC_UNSOURCED`); 2 entrada inválida o ausente (fail-closed), con el hallazgo `INPUT_INVALID` y el motivo (`json_malformed`, `study_missing`, `text_missing`). **Precedencia:** si hay entrada inválida en cualquier ficha, la salida es 2 aunque otras fichas tengan hallazgos de contenido (no se puede afirmar nada sobre una entrada que no se pudo leer); si no, 1 si hay algún hallazgo; si no, 0. Todos los hallazgos se listan en la salida, no solo el primero. `check` no hace red nunca.
   - **Informe:** `check --report RUTA` escribe además el informe Markdown de las fichas verificadas, con una sección «Apoyos» y otra «Contraevidencia» (las `contradicts[]` válidas). El verificador es quien genera esa sección; `/tech-research` (S2) la incluye tal cual.
   - El juez LLM queda como segunda opinión opcional, nunca como sustituto.
2b. **Puerta de nivel, separada del verificador.** `scripts/evidence-claim-check.py level <ruta-pregunta> [--ficha RUTA]` decide, sin red, si una pregunta puede consultar APIs externas: exit 0 si es N1; exit 3 con `LEVEL_MISSING` (sin clasificación) o `LEVEL_NOT_ALLOWED` (N2 o superior, o, con `--ficha`, ficha que declara un nivel menos restrictivo que el de su pregunta). Sin `--ficha` solo se evalúa la pregunta; la comparación con la ficha solo existe cuando se pasa. Quien hace la consulta externa es el paso de búsqueda (S0 a mano; S2, `/tech-research` y `scripts/web-research/search.py`), y está obligado a llamar a `level` antes y a no consultar nada si sale distinto de 0. Los dos subcomandos tienen códigos disjuntos (`check`: 0/1/2; `level`: 0/2/3), así que no hay precedencia que resolver entre 1 y 3.
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
| AC-2 | **Negativo:** la misma `quote` con una palabra cambiada → `QUOTE_NOT_FOUND`, exit 1; la misma `quote` con comillas tipográficas, doble espacio o partida por `-\n` → `SUPPORTED_LITERAL`; texto con «well-\n    known» (salto y sangría tras el guion): la cita «well-known …» y la cita «wellknown …» → ambas `SUPPORTED_LITERAL`; **negativo:** la cita «well- known …» (con espacio) → `QUOTE_NOT_FOUND` | estática | ídem |
| AC-2c | **Precedencia:** dos fichas, una con `QUOTE_NOT_FOUND` y otra con JSON malformado → exit 2 y la salida lista los dos hallazgos (`QUOTE_NOT_FOUND` e `INPUT_INVALID json_malformed`) | estática | ídem |
| AC-2b | **Negativo:** cita literal que existe en el estudio pero fuera de la sección de su `locator` → `QUOTE_OUTSIDE_LOCATOR`, exit 1; **límite:** cita de 7 palabras → `QUOTE_TOO_SHORT`, exit 1; de 8 → se verifica | estática | ídem |
| AC-3 | **Negativo:** revisión declarada distinta del hash del texto guardado → `REVISION_MISMATCH`, exit 1 (la cita podría existir en otra versión) | estática | ídem |
| AC-4 | **Negativo:** `epistemic: observed` sin ningún `supports[]` → `EPISTEMIC_UNSOURCED` (mismo código que SE-449 AC2), exit 1; `observed` cuyos `supports[]` fallan todos (p. ej. `QUOTE_NOT_FOUND`) → esos hallazgos **y además** `EPISTEMIC_UNSOURCED`, porque no le queda ningún apoyo válido; con al menos un apoyo válido → sin `EPISTEMIC_UNSOURCED` | estática | ídem |
| AC-5 | `level`: pregunta N1 → exit 0; **negativo:** pregunta sin clasificación → `LEVEL_MISSING`, exit 3; pregunta N2 o superior → `LEVEL_NOT_ALLOWED`, exit 3; `level <pregunta N2> --ficha <ficha que declara N1>` → `LEVEL_NOT_ALLOWED`, exit 3; `level <pregunta N1> --ficha <ficha que declara N2>` → `LEVEL_NOT_ALLOWED`, exit 3 (manda el más restrictivo); fichero de pregunta ausente → exit 2 | estática | ídem |
| AC-5b | **Negativo (quien consulta):** el paso de búsqueda de S2 lanzado con una pregunta N2 y un stub de red que anota cada llamada en un fichero → el fichero queda vacío y la búsqueda sale con 3; con una pregunta N1 → el stub recibe la llamada (el test comprueba también el positivo, para que no pase con un paso de búsqueda que nunca llama a la red) | estática | `tests/test-se506-level-gate.bats` (S2) |
| AC-6 | Dos estudios con el mismo DOI escrito de forma distinta (mayúsculas, prefijo `https://doi.org/`) → un solo `StudyRecord`; sin DOI, mismo título con distinta capitalización y espacios y mismo año → uno solo; **negativo:** mismo título y año distinto → dos | estática | ídem |
| AC-7 | **Fail-closed:** JSON malformado, estudio citado inexistente o texto guardado ausente → exit 2, nunca `SUPPORTED_LITERAL` | estática | ídem |
| AC-8 | `check --report`: una afirmación con `contradicts[]` válido se lista en la sección «Contraevidencia» del informe generado, no se descarta; **negativo:** una `contradicts[]` con `QUOTE_NOT_FOUND` no aparece en esa sección y sí como hallazgo | estática | ídem |
| AC-9 | S0 (piloto PA) prerregistrado antes de medir: 3 preguntas N1, ≥30 afirmaciones, baseline `/tech-research` actual, métrica `claim_supported_precision` y tiempo de revisión humana | experimento | prerregistro en Savia Labs |
| AC-10 | S1 solo arranca si el piloto mejora `claim_supported_precision` con un IC al 95 % que excluye 0 y el tiempo de revisión humana no sube más de un 50 %. El método del IC (bootstrap pareado por afirmación, 10 000 remuestreos) y el tamaño se fijan en el prerregistro; si con ≥30 afirmaciones el IC no puede excluir 0 por potencia, el prerregistro amplía la muestra antes de medir, no después. Si no se cumple, la spec pasa a `REJECTED` con el resultado publicado | gate | informe del piloto |
| AC-11 | `capability-entropy.py --check` PASS | CI | — |

## Plan por slices

| Slice | Entrega | Condición |
|---|---|---|
| S0 | Piloto PA en Savia Labs con fichas escritas a mano y verificador mínimo | SE-449 S1 en main; operadora autoriza consultas a APIs académicas con preguntas N1 |
| S1 | `scripts/evidence-claim-check.py` (stdlib, subcomandos `check` y `level`), esquema `docs/schemas/evidence-claim.schema.json`, tests AC-1..8 (con 2b, 2c y AC-5) | AC-10 en verde |
| S2 | `/tech-research` emite fichas además del informe en prosa y su paso de búsqueda llama a `level` antes de cualquier consulta externa (AC-5b); el Truth Tribunal lee el resultado del verificador como hallazgo de trazabilidad | S1 fusionado |

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

- [x] **PURE_BASH**: Python stdlib y BATS; ni `check` ni `level` abren conexiones. La red solo está en el paso de búsqueda que ya existe (`scripts/web-research/search.py`), detrás de `level`.

## Aprobación

Spec PROPOSED. La aprueba la operadora o la orquestadora con autoridad delegada en su PR. Esta PR solo añade documentación; ningún agente la fusiona sin grant.
