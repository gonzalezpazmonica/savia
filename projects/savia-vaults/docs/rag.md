# RAG autónomo del servicio (SE-480)

El servidor de cúpulas mantiene su RAG sin intervención: relee el registro cuando cambia y el servicio sincroniza el índice por sí mismo. El cron de 6 h y el checkpoint semanal siguen siendo el respaldo y no cambian; cron y servicio no se pisan porque comparten el lock del indexador.

## Recarga del registro

`DomeRegistry.reloadIfChanged()` compara `mtimeMs`, `size` e `ino` del fichero de cúpulas y de su fichero `.local`. La llaman cada herramienta del MCP y cada petición de A2A, como mucho una vez por segundo (`SAVIA_VAULTS_RELOAD_MS` cambia el intervalo; `0` lo desactiva).

- Cúpula eliminada: deja de servirse en la llamada siguiente. Cúpula nueva o con `rag.enabled` cambiado: aparece o cambia de estado.
- Fichero que no parsea o no valida: se conserva el último registro válido, se escribe el error en stderr y `vault_rag_status` lo devuelve en `registry.error` (también lo añade `vault_health`).
- `vault_rag_status` incluye en cada cúpula `registry: { file, loadedAt, mtime, error? }`.

## Sincronización autónoma

```
savia-vaults serve --transport a2a --rag-autosync <minutos>
```

Desactivado por defecto: sin la opción no arranca ningún temporizador. Con ella, el servicio hace el sync incremental de las cúpulas con `rag.enabled:true` a los 30 s de arrancar, cada N minutos y cuando una recarga del registro habilita una cúpula.

- Si otro proceso tiene el lock (por ejemplo el cron), la cúpula se salta como `skipped:LOCKED`. Nunca hay dos ciclos solapados en el proceso.
- Solo hace el incremental de la generación activa, igual que `rag sync` sin `--rebuild`. La reconstrucción semanal sigue en el cron.
- Un ciclo fallido (Ollama caído, error de E/S) se registra y no tumba el servicio; la búsqueda sigue degradando a BM25.
- Estado del último ciclo (`lastRunAt`, `lastOk`, `lastError`, `consecutiveFailures`, `lastResults`): campo `autosync` de `status` en el proceso del servicio y resumen (sin textos de error) en `GET /health`. Con 3 fallos seguidos, `slo.ok:false` con la alerta `autosync-failing`.

El estado vive en el proceso del servicio: un MCP de sesión es otro proceso y no lo ve. Para vigilar el sincronizador, consulta `/health` del servicio.

## Servicio siempre en pie

La plantilla `deploy/savia-vaults.service` usa `Restart=always`, `RestartSec=5`, `--rag-autosync 15` y el hardening de siempre (`NoNewPrivileges`, `MemoryMax`, solo loopback). Instalación como unidad de usuario:

```
mkdir -p ~/.config/systemd/user ~/.savia/vaults
cp projects/savia-vaults/deploy/savia-vaults.service ~/.config/systemd/user/savia-vaults.service
# edita WorkingDirectory y PATH (nvm) si tu instalación no es la de la plantilla
npm --prefix projects/savia-vaults run build
systemctl --user daemon-reload
systemctl --user enable savia-vaults.service
systemctl --user restart savia-vaults.service
curl -s http://127.0.0.1:8923/health
```

Rollback: volver a la unidad anterior y reiniciar; el sync usa el almacén existente y no deja estado nuevo.
