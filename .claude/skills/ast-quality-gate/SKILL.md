---
layer: peripheral
name: ast-quality-gate
description: Usar cuando se verifica la calidad de código generado por IA antes de merge.
allowed-tools: [Bash, Read, Glob, Grep, Write]
metadata:
  # --- metadata.savia.* (SE-333) ---
  savia.agent: code-reviewer
  savia.maturity: stable
  savia.category: quality
  savia.context: fork
  savia.maturity: experimental
  savia.priority: high
  savia.summary: "Meta-analizador AST para 16 lenguajes. Detecta patrones de error LLM (async sin await, N+1, null deref, magic numbers, catch vacio). Output JSON unificado con score 0-100 y gates QG-01..QG-12. Invocable como CLI, hook o skill bajo demanda."
  savia.tags: "ast, static-analysis, quality-gates, llm-patterns, sdd"
---

# AST Quality Gate — Verificación de Calidad Multi-Lenguaje

Sistema de quality gates para verificar código generado por IA en los 16
language packs de pm-workspace. Detecta los 5 patrones de error más comunes
en código LLM-generado y 7 criterios universales adicionales.

## Cuándo usar

- Post-implementación SDD: verificar código antes de PR
- Pre-commit hook: bloquear patrones críticos
- `/ast-quality-gate {fichero-o-directorio}` — bajo demanda
- `PostToolUse` hook async tras `Edit|Write` en SDD sessions

## Arquitectura de 3 Capas

```
Capa 1: Herramienta nativa del lenguaje (máxima precisión)
  → eslint/ruff/golangci-lint/cargo clippy/dotnet build/phpstan/...
  → Output: JSON nativo normalizado

Capa 2: Semgrep (cobertura universal de patrones LLM)
  → rules/llm-antipatterns.yaml (8+ lenguajes simultáneos)
  → Output: semgrep JSON normalizado

Capa 3: LSP Claude Code (semántica real-time)
  → 11 lenguajes (dic 2025)
  → tipo nulo, símbolo no resuelto, import no usado
```

## 12 Quality Gates

| Gate | Patrón | Severidad |
|------|--------|-----------|
| QG-01 | Async/concurrencia sin manejo de errores | error |
| QG-02 | N+1 queries / acceso DB en loop | error |
| QG-03 | Null/nil/None dereference sin check | error |
| QG-04 | Magic numbers/strings sin nombre | warning |
| QG-05 | Exception handling vacío o excesivamente amplio | error |
| QG-06 | Complejidad ciclomática > 15 | warning |
| QG-07 | Función/método > 50 líneas | warning |
| QG-08 | Duplicación de código > 15% | warning |
| QG-09 | Credenciales/secrets hardcodeados | error |
| QG-10 | Logging excesivo en producción | warning |
| QG-11 | Código muerto / imports no usados | info |
| QG-12 | Lógica nueva sin tests | error |

## Pipeline de Ejecución

### Paso 1: Detectar lenguaje

`scripts/ast-quality-gate.sh` detecta por extensión/fichero de proyecto (16 lenguajes).

### Paso 2: Ejecutar herramienta nativa

Ver comandos por lenguaje en `references/language-commands.md`.

### Paso 3: Ejecutar Semgrep (patrones LLM)

```bash
semgrep --config .opencode/skills/ast-quality-gate/references/semgrep-rules.yaml \
        --json --no-git-ignore "$TARGET"
```

### Paso 4: Normalizar a JSON unificado

Ver `references/unified-schema.md` para el schema completo.
Output en `output/quality-gates/YYYYMMDD-HHMMSS-{lenguaje}.json`

### Paso 5: Calcular score y veredicto

```
score = 100 - (errores × 10) - (warnings × 3) - (infos × 1)  [min 0]
```

| Score | Grade | Veredicto |
|-------|-------|-----------|
| 90-100 | A | PASS: listo para PR |
| 75-89 | B | PASS_WITH_WARNINGS: PR con advisory |
| 60-74 | C | REVIEW: requiere revisión human |
| 40-59 | D | FAIL: corregir antes de PR |
| 0-39 | F | BLOCK: bloquear commit |

## Integración SDD

### PostToolUse hook (async)

```json
{
  "hooks": {
    "PostToolUse": [{
      "matcher": "Edit|Write",
      "command": ".opencode/hooks/ast-quality-gate-hook.sh",
      "async": true
    }]
  }
}
```

### Umbral de bloqueo

Gates QG-01, QG-03, QG-05, QG-09, QG-12 son **bloqueantes** (exit 1).
Gates QG-02, QG-04, QG-06, QG-07, QG-08, QG-10, QG-11 son **advisory**.

## Uso manual

```bash
bash scripts/ast-quality-gate.sh src/               # completo
bash scripts/ast-quality-gate.sh src/ --semgrep-only # solo Semgrep
bash scripts/ast-quality-gate.sh src/ --native-only  # solo nativo
bash scripts/ast-quality-gate.sh src/ --advisory     # sin bloqueo
```

## Prerequisitos

- `semgrep` ≥ 1.60.0 (`pip install semgrep`)
- Herramienta nativa del lenguaje instalada (ver `references/language-commands.md`)
- `jq` para normalización JSON

## Esquemas y referencias

- `references/unified-schema.md` — Schema JSON unificado y jq transformations
- `references/semgrep-rules.yaml` — 20 reglas Semgrep por lenguaje
- `references/language-commands.md` — Comandos CLI por lenguaje
