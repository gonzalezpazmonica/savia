# Spec: Endurecimiento de la ejecución de Savia en OpenCode 2

**Task ID:**        SPEC-OC2-03
**PBI padre:**      Adaptación de Savia a OpenCode 2
**Sprint:**         2026-42 (nocturno)
**Fecha creación:** 2026-10-18
**Creado por:**     Savia (overnight-sprint)

**Developer Type:** agent-single
**Asignado a:**     agent
**Estimación:**     2h
**Estado:**         Pendiente
**Prioridad:**      ALTA
**Max turns:**      15

---

## 1. Contexto y motivación

Con los plugins caídos (SPEC-OC2-01), los únicos límites efectivos en V2 eran
los `permission` de V1 normalizados. V2 cambia dos reglas que importan:

1. `external_directory` está permitido por defecto (V1 preguntaba).
2. `subagent_depth` por defecto es 1: un subagente no puede lanzar subagentes,
   lo que rompe el encadenado de `dev-orchestrator` → `*-developer`.

## 2. Objetivo

Que la ejecución en V2 tenga límites duros verificables y que la orquestación
SDD pueda encadenar dos niveles, sin depender solo de guards cooperativos.

## 3. Alcance

- Dentro: `opencode.json` (`permissions`, `policies`, `subagent_depth`),
  `scripts/opencode-health-check.sh`.
- Fuera: hooks de Claude Code/Codex, política de red.

## 4. Diseño

1. **Permissions** (V2):
   - `external_directory: ask` — recupera el comportamiento V1.
   - `subagent: allow` — la restricción real la fija `subagent_depth`.
2. **Policies** (binarias, no preguntan, ganan a aprobaciones guardadas):
   - `shell:git push --force*`, `shell:git push -f*` → deny
   - `shell:git push origin main*`, `shell:git push origin master*` → deny
   - `shell:rm -rf /*`, `shell:sudo *` → deny
   - `edit:*.env` → deny
   No se bloquean pushes a ramas `agent/*` ni a ramas de trabajo.
3. **subagent_depth: 2** para la cadena orquestador → developer.
4. **Gate** `scripts/opencode-health-check.sh`:
   - versión de OpenCode y canal
   - `opencode plugin list` (detecta plugins locales)
   - `opencode mcp list` (fallos inesperados)
   - `opencode debug config` (presencia de `permissions`, ausencia de `model_tier`)
   - smoke del plugin dual
   Salida PASS/WARN/FAIL con exit code.

## 5. Criterios de aceptación

- **AC-1** `permissions` efectivos incluyen `external_directory: ask`.
- **AC-2** `policies` incluye las 6 reglas y ninguna bloquea ramas `agent/*`.
- **AC-3** `subagent_depth` vale 2 en la config efectiva.
- **AC-4** El gate detecta un plugin no cargado y devuelve FAIL.
- **AC-5** El gate devuelve PASS en el estado sano (plugin dual + MCP conocidos).
- **AC-6** El gate no modifica configuración ni estado (solo lectura).

## 6. Verificación

```bash
bash scripts/opencode-health-check.sh
```

## 7. Riesgos

- `policies` solo existe en V2: en V1 el límite sigue siendo el guard.
- Un `policy` demasiado amplio puede bloquear trabajo legítimo; las reglas se
  limitan a force-push, main/master, root destructivo, sudo y `.env`.

## OpenCode Implementation Plan

### Bindings touched

| Componente | Claude Code | OpenCode 1 | OpenCode 2 |
|---|---|---|---|
| Límites duros | `settings.json` permissions | `permission` | `permissions` + `policies` |
| Profundidad subagentes | n/a | n/a | `subagent_depth` |
| Gate de salud | n/a | `opencode` CLI | `opencode` CLI + API |

### Verification protocol

- [x] Gate ejecutado contra V2 real
- [ ] Verificado en OpenCode 1 real (no instalado)
- [x] Sin efectos secundarios: el gate es de solo lectura

### Portability classification

- [x] **DUAL_BINDING** con deuda declarada: `policies` y `subagent_depth` son
      V2-only; en V1 la protección equivalente son los guards.
