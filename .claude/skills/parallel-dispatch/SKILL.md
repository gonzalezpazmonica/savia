---
layer: peripheral
name: parallel-dispatch
description: Usar cuando se necesitan subagentes en paralelo con admission-handle — lanza N tareas en background y recoge resultados después, sin bloquear el turno padre. Triggers: lanza subagentes en paralelo, paraleliza esto, admission-handle, recoge resultados.
metadata:
  # --- metadata.savia.* (SE-333) ---
  savia.category: orchestration
  savia.maturity: stable
  savia.context: standalone
  savia.context_cost: low
  savia.maturity: beta
  savia.priority: medium
  savia.tags: "parallel, subagents, admission-handle, orchestration"
  savia.trigger_keywords: "paralelo, parallel, subagentes, lanza en background"
---

# Skill: Parallel Dispatch (admission-handle)

Patrón extraído de Prime Agent (SE-347): `await rlm("tarea")` devuelve un
**handle de admisión inmediato** (nunca espera la respuesta). Savia lo
implementa con `scripts/parallel-dispatch.sh` sobre `opencode run` en
background (o cualquier comando).

## Authoritative Paths

> Lee estos paths antes de actuar.

| Para | Lee este path |
|---|---|
| Script de despacho | `scripts/parallel-dispatch.sh` |
| Resultados (runtime) | `~/.savia/dispatch/` |
| Regla de autonomía | `docs/rules/domain/autonomous-safety.md` |
| Lección origen | `output/research/prime-agent-eval/lecciones-prime-agent-20260827.md` |

## Cuándo usar

- Tienes N subagentes/tareas independientes (revisiones, digests, búsquedas)
  que hoy lanzarías en serie o con dag-scheduling.
- El turno padre debe continuar sin esperar el resultado completo.
- Resultados: cada tarea escribe su output en un fichero conocido.

## Cuándo NO usar

- Necesitas el resultado en el MISMO turno (usa Task tool bloqueante).
- Hay dependencias entre tareas (usa dag-scheduling).
- La tarea toca el mismo fichero que otra (concurrencia de escritura).

## Flujo

1. **launch** cada tarea (id único, dir, comando):
   ```bash
   bash scripts/parallel-dispatch.sh launch --id api-review \
     --dir /home/monica/savia \
     --cmd 'opencode run --format json "Revisa la API; escribe resumen en output/review-api.md"'
   ```
   Devuelve el id AL INSTANTE (handle). No esperes el resultado.
2. Termina tu turno; los trabajos corren en background (disco propio).
3. En un turno posterior, **status** y **collect**:
   ```bash
   bash scripts/parallel-dispatch.sh status --all --quiet
   bash scripts/parallel-dispatch.sh collect --all --fail-fast
   ```
   `collect` muestra stdout de cada job completado; `--fail-fast` marca error si
   alguno falló.
4. **clean** cuando hayas agregado los resultados.

## Reglas

- CRIT-001: resultados en `~/.savia/dispatch` (disco propio). Nunca en el repo.
- Timeout por job (`--timeout N`, default 3600s) — un job colgado no debe
  quedarse vivo para siempre.
- No lances más de ~4 jobs a la vez con el mismo modelo local (evita
  saturación de Ollama/GPU).
- Los jobs en background NO tienen supervisión humana en tiempo real: aplica
  `autonomous-safety.md` (PRs Draft, revisión humana de outputs).

## Related

- `scripts/parallel-dispatch.sh` · `dag-scheduling` (dependencias) ·
  `agent-messaging` (recoger por mensaje en vez de fichero)
