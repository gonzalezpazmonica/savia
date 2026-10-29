---
status: APPROVED
priority: P0
developer_type: agent-single
created: 2026-10-30
approved_at: 2026-10-30
author: Savia
phase: D
risk: L2
related_specs: [SE-410, SE-481, SE-482]
origin: incidente 2026-10-21→30 (RAG con enabled:false nueve días sin alerta; PR #1416 cubre la parte de SLO) y orden de la operadora 2026-10-30 «el MCP siempre online, el RAG tiene que funcionar de forma autónoma»; opción elegida por AskUserQuestion: recarga en caliente + servicio sincronizador (sin cambiar la configuración MCP de los frontends)
timeline:
  - from: "2026-10-30"
    learned: "2026-10-30"
    value: "APPROVED"
    source: "spec-lifecycle:auto"
---
# SE-480 — Vaults: RAG autónomo (recarga del registro y sincronización por el servicio)

## Problema (verificado 2026-10-30)

- **El registro se lee una sola vez.**
  - Cada sesión de Claude Code u OpenCode arranca su propio proceso `serve --transport mcp`.
  - Ese proceso lee `savia-vaults.domes.json` al arrancar y no lo vuelve a leer.
  - Tras reactivar el RAG (`rag.enabled:true`), el MCP de la sesión abierta seguía informando `enabled:false` en todas las cúpulas.
  - Lo mismo le pasa al servicio A2A de systemd (`savia-vaults.service`).
- **Solo el cron mantiene el índice al día.**
  - El índice se actualiza únicamente con el cron de 6 h. Si el cron falla, o no hay cúpulas habilitadas, nada lo sustituye.
  - #1416 hace visible el fallo en el SLO, pero no lo repara.
- **El servicio no se reinicia en todos los casos.** `Restart=on-failure` no cubre una salida limpia inesperada.

## Requisitos

### R1 — Recarga del registro en caliente

- `DomeRegistry.reloadIfChanged(): boolean` compara `mtimeMs`, `size` e `ino` del fichero de cúpulas y de su fichero local, si existe, con los de la última carga.
- Si cambian, recarga. Si el fichero nuevo no parsea o no valida, conserva el último registro válido, registra el error en stderr y lo expone en `vault_health` y en `vault_rag_status` (`registry.error`).
- El MCP (cada llamada a herramienta) y A2A (cada petición) llaman a `reloadIfChanged()` antes de resolver cúpulas. La comprobación cuesta un `stat` por fichero y se limita a una vez por segundo.
- `RagService`, los `VaultInstance` y los controladores de acceso ven el registro nuevo en la llamada siguiente:
  - una cúpula eliminada deja de servirse;
  - una cúpula con `rag.enabled` cambiado cambia de estado;
  - una cúpula nueva aparece.
- `vault_rag_status` añade `registry: { file, loadedAt, mtime, error? }` para que la frescura del registro sea visible.

### R2 — Sincronización autónoma en el servicio

- `serve --transport a2a --rag-autosync <minutos>` (desactivado por defecto) lanza en el proceso del servicio un sync incremental de las cúpulas con `rag.enabled:true`:
  - al arrancar, tras un retardo de 30 s;
  - cada N minutos;
  - cuando `reloadIfChanged()` detecta un cambio que habilita una cúpula.
- Usa el lock existente (`acquireLock`). Si otro proceso, por ejemplo el cron, tiene el lock, el ciclo se salta y se registra como `skipped:LOCKED`.
- Nunca hay dos ciclos solapados en el mismo proceso.
- Un ciclo fallido (Ollama caído, error de E/S) no tumba el servicio:
  - se registra;
  - la recuperación sigue degradando a BM25 como hoy;
  - el estado del último ciclo (`lastRunAt`, `lastOk`, `lastError`, `consecutiveFailures`) aparece en `vault_rag_status` (`autosync`);
  - con 3 fallos seguidos, `slo.ok:false` y una alerta `autosync-failing`.
- El sync autónomo **no** promueve generaciones nuevas por reconstrucción completa: hace solo el incremental de la generación activa, con las mismas reglas que `rag sync` sin `--rebuild`. La reconstrucción semanal sigue en el cron.

### R3 — Servicio siempre en pie

- La plantilla versionada de la unidad (`projects/savia-vaults/deploy/savia-vaults.service`, nueva) incluye:
  - `Restart=always`, `RestartSec=5`;
  - `--rag-autosync 15`;
  - el hardening actual (`NoNewPrivileges`, `MemoryMax`, solo loopback).
- La documentación (`docs/rag.md` o el README del proyecto) explica cómo instalarla en `~/.config/systemd/user/`.
- La instalación en la máquina de la operadora la hace la orquestadora, fuera de la PR.

### R4 — El cron queda como respaldo

El cron de 6 h y el checkpoint semanal no cambian. Con el lock, cron y servicio no se pisan.

## Criterios de aceptación

- **AC-1:** un MCP en marcha con una cúpula `rag.enabled:false` informa `enabled:true` en la llamada siguiente a reescribir el fichero, sin reiniciar el proceso (test e2e con el servidor MCP en proceso).
- **AC-2:** si se elimina una cúpula del fichero, el MCP y A2A dejan de servirla en la llamada siguiente.
- **AC-3:** un fichero de registro corrupto conserva el último válido y `vault_rag_status.registry.error` lo expone.
- **AC-4:** con `--rag-autosync`, una nota nueva en una cúpula habilitada aparece en `vault_rag` tras un ciclo, sin cron (test con reloj falso o intervalo corto y embedder falso).
- **AC-5:** con el lock tomado por otro proceso, el ciclo termina en `skipped:LOCKED` y el servicio sigue.
- **AC-6:** tras 3 fallos seguidos del embedder, `slo.ok:false` con la alerta `autosync-failing`. La búsqueda sigue respondiendo en modo BM25.
- **AC-7:** los tests de AC-1, AC-2, AC-4 y AC-6 fallan contra main.
- **AC-8:** sin `--rag-autosync`, el comportamiento es idéntico al de main (no arranca ningún temporizador).

## Fuera de alcance

- MCP por HTTP con un proceso único compartido: descartado por la operadora el 2026-10-30, por coste y superficie.
- Vigilancia por inotify de cada nota. El intervalo de 15 min basta y es más simple.

## Rollback

Revert de la PR y volver a la unidad anterior. Sin estado persistente nuevo: el sync usa el almacén existente.

## OpenCode Implementation Plan

### Bindings touched

| Componente | Claude Code | OpenCode v1.14 |
|---|---|---|
| Servidor MCP savia-vaults | `~/.claude.json` mcpServers (stdio) | `opencode.json` mcp (stdio), mismo binario |
| Servicio A2A + autosync | systemd de usuario, independiente del frontend | idéntico |

### Verification protocol

- [ ] La recarga funciona igual con cualquier frontend: está en el servidor y no depende del cliente
- [ ] Tests vitest del servidor
- [ ] No añade hooks

### Portability classification

- [x] **PURE_BASH** (equivalente: lógica en el servidor MCP/A2A, independiente del frontend)
