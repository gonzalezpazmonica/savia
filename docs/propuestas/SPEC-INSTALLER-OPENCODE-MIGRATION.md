---
spec_id: SPEC-INSTALLER-OPENCODE-MIGRATION
title: Migrar instaladores de Claude Code a OpenCode
status: IMPLEMENTED
approved_by: operator (2026-05-07)
---

# SPEC-INSTALLER-OPENCODE-MIGRATION — Migrar instaladores de Claude Code a OpenCode

> **Status**: IMPLEMENTED
> **Approved**: —
> **Spec version**: 1.0
> **Parent**: SE-077 OpenCode v1.14 replatform
> **Depends on**: SPEC-127 (provider-agnostic env layer, merged)

---

## Resumen ejecutivo

Los 4 instaladores de Savia (`install.sh`, `install.ps1`, `.opencode/install.sh`, `.opencode/install.ps1`) y 8+ scripts de setup/documentos de instalación asumen Claude Code como frontend por defecto. `SAVIA_HOME` por defecto es `~/claude`. La documentación dice `cd pm-workspace && claude`. Esta spec los migra a OpenCode como frontend primario, manteniendo Claude Code como fallback documentado.

---

## Alcance

### Slice 1: Instaladores primarios (MVP)

| Fichero | Cambio |
|---|---|
| `install.sh` | `SAVIA_HOME` default `~/claude` → `~/savia`. Step 3: instalar OpenCode en vez de Claude Code. Step 6: configurar `.opencode/` en vez de `.claude/settings.local.json`. Banner final: `opencode` en vez de `claude`. |
| `install.ps1` | Mismos cambios que `install.sh` para Windows. |
| `.opencode/install.sh` | `SAVIA_HOME` default `~/claude` → `~/savia`. Eliminar export de `CLAUDE_PROJECT_DIR` obsoleto (usar `SAVIA_WORKSPACE_DIR` via `savia-env.sh`). Simplificar compat shim. |
| `.opencode/install.ps1` | Mismos cambios que `.opencode/install.sh` para Windows. |

### Slice 2: Setup scripts con paths hardcodeados

| Fichero | Cambio |
|---|---|
| `scripts/session-init-bootstrap.sh` | `$HOME/claude/scripts/` → usar `$SAVIA_WORKSPACE_DIR` o `git rev-parse --show-toplevel`. |
| `scripts/install-savia-bridge-system.sh` | `REPO_DIR="${USER_HOME}/claude"` → detectar desde `$SAVIA_WORKSPACE_DIR` o `$HOME/savia`. |
| `scripts/setup-savia-remote.sh` | `~/claude` paths → `~/savia`. `claude -p` → referencia genérica a "agente CLI". |
| `scripts/setup-memory.sh` | `~/.claude/projects/` → `~/.savia/projects/` con fallback legacy. |

### Slice 3: Documentación de instalación (todos los idiomas)

#### 3a. Documentos de entrada (top-level)

| Fichero | Idioma | Cambio |
|---|---|---|
| `README.md` (línea 27) | es | `cd pm-workspace && claude` → `opencode`. |
| `README.en.md` | en | Ídem. |
| `docs/getting-started.md` | es | Prerrequisito "Claude Code" → "OpenCode". Comando `claude` → `opencode`. |

#### 3b. Guía de configuración / setup

| Fichero | Idioma | Cambio |
|---|---|---|
| `docs/readme/03-configuracion.md` | es | Prerrequisito "Claude Code instalado y autenticado" → "OpenCode instalado". Path `~/claude` → `~/savia`. |
| `docs/readme_en/03-setup.md` | en | Ídem en inglés. |

#### 3c. Guía de estructura del workspace

| Fichero | Idioma | Cambio |
|---|---|---|
| `docs/readme/02-estructura.md` | es | `~/claude/` → `~/savia/` en árbol de directorios y nota. |
| `docs/readme_en/02-structure.md` | en | Ídem en inglés. |

#### 3d. Guía de onboarding

| Fichero | Idioma | Cambio |
|---|---|---|
| `docs/readme/11-onboarding.md` | es | Referencias a "Claude" como asistente → genérico o "Savia". |
| `docs/readme_en/11-onboarding.md` | en | Ídem en inglés. |

#### 3e. Resto de docs readme (13 ficheros × 2 idiomas) — paths `~/claude`

