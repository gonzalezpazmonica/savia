---
title: "Guia de Migracion: Claude Code a OpenCode"
spec_ref: SPEC-INSTALLER-OPENCODE-MIGRATION
updated: "2026-06-24"
---

# Guia de Migracion: Claude Code a OpenCode

> OpenCode es el frontend primario de Savia desde SE-077 (2026-04-19).
> Claude Code sigue siendo un fallback totalmente funcional.

## Que cambia

### Comando de arranque

Antes: cd ~/claude && claude
Despues: cd ~/savia && opencode

### Directorio de instalacion

Default anterior: SAVIA_HOME=~/claude
Default nuevo: SAVIA_HOME=~/savia

### Fichero de configuracion del frontend

| Aspecto | Claude Code | OpenCode |
|---|---|---|
| Config global | ~/.claude/settings.json | ~/.config/opencode/opencode.json |
| Config proyecto | .claude/settings.local.json | opencode.json (raiz del workspace) |
| Instrucciones sistema | CLAUDE.md | AGENTS.md + instrucciones en opencode.json |
| Slash commands | .claude/commands/*.md | .opencode/commands/*.md (symlink) |
| Hooks | .claude/hooks/*.sh via settings.json | .opencode/plugins/*.ts + hooks bash |

## Que NO cambia

Todo lo siguiente es compartido entre ambos frontends via symlinks:

- Todos los agentes (.opencode/agents/ = .claude/agents/)
- Todos los skills (.opencode/skills/ -> .claude/skills/)
- Todos los hooks bash (.opencode/hooks/ -> .claude/hooks/)
- Todas las specs SDD (docs/propuestas/)
- El workspace entero de pm-workspace

Claude Code puede seguir usandose en el mismo directorio con el comando claude.

## Como migrar paso a paso

### 1. Detectar frontends disponibles

    bash scripts/detect-frontend.sh

Salida esperada:

    {
      "opencode": true,
      "claude_code": true,
      "recommended": "opencode"
    }

### 2. Instalar OpenCode (si no esta instalado)

Via npm (recomendado — ya tenemos Node.js como prerequisito):

    npm install -g @opencode/cli   # OpenCode 2 (opencode-ai para OpenCode 1)
    opencode --version

Via binario (si no hay npm disponible):

    # Descarga el binario para Linux x64:
    # https://github.com/sst/opencode/releases/latest
    # Luego: tar xz -C /usr/local/bin (revisar antes de ejecutar)

### 3. Migrar el directorio (si usas ~/claude)

    # Comprobar si existe ~/claude
    ls ~/claude 2>/dev/null && echo "Existe ~/claude"

    # Migrar
    mv ~/claude ~/savia

    # Actualizar variable de entorno si la tienes en .bashrc/.zshrc
    # Reemplaza SAVIA_HOME=~/claude por SAVIA_HOME=~/savia

### 4. Verificar que todo funciona

    cd ~/savia && opencode
    # Luego ejecutar: /savia-goal status

## Rollback: volver a Claude Code

Si algo falla, Claude Code sigue funcionando sin cambios:

    # Opcion A: usar Claude Code en el mismo directorio
    cd ~/savia && claude

    # Opcion B: usar el directorio anterior
    export SAVIA_HOME="/home/monica/claude"
    cd ~/claude && claude

Los agentes, skills, specs y hooks son identicos en ambos frontends. No hay perdida de funcionalidad.

## Variables de entorno

| Variable | Claude Code | OpenCode | Nota |
|---|---|---|---|
| CLAUDE_PROJECT_DIR | Requerida | Exportada como fallback | savia-env.sh la resuelve |
| SAVIA_WORKSPACE_DIR | No existia | Nueva standard | Preferida en scripts nuevos |
| SAVIA_HOME | ~/claude default | ~/savia default | Configurable via env |
| OPENCODE_PROJECT_DIR | No existia | Soportada | Alternativa a CLAUDE_PROJECT_DIR |

## Preguntas frecuentes

Puedo usar ambos frontends en el mismo workspace?
Si. Claude Code y OpenCode comparten el mismo workspace.
Puedes alternar entre claude y opencode sin conflictos.

Mis hooks siguen funcionando en OpenCode?
Si. Los hooks bash (.claude/hooks/) estan disponibles en OpenCode via
el plugin savia-foundation. Los plugins TypeScript (.opencode/plugins/)
son equivalentes OpenCode-nativos.

Los slash commands funcionan igual?
Si. Los comandos en .opencode/commands/ (symlinks a .claude/commands/)
funcionan en ambos frontends con la misma sintaxis /nombre-comando.

## Ver tambien

- scripts/detect-frontend.sh - detectar frontends disponibles
- install.sh - instalador principal (OpenCode-first)
- .opencode/install.sh - instalador legacy (wrapper)
- docs/propuestas/SPEC-INSTALLER-OPENCODE-MIGRATION.md - spec completa
- docs/rules/domain/provider-agnostic-env.md - variables de entorno
