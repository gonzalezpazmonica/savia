---
name: savia-directory
description: >
  Listar miembros de la empresa con @handles, roles y disponibilidad.
argument-hint: "[--filter <role>]"
allowed-tools: [Read, Bash, Glob]
model_tier: fast
context_cost: low
tier: core
---

# Savia Directory

**Argumentos:** $ARGUMENTS

> Uso: `/savia-directory` | `/savia-directory --filter Developer`

## Parámetros

- `--filter <role>` — Filtrar por rol (Admin, Developer, PM, etc.)

## Contexto requerido

1. @.opencode/skills/company-messaging/references/company-savia-config.md — Config Company Savia

## Pasos de ejecución

1. Mostrar banner: `━━━ 👥 Savia Directory ━━━`
2. Verificar company repo configurado
3. Ejecutar: `bash scripts/savia-messaging.sh directory`
4. Si `--filter` → filtrar tabla por rol
5. Para cada miembro, verificar si tiene pubkey (indica cifrado disponible)
6. Mostrar tabla formateada:

```
| Handle | Name | Role | Status | 🔐 Crypto |
|--------|------|------|--------|-----------|
| @admin | Admin Name | Admin | active | ✅ |
| @dev1  | Dev Name | Developer | active | ❌ |
```

## Voz Savia (humano)

"Aquí tienes el directorio del equipo. Usa @handle para enviar mensajes."

## Modo agente

```yaml
status: OK
members: [{handle, name, role, status, has_pubkey}]
```

## Restricciones

- Solo muestra información del directorio público (directory.md)
- No expone datos privados de las carpetas personales

⚡ /compact — Ejecuta para liberar contexto antes del siguiente comando