| Fichero (es) | Fichero (en) | Cambio |
|---|---|---|
| `docs/readme/01-introduccion.md` | `docs/readme_en/01-introduction.md` | `~/claude` → `~/savia` si aparece |
| `docs/readme/04-uso-sprint-informes.md` | `docs/readme_en/04-usage-sprint-reports.md` | Ídem |
| `docs/readme/05-sdd.md` | `docs/readme_en/05-sdd.md` | Ídem |
| `docs/readme/06-configuracion-avanzada.md` | `docs/readme_en/06-advanced-config.md` | Ídem |
| `docs/readme/07-infraestructura.md` | `docs/readme_en/07-infrastructure.md` | Ídem |
| `docs/readme/09-proyecto-test.md` | `docs/readme_en/09-test-project.md` | Ídem |
| `docs/readme/10-kpis-reglas.md` | `docs/readme_en/10-kpis-rules.md` | Ídem |
| `docs/readme/12-comandos-agentes.md` | `docs/readme_en/12-commands-agents.md` | Ídem |
| `docs/readme/13-cobertura-contribucion.md` | `docs/readme_en/13-coverage-contributing.md` | Ídem |

#### 3f. Documentación OpenCode interna

| Fichero | Cambio |
|---|---|
| `.opencode/README.md` | `~/claude` → `~/savia` en todos los ejemplos (8 ocurrencias). |
| `.opencode/HOOKS-STRATEGY.md` | Actualizar referencias a paths si menciona `~/claude`. |

#### 3g. Guía de migración

| Fichero | Cambio |
|---|---|
| `docs/migration-claude-code-to-opencode.md` | Actualizar referencias a paths (`~/claude` → `~/savia`). Añadir sección sobre el nuevo instalador unificado. |

**Total Slice 3: 27 ficheros** (13 es + 13 en + 1 .opencode) más 3 top-level + 1 migration.

### Slice 4: Unificación (post-MVP)

| Acción | Descripción |
|---|---|
| Deprecar `.opencode/install.sh` | Redirigir a `install.sh` (ya OpenCode-first). Mantener como symlink por 3 versiones. |
| Eliminar `SKIP_CLAUDE` flag | Ya no aplica — el instalador instala OpenCode, no Claude Code. |
| `scripts/setup-claude-permissions.sh` | Renombrar a `scripts/setup-opencode-permissions.sh` o deprecar. |

---

## Diseño detallado

### 1. `install.sh` — Cambios paso a paso

```
ANTES                                  DESPUÉS
────────────────────────────────────── ──────────────────────────────────────
SAVIA_HOME="${SAVIA_HOME:-$HOME/claude}"  SAVIA_HOME="${SAVIA_HOME:-$HOME/savia}"
SKIP_CLAUDE flag                       (eliminado — ya no se instala Claude Code)

Step 3: "Checking Claude Code..."      Step 3: "Checking OpenCode..."
  • curl https://claude.ai/install.sh    • curl/script para instalar OpenCode
  • sh claude_installer                  • (ver sección "Instalación de OpenCode")

Step 6: "Claude Code permissions"       Step 6: "OpenCode configuration"
  • setup-claude-permissions.sh          • opencode config set ...
                                         • opencode plugin install savia-gates

Final banner:                           Final banner:
  cd $SAVIA_HOME && claude               cd $SAVIA_HOME && opencode
```

### 2. Instalación de OpenCode

OpenCode se instala via npm (global) o binary download:

```bash
# Opción A: npm global (recomendada — ya tenemos Node.js como prerequisito)
npm install -g @opencode/cli   # OpenCode 2 (opencode-ai para OpenCode 1)

# Opción B: binary download (si no hay npm)
curl -fsSL https://github.com/sst/opencode/releases/latest/download/opencode-linux-x64.tar.gz | tar xz -C /usr/local/bin
```

El script `scripts/opencode-install.sh` ya existe y maneja la instalación binaria. El instalador principal lo invocará.

### 3. Configuración post-install OpenCode

```bash
# Generar opencode.json base (si no existe)
opencode init --workspace "$SAVIA_HOME"

# Instalar plugin savia-gates
opencode plugin install "$SAVIA_HOME/.opencode"

# Configurar modelo por defecto
bash "$SAVIA_HOME/scripts/savia-preferences.sh" init
```

### 4. Default path: `~/claude` → `~/savia`

