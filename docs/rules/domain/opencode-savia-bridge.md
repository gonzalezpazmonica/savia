---
context_tier: L3
token_budget: 1031
---

# Regla: OpenCode ↔ Savia bridge

> Permite operar pm-workspace desde OpenCode v1.14 sin perder hooks, AUTONOMOUS_REVIEWER ni la base instalada de skills/agents. Vigente desde SE-077 Slice 1+2.

## Cuándo usar

- Plan B operativo cuando Anthropic restrinja Claude Code (Pro→Max ya en abril 2026, API-only previsto 6-18 meses)
- Sesiones donde necesitas el modelo via OpenAI/Gemini/local LLM en lugar de Anthropic
- Tests de equivalencia cross-frontend (canary mensual)

## Cuándo NO usar

- Operación principal: Claude Max sigue siendo frontend default (esto es plan B, no migración)
- Casos `API down` totales: usar SPEC-122 emergency-mode (LocalAI), no OpenCode
- Tareas con dependencia hardware GPU (Era 190+)

## Instalación

```bash
# Instala OpenCode v1.14.x en ~/.savia/opencode/ y enlaza el plugin savia-gates
bash scripts/opencode-install.sh

# Versión específica
bash scripts/opencode-install.sh --version 1.14.25

# Sólo re-enlazar el plugin (binary ya instalado)
bash scripts/opencode-install.sh --link-only

# Dry-run — muestra el plan sin tocar nada
bash scripts/opencode-install.sh --dry-run

# Desinstalar
bash scripts/opencode-install.sh --uninstall
```

Tras la instalación, el plugin escribe un manifest `~/.savia/opencode/plugins/savia-gates/manifest.json` que la herramienta de parity-audit usa para detectar gaps.

## Arquitectura

OpenCode carga el plugin TypeScript `savia-gates` en cada sesión. El plugin lee `.claude/settings.json` (mismo origen que Claude Code) y construye un mapa evento→hooks en memoria. Cada vez que OpenCode dispara un evento (`tool.execute.before`, `chat.message`, `permission.ask`, etc.), el plugin invoca los `.sh` correspondientes vía Bun's `$` shell — los hooks bash se ejecutan **sin modificar**.

| Evento Claude Code | Handler OpenCode |
|---|---|
| `PreToolUse` | `tool.execute.before` |
| `PostToolUse` | `tool.execute.after` |
| `UserPromptSubmit` | `chat.message` |
| `SessionStart` + `InstructionsLoaded` | `event:session.created` |
| `SessionEnd` | `event:session.deleted` |
| `Stop` | `event:session.stopped` |
| `PostCompact` | `event:session.compacted` + `experimental.compaction.autocontinue` |
| `SubagentStart`/`SubagentStop` | `event:subagent.*` |
| `TaskCreated`/`TaskCompleted` | `event:task.*` |
| `PreCompact` | `experimental.session.compacting` |
| `FileChanged` | `event:file.edited` + `event:file.watcher.updated` |
| `CwdChanged` | `shell.env` (dedup por cambio de cwd) |
| `ConfigChange` | `config` |
| `PostToolUseFailure` | `NOT_EXPOSED` (sin hook point nativo de tool-failure en v1.18) |

Eventos sin binding nativo (`Notification`, `PostToolUseFailure`, etc.) quedan
documentados como `# opencode-binding: NOT_EXPOSED — <razón>` en el header del
hook bash. La parity-audit los excluye del gap.

## Ejecución de hooks bash

- `shell-bridge` resuelve `$CLAUDE_PROJECT_DIR` **y** `$CLAUDE_PLUGIN_ROOT` del
  comando del hook.
- Cada hook corre con `bash -c` (interpolación `{raw}` para no romper comillas)
  y `cwd(projectRoot)`, con el payload en stdin vía fichero temporal local.
- Bloqueo por **dos contratos**: exit code 2 (Claude Code clásico) y stdout JSON
  `{"decision":"block"}` con exit 0 (patrón SE-337 commit guard y los gates de
  Stop).
- Los matchers `Bash(git commit*)` / `Bash:gh pr create*` se resuelven
  reconstruyendo el nombre compuesto `bash(<command>)` / `bash:<command>`.

### Anti-leak / timeout (SE-077 process-leak fix)

> Los hooks se lanzan con `Bun.spawn({ detached: true })` — cada hook vive en su
> propio proceso/process-group, NO como hijo pipe-able de `$` shell. Esto
> permite matar el ÁRBOL completo del hook (incl. hijos como `ollama classify`
> que cuelgan cuando el Shield daemon está caído).

- **Timeout kill**: si un hook excede su timeout (`runHookOnce`), se ejecuta
  `process.kill(-pid, SIGKILL)` contra el grupo del hook. Antes, el proceso se
  abandonaba vivo: sesiones largas acumulaban cientos de `bash` + `ollama`
  huérfanos (387 procesos / ~5000 FDs observados en 4 instancias en ~5h) y
  opencode quedaba prácticamente bloqueado.
