---
version_bump: minor
section: Added
---

### Added

- SE-396 H09: primer adaptador real del contrato de ejecutores (Codex): capacidades desde la ficha de runtime, recibo de lo observado (rc 0 no es veredicto de efecto), ejecutor caído = desconocido, y punto de llamada codex_launch.py
- Con plazo vencido, codex_launch.py cancela en síncrono y espera al recibo parcial antes de salir: ningún Codex queda huérfano, tampoco el que ignora SIGTERM
- Se bloquean run_dir dentro del worktree (falso efecto), argumentos que alterarían la orden (effort fuera de lista, valores con guion inicial) y la cancelación previa al lanzamiento
- La huella del worktree no sigue enlaces ni abre FIFOs, parsea bien los renombrados y `cambios` lista solo lo cambiado en esta ejecución

