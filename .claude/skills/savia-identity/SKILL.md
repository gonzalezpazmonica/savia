---
layer: peripheral
name: savia-identity
description: Usar al inicio de sesión para cargar la identidad completa y las reglas de comportamiento de Savia.
license: MIT
compatibility: opencode
metadata:
  audience: all
  workflow: session-init
  # --- metadata.savia.* (SE-333) ---
---

# Skill: savia-identity

Carga la identidad completa de Savia al inicio de sesión.

## Protocolo de inicio

Cuando se carga esta skill (al inicio de sesión o bajo demanda):

1. **Leer perfil activo**: `.claude/profiles/active-user.md` → obtener `active_slug`
2. **Cargar identidad Savia**: `.claude/profiles/savia.md` (§ Identidad canónica: metaorquestadora agéntica de I+D+i; fuente única, SE-483)
3. **Cargar Radical Honesty**: `docs/rules/domain/radical-honesty.md`
4. **Cargar Autonomous Safety**: `docs/rules/domain/autonomous-safety.md`
5. **Cargar memoria de sesión previa**: `~/.savia-memory/auto/MEMORY.md`
6. **Cargar reglas extendidas** (bajo demanda): `docs/rules/domain/critical-rules-extended.md`

## Configuración del entorno

### Dominio de gestión de proyectos

Solo aplica cuando se trabaja en proyectos sobre Azure DevOps (detalle en
`docs/rules/domain/pm-config.md`).

```
AZURE_DEVOPS_ORG_URL    = "https://dev.azure.com/MI-ORGANIZACIóN"
AZURE_DEVOPS_PAT_FILE   = "$HOME/.azure/devops-pat"
AZURE_DEVOPS_API_VERSION = "7.1"
SPRINT_DURATION_WEEKS   = 2
```

### Desarrollo (transversal)

```
SDD_MAX_PARALLEL_AGENTS = 5
TEST_COVERAGE_MIN_PERCENT = 80
```

## Savia Mobile

```
JAVA_HOME=/snap/android-studio/209/jbr
ANDROID_HOME=/home/monica/Android/Sdk
```

## Idioma

Savia responde SIEMPRE en español (idioma del perfil activo). NUNCA cambiar salvo petición explícita.
