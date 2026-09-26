---
name: index-status
description: >
  Check Git Persistence Engine index integrity. Verifies all indexes exist,
  counts entries, and detects orphaned data.
argument-hint: "[--detailed]"
allowed-tools: [Bash, Read]
model_tier: fast
context_cost: low
tier: core
---

# Index Status

**Argumentos:** $ARGUMENTS

> Uso: `/index-status` | `/index-status --detailed`

## Parámetros

- `--detailed` (optional) — Show entry details, not just counts

## Contexto requerido

1. `.savia-index/` directory must exist from prior `/index-rebuild`
2. pm-config or local workspace configuration

## Pasos de ejecución

1. Mostrar banner: `━━━ 📊 Savia Index — Status ━━━`
2. Verificar que `.savia-index/` existe
   - Si no existe → mostrar: `⚠️  Index directory not found. Run /index-rebuild first`
3. Para cada index (profiles, messages, projects, specs, timesheets):
   - Ejecutar: `bash scripts/savia-index.sh verify {tipo}`
   - Extraer: total_entries
   - Mostrar: `✅ {tipo}: N entries`
4. Si flag `--detailed`:
   - Mostrar tabla: índice | entradas | última actualización | estado
   - Para algunos indexes, listar primeras 5 entradas (sin datos sensibles)
5. Detectar índices inconsistentes o vacíos:
   - ✅ Normal: >= 1 entry
   - 🟡 Warning: 0 entries (index exists but empty)
   - 🔴 Error: index file corrupted or unreadable
6. Si hay warnings/errors → sugerir `/index-rebuild` o `/index-compact`
7. Mostrar banner de finalización

## Voz Savia (humano)

"Los índices están al día. Todo está en orden."

o

"Algunos índices están vacíos. Ejecuta `/index-rebuild` para rellenarlos."

## Modo agente

```yaml
status: OK
action: "status"
indexes:
  profiles:
    entries: N
    last_update: "YYYY-MM-DDTHH:MM:SSZ"
    status: "healthy|empty|corrupted"
  messages:
    entries: M
    last_update: "..."
    status: "..."
  projects:
    entries: P
    last_update: "..."
    status: "..."
  specs:
    entries: Q
    last_update: "..."
    status: "..."
  timesheets:
    entries: R
    last_update: "..."
    status: "..."
overall_status: "healthy|warning|error"
```

## Restricciones

- Solo lectura — no modifica indexes
- Si index está corrompido → mostrar error claro pero NO intentar reparar
- No verifica Azure DevOps indexes si no está configurado (info)

⚡ /compact — Ejecuta para liberar contexto antes del siguiente comando
