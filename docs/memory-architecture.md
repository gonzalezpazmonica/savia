# Memory Architecture — SE-257 Slice 2

> Modelo canonico de memoria de Savia. Decision explicita por paradigma.
> Fecha: 2026-07-07. Version: v1.

## Paradigmas y su clasificacion

Una fila solo dice `Cableado` si la columna Consumidor da `fichero:linea` y esa
linea nombra el script (lo comprueba `tests/scripts/test_memory_architecture_wiring.py`).
Lo que nada invoca figura como `Sin invocador`.

| Paradigma | Clasificacion | Script/Archivo | Consumidor (fichero:linea) | Decision |
|---|---|---|---|---|
| Memoria externa (auto) | canonico | memory-store.sh | .claude/hooks/memory-auto-capture.sh:13 | Cableado |
| Memoria externa (manual) | canonico | memory-store.sh | .claude/commands/memory-recall.md:30 | Cableado |
| Bitemporal | canonico | memory-bitemporal.py | ninguno (solo sus tests) | Sin invocador: el ledger SE-255 S3 no lo llama |
| Higiene de memoria | canonico | memory-hygiene.sh | .claude/hooks/session-init.sh:355 | Cableado |
| Canary check | canonico | memory-canary-check.sh | .claude/hooks/session-init.sh:370 | Cableado |
| Conflict check | canonico | memory-conflict-check.sh | scripts/memory-save.sh:250 | Cableado |
| Status check | canonico | memory-status-check.sh | ninguno | Sin invocador: uso manual |
| Capture (relacion) | canonico | relacion-capture.sh | ninguno (solo sus tests) | Sin invocador |
| Report (relacion) | canonico | relacion-report.sh | ninguno (solo sus tests) | Sin invocador |
| Liveness check | canonico | memory-liveness-check.sh | .github/workflows/ci.yml:150 | Cableado |
| Verificacion de principal | canonico | verify-principal.sh | ninguno (CRIT-031 lo cita como enforcement) | Sin invocador |
| obsidian-export (ext) | satelite | external/engram | TUI | Externo, no mantener |

## Archivados

| Script | Origen | Motivo |
|---|---|---|
| save-nudge.sh | SE-256 S1 | Nunca se registro como hook; `memory-auto-capture` ya captura por ediciones. |
| relacion-detect-conflicts.sh | SE-256 S2 | Lee `data/relacion/ledger.jsonl`, que ningun flujo escribe; sin consumidor. |

Quedan en el historial de git.

## Decisiones

1. **memory-bitemporal.py no esta cableado al ledger**: SE-255 S3 declaraba la
   dependencia, pero ningun script del ledger lo invoca. Pendiente de cablear o archivar.

2. **Huerfanos conocidos**: esta revision encontro cinco scripts sin invocador
   (tabla), pese a la auditoria de SE-257. `memory-liveness-check.sh` cuenta
   referencias textuales, no invocaciones.

3. **Requirements podados**: requirements-vector.txt y
   scripts/requirements-memory.txt contienen solo imports vivos.

4. **Guard permanente**: memory-liveness-check.sh en CI (SE-257 S4) y el test de
   cableado de este documento.
