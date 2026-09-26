---
name: eval-output
description: >
  LLM-as-a-Judge — Evalúa la calidad de un output de agente/comando
  con scoring G-Eval (1-10), comparación A/B Arena, y análisis de tool selection.
model_tier: heavy
context_cost: high
tier: core
---

# /eval-output

Evalúa outputs de pm-workspace usando G-Eval (LLM-as-a-Judge).

**Argumentos:** $ARGUMENTS

> Uso: `/eval-output {fichero}` o `/eval-output --compare {A} {B}`

## Parámetros

- `{fichero}` — Ruta al output a evaluar (obligatorio salvo --compare)
- `--criteria {criterios}` — Criterios custom en lenguaje natural (opcional)
- `--compare {A} {B}` — Modo Arena: compara dos outputs head-to-head
- `--type {tipo}` — Tipo de output: spec, report, code, plan (carga criterios base)
- `--verbose` — Incluir justificación detallada por criterio

## Ejemplos

**✅ Correcto:**
```
/eval-output output/audits/20260305-audit-alpha.md --type report
→ Score: 7.8/10 | Completitud: 8 | Claridad: 9 | Accionabilidad: 6
→ Guardado en output/evals/20260305-eval-audit-alpha.md
```

**❌ Incorrecto:**
```
/eval-output output/audits/20260305-audit-alpha.md
→ "El informe está bien" (sin score numérico ni criterios)
Por qué falla: Sin scoring cuantitativo no hay feedback accionable
```

## Razonamiento

Piensa paso a paso antes de evaluar:
1. Primero: Identificar el tipo de output y cargar criterios base
2. Luego: Leer el output completo y evaluar contra cada criterio (1-10)
3. Finalmente: Calcular score global ponderado, generar feedback accionable

## 1. Banner de inicio

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🔍 /eval-output — Evaluación G-Eval
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

## 2. Verificar prerequisitos

- ✅ Fichero existe y no está vacío
- ✅ Si --compare: ambos ficheros existen
- ✅ Si --type: tipo válido (spec|report|code|plan)

## 3. Cargar criterios

Si `--criteria` proporcionado → usar custom.
Si `--type` proporcionado → cargar de `@docs/rules/domain/eval-criteria.md`.
Si ninguno → usar criterios genéricos: claridad, completitud, accionabilidad.

## 4. Modo estándar (G-Eval)

Delegar a subagente:

```
Lee el output en {fichero}.
Evalúa contra estos criterios (1-10 cada uno):
{criterios con descripciones}

Para cada criterio:
1. Score (1-10)
2. Justificación (1-2 frases)
3. Mejora sugerida (si score < 7)

Score global = media ponderada según pesos del tipo.
Guardar evaluación en output/evals/YYYYMMDD-eval-{nombre}.md
```

## 5. Modo Arena (--compare)

Delegar a subagente:

```
Lee ambos outputs: {A} y {B}.
Evalúa cada uno contra los criterios de forma independiente.
Determina ganador por criterio y ganador global.
NO revelar cuál es A o B hasta el veredicto final.
Formato: tabla comparativa + veredicto justificado.
```

## 6. Template de Output

```markdown
# Evaluación G-Eval — {fichero}
Fecha: {YYYY-MM-DD} | Tipo: {tipo} | Criterios: {n}

## Score Global: X.X/10

## Detalle por Criterio
| Criterio | Peso | Score | Justificación |
|----------|------|-------|---------------|

## Mejoras Sugeridas
1. [criterio con score < 7]: [mejora concreta]

## Metadata
Evaluador: Claude {model} | Criterios: {fuente}
```

## 7. Banner de fin

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
✅ /eval-output — Completado
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📄 Evaluación: output/evals/YYYYMMDD-eval-{nombre}.md
📊 Score: X.X/10 | Mejoras: N sugeridas
⚡ /compact
```

## Restricciones

- Solo lectura — no modifica el output evaluado
- Score orientativo, no sustituye juicio humano
- **SIEMPRE subagente** para evaluaciones (proteger contexto)
