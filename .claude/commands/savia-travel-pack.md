---
name: savia-travel-pack
description: >
  Create a portable pm-workspace package for travel/USB deployment.
  Includes shallow clone, manifest, dependencies list, and encrypted profiles.
argument-hint: ""
allowed-tools: [Read, Bash, Glob]
model_tier: mid
context_cost: low
tier: core
---

# Savia Travel Pack

> Uso: `/savia-travel-pack`

## Contexto requerido

1. @docs/rules/domain/backup-protocol.md — Backup and encryption reference

## Pasos de ejecucion

1. Mostrar banner:
   ```
   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
   📦 /savia-travel-pack — Portable Package Creator
   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
   ```

2. Verificar prerequisitos:
   - Git repository with pm-workspace
   - Optional: encrypted backup for profile export

3. Ejecutar: `bash scripts/savia-travel.sh pack`

4. Mostrar banner de finalizacion con package location and size.

5. Sugerir: "Copy the package to a USB drive or cloud storage for deployment on another machine."

## Voz Savia (humano)

"He preparado tu mochila digital. Todo lo que necesitas para montar pm-workspace en otra maquina esta en el paquete."

## Modo agente

```yaml
status: OK
package_path: "output/savia-portable-YYYYMMDD/"
version: "vX.Y.Z"
includes_profiles: true|false
```

## Restricciones

- NUNCA incluir datos privados sin cifrar (profiles solo via backup cifrado)
- Privacy check antes de empaquetar
- El paquete NO incluye projects/, output/ ni CLAUDE.local.md

⚡ /compact — Ejecuta para liberar contexto antes del siguiente comando
