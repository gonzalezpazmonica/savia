---
context_tier: L3
token_budget: 1056
---

# Hook Profiles — SAVIA_HOOK_PROFILE

> **Por qué existe esto**: Los LLMs olvidan instrucciones ~20% de las veces.
> Las reglas críticas deben vivir en hooks deterministas, no en CLAUDE.md.
> Los perfiles controlan qué hooks corren según el contexto de trabajo.
> Guia de usuario: `docs/savia-shield-guide.md`

## Los 4 perfiles

| Perfil | Qué activa | Cuándo usarlo |
|--------|------------|---------------|
| `minimal` | Solo blockers de seguridad | Demos, onboarding, debugging de hooks |
| `standard` | Seguridad + todos los gates de calidad | **Default** — trabajo diario |
| `strict` | Todo + scrutinio extra | Antes de releases, código crítico |
| `ci` | Igual que standard pero no interactivo | Pipelines CI/CD, scripts automáticos |

## Qué incluye cada perfil

### Tier `security` (siempre activo en todos los perfiles)
Hooks que **nunca se saltan** porque protegen datos o infraestructura:
- `block-credential-leak.sh` — bloquea credenciales en comandos
- `block-force-push.sh` — bloquea git push --force a main
- `block-infra-destructive.sh` — bloquea comandos terraform destroy, etc.
- `data-sovereignty-gate.sh` — Savia Shield, bloquea datos N4 en ficheros N1

### Tier `standard` (activo en standard, ci y strict)
Gates de calidad del workflow diario:
- `validate-bash-global.sh` — valida scripts bash
- `plan-gate.sh` — verifica spec aprobada antes de editar
- `block-project-whitelist.sh` — protege privacidad de proyectos
- `tdd-gate.sh` — requiere tests antes de código de producción
- `scope-guard.sh` — alerta si se edita fuera del scope de la spec
- `compliance-gate.sh` — verifica reglas de compliance
- `agent-hook-premerge.sh` — quality gate pre-merge
- `prompt-hook-commit.sh` — valida semántica de commits
- `postponement-judge.sh` — bloquea deferrals injustificados ("mañana seguimos" sin motivo) y fuerza continuación

### Tier `strict` (solo en strict)
Extra scrutinio para código crítico:
- `agent-dispatch-validate.sh` — valida contexto del agente antes de dispatchar
- `stop-quality-gate.sh` — quality gate adicional al parar
- `competence-tracker.sh` — tracking de competencias del equipo

### Siempre activos (observabilidad, no bloquean)
Hooks de logging y memoria corren independientemente del perfil:
- `agent-trace-log.sh`, `data-sovereignty-audit.sh`, `memory-auto-capture.sh`
- `memory-prime-hook.sh`, `pbi-history-capture.sh`, `pre-compact-backup.sh`
- `session-init.sh`, `session-end-snapshot.sh`

## Cambiar perfil

```bash
# Ver perfil activo
bash scripts/hook-profile.sh get

# Validar el nombre e imprimir cómo fijarlo (no escribe ningún fichero;
# el perfil solo se lee de la variable SAVIA_HOOK_PROFILE)
bash scripts/hook-profile.sh set minimal
bash scripts/hook-profile.sh set standard   # ← default
bash scripts/hook-profile.sh set strict
bash scripts/hook-profile.sh set ci

# O con el comando slash
/hook-profile set ci
```

## Variable de entorno

```bash
# En cualquier shell o script
export SAVIA_HOOK_PROFILE=ci

# En CI/CD (GitHub Actions, Azure Pipelines, etc.)
env:
  SAVIA_HOOK_PROFILE: ci
```

## Añadir soporte de perfiles a un hook nuevo

```bash
#!/bin/bash
set -uo pipefail
# mi-hook.sh — Descripción

# Tier: standard  ← documentar el tier de este hook
LIB_DIR="$(dirname "${BASH_SOURCE[0]}")/lib"
if [[ -f "$LIB_DIR/profile-gate.sh" ]]; then
  # shellcheck source=/dev/null
  source "$LIB_DIR/profile-gate.sh"
  profile_gate "standard"   # salir si el perfil es < standard
fi

# ... resto del hook ...
```

## Principio: Hooks sobre prompts

Los LLMs olvidan instrucciones del ~20% de las conversaciones (documentado en
Everything Claude Code, gstack, Astromesh — tres proyectos que convergieron
independientemente en esta conclusión).

Regla de arquitectura: **Si una regla es crítica, va en un hook. No en CLAUDE.md.**

| Tipo de regla | Mecanismo correcto |
|--------------|-------------------|
| "No hardcodees PATs" | Hook regex en `block-credential-leak.sh` |
| "No pushes a main" | Hook en `block-force-push.sh` |
| "Tests antes de código" | Hook `tdd-gate.sh` |
| "Confirmar antes de infra" | Hook `block-infra-destructive.sh` |
| Preferencias de estilo | CLAUDE.md (olvidar ok) |
| Guías de comunicación | CLAUDE.md (olvidar ok) |
