---
name: workspace-doctor
description: >
  Health check del entorno pm-workspace. Verifica settings, hooks, CLIs,
  permisos y configuracion. 14 checks con acciones correctivas.
  Inspirado en jato doctor (SPEC-031).
model_tier: fast
context_cost: low
allowed-tools:
  - Bash
  - Read
tier: core
---

# /workspace-doctor [--quick] [--fix]

## Ejecucion

1. Banner: `━━ /workspace-doctor — Health Check ━━`

2. Ejecutar script:
   ```bash
   bash scripts/workspace-doctor.sh $ARGUMENTS
   ```

3. Parsear output (formato: `STATUS | check_name | message`):
   - Agrupar por categoria: Criticos (1-5), Importantes (6-10), Recomendados (11-14)
   - Contar OK, WARN, FAIL

4. Mostrar resultado formateado:

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  /workspace-doctor — Health Check
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  Criticos .............. X/5 OK
  Importantes ........... X/5 (N warnings)
  Recomendados .......... X/4 (N info)

  -- Warnings --------------------------
  #N  {check_name}
      {message}
      Fix: {accion correctiva}

  -- Info -------------------------------
  #N  {check_name}
      {message}
      Fix: {accion correctiva}

  RESULTADO: X/14 checks OK
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

5. Si `--fix` en argumentos: para cada WARN/FAIL, preguntar
   "Quieres que aplique el fix para {check}? [s/n]" y ejecutar.
   NUNCA aplicar fixes automaticamente sin confirmacion.

6. Si `--quick` en argumentos: solo checks criticos (1-5), <2 segundos.

7. Banner fin con sugerencia: `⚡ /compact`

## Fixes disponibles

| Check | Fix automatico |
|-------|---------------|
| Scripts no ejecutables | `chmod +x scripts/*.sh` |
| CLI jq faltante | Sugerir `sudo apt install jq` (no ejecutar sudo) |
| CLI gh faltante | Sugerir `sudo apt install gh` (no ejecutar sudo) |
| CHANGELOG con conflictos | Sugerir resolucion manual |
| Perfil no activo | Sugerir `/profile-setup` |

Los fixes que requieren `sudo` se SUGIEREN, nunca se ejecutan.

## Cuando usar

- Al inicio de sesion si algo falla
- Tras `/update` (actualizacion de pm-workspace)
- Cuando un comando da errores inesperados
- Como primer diagnostico ante cualquier problema
