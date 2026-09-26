---
name: index-rebuild
description: >
  Rebuild Git Persistence Engine indexes. Scans profiles, messages, projects,
  specs, and timesheets to reconstruct TSV lookup tables.
argument-hint: "[--all|--profiles|--messages|--projects|--specs|--timesheets]"
allowed-tools: [Bash, Read, Glob]
model_tier: fast
context_cost: low
tier: core
---

# Index Rebuild

**Argumentos:** $ARGUMENTS

> Uso: `/index-rebuild` | `/index-rebuild --all` | `/index-rebuild --profiles`

## Parámetros

- `--all` (default) — Rebuild all indexes
- `--profiles` — Rebuild profiles.idx only
- `--messages` — Rebuild messages.idx only
- `--projects` — Rebuild projects.idx only
- `--specs` — Rebuild specs.idx only
- `--timesheets` — Rebuild timesheets.idx only

## Contexto requerido

1. `.savia-index/` directory (created if missing)
2. Source files: `identity.md`, `CLAUDE.md`, `*.spec.md`, timesheet files

## Pasos de ejecución

1. Mostrar banner: `━━━ 📇 Savia Index — Rebuild ━━━`
2. Detectar modo: si `$ARGUMENTS` vacío o `--all` → rebuild todos
3. Para cada index a reconstruir:
   - Ejecutar: `bash scripts/savia-index.sh rebuild-{tipo}`
   - Contar entradas: `bash scripts/savia-index.sh verify {tipo}`
   - Mostrar progreso: `📋 Rebuilding {tipo}... N entries found`
4. Si algún rebuild falla → mostrar error, continuar con otros
5. Al finalizar, mostrar resumen:
   ```
   ✅ Index rebuild complete
   profiles:   M entries
   messages:   N entries
   projects:   P entries
   specs:      Q entries
   timesheets: R entries
   Location: .savia-index/
   ```
6. Mostrar banner de finalización

## Voz Savia (humano)

"He actualizado los índices de búsqueda. Ahora podrás encontrar cosas más rápido."

## Modo agente

```yaml
status: OK
action: "rebuild"
indexes_rebuilt:
  profiles: N
  messages: M
  projects: P
  specs: Q
  timesheets: R
```

## Restricciones

- Solo lectura de ficheros source — no modifica contenido
- Si `.savia-index/` no existe → crearla automáticamente
- Skips indexes que dependen de Azure DevOps si no configurado
- **NUNCA** borra índices existentes — siempre reconstruye desde fuente

⚡ /compact — Ejecuta para liberar contexto antes del siguiente comando
