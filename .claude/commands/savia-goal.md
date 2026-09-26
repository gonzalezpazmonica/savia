---
name: savia-goal
description: Establece, gestiona y persigue objetivos persistentes cross-turn — equivalente Savia de /goal de Codex
model_tier: mid
context_cost: low
tier: core
---

Objetivo: $ARGUMENTS

## /savia-goal

Equivalente Savia del `/goal` de Codex CLI 0.128.0. Goal persistente cross-turn con máquina de estados y verificación obligatoria (Rule #22).

**Subcomandos:** `set`, `pause`, `resume`, `clear`, `status`, `history`. Si no hay argumentos → `status`.

**Fichero canónico:** `.savia-memory/goals/current.json` · **Historial:** `.savia-memory/goals/history.jsonl`

## Schema current.json

```json
{"id":"goal-YYYYMMDD-NNN","objective":"...","state":"pursuing|paused|achieved|blocked|budget_exceeded","created_at":"ISO8601","updated_at":"ISO8601","paused_at":"ISO8601|null","achieved_at":"ISO8601|null","turns_spent":0,"estimated_turns":null,"budget_limit_turns":40,"block_reason":null,"verification_rounds":0,"sprint_ref":"Sprint-YYYY-NN|null","pbi_ref":"AB#XXXX|null"}
```

## Máquina de estados

`set` → pursuing → (pause) → paused → (resume) → pursuing · pursuing → (verify+confirm) → achieved · pursuing → (budget exceeded) → budget_exceeded · pursuing → (blocker) → blocked · clear → history.jsonl

## Bugs de Codex prevenidos desde día 1

1. **Pérdida post-compact (#19910):** Goal en memoria canónica externa, no en contexto de chat. Inmune a compaction.
2. **Goal-first invisible (#20792):** Auto-memory carga goal al inicio de sesión. Independiente del primer mensaje.
3. **Plan mode silencioso (#20656):** Si plan mode activo, mostrar "Goal pausado en Plan mode. Usa /savia-goal resume al salir."
4. **Falta completion audit (#19910):** Rule #22: verification_rounds >= 1 obligatorio antes de marcar achieved.

## Subcomandos

### set `<objetivo>` (default si texto libre)
1. Leer `current.json`. Si existe y state es pursuing|paused → error: "Ya hay goal activo."
2. Extraer objetivo. Detectar Sprint YYYY-NN y AB#XXXX.
3. Estimar turns: simple/fix=5, feature/implementar=15, refactor/migrar=30.
4. budget_limit = estimated * 2.5. Crear current.json + entry en history.jsonl.
5. Confirmar: "Goal establecido: {obj} · {estimated} turns · Máx {budget}"

### pause
Cambiar state a paused, guardar paused_at. Confirmar "🟡 Goal pausado."

### resume
Cambiar state a pursuing, limpiar paused_at. Confirmar "🟢 Goal reanudado: {obj} [{turns}/{budget}]"

### clear
Preguntar confirmación. Mover a history.jsonl como `cleared`. Borrar current.json.

### status (sin args)
Leer current.json. Si no existe: "No hay goal activo. Usa /savia-goal set <objetivo>."
Si existe:
```
{emoji} Savia Goal — {state_label} desde {created_at}
Objetivo: "{objective}" · Estado: {state}
Turns: {turns}/{budget} · Verificaciones: {verifications}/1
Sprint: {sprint} · PBI: {pbi}
```
Emojis: 🟢 pursuing · 🟡 paused · ✅ achieved · 🔴 blocked · ⚠️ budget_exceeded

### history [N]
Leer history.jsonl. Mostrar últimos N (default 10): timestamp | event | state | objective_truncado_60.

## Integración con flujo Savia

Al inicio de cada turno, Savia ejecuta `bash scripts/savia-goal.sh auto-inject`:
- pursuing → Inyecta goal en contexto: "GOAL ACTIVO: {obj} [{turns}/{budget}]. Verifica progreso al final."
- paused → "GOAL PAUSADO: {obj}. Usa /savia-goal resume."
- budget_exceeded → "GOAL EXCEDIDO. Usa /savia-goal clear o ajusta presupuesto."
- blocked → "GOAL BLOQUEADO: {obj}. Razón: {reason}"

Al final de cada turno, `bash scripts/savia-goal.sh advance`:
- Incrementa turns_spent
- Al 80% del presupuesto: advierte
- Al 100%: cambia automáticamente a budget_exceeded

## Budget guard

- default 40 turns (hereda SDD_DEFAULT_MAX_TURNS)
- Alerta al 80%: "⚠️ Goal al 80% del presupuesto ({n}/{max} turns). ¿Ajustar?"
- Bloqueo al 100%: state → budget_exceeded automático

## Diferencias con comandos adyacentes

| Comando | Propósito | vs /savia-goal |
|---|---|---|
| /sprint-plan | Planificar sprint | Goal = un objetivo dentro del sprint |
| /pbi-decompose | Descomponer PBI | Goal persigue, no descompone |
| /spec-implement | Implementar spec SDD | Goal puede abarcar múltiples specs |
| /overnight-sprint | Modo nocturno autónomo | Goal es la unidad que overnight ejecuta |

## Script

`scripts/savia-goal.sh` implementa CRUD completo: status, set, pause, resume, clear, history, advance, verify, auto-inject.

## Referencias

- Codex: PRs #18073-#18077, issues #20536 #19910 #20792 #20656
- Savia: Rule #22 (Verification Before Done), Rule #3 (Confirmar antes de escribir)
- Spec: docs/propuestas/SPEC-SAVIA-GOAL-command.md
