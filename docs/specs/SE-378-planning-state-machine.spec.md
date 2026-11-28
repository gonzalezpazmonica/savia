# SE-378 — Planning State Machine

**Estado:** IMPLEMENTED — aprobada por la operadora 2026-09-05; graduada 2026-11-21 (pregunta interactiva, PR de evidencia #1635)
**Prioridad:** P1 · **Developer Type:** agent-single · **Context Risk:** medium
**Origen:** auditoría externa §9 (PARTIALLY_ALREADY_SOLVED — extiende SE-222)

## 1. Motivación

`scripts/spec-lifecycle.sh` (SE-222) ya da transiciones de estado + LOG.md append-only a las specs, pero el estado global de iniciativas sigue repartido en documentos narrativos que mezclan historia, eras, backlog y prioridades: `docs/ROADMAP.md`, `docs/propuestas/ROADMAP-UNIFIED-20260827.md`, `docs/propuestas/INDEX.md`, specs sueltas. La prioridad termina dependiendo de interpretación (F4).

## 2. Alcance

Una única representación machine-readable del ciclo de vida de las iniciativas, de la que los roadmaps pasan a ser **vistas generadas**.

### Estados

`IDEA → PROPOSED → APPROVED → IMPLEMENTING → IMPLEMENTED` · terminales: `REJECTED | SUPERSEDED | DEFERRED | RETIRED`

## 3. Reglas

- Una iniciativa = un estado actual. Transiciones append-only (reconstruibles desde LOG.md de SE-222).
- `APPROVED` requiere aprobación humana registrada. `IMPLEMENTED` requiere evidencia commit/PR mergeado.
- IDs únicos; no se vuelve de IMPLEMENTED a PROPOSED; reemplazo → SUPERSEDED con `replaced_by`.
- Las specs de esta era (SE-375..384) nacen aquí como PROPOSED.

## 4. Vistas y CLI conceptual

```
roadmap current     # iniciativas activas con estado
roadmap next        # candidatas ordenadas por prioridad/dependencias
roadmap history SE-xxx
roadmap validate    # estados conflictivos, ID collision, IMPLEMENTED sin
                    # evidencia, APPROVED sin approval, vuelta atrás desde IMPLEMENTED
                    # (prioridades contradictorias: sin comprobar, ver §6)
```

## 5. Criterios de aceptación

- `roadmap validate` detecta los 5 tipos de inconsistencia (fixtures por cada una).
- Roadmaps narrativos actuales marcados como vista/histórico con provenance al estado.
- Toda transición queda en LOG.md (append-only, SE-222).

## 6. OpenCode Implementation Plan

### Clasificación
- **Tier:** 2 · **Agent-capable:** yes
- **Slices:** S1 planning-state.json canónico + populate era actual · S2 CLI roadmap current/next/history/validate · S3 vista generada ROADMAP-CURRENT.md

## Referencias

- Auditoría externa §9 · SE-222 `spec-lifecycle.sh` · `docs/propuestas/LOG.md`

## 6. Resto tras la graduación (2026-11-27)

- **No volver de IMPLEMENTED**: `roadmap validate` lo comprueba sobre LOG.md (fechas estrictamente posteriores a la primera IMPLEMENTED; salidas legítimas SUPERSEDED/RETIRED/REJECTED/DEFERRED). El orden dentro de un mismo día no se evalúa.
- **Roadmaps narrativos**: `ROADMAP-UNIFIED-20260827.md` marcado SUPERSEDED y `docs/ROADMAP.md` avisa de que su bloque de prioridad única es histórico.
- **Prioridades contradictorias: NO comprobadas.** `planning-state.json` no guarda dependencias entre iniciativas y la prioridad de cada sesión de la cola difiere de la de sus iniciativas en muchos casos legítimos; sin un campo `depends_on` no hay contradicción verificable. Decisión pendiente de la operadora: añadir `depends_on` al esquema (y la comprobación) o retirar ese requisito de los AC.