**Razón**: `~/claude` asume Claude Code como frontend. `~/savia` es neutral y semánticamente correcto (el workspace se llama Savia, no Claude).

**Migración de usuarios existentes**: Si `~/claude` ya existe, el instalador lo detecta y pregunta si migrar. La migración es: `mv ~/claude ~/savia` + reconfigurar opencode.json con el nuevo path.

**Fallback**: `SAVIA_HOME` puede seguir apuntando a `~/claude` via variable de entorno para usuarios que no quieran migrar.

### 5. Compatibilidad con `CLAUDE_PROJECT_DIR`

El ecosistema Savia usa `CLAUDE_PROJECT_DIR` como variable de entorno para el workspace root. Con la migración a OpenCode:

- `scripts/savia-env.sh` ya resuelve `SAVIA_WORKSPACE_DIR` desde `CLAUDE_PROJECT_DIR`, `OPENCODE_PROJECT_DIR`, o `git rev-parse`.
- El instalador OpenCode exportará `CLAUDE_PROJECT_DIR` como fallback (compatibilidad con scripts legacy).
- Los scripts nuevos usarán `SAVIA_WORKSPACE_DIR`.

### 6. `init-pm.sh` / bootstrap

El fichero `.opencode/init-pm.sh` actualmente exporta `CLAUDE_PROJECT_DIR`. Se actualiza para:

```bash
export PM_WORKSPACE_ROOT="${PM_WORKSPACE_ROOT:-$HOME/savia}"
export CLAUDE_PROJECT_DIR="$PM_WORKSPACE_ROOT"   # backward compat
export SAVIA_WORKSPACE_DIR="$PM_WORKSPACE_ROOT"  # new standard
```

---

## Acceptance Criteria

### AC-1: Instalador principal OpenCode-first
- `curl .../install.sh | bash` instala OpenCode (no Claude Code).
- `SAVIA_HOME` default es `~/savia`.
- El comando final del banner es `opencode`.
- Claude Code puede instalarse opcionalmente con `--with-claude-code`.

### AC-2: Instalador Windows
- `install.ps1` instala OpenCode en Windows.
- Default path `~\savia`.

### AC-3: Instalador OpenCode legacy unificado
- `.opencode/install.sh` es un wrapper que llama a `install.sh`.
- No duplica lógica.

### AC-4: Scripts de setup sin paths hardcodeados
- `session-init-bootstrap.sh` no contiene `$HOME/claude`.
- `install-savia-bridge-system.sh` detecta el workspace root dinámicamente.
- `setup-savia-remote.sh` usa `~/savia` como default.
- `setup-memory.sh` usa `~/.savia/projects/` como default.

### AC-5: Documentación actualizada (todos los idiomas)
- `README.md` (es) y `README.en.md` (en): instruyen `opencode` en vez de `claude`.
- `docs/getting-started.md` (es): lista OpenCode como prerequisito.
- `docs/readme/03-configuracion.md` (es) y `docs/readme_en/03-setup.md` (en): prerrequisito OpenCode, paths `~/savia`.
- `docs/readme/02-estructura.md` (es) y `docs/readme_en/02-structure.md` (en): árbol `~/savia/`.
- `docs/readme/11-onboarding.md` (es) y `docs/readme_en/11-onboarding.md` (en): referencias genéricas.
- Resto de ficheros `docs/readme/*.md` (9 es + 9 en): paths `~/claude` → `~/savia` donde aparezcan.
- `.opencode/README.md`: 8 paths `~/claude` → `~/savia`.
- `.opencode/HOOKS-STRATEGY.md`: paths actualizados.
- `docs/migration-claude-code-to-opencode.md`: refleja los nuevos defaults.

### AC-6: Smoke test
- `bash scripts/test-install.sh` pasa tras los cambios.
- `bash scripts/opencode-migration-smoke.sh` → 6/6 PASS.

### AC-7: Usuario existente con ~/claude
- El instalador detecta `~/claude` existente.
- Pregunta si migrar a `~/savia` (con `mv`).
- Si el usuario rechaza, usa `~/claude` como fallback.

---

## Riesgos

