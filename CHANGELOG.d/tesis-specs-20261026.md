---
version_bump: patch
section: Added
---

### Added

- Seis specs desde tres tesis, todas APPROVED por la operadora (SE-468 el 2026-10-26; SE-469..SE-473 el 2026-10-27 por AskUserQuestion, de SE-473 solo S0): SE-468 gate de evals que puede fallar (P0), SE-469 tribunales medidos con sus golden sets (P1), SE-470 integridad de artefactos de evaluación (P2), SE-471 relevo nocturno con evidencia (P1), SE-472 vigencia de la autoridad por tarea nocturna (P2) y SE-473 lecciones contrastables (P2).
- Deltas 2026-10-26 en SE-449 (estados rejected y estimated), SE-461 (criterio para escalar a solver) y SE-406 (horas de silencio como AC); sesiones S18..S20 en la cola del roadmap.
- `roadmap.sh validate` rechaza una entrada de sesión que todavía pide aprobar una spec ya APPROVED o posterior (check 10); corregidas las entradas S10, S11, S12, S17 y S18.
- Check 10 de `roadmap.sh validate`: comprueba todas las specs de una enumeración («Aprobación de SE-A y SE-B»), no trata DEFERRED como resuelta y falla cerrado si jq no puede evaluarlo. SE-468 AC7 pasa a condicional (decisión de la operadora 2026-10-26); el `findings` con sabotaje es criterio de salida de SE-469.
- Check 10 ampliado: reconoce variantes léxicas («Aprobacion», «aprobar SE-N», «approval of SE-N», enumeraciones con «/») y peticiones genéricas («Aprobación de cada spec») cuando todas las iniciativas de la sesión ya están resueltas; corregidas las entradas S19 y S20.
