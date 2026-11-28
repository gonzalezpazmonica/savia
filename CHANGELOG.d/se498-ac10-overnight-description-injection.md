---
version_bump: patch
section: Fixed
---

### Fixed

- Seguridad (SE-498 AC-10): el bucle nocturno (`scripts/overnight-sprint-loop.sh`) metía la descripción de la tarea dentro de `bash -c "…"`; una comilla simple en la descripción ejecutaba órdenes arbitrarias y la tarea contaba como hecha. Ahora los argumentos van como posicionales (`bash -c 'run_agent_task "$@"' …`) con `run_agent_task` exportada (antes el hijo no la encontraba y toda tarea real salía con 127), el bucle se niega a arrancar sin `timeout`/`gtimeout` en lugar de correr sin límite, los respaldos en Python leen por argv y el audit log escapa los saltos de línea para que una descripción no falsifique entradas.
