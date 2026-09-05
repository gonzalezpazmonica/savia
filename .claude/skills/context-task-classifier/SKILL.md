---
layer: peripheral
name: context-task-classifier
description: Usar antes de compactar contexto para clasificar la tarea del turno actual.
metadata:
  # --- metadata.savia.* (SE-333) ---
  savia.input: text
  savia.maturity: stable
  savia.output: json
---

# context-task-classifier

Clasificador determinístico de turnos para rate-distortion-aware compression
(SE-029). Cada clase tiene un ratio máximo de compresión y una marca
`frozen` que indica si el contenido queda exento de compactación.

## Input

Un turno de conversación (texto, markdown, diff, o stack trace) pasado
por `--stdin` o `--input FILE`.

## Output

Una sola línea con la clase (modo texto) o JSON con detalles (modo `--json`):

```json
{
  "class": "decision",
  "max_ratio": 5,
  "frozen": "true",
  "words": 4,
  "lines": 1,
  "scores": {
    "decision": 3,
    "spec": 0,
    "code": 0,
    "review": 0,
    "context": 0,
    "chitchat": 0
  }
}
```

## 6 clases de tarea

| Clase | max_ratio | frozen | Señales principales |
|---|---|---|---|
| `decision` | 5:1 | true | APPROVED/merge/commit, yes/no verdicts |
| `spec` | 3:1 | true | SPEC-NNN, SE-NNN, PBI-NNN, AC-MM, frontmatter |
| `code` | 10:1 | partial | fences ```, diff markers, Traceback/Error |
| `review` | 15:1 | false | PASS/FAIL/WARN, G\d+ gates, judge findings |
| `context` | 25:1 | false | markdown largo, headings, bullets, >100 words |
| `chitchat` | 80:1 | false | ≤8 words, thanks/ok/gracias/hi |

## Ejemplos de uso

```bash
# Clasifica un mensaje de chat
echo "APPROVED — merge PR #624" | scripts/context-task-classify.sh --stdin
# → decision

# Clasifica un diff file en JSON
scripts/context-task-classify.sh --input /tmp/pr.diff --json

# Integración con context-budget (SE-029 Slice 4, futuro):
#   foreach turn in session:
#     class = classify(turn)
#     apply max_ratio[class] when compacting
#     skip if frozen[class]
```

## Reglas de clasificación

1. **Scoring aditivo** — cada patrón matched suma puntos a su clase.
2. **Tie-breaking por prioridad** — empates se resuelven a favor de la
   clase más estricta (decision > spec > code > review > context >
   chitchat). Err del lado de preservar contenido.
3. **Fallback** — sin señal: ≤15 words → chitchat, else context.

## Integración con SE-029

Este clasificador es el input del **operational point selector**
(SE-029-O, Slice 4) que elige R(D) óptimo por turn:

```
Turn → classify() → max_ratio_class
                 → frozen? → compress-skip-frozen.sh hook
                 → else: compress(ratio = min(budget_target, max_ratio_class))
```

## Ref

- `scripts/context-task-classify.sh` — implementación
- `tests/test-context-task-classify.bats` — 34 tests (auditor score 98)
- `docs/propuestas/SE-029-rate-distortion-context.md` §2
- `scripts/context-distortion-measure.sh` — SE-029 Slice 1 (distortion metric)
