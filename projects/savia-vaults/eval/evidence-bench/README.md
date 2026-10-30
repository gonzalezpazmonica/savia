# Banco de evidencia SE-489 (R1)

Banco estratificado con verdad a nivel de evidencia para comparar rutas de recuperación de Vaults (SE-489).
El banco de regresión de 36 consultas (`eval/rag-savia-docs.json`) no se toca.

## Ficheros

| Fichero | Qué es |
|---|---|
| `schema.json` | Esquema de un caso (JSON Schema 2020-12, subconjunto) |
| `cases.jsonl` | 302 casos, uno por línea. Generado: no se edita a mano |
| `manifest.json` | Cúpulas del banco, `snapshot_commit` del corpus real, mínimos y split |
| `corpus/` | Corpus sintético (`bench-legal` N2, `bench-restringida` N3). Generado |
| `corpus_synth.py` | Generador determinista del corpus sintético |
| `build_bench.py` | Generador de `cases.jsonl` y `manifest.json`; valida al terminar |
| `validate.py` | Validador: esquema + evidencia contra ficheros. Solo stdlib |
| `evidence-difficulty.ts` | Validación de dificultad con el baseline híbrido (M0). No es el runner de R2 |
| `tests/` | Tests unittest del corpus, del validador y del banco |

## Caso

`id`, `category` (A–F), `query`, `intent`, `scope` (`allowed_domes`, `as_of`), `expected` y `split` (`dev`/`test`).
`expected` declara:

- `answer_facts`: lo que debe contener la respuesta;
- `required_evidence[]`: cúpula, documento, revisión y localizador (`section` + `quote` literal);
- `forbidden_evidence[]`: lo que no debe leerse ni citarse (otra revisión, código casi igual, cúpula no autorizada, cuarentena);
- `must_abstain`: la respuesta correcta es no responder (puede llevar la evidencia que lo justifica);
- `max_unauthorized_reads: 0`.

La revisión es el blob SHA-1 de git. En `savia-docs` es el blob de la ruta en `snapshot_commit`
(`c783d6bcf`), así que el banco no se rompe cuando la documentación cambia en main. En el corpus sintético
es el blob del fichero en disco.

## Categorías

| Cat. | Casos | Contenido |
|---|---|---|
| A | 50 | AC de specs con identificador casi igual prohibido, sub-specs (SE-396 A01/P01…), prohibiciones «NUNCA» preguntadas en positivo |
| B | 50 | Paráfrasis redactadas a mano sobre reglas que no están en el banco de 36 |
| C | 50 | Respuesta repartida entre una cláusula del contrato y su anexo; anexos de contratos con código casi igual prohibidos |
| D | 52 | Normas con revisiones que se sustituyen y `as_of`; las demás revisiones prohibidas; 2 fechas anteriores a la norma (abstención) |
| E | 50 | 25 pares de reglas reales y 25 sintéticos (agregación sobre contratos, contrato → norma vigente, comparación) |
| F | 50 | Cúpula N3 no autorizada, notas en cuarentena, anexo inexistente, circulares contradictorias, inyección, identificadores inexistentes |

Split 70/30 por categoría, fijo por `sha256(id)`. Hay un subconjunto oculto de 30 casos fuera del repo.

Los casos no se derivan del grafo de vínculos: cada evidencia es una cita literal elegida leyendo el
documento (A y B) o una plantilla sobre el corpus sintético (C, D, E, F).

## Uso

```bash
python3 eval/evidence-bench/validate.py                  # 0 válido · 1 inválido · 2 error de entrada
python3 eval/evidence-bench/build_bench.py --write       # regenera corpus/, cases.jsonl y manifest.json
python3 -m unittest discover -s eval/evidence-bench/tests
```

El validador necesita el historial de git con `snapshot_commit`. Sin él falla (cierre seguro).

Dificultad (SAVIA_RAG_HOME temporal, nunca la de producción): registrar las tres cúpulas en un
`domes.json` temporal (`savia-docs` = `git archive c783d6bcf docs`, las sintéticas = copia de `corpus/`),
`rag sync` de cada una y:

```bash
SAVIA_RAG_HOME=/tmp/x npx tsx eval/evidence-bench/evidence-difficulty.ts --domes-file /tmp/x/domes.json --cases eval/evidence-bench/cases.jsonl --out /tmp/x/report.json
```
