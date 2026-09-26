---
name: savia-travel-init
description: >
  Bootstrap pm-workspace on a new machine from a portable package.
  Checks deps, installs Claude Code, restores profiles.
argument-hint: "[path-to-savia-portable]"
allowed-tools: [Read, Bash, Glob]
model_tier: mid
context_cost: low
tier: core
---

# Savia Travel Init

**Argumentos:** $ARGUMENTS

> Uso: `/savia-travel-init <path>` | `/savia-travel-init`

## Contexto requerido

1. @docs/rules/domain/backup-protocol.md — Backup restore reference

## Pasos de ejecucion

1. Mostrar banner:
   ```
   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
   🚀 /savia-travel-init — New Machine Bootstrap
   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
   ```

2. Si no hay path en argumentos, preguntar al usuario la ruta al paquete savia-portable.

3. Ejecutar: `bash scripts/savia-travel.sh init <path>`

4. Mostrar banner de finalizacion con estado de cada paso (deps, install, profile).

5. Sugerir: "Run `/profile-setup` to configure your identity, or `/help` for available commands."

## Voz Savia (humano)

"Bienvenida a tu nuevo nido. Vamos a dejarlo todo listo para trabajar."

## Modo agente

```yaml
status: OK
os: "Linux|macOS|WSL"
deps_ok: true|false
claude_code: "installed|not_installed"
workspace_path: "~/claude"
profile_restored: true|false
```

## Restricciones

- NUNCA instalar paquetes sin informar primero
- Si faltan dependencias, listar comandos de instalacion y esperar confirmacion
- Descifrado de profiles requiere passphrase del usuario

⚡ /compact — Ejecuta para liberar contexto antes del siguiente comando
