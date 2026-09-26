---
name: ci-health
description: Muestra tasa de fallo de pipelines CI a partir del log local de ejecuciones.
model_tier: fast
context_cost: low
allowed-tools: [Bash]
argument-hint: "[--days N]"
tier: core
---

# /ci-health

Analiza `output/ci-runs.jsonl` y reporta la tasa de fallo de los checks de CI
por workflow/check, además de las 5 causas recurrentes más frecuentes.

Argumentos: $ARGUMENTS

## Flujo

1. Banner:

   ```
   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
   📊 /ci-health — CI failure analysis
   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
   ```

2. Verificar prerequisitos:
   - `scripts/ci-failure-tracker.sh` existe y es ejecutable
   - Si falta → indicar cómo crearlo (viene de SPEC-SE-012)

3. Ejecutar:

   ```bash
   bash scripts/ci-failure-tracker.sh health $ARGUMENTS
   bash scripts/ci-failure-tracker.sh top $ARGUMENTS
   ```

4. Si el log está vacío, sugerir:

   ```
   Aún no hay datos. Registra una PR con:
     bash scripts/ci-failure-tracker.sh record <pr-number>
   ```

5. Banner de fin con recomendaciones si hay checks con ≥50% fallo.

## Notas

- `output/ci-runs.jsonl` es local (N3), gitignored.
- El script lee `gh pr view` para obtener el estado actual de una PR. Requiere
  `gh` autenticado con PAT.
- Default `--days 30`. Ajustar a 7 o 90 según alcance.

## Ejemplos

```
/ci-health
/ci-health --days 7
```
