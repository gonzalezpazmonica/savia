# Validated: 2026-06-08 (Copilot CLI 1.0.60, hooks ENABLED tras opt-in) — Test 1/3, ver tabla
# Copilot CLI cross-tool support — smoke test runbook (SE-179 + SE-180)

> ✅ Validado empíricamente el 2026-06-08: Copilot CLI 1.0.60 ejecuta los hooks
> de pm-workspace tras opt-in del usuario.
>
> ⚠️ **HALLAZGO crítico (SE-180):** Copilot CLI 1.0.60 NO lee `.claude/settings.json`
> directamente (a pesar de lo que docs.github.com sugiere). Lee **`.github/hooks/*.json`**
> desde gitRoot. Por eso este workspace genera `.github/hooks/savia.json` desde
> `.claude/settings.json` vía `bash scripts/generate-github-hooks.sh`.
>
> ⚠️ **OPT-IN del usuario:** la primera vez que Copilot CLI detecta hooks en el
> workspace, PIDE permiso al usuario para activarlos. Si el usuario los rechaza,
> los hooks NO se disparan. Verificar en la sesión que se aceptó el prompt.

## Pre-requisitos

| Requisito | Verificación |
|---|---|
| Copilot CLI Enterprise instalado | `gh copilot --version` |
| Versión mínima (TBD: documentar en validación) | ej. `>= 0.9.x` (verificar releases) |
| Cuenta Copilot Business/Enterprise activa | `gh copilot status` (o equivalente) |
| Workspace clonado en local | `git clone <repo-url> && cd <repo>` |
| Bash 5+ disponible (macOS: `brew install bash`) | `bash --version` |

## Setup

```bash
# 1. Clonar workspace en path limpio
cd ~/sandboxes
git clone <repo-url> copilot-test
cd copilot-test

# 2. Verificar que .claude/settings.json tiene hooks
jq '.hooks | keys' .claude/settings.json
# Esperado: ["PostToolUse","PreCompact","PreToolUse","SessionEnd","SessionStart","Stop","SubagentStop","UserPromptSubmit"]

# 3. Verificar que hooks .sh son ejecutables
ls -la .claude/hooks/*.sh | head -3
# Esperado: -rwx... (executable bit)

# 4. Confirmar que Copilot CLI detecta el workspace
gh copilot config show 2>&1 | head -20
# Buscar: referencia a .claude/settings.json o .claude/settings.local.json
```

## Test 1: PreToolUse blocking — credential leak

**Hipótesis:** Copilot CLI dispara `block-credential-leak.sh` cuando se intenta ejecutar un bash command con un credential pattern.

```bash
# Intentar ejecutar comando con credential pattern fixture (NO real)
gh copilot suggest 'execute: echo SECRET_KEY_VAR=<dummy-token-placeholder>' 2>&1
```

**Resultado esperado:**

- Copilot CLI responde con `permissionDecision: "deny"` o equivalente.
- `block-credential-leak.sh` emite mensaje a stderr indicando el patrón detectado.
- Comando NO se ejecuta.

**Si pasa:** ✅ PreToolUse + cross-tool support funciona.
**Si falla:** ❌ Capturar output completo + ejecutar diagnóstico (sección abajo).

## Test 2: SessionStart context injection

**Hipótesis:** Copilot CLI dispara `session-init.sh` al inicio de sesión y el output llega al modelo como contexto.

```bash
# Iniciar nueva sesión
gh copilot chat 'what workspace am I in?' 2>&1
```

**Resultado esperado:**

- `session-init.sh` se ejecuta antes de que el modelo procese el prompt.
- Respuesta del modelo incluye contexto inyectado por el hook (ej. "Savia Init").

**Si pasa:** ✅ SessionStart support funciona.
**Si falla:** verificar logs en `~/.copilot/logs/` y reportar.

## Test 3: agentStop (= Claude Code Stop) hook

**Hipótesis:** Copilot CLI dispara `postponement-judge.sh` al terminar el agente, bloqueando deferimientos no justificados.

```bash
# Provocar respuesta que contiene "lo dejamos para mañana"
gh copilot chat 'I want to defer all work until tomorrow' 2>&1
```

**Resultado esperado:**

- Si el agente intenta postponer sin razón válida, `postponement-judge.sh` fuerza una iteración más.
- Output incluye el push-back.

**Si pasa:** ✅ agentStop (Stop) hook funciona.
**Si falla:** considerar que el evento se llama distinto en la versión instalada.

## Diagnóstico si algún test falla

```bash
# 1. Verificar versión de Copilot CLI
gh copilot --version

# 2. Verificar que cross-tool reading está activo
gh copilot --debug config 2>&1 | grep -i "claude\|settings\|hooks"

# 3. Verificar que .claude/settings.json es leído
strace -e trace=openat -f gh copilot config show 2>&1 | grep "settings.json" | head -5
# Si no aparece .claude/settings.json en los openat, el cross-tool no está activo

# 4. Forzar configuración explícita (si var soportada)
COPILOT_CONFIG_FILE=.claude/settings.json gh copilot config show

# 5. Revisar issues GitHub
gh issue list --repo github/copilot-cli --search "claude settings" --state all
```

## Schema compatibility quick-check (sin necesidad de Copilot CLI)

Ejecutar antes del test empírico para validar que `.claude/settings.json` cumple el contrato de Copilot CLI:

```bash
bats tests/structure/test-copilot-cli-compat.bats
# Esperado: 4/4 PASS + 1 skip (doc cross-frontend reference)
```

## Reportar resultado

Una vez ejecutado el runbook:

```bash
# Si exitoso, reemplazar línea 1 del fichero
sed -i '' "1s/.*/# Validated: $(date +%Y-%m-%d) by $(git config user.name | tr ' ' '-')/" docs/runbooks/copilot-cli-cross-tool-smoke.md

# Confirmar
head -1 docs/runbooks/copilot-cli-cross-tool-smoke.md
```

## Resultados conocidos

| Fecha | User | Copilot CLI version | Resultado | Notas |
|---|---|---|---|---|
| 2026-06-08 | contributor | 1.0.60 | ⚠️ PARCIAL (1/3) | Tras opt-in. Hooks ejecutados desde `.github/hooks/savia.json` (generado por `scripts/generate-github-hooks.sh`). Test 1 (block-credential-leak): bloqueó como esperado con mención explícita al hook. Tests 2/3 (SessionStart injection, agentStop) pendientes de ejecución. |

## Referencias

- [GitHub Copilot hooks reference](https://docs.github.com/en/copilot/reference/hooks-configuration)
- [Using hooks with GitHub Copilot CLI](https://docs.github.com/en/copilot/how-tos/copilot-cli/customize-copilot/use-hooks)
- SE-178 — `docs/rules/domain/cross-frontend-coverage.md`
- SE-179 — esta spec

## Verificación `permissionDecision`

Después de ejecutar Test 1, el output esperado contiene la cadena `permissionDecision` con valor `deny`, confirmando que el hook PreToolUse intervino correctamente. Si esa cadena no aparece, el hook no se está disparando (cross-tool no activo).
