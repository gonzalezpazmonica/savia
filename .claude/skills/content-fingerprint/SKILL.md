---
layer: peripheral
name: content-fingerprint
description: "Usar cuando se necesita un identificador corto, deterministico y reproducible derivado del contenido de una cadena o fichero — cache keys, ids de patrones, fingerprints de docs."
metadata:
  # --- metadata.savia.* (SE-333) ---
  savia.bioquimica: "{\"inspiracion\": \"DNA barcoding (Hebert et al. 2003, Proc Roy Soc B), Drosophila olfactory LSH (Dasgupta et al. 2017, Science)\", \"analogo_biologico\": \"fragmento canonico discriminativo del gen COI (650 bp) que identifica especies por su firma corta invariante intra-especie\", \"propiedad_aplicada\": \"fingerprint determinista corto (8-64 chars hex) invariante para mismo input, divergente para inputs distintos\", \"no_aplicado_aun\": [\"Dasgupta sparse expansion (random projection a alta dimension)\", \"winner-take-all top-k sparsening\", \"olfactory combinatorial encoding (N receptores -> 2^N patrones)\"], \"paper_dois\": [\"10.1098/rspb.2002.2218\", \"10.1126/science.aam9868\"], \"doi_validated\": \"2026-06-19\", \"warning\": \"Esta seccion documenta inspiracion biologica. El codigo es honestamente sha256 truncado (SimHash/MinHash equivalent), no implementa Dasgupta-LSH. Sin biomimetic theater.\"}"
  savia.maturity: stable
  savia.context_tier: L3
  savia.token_budget: 350
---

# Skill: content-fingerprint

## Cuando usar

Cuando un script necesita derivar un identificador corto, reproducible y resistente a colisiones a partir de un contenido (cadena, fichero, agregado). Casos tipicos:

- Cache keys (`ado-bridge.sh`)
- Pattern signatures (`failure-pattern-memory.sh`)
- Doc fingerprints de auditoria (`semantic-map.sh`)
- Test attempt hashes (`test-auditor.sh`)

## Cuando NO usar

- Si necesitas hash criptografico para integridad fuerte: usa `sha256sum` directo (ya disponible).
- Si necesitas detectar near-duplicates con tolerancia a 1 byte: SHA truncado NO sirve. Considera SimHash/MinHash o embeddings (`memory-vector.py`).
- Si necesitas buscar por similitud semantica: usa `memory-vector.py` (HNSW + MiniLM).

## Como usar

```bash
# Identificador corto
ID=$(echo "agente:tarea:contexto" | scripts/content-fingerprint.sh 8)
# Output: 8 chars hex deterministicos

# Cache key 16 chars
KEY=$(printf '%s|%s' "$query" "$context" | scripts/content-fingerprint.sh 16)

# Fichero completo
FP=$(scripts/content-fingerprint.sh 16 < my-doc.md)

# Self-test
scripts/content-fingerprint.sh --self-test
```

## Acceptance criteria validados (SE-151)

- AC-1: longitudes 8/16/32/64 producen hex de tamaño exacto.
- AC-1: avalanche — 1 byte de diferencia → fingerprint distinto.
- AC-1: determinismo — mismo input → mismo output.
- AC-4: dataset etiquetado de 30 fixtures (15 pares) verifica precision/recall.
- AC-5: 100 invocaciones <5s total (sanity check de latencia).

Tests: `bats tests/scripts/content-fingerprint.bats` (14/14 verde).

## Limitaciones honestas

- **No detecta near-duplicates**: 1 char de cambio cambia el fingerprint entero (avalanche). Esto es una propiedad deseable para identificadores, una limitacion para clustering.
- **No es LSH biologico**: Dasgupta 2017 requiere vectorizacion previa + sparse expansion, no implementado aqui.
- **Coliciones a 8 chars**: para corpus muy grandes (>10^6 docs), considerar 16 chars o mas (paradoja del cumpleanos).

## Referencias

- Spec: `docs/specs/SE-151-content-fingerprint-consolidation.spec.md`
- Tests: `tests/scripts/content-fingerprint.bats`
- Fixtures: `tests/fixtures/fingerprint/`
- Sesion previa archivada: `experiments/brainless/RESEARCH-LOG.md`