| Riesgo | Prob | Impacto | Mitigación |
|---|---|---|---|
| Usuarios con paths hardcodeados en cron/systemd | Media | Alto | Documentar en guía de migración. El instalador pregunta antes de mover. |
| OpenCode no disponible en todos los package managers | Baja | Medio | Fallback a binary download desde GitHub Releases. |
| Scripts legacy que dependen de `~/claude` | Media | Bajo | Mantener `CLAUDE_PROJECT_DIR` exportado como fallback. |
| Windows `~\savia` vs `~\claude` en PowerShell | Baja | Bajo | Mismo tratamiento que Linux. |

---

## Rollback

```bash
# Si algo falla, Claude Code sigue funcionando:
export SAVIA_HOME="$HOME/claude"
cd ~/claude && claude

# O reinstalar Claude Code:
curl -fsSL https://claude.ai/install.sh | sh
```

---

## Plan de implementación

### Slice 1 (MVP — 1 sesión)
1. Modificar `install.sh`: SAVIA_HOME, step 3, step 6, banner.
2. Modificar `install.ps1`: mismos cambios.
3. Modificar `.opencode/install.sh`: wrapper hacia `install.sh`.
4. Modificar `.opencode/install.ps1`: wrapper hacia `install.ps1`.
5. Ejecutar `test-install.sh` y corregir fallos.

### Slice 2 (setup scripts — 1 sesión)
6. `session-init-bootstrap.sh`: paths dinámicos.
7. `install-savia-bridge-system.sh`: detección de workspace root.
8. `setup-savia-remote.sh`: `~/savia` default.
9. `setup-memory.sh`: `~/.savia/projects/` default.

### Slice 3 (docs todos los idiomas — 1 sesión)
10. `README.md` (es) + `README.en.md` (en): `claude` → `opencode`.
11. `docs/getting-started.md` (es): prerrequisito OpenCode.
12. `docs/readme/03-configuracion.md` (es) + `docs/readme_en/03-setup.md` (en).
13. `docs/readme/02-estructura.md` (es) + `docs/readme_en/02-structure.md` (en).
14. `docs/readme/11-onboarding.md` (es) + `docs/readme_en/11-onboarding.md` (en).
15. Resto `docs/readme/*.md` (9 es + 9 en): `~/claude` → `~/savia`.
16. `.opencode/README.md` + `.opencode/HOOKS-STRATEGY.md`.
17. `docs/migration-claude-code-to-opencode.md`.

### Slice 4 (unificación — 1 sesión)
14. Deprecar `.opencode/install.sh`.
15. Eliminar `SKIP_CLAUDE`.
16. Renombrar/deprecar `setup-claude-permissions.sh`.

---

## OpenCode Implementation Plan

### Bindings touched

| Componente | Claude Code | OpenCode v1.14 |
|---|---|---|
| `install.sh` step 3 | Instala Claude Code CLI | Instala OpenCode CLI |
| `install.sh` step 6 | `.claude/settings.local.json` | `opencode.json` + plugin |
| `install.sh` banner | `cd ~/claude && claude` | `cd ~/savia && opencode` |
| `init-pm.sh` | Exporta `CLAUDE_PROJECT_DIR` | Exporta ambos `CLAUDE_PROJECT_DIR` + `SAVIA_WORKSPACE_DIR` |
| `install-savia-bridge-system.sh` | Hardcodea `/home/monica/claude` | Detecta desde env o default `~/savia` |
| `session-init-bootstrap.sh` | `$HOME/claude/scripts/` | `$SAVIA_WORKSPACE_DIR/scripts/` |
| `setup-savia-remote.sh` | `~/claude`, `claude -p` | `~/savia`, referencia genérica |
| `setup-memory.sh` | `~/.claude/projects/` | `~/.savia/projects/` |

### Verification protocol

- [ ] `install.sh` completa sin errores en Linux (Ubuntu 22.04+)
- [ ] `install.sh` completa sin errores en macOS
- [ ] `install.ps1` completa sin errores en Windows 10+
- [ ] `opencode` arranca y reconoce el workspace (`opencode run '/savia-goal status'`)
- [ ] Smoke test: `bash scripts/test-workspace.sh --mock` pasa
- [ ] Migration smoke test: `bash scripts/opencode-migration-smoke.sh` → 6/6
- [ ] Usuario con `~/claude` existente puede migrar sin pérdida de datos
- [ ] Rollback: `claude` en `~/claude` sigue funcionando

### Portability classification

- [x] **PURE_BASH**: los instaladores son bash puro (install.sh) o PowerShell (install.ps1). Sin bindings de frontend. El runtime se invoca al final (`opencode` o `claude`).
