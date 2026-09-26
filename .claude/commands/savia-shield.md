---
name: savia-shield
description: "Gestión de Savia Shield: activar, desactivar y comprobar instalación del sistema de soberanía de datos. Desactivado por defecto."
allowed-tools: [Read, Edit, Write, Bash]
argument-hint: "[enable|disable|status]"
model_tier: fast
context_cost: low
complexity_tier: mode2
tier: core
---

# /savia-shield — Gestión de Savia Shield

Savia Shield protege los datos de proyectos privados filtrando credenciales,
IPs y datos sensibles antes de que lleguen a ficheros públicos.
Por defecto está **desactivado** — actívalo cuando trabajes con proyectos privados.

## Uso

```
/savia-shield enable    — Activar Savia Shield
/savia-shield disable   — Desactivar Savia Shield
/savia-shield status    — Verificar estado e instalación (por defecto)
```

## Instrucciones

Leer el argumento `$ARGUMENTS`. Si está vacío, ejecutar `status`.

### Subcomando: `enable`

1. Leer `.claude/settings.local.json`
2. Actualizar (o crear) la sección `env.SAVIA_SHIELD_ENABLED` con valor `"true"`
3. Guardar el fichero
4. Confirmar: "✅ Savia Shield activado. Ejecuta `/savia-shield status` para verificar la instalación."

### Subcomando: `disable`

1. Leer `.claude/settings.local.json`
2. Actualizar `env.SAVIA_SHIELD_ENABLED` con valor `"false"`
3. Guardar el fichero
4. Confirmar: "⛔ Savia Shield desactivado."

### Subcomando: `status`

Mostrar estado completo en este formato:

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🛡️  Savia Shield — Estado
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Estado global ....... [✅ ACTIVADO / ⛔ DESACTIVADO]
Hook gate ........... [✅ existe / ❌ no encontrado]
Hook audit .......... [✅ existe / ❌ no encontrado]
Daemon (8444) ....... [✅ activo / ⚠️ no disponible (fallback regex)]
Ollama (11434) ...... [✅ activo / ⚠️ no disponible]

Capas activas:
  Capa 1 regex ....... ✅ siempre activa
  Capa 2 LLM ......... [✅ / ⚠️ requiere daemon u Ollama]
  Capa 3 auditoría ... ✅ siempre activa
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Para instalar completo: bash scripts/savia-shield-setup.sh
Documentación: docs/savia-shield.md
```

Para determinar el estado:
- Leer `.claude/settings.local.json` → comprobar `env.SAVIA_SHIELD_ENABLED`
  - `"true"` o ausente → ACTIVADO
  - `"false"` → DESACTIVADO
- Comprobar existencia de hooks con `Glob` o `Bash`
- Comprobar daemon: `bash -c "curl -sf --max-time 1 http://127.0.0.1:8444/health"`
- Comprobar Ollama: `bash -c "curl -sf --max-time 1 http://127.0.0.1:11434 && echo OK"`

## Implementación técnica

`SAVIA_SHIELD_ENABLED` se configura en `.claude/settings.local.json` (gitignored).
Los hooks leen esta variable al inicio — si es `"false"`, salen inmediatamente sin escanear.

Edición manual del fichero (alternativa al comando):
```json
{
  "env": {
    "SAVIA_SHIELD_ENABLED": "true"
  }
}
```

Ver `docs/savia-shield.md` para arquitectura completa y requisitos de instalación.
