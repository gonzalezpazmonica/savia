---
name: index-compact
description: >
  Compact Git Persistence Engine indexes. Removes orphaned entries where
  source files no longer exist, and repairs inconsistencies.
argument-hint: "[--all|--profiles|--messages|--projects|--specs|--timesheets]"
allowed-tools: [Bash, Read]
model_tier: fast
context_cost: low
complexity_tier: mode1
tier: core
---

# Index Compact

**Argumentos:** $ARGUMENTS

> Uso: `/index-compact` | `/index-compact --all` | `/index-compact --profiles`

## Parámetros

- `--all` (default) — Compact all indexes
- `--profiles` — Compact profiles.idx only
- `--messages` — Compact messages.idx only
- `--projects` — Compact projects.idx only
- `--specs` — Compact specs.idx only
- `--timesheets` — Compact timesheets.idx only

## Contexto requerido

1. `.savia-index/` directory must exist
2. Source files (profiles, messages, projects, specs, timesheets)

## Pasos de ejecución

1. Mostrar banner: `━━━ 🧹 Savia Index — Compact ━━━`
2. Verificar que `.savia-index/` existe
   - Si no → error: `Index directory not found. Run /index-rebuild first`
3. Detectar modo (--all o específico)
4. Para cada index a compactar:
   - Ejecutar: `bash scripts/savia-index.sh compact {tipo}`
   - Contar entradas antes y después
   - Mostrar: `📋 Compacting {tipo}... {removed} orphaned entries`
5. Al finalizar, mostrar resumen:
   ```
   ✅ Index compaction complete
   profiles:   removed X orphaned entries
   messages:   removed Y orphaned entries
   projects:   removed Z orphaned entries
   specs:      removed A orphaned entries
   timesheets: removed B orphaned entries
   ```
6. Si se removieron entradas → sugerir revisar las deletions
7. Mostrar banner de finalización

## Voz Savia (humano)

"He limpiado los índices. Se removieron entradas huérfanas."

## Modo agente

```yaml
status: OK
action: "compact"
compacted:
  profiles:
    before: N
    after: M
    removed: X
  messages:
    before: N
    after: M
    removed: X
  projects:
    before: N
    after: M
    removed: X
  specs:
    before: N
    after: M
    removed: X
  timesheets:
    before: N
    after: M
    removed: X
total_removed: K
```

## Restricciones

- Solo elimina entradas cuyo fichero source ya no existe
- NUNCA elimina la header de los indexes (primera línea)
- Si un index está vacío tras compactar → no error, solo info
- Backup implícito: ficheros removidos pueden recuperarse del git history

⚡ /compact — Ejecuta para liberar contexto antes del siguiente comando
