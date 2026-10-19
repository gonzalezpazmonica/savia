---
context_tier: L3
token_budget: 1031
---

# Regla: OpenCode ↔ Savia bridge

> Permite operar pm-workspace desde OpenCode 1 (>= 1.18.29) o 2 sin perder hooks, AUTONOMOUS_REVIEWER ni la base instalada de skills/agents. Vigente desde SE-077 Slice 1+2.

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
# Instala OpenCode 2 (@opencode/cli, recomendado) en ~/.savia/opencode/ y enlaza el plugin savia-gates
bash scripts/opencode-install.sh

# OpenCode 1 (paquete opencode-ai, >= 1.18.29) o versión específica
bash scripts/opencode-install.sh --flavor v1
bash scripts/opencode-install.sh --version 2.0.32

# Sólo re-enlazar el plugin (binary ya instalado)
bash scripts/opencode-install.sh --link-only

# Dry-run — muestra el plan sin tocar nada
bash scripts/opencode-install.sh --dry-run

# Desinstalar
bash scripts/opencode-install.sh --uninstall
```

La instalación (`opencode-install.sh`) genera el manifest `~/.savia/opencode/plugins/savia-gates/manifest.json` que la herramienta de parity-audit usa para detectar gaps; es determinista y se regenera con `bun scripts/opencode-plugin/savia-gates/lib/manifest.ts`. El plugin no escribe en su directorio al cargarse: forma parte de la huella del motor (pluginSetHash de Savia Space).

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

## OpenCode 1 y 2: un plugin, dos enlaces

`index.ts` exporta un objeto con `id` + `setup()` (OpenCode 2) y `server()` (OpenCode >= 1.18.29): un plugin solo-V1 **no carga** en OpenCode 2 y los guards se perdían sin error. Las decisiones viven en `lib/gates.ts`; `lib/v1-adapter.ts` (hooks por clave) y `lib/v2-adapter.ts` (hooks por dominio, un evento mutable) solo traducen. En V2 los nombres se normalizan antes de decidir (`shell`→`bash`, `subagent`→`task`, `path` visible también como `filePath`) y el bloqueo es fallo cerrado: una excepción en `tool.execute.before` rechaza esa llamada, en `prompt` no se admite el prompt, y si los guards no arrancan se rechaza todo (`GUARDS_UNAVAILABLE`). OpenCode 1.19 también llama a `setup()` con un contexto reducido: ahí no hace nada.

| Guard | V1 | V2 |
|---|---|---|
| PreToolUse (hooks, cúpulas, pin) | `tool.execute.before` | `ctx.tool.hook("execute.before")` |
| PostToolUse | `tool.execute.after` | `ctx.tool.hook("execute.after")` |
| UserPromptSubmit y contexto por proveedor | `chat.message` (partes sintéticas) | `ctx.session.hook("prompt")` + `"context"` (por modelo de cada petición) |
| AUTONOMOUS_REVIEWER | `permission.ask` | `ctx.permission.hook("evaluate")` |
| `command.execute.before` | hook propio | sin equivalente: el prompt de un comando pasa por `prompt` y sus herramientas por `execute.before` |
| FileChanged | `file.edited` | resultado de `edit`/`write`/`patch` |
| Stop, SessionStart/End, PostCompact, PreCompact, ConfigChange | eventos | `ctx.event.subscribe()` |
| CwdChanged | `shell.env` | `ctx.shell.hook("create.before")` |

Prueba contra el motor real (sin modelo ni red, aislado en un directorio temporal): `python3 scripts/opencode-gates-real.py` (`--engine v1|v2`); en bats, `SAVIA_GATES_REAL=1`.

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
- OK Guards fijados por quien arranca (T1). El motor crea una instancia por directorio y el plugin carga registro y scripts de `ctx.directory`; en un worktree `agent/*` eso es el directorio del agente. El registro queda en memoria hasta recargar la instancia, pero los scripts se ejecutan desde disco en cada llamada: un guard editado por el agente valía en la siguiente (canario 2026-10-03 contra OpenCode 1.18.32). Con `SAVIA_GATES_PIN=1` (Space lo pone en modo mediado), la primera carga de cada directorio copia `.claude/hooks`, `scripts/` y el registro a un directorio privado (0700, ficheros de solo lectura, fuera del workspace). Cada hook se ejecuta bajo `bwrap --dev-bind / /` con esa copia montada de solo lectura sobre las rutas del workspace y sobre los alias que nombra el registro (`.opencode/hooks -> ../.claude/hooks`), y el registro se lee de la copia (`lib/trusted-guards.ts`). Así lo que un guard carga con `source`, `.`, `$(dirname "${BASH_SOURCE[0]}")/../../scripts/…` o `$CLAUDE_PROJECT_DIR/scripts/…` (por ejemplo `scripts/savia-env.sh`, que cargan 41 hooks) sale de la copia: editarlo, sustituir `scripts/` por un enlace o alternar ficheros en carrera no llega a los guards, y el agente puede seguir editando scripts sin bloquear el motor. Además se fija por hash el registro, cada script que nombra, el árbol de su directorio, `.env` y `.venv/bin/activate` (`lib/guard-pin.ts`); la copia se vigila por inodo, tamaño, ctime y modo. Antes de cada `tool.execute.before`, `chat.message`, `command.execute.before` y `permission.ask` se verifica todo, y en los tres primeros se vuelve a verificar después de los hooks y antes de permitir: una escritura en la copia mientras corre el pipeline (cientos de ms) bloquea esa misma decisión, porque cualquier escritura que un hook pudo leer ya ha cambiado el ctime; la primera violación bloquea con `GUARDS_MODIFIED` hasta reiniciar el motor, aunque se restaure el fichero (una recarga de instancia conserva pin y copia). Una edición (`edit`, `write`, `apply_patch`) sobre un guard fijado se bloquea con `GUARD_PROTECTED`. Sin `bwrap` utilizable (`SAVIA_GATES_BWRAP` cambia la ruta) toda decisión se bloquea con `GUARDS_ISOLATION_UNAVAILABLE`. Límites: la copia sale del disco en la primera carga, no de `HEAD` (Space sí ancla en `HEAD` o en lo aprobado); no cubre los paquetes Python de `.venv` ni lo que un hook lea fuera de esos directorios; la copia vive en `tmpdir()` con el mismo uid que el agente, así que un agente que pueda escribir fuera de su worktree puede modificarla (0700/0400 no frena al propietario): eso no se impide (es tarea del sandbox del motor), pero se detecta antes de devolver la decisión, sin dejar pasar la acción en curso. Coste medido con el registro real: unos 10 ms de verificación y unos 4 ms de `bwrap` por hook ejecutado. Sin la variable, el comportamiento interactivo no cambia.
- OK Contexto de `UserPromptSubmit` fuera de la nube. Lo que un hook añade con `additionalContext` no lleva nivel de confidencialidad, así que cuenta como N3 y solo se adjunta al prompt si el turno es local según dos señales a la vez: `SAVIA_GATES_ENGINE_LANE` (Space la exporta como `cloud` o `local`; sin Space no existe) y los proveedores que alcanza el turno (modelo del mensaje, `model`, `small_model` para el título, el modelo del agente y los modelos de los agentes internos `title`, `summary` y `compaction`, leídos de la configuración efectiva) declarados locales en `SAVIA_GATES_LOCAL_PROVIDERS` (lista separada por comas). Si una de las dos dice nube, o el proveedor no se puede resolver, solo se adjunta el contexto que el hook declara `N1` con `hookSpecificOutput.saviaLevel`; el resto se retiene y se registra `prompt-context-withheld` (sin el texto). Por defecto, en el OpenCode CLI sin Space y sin proveedores declarados, no se adjunta nada sin nivel. La configuración se consulta solo si hay contexto que filtrar y con un límite de 3 s; si no responde, cuenta como nube. Cada hook aporta su propio contexto; antes solo llegaba el del último. Límite conocido: el contexto adjuntado en un turno local queda en el historial de la sesión; si después se cambia a un modelo de nube en la misma sesión (CLI sin Space), el historial con esa parte sintética se reenvía. El plugin no reescribe mensajes ya guardados; con Space el carril es fijo por sesión. Para cambiar a nube, abrir una sesión nueva.

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