- **Async hooks** (`async: true`) se lanzan con stdout/stderr a `/dev/null` y un
  hard-cap de 60s — nunca acumulan FDs en opencode.
- **Self-heal**: al cargar el plugin, `sweepOrphanedHooks()` elimina payloads
  `/tmp/savia-gates-<deadpid>-*.json` y mata hooks huérfanos de instancias
  opencode muertas. Para matar los hooks usa el **registro de pids**
  `/tmp/savia-gates-<owner>-hook-<hookpid>.json` que escribe cada spawn: enviar
  SIGKILL a un pid del mismo uid siempre está permitido, pero leer el
  `/proc/<pid>/fd/0` de un proceso ajeno lo bloquea Yama `ptrace_scope=1`
  (solo ancestros/descendientes). El barrido `/proc` queda como best-effort
  para el caso descendiente. Nunca toca procesos de pids vivos.
- **Heal manual**: `bash scripts/opencode-gates-heal.sh` (dead owners) o
  `--force` (también hooks colgados de pids vivos), `--dry-run` para prever.


## Garantías de seguridad (autonomous-safety)

- FAIL El plugin NUNCA hace `git push`, `gh pr merge`, `--force`
- FAIL El plugin NUNCA aprueba un PR autónomamente
- OK `permission.ask` retorna `deny` para acciones destructivas en branches `agent/*` o `spec-*`
- OK AUTONOMOUS_REVIEWER respetado vía variable de entorno (mismo contrato que Claude Code)
- OK Audit log append-only en `~/.savia/audit/savia-gates.jsonl`
- OK Plugins de sandbox (`opencode-sandbox`): si envuelven el comando antes que savia-gates (`bwrap … bash -c '<cmd>'`), los hooks `PreToolUse` evalúan la forma original y la desenvuelta, y basta con que una bloquee. Solo se desenvuelve un envoltorio limpio (tras la última comilla simple no queda más que cierres de comillas): `bwrap … -c 'echo hola'; rm -rf x` se evalúa entero (`lib/sandbox.ts`). Los guards TS de `savia-foundation` siguen la misma regla (`.opencode/plugins/lib/sandbox.ts`); antes, `sudo` envuelto pasaba.
- OK Guards fijados por quien arranca (T1). El motor crea una instancia por directorio y el plugin carga registro y scripts de `ctx.directory`; en un worktree `agent/*` eso es el directorio del agente. El registro queda en memoria hasta recargar la instancia, pero los scripts se ejecutan desde disco en cada llamada: un guard editado por el agente valía en la siguiente (canario 2026-10-03 contra OpenCode 1.18.32). Con `SAVIA_GATES_PIN=1` (Space lo pone en modo mediado) el plugin fija un hash por fichero la primera vez que carga cada directorio: el registro, cada script que nombra y el árbol de su directorio (salvo la raíz del proyecto o árboles de más de 1000 ficheros). Antes de cada `tool.execute.before`, `chat.message`, `command.execute.before` y `permission.ask` lo verifica; si algo cambió, bloquea todo con `GUARDS_MODIFIED` hasta reiniciar el motor (una recarga de instancia conserva el pin). Una edición (`edit`, `write`, `apply_patch`) sobre un guard se bloquea con `GUARD_PROTECTED`. No cubre lo que un hook carga fuera de esos directorios (por ejemplo `scripts/savia-env.sh`). Sin la variable, el comportamiento interactivo no cambia (`lib/guard-pin.ts`).

## Parity audit + canary

```bash
# Reporte de gap (texto)
bash scripts/opencode-parity-audit.sh

# Como JSON
bash scripts/opencode-parity-audit.sh --json

# Tras instalar, capturar el gap actual como baseline
bash scripts/opencode-parity-audit.sh --baseline

# Verificar regresión vs baseline
bash scripts/opencode-parity-audit.sh --check

# Canary mensual (compara equivalencia OpenCode vs Claude Code)
bash scripts/opencode-monthly-canary.sh --spec SE-073 --report-only
```

**Re-baseline post-instalación**: el baseline inicial commiteado refleja el estado pre-plugin (gap=N). Tras `bash scripts/opencode-install.sh` y la primera carga del plugin, ejecutar `--baseline` de nuevo y commitear el nuevo número.

## Pre-requisitos cumplidos

OpenCode v1.14.25 (latest abril 2026), Bun runtime (instalado por OpenCode), `.claude/settings.json` estable, AUTONOMOUS_REVIEWER configurado, AGENTS.md generado (SE-078).

## Referencias

- SE-077 spec — `docs/propuestas/SE-077-opencode-replatform-v114.md`
- SE-078 AGENTS.md cross-frontend — `docs/propuestas/SE-078-agents-md-cross-frontend.md`
- `https://github.com/sst/opencode` v1.14.25 (2026-04-25)
- `docs/rules/domain/autonomous-safety.md` — gates inviolables
- `docs/rules/domain/agents-md-source-of-truth.md` — SE-078
