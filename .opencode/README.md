# Savia (pm-workspace) — OpenCode frontend

> Frontend OpenCode (v1.14+) de Savia, metaorquestadora agéntica de I+D+i
> (identidad canónica en `../.claude/profiles/savia.md`). Comparte recursos con Claude Code
> nativo vía symlinks; ejecuta hooks y commands sin duplicación de fuentes.
>
> **Fuente única de verdad**: `../CLAUDE.md` (raíz del workspace).

---

## ¿Qué es esto?

`.opencode/` es el **entrypoint OpenCode** del workspace. No es una copia
paralela de `.claude/`; es una vista del mismo workspace para un frontend
distinto, con algunas piezas propias (agentes con frontmatter adaptado,
plugins TS, mcp-templates).

OpenCode v1.14+ carga este directorio como raíz de configuración cuando
detecta `OPENCODE_PROJECT_DIR` apuntando aquí o se lanza desde el workspace.

---

## Estructura real

```
.opencode/
├── .claude     → symlink ../.claude              (config raíz compartida)
├── commands    → symlink ../.claude/commands     (559 commands compartidos)
├── hooks       → symlink ../.claude/hooks        (69 hooks compartidos)
├── skills      → symlink ../.claude/skills       (98 skills compartidos)
├── docs        → symlink ../docs                 (documentación compartida)
├── agents/                                       (70 agents, frontmatter OpenCode)
├── plugins/                                      (TS plugins para hooks runtime)
├── mcp-templates/                                (templates MCP servers)
├── CLAUDE.md                                     (redirige al canónico)
├── CLAUDE.local.md                               (config privada local)
├── HOOKS-STRATEGY.md                             (estrategia hooks cross-frontend)
├── install.sh / install.ps1                      (instalador)
├── init-pm.sh                                    (carga variables PM)
└── package.json, bun.lock                        (deps plugins TS)
```

**Lo único independiente de `.claude/`**: `agents/`, `plugins/`, `mcp-templates/`
y este README. Todo lo demás vive en `.claude/` y se accede vía symlink.

---

## Instalación

```bash
# Linux/macOS
bash .opencode/install.sh

# Windows PowerShell
.opencode\install.ps1
```

Tras instalar:

```bash
# Cargar variables PM (Azure DevOps, paths)
source .opencode/init-pm.sh

# Verificar integridad
bash scripts/claude-md-drift-check.sh
bash scripts/hooks-integrity-check.sh
```

---

## Configuración opcional

### Azure DevOps (para skills `azure-devops-*`)

```bash
# 1. Crear PAT en https://dev.azure.com/<org>/_usersSettings/tokens
# 2. Guardar en fichero local (sin salto de línea)
echo "TU_PAT" > $HOME/.azure/devops-pat
chmod 600 $HOME/.azure/devops-pat
# 3. Editar pm-config.local.md con tu org
$EDITOR .claude/rules/pm-config.local.md
```

### Azure CLI (opcional)

```bash
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash
az login
```

### Provider model aliases (SPEC-127)

```bash
$EDITOR ~/.savia/preferences.yaml
# Declara: model_heavy, model_mid, model_fast
# Ver: docs/rules/domain/model-alias-schema.md
```

---

## Hooks y seguridad

Estrategia completa: `HOOKS-STRATEGY.md`.

Resumen:

- **Claude Code shell o LocalAI**: 69 hooks via `.claude/settings.json` (100% cobertura).
- **OpenCode nativo (v1.14+)**: 69 hooks via `plugins/` TS (~80% eventos).
- **OpenCode-Copilot Enterprise**: sin hooks runtime; degradación a git pre-commit + CI.

Verificar registro: `bash scripts/hooks-integrity-check.sh`.

Capas de defensa:

1. Hooks runtime (PreToolUse/PostToolUse/Stop) — cobertura completa cuando disponibles.
2. Git hooks (`bash scripts/install-git-hooks.sh`) — defensa de última línea.
3. CI (`bash scripts/validate-ci-local.sh`) — validación post-push.

---

## Troubleshooting

### "Comando az no encontrado"

Instalar Azure CLI (sección anterior) o ejecutar tests con `--mock`.

### "Error al cargar skill"

Verificar que el symlink `.claude/` está intacto:

```bash
ls -la .opencode/.claude
# Debe mostrar: .claude -> ../.claude
readlink .opencode/.claude
# Debe imprimir: ../.claude
```

Si falta, recrearlo:

```bash
cd .opencode && ln -s ../.claude .claude
```

### "Los hooks no se ejecutan en OpenCode-Copilot Enterprise"

Comportamiento esperado: ese frontend no expone surface de eventos.
La protección se degrada a git pre-commit + CI:

```bash
bash scripts/install-git-hooks.sh
bash scripts/validate-ci-local.sh
```

### "Drift detectado en CLAUDE.md"

```bash
bash scripts/claude-md-drift-check.sh
# Si reporta counters incorrectos, ejecutar:
bash scripts/count-commands.sh
# Y actualizar manualmente CLAUDE.md y docs/rules/domain/pm-workflow.md
```

---

## Counters actuales (auto-generados)

| Recurso | Total |
|---|---|
| Agents | 70 (en `agents/`, frontmatter OpenCode) |
| Commands | 559 (via symlink) |
| Hooks | 69 (via symlink) |
| Skills | 98 (via symlink) |

---

## Comandos slash

Los 559 comandos slash están en `commands/` (symlink a `.claude/commands/`).
Cada `.md` contiene la especificación del comando: banner, prerequisitos,
pasos, output esperado. OpenCode los lee y ejecuta con sus herramientas
(Bash, Read, Grep, Task, Edit, Write).

Catálogo completo: `docs/rules/domain/pm-workflow.md`.

---

## Compatibilidad cross-frontend

| Frontend | Workspace var | Hooks | Slash commands |
|---|---|---|---|
| Claude Code nativo | `CLAUDE_PROJECT_DIR` | 100% | Nativos |
| OpenCode v1.14+ | `OPENCODE_PROJECT_DIR` | ~80% via plugins | Nativos (`.opencode/commands/`) |
| OpenCode-Copilot Enterprise | `OPENCODE_PROJECT_DIR` | **0%** | **0%** |
| LocalAI emergency (SPEC-122) | `CLAUDE_PROJECT_DIR` | 100% | Nativos |

Detalle: `docs/rules/domain/provider-agnostic-env.md`, `docs/rules/domain/model-alias-schema.md`.

---

## Histórico

- **2025-03**: este directorio se creó como copia paralela de `.claude/` con wrappers manuales. Modelo "OpenCode no ejecuta hooks".
- **2026-04-09**: refactor a symlinks compartidos. Hooks runtime disponibles cross-frontend.
- **2026-05-27 (SE-100)**: README reescrito reflejando el modelo real (symlinks, no duplicación). Eliminadas afirmaciones falsas sobre "`.claude/` es enlace simbólico al directorio original" (era al revés).

---

## Referencias

- `../CLAUDE.md` — fuente única de verdad, reglas críticas, identidad Savia.
- `../AGENTS.md` — catálogo cross-frontend de agentes.
- `../SKILLS.md` — catálogo cross-frontend de skills.
- `CLAUDE.md` (este directorio) — redirige al canónico.
- `HOOKS-STRATEGY.md` — estrategia hooks cross-frontend.
- `docs/rules/domain/pm-workflow.md` — catálogo comandos.
- `docs/rules/domain/agents-catalog.md` — catálogo agentes.
