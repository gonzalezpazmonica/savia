---
layer: peripheral
name: context-rot-strategy
description: Usar cuando una sesión larga se aproxima al límite de contexto y hay que decidir qué compactar.
allowed-tools: [Read, Bash]
metadata:
  # --- metadata.savia.* (SE-333) ---
  savia.category: context-engineering
  savia.maturity: stable
  savia.disable-model-invocation: false
  savia.maturity: beta
  savia.priority: high
  savia.summary: "Meta-skill para gestionar context rot en sesiones con ventanas de 1M tokens (Opus 4.7). Rutea entre 5 opciones de gestion de contexto per turno: continue, rewind, /compact con hint, /clear, subagent. Propone proactive compact por encima de 75% antes de auto-compact."
  savia.tags: "context, 1M, rot, compact, session, opus-4-7"
  savia.user-invocable: True
---

# Context Rot Strategy — Skill

> Ventanas de 1M tokens no garantizan 1M de atencion efectiva. La inteligencia del modelo degrada mucho antes del limite fisico. Este skill elige la opcion correcta per turno.

## Por que existe

Opus 4.7 + 1M context habilita sesiones largas. Pero **context rot** es real: a medida que el contexto se llena, la atencion se dispersa, el contenido antiguo distrae del task actual, y el modelo se vuelve menos inteligente antes de tocar el limite duro.

La pregunta correcta no es *"cuanto cabe?"* sino *"cuando cortar?"*.

## Modelo mental — 5 opciones per turno

```
┌─────────────────────────────────────────────────────────┐
│  En cada turno, elige UNA de estas 5 acciones           │
└─────────────────────────────────────────────────────────┘

 1. Continue      →  relevancia intacta, sigue la sesion
 2. Rewind (⎋⎋)  →  drop failed attempts, keep file reads
 3. /compact hint →  lossy summary dirigido
 4. /clear        →  fresh session + notas manuales
 5. Subagent      →  delegar output grande, traer solo conclusion
```

## Decision Checklist

1. Necesitas el output de la tool otra vez, o solo la conclusion?
   - Solo conclusion → **Subagent**
   - Si, el output completo → mantener en contexto
2. Hay multiples intentos fallidos atascando el contexto?
   - Si → **Rewind** (double-Esc) al punto anterior al fallo
   - No → siguiente check
3. La sesion sigue enfocada en un mismo tema?
   - Si, larga pero coherente → **/compact con hint** especifico
   - No, cambio de tema → **/clear** + notas manuales
4. Token counter > 75%?
   - Si → accion proactiva AHORA (compact/clear/subagent)
   - 60-75% → yellow flag, planifica el corte
   - < 60% → **Continue**

## Umbrales de token usage

| % del context | Flag | Recomendacion |
|---|---|---|
| 0-60% | Verde | Continue libre |
| 60-75% | Amarillo | Planifica corte; usa subagents para proximos steps grandes |
| 75-90% | Rojo | Compact PROACTIVO antes de auto-compact (el modelo esta en su peor punto de atencion cuando auto dispara) |
| 90%+ | Critico | /clear + notas; no confies en compact automatico a este nivel |

Settings actual: `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=75` (ajustado para disparar antes del pico de rot).

## Opciones en detalle

### 1. Continue
Cuando la informacion del contexto sigue siendo util y has trabajado menos del 60%. Es el default. No lo fuerces si una de las otras 4 opciones aplica.

### 2. Rewind (double-Esc)
**Cuando**: intentaste algo, fallo, y el diagnostico ocupa mucho contexto.

**Beneficio vs "eso no funciono, prueba X"**: rewind descarta las lineas de diagnostico fallido, conservando las file reads utiles. Escribir "trata de nuevo con X" inflacciona el contexto con las lineas que querias olvidar.

### 3. /compact con hint
**Cuando**: sesion larga, un solo tema, necesitas seguir pero bajar ruido.

**Hint efectivo** (ejemplos):
- `/compact focus on the auth refactor, drop test debugging`
- `/compact keep the spec decisions, drop exploration dead-ends`
- `/compact retain the 3 file paths I'm editing, drop everything else`

Sin hint, el compact resume con sesgo al final de la sesion — frecuentemente es lo que no necesitas.

#### Formato estructurado de resumen (lección SE-347 / Prime Agent)

Usa este formato (PMA docs/compaction.md) para que el resumen sea recuperable:

```
## Goal · ## Progress (Done/In Progress/Blocked) · ## Key Decisions
## Next Steps · ## Critical Context
<read-files>   path/a.ts path/b.sh </read-files>
<modified-files> path/cambia.ts </modified-files>
```

Reglas:
- **Nunca cortar tool results** en el punto de corte (quedan con su llamada).
- **Tracking acumulativo de ficheros**: `<read-files>`/`<modified-files>` se
  acumulan entre compactaciones.
- **Truncar tool results a ~2000 chars** en el material a resumir.
- Compactación iterativa: **incluye el resumen anterior** como contexto.
- Hint dirigido: `/compact focus on <tema>, keep <ficheros>, drop <ruido>`.

### 4. /clear
**Cuando**: la sesion cambio de tema o llego al 90%+. Rompe limpio.

**Protocolo**:
1. Antes de /clear, anota manualmente en `session-journal.md`: tarea actual, decisiones tomadas, proximos pasos
2. /clear
3. Primera turno nuevo: lee `session-journal.md` + el fichero especifico donde sigues

### 5. Subagent
**Cuando**: la siguiente accion va a producir mucho output tool (grep masivo, multiples Reads, research con WebFetch).

Subagent tiene su propio context window fresco. Solo la conclusion vuelve al main thread. Util cuando vas a leer 20 ficheros pero solo necesitas el resumen.

## Anti-patrones

| Error | Por que es malo | Fix |
|---|---|---|
| Esperar a auto-compact | Se dispara cuando el modelo esta en su peor punto de atencion | Compact proactivo > 75% con hint |
| "Eso no funciono, intenta X" | Mantiene las lineas del fallo en contexto | Rewind al punto anterior, re-prompt |
| /clear sin notas | Pierdes continuidad de trabajo | Escribe session-journal.md antes |
| Subagent para cosa pequena | Overhead de spin-up sin beneficio | Subagent solo si output > 5K tokens |
| 10 compact en serie | Cada compact es lossy, 10 pierden mucho | Compact 1 vez bien > 10 veces mal |

## Invocacion

Como meta-skill, este skill no se ejecuta autonomamente. Sirve de rubrica mental antes de cada turno cuando la sesion se alarga. Invocacion tipica:

```
/skill context-rot-strategy
```

Muestra la decision checklist + umbrales actuales. El usuario decide la opcion.

Script helper: `scripts/context-rot-advisor.sh` — lee el % de context usage si esta disponible como env var y devuelve la recomendacion.

## Referencias

- Opus 4.7 migration guide — "Context rot is real. You have five options at every turn"
- Propuesta: `docs/propuestas/SE-069-context-rot-strategy-skill.md`
- Skills relacionadas: `context-optimized-dev`, `context-budget`, `context-compress`, `context-defer`
- Settings: `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=75` en `.claude/settings.json`
