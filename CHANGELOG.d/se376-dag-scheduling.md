---
version_bump: patch
section: Fixed
---

### Fixed

- SE-376: dag-scheduling calibrada con tests de comportamiento del motor `scripts/wave-executor.sh` (93, certificado). Fallos reales corregidos: `max_parallel` 0 o no numérico, un grafo sin `tasks` o una tarea sin `depends_on` terminaban en «success» sin ejecutar nada; una tarea que ignoraba SIGTERM colgaba el motor para siempre; un id con espacios se partía en dos tareas inexistentes; una tarea que salía con 124 se contaba como timeout; interrumpir el motor dejaba las tareas huérfanas; `--report` sin valor fallaba con «unbound variable». El motor lee ya `SDD_MAX_PARALLEL_AGENTS` y `SDD_DEFAULT_TIMEOUT_MIN`, que la skill documentaba sin efecto.
