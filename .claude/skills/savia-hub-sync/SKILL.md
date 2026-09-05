---
layer: peripheral
name: savia-hub-sync
description: Usar cuando se sincroniza el repositorio SaviaHub con el workspace local.
metadata:
  # --- metadata.savia.* (SE-333) ---
  savia.agent: 
  savia.maturity: stable
  savia.category: pm-operations
  savia.context: fork
  savia.context_cost: low
  savia.maturity: stable
  savia.priority: medium
  savia.summary: "Orquesta sincronizacion del repositorio SaviaHub. Detecta cambios locales vs remotos, resuelve conflictos. Soporta modo offline con cola de sync."
  savia.tags: "sync, savia-hub, repository, backup"
---

# Skill: savia-hub-sync

> Gestiona la sincronización entre la instancia local de SaviaHub y el remote
> opcional. Incluye init, push, pull, flight mode y resolución de conflictos.

## Configuración

```bash
SAVIA_HUB_PATH="${SAVIA_HUB_PATH:-$HOME/.savia-hub}"
SAVIA_HUB_REMOTE="${SAVIA_HUB_REMOTE:-}"   # vacío = solo local
SYNC_QUEUE="$SAVIA_HUB_PATH/.sync-queue.jsonl"
HUB_CONFIG="$SAVIA_HUB_PATH/.savia-hub-config.md"
```

---

## 1. Inicialización

Ejecutar `bash scripts/savia-hub-init.sh [--remote URL] [--path PATH]`.

- **Sin remote**: `git init` + crear estructura (company/, clients/, users/) + commit inicial
- **Con remote**: `git clone $SAVIA_HUB_REMOTE` + crear config local
- En ambos casos: crear `.savia-hub-config.md` (local, gitignored) y `.gitignore`

---

## 2. Push (local → remote)

### Precondiciones
- Remote configurado (`remote_url` no vacío)
- Flight mode OFF (o forzar con `--force`)
- Al menos 1 cambio local pendiente

### Flujo
```
1. cd $SAVIA_HUB_PATH
2. git add -A
3. git status --porcelain → listar cambios
4. Si no hay cambios → "Nada que sincronizar"
5. Mostrar resumen al PM:
   "Se van a subir N ficheros: [lista]"
6. Confirmar con PM
7. git commit -m "[savia-hub] sync: {resumen}"
8. git push origin main
9. Actualizar last_sync en config
10. Drenar .sync-queue.jsonl si existe
```

---

## 3. Pull (remote → local)

### Flujo
```
1. cd $SAVIA_HUB_PATH
2. git fetch origin
3. Comparar HEAD vs origin/main
4. Si no hay cambios remotos → "Ya actualizado"
5. git pull --rebase
6. Si conflicto:
   a. Listar ficheros en conflicto
   b. Para cada uno: mostrar diff al PM
   c. PM decide: [local] [remote] [manual]
   d. git add fichero && git rebase --continue
7. Actualizar last_sync en config
```

---

## 4. Flight Mode

### Activar
```
1. Setear flight_mode: true en .savia-hub-config.md
2. Mostrar: "✈️ Modo vuelo activado"
```

### Desactivar
```
1. Setear flight_mode: false
2. Si hay remote configurado:
   a. Drenar cola → commit + push
   b. Pull cambios remotos
   c. Resolver conflictos si los hay
3. Mostrar: "✅ Online, sincronizado"
```

### Cola de escritura
Cada escritura durante flight mode se registra en `.sync-queue.jsonl`:
```json
{"ts":"2026-03-05T14:30:00Z","action":"write","path":"clients/acme/profile.md"}
```

---

## 5. Status

Muestra: path, modo (local/remote), flight mode, remote URL, last sync, nº clientes/users, cambios pendientes. El fichero `clients/.index.md` se auto-regenera al crear/eliminar clientes.

---

## Reglas de seguridad

1. NUNCA auto-resolver conflictos en datos de clientes
2. NUNCA pushear sin confirmación del PM
3. `.savia-hub-config.md` SIEMPRE local (gitignored)
4. PATs/secrets NUNCA en SaviaHub
5. Contactos sensibles → el equipo decide si van en `.gitignore`
