# Plan de adaptación de Savia a OpenCode 2

**Estado:** propuesta para revisión (2026-10-18)
**Alcance:** mantener operativos OpenCode 2, OpenCode 1, Claude Code y Codex
**Evidencia base:** OpenCode v2.0.32 instalado; `opencode debug config` y log del servicio del 2026-10-18

## 1. Diagnóstico verificado

| Hecho | Evidencia |
|---|---|
| Los plugins V1 no cargan en V2 (`Plugin must export a default definition with an id and an effect or setup function`) | log `~/.local/share/opencode/log/opencode.log` |
| Los 28 guards de `.opencode/plugins/guards/` no se ejecutan en V2 | misma entrada de log, 3 plugins locales + `opencode-sandbox` |
| `model_tier` de agente se copia a `request.body` (clave desconocida) | `opencode debug config` |
| `external_directory` pasa a `allow` por defecto en V2 | docs V2 Permissions |
| `subagent_depth` por defecto 1: un subagente no lanza subagentes | docs V2 schema |
| Los 3 MCP fallan (node 22.23.2 inexistente, binarios ausentes, `dist/` sin compilar) | `opencode mcp list` |
| `tui.json` ya no se lee; no hay keybind V2 para invocar un comando por nombre | docs V2 CLI/Keybinds |

## 2. Invariantes

1. Los guards son funciones puras: mismo comportamiento en los cuatro frontends.
2. Ningún frontend depende de nombres de proveedor (PV-06).
3. OpenCode 1 sigue funcionando con el formulario objeto (`server()`), mínimo 1.18.29.
4. Claude Code sigue usando `.claude/hooks/*` y Codex `.codex/hooks.json`; este plan no los toca.
5. Ningún cambio de comportamiento sin evidencia ejecutable (smoke o gate).

## 3. Matriz de compatibilidad

| Frontend | Punto de entrada | Estado tras el plan |
|---|---|---|
| OpenCode 2 | `.opencode/plugins/savia-foundation.ts` export objeto `{id, setup, server}` | guards activos vía `ctx.tool.hook` |
| OpenCode 1 ≥1.18.29 | mismo archivo, `server()` | guards activos vía hooks V1 |
| OpenCode 1 <1.18.29 | no soportado por el objeto; requiere el export función | fuera de baseline (declarado) |
| Claude Code | `.claude/hooks/*.sh` + `settings.json` | sin cambios |
| Codex | `.codex/hooks.json` | sin cambios |

## 4. Fases

### P0 — Recuperar la red de seguridad (SPEC-OC2-01)

- Export dual V1/V2 en un solo archivo.
- Adaptador `lib/v2-compat.ts`: evento V2 → `(input, output)` V1 y normalización `shell→bash`, `subagent→task`.
- Smoke ejecutable sin bun (`node --experimental-strip-types`).

**Aceptación:** el smoke bloquea force-push y push a main por la ruta V2 y por la V1.

### P1 — Configuración sin fugas (SPEC-OC2-02)

- Tiers fuera del agente: `x_savia_model_tiers` de nivel superior.
- Claves nativas V2 aditivas que V1 ignora: `permissions`, `policies`, `subagent_depth`, `snapshots`, `update`.
- Eliminar `opencode-sandbox` y `experimental.sandbox` (plugin roto, V2 sin sandbox).

**Aceptación:** `opencode debug config` no muestra `model_tier` en `request.body`; `permissions` incluye `external_directory: ask`.

### P2 — Endurecer ejecución (SPEC-OC2-03)

- Policies duras: force-push, push a main/master, `rm -rf /`, `sudo`, `*.env`.
- Profundidad de subagentes 2 para orquestación SDD.
- Gate `scripts/opencode-health-check.sh`: versión, plugins activos, MCP, permisos efectivos.

**Aceptación:** el gate devuelve PASS con el plugin cargado y los MCP en estado conocido.

### P3 — MCP resiliente (SPEC-OC2-04)

- Intérprete del sistema (`/usr/bin/env node`) y rutas relativas al workspace.
- `savia-vaults` compilado y activo; `codegraph` y `codebase-memory-mcp` desactivados con motivo y comando de reinstalación.
- Estado dual `enabled` (V1) / `disabled` (V2).

**Aceptación:** `opencode mcp list` sin fallos inesperados; `savia-vaults` conectado.

### P4 — Deuda documentada

- `tui.json` se conserva para OpenCode 1; V2 no tiene keybind para comandos por nombre (limitación upstream).
- Tiers en V2: el adaptador no transforma agentes; los agentes usan el modelo de sesión hasta que exista `ctx.agent.transform` con mapeo validado.

## 5. Riesgos

| Riesgo | Mitigación |
|---|---|
| V1 <1.18.29 rompe con export objeto | baseline declarado y archivo legacy documentado |
| Un guard V2 no dispara por nombres de tool | normalización centralizada + smoke con `shell` y `subagent` |
| `policies` bloquea pushes legítimos | solo force-push y main/master; pushes de ramas `agent/*` permitidos |
| Cambios de config afectan a Claude Code/Codex | solo claves de OpenCode; hooks de otros frontends intactos |

## 6. Rollback

- Revertir el commit de `savia-foundation.ts` a la función V1.
- Revertir `opencode.json` al estado anterior (guardado en el PR).
- Los MCP desactivados se rehabilitan con `enabled: true` y el binario instalado.

## 7. Verificación

```bash
node --experimental-strip-types .opencode/plugins/__tests__/v2-compat.smoke.ts
bash scripts/opencode-health-check.sh
opencode mcp list
opencode debug config
bash scripts/validate-ci-local.sh --quick
```
