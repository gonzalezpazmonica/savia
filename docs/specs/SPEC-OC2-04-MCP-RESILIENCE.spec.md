# Spec: MCP resilientes y rutas deterministas

**Task ID:**        SPEC-OC2-04
**PBI padre:**      Adaptación de Savia a OpenCode 2
**Sprint:**         2026-42 (nocturno)
**Fecha creación:** 2026-10-18
**Creado por:**     Savia (overnight-sprint)

**Developer Type:** agent-single
**Asignado a:**     agent
**Estimación:**     1.5h
**Estado:**         Pendiente
**Prioridad:**      ALTA
**Max turns:**      12

---

## 1. Contexto y motivación

Los tres MCP de Savia fallaban el 2026-10-18:

| Servidor | Error | Causa |
|---|---|---|
| `codegraph` | `env: …/v22.23.2/bin/codegraph: No existe` | nvm eliminado; binario inexistente |
| `codebase-memory-mcp` | `NotFound` | binario inexistente en `~/.local/bin` |
| `savia-vaults` | `NotFound` | `dist/cli/index.js` sin compilar y node de nvm |

`vault_search` es la prioridad 1 de `knowledge-discovery-priority.md`: sin él,
Savia cae a memoria y grep.

## 2. Objetivo

Que `opencode mcp list` no muestre fallos inesperados: los servidores
recuperables conectan y los no recuperables quedan desactivados con motivo.

## 3. Alcance

- Dentro: bloque `mcp` de `opencode.json`, build de `projects/savia-vaults`.
- Fuera: instalar binarios globales (`codegraph`, `codebase-memory-mcp`).

## 4. Diseño

1. **Intérprete determinista**: `/usr/bin/env node` (v22.23.3) y rutas relativas
   al workspace para scripts y domes (sin `/home/<usuario>` en repo público).
2. **savia-vaults**: `npm ci && npm run build` (lockfile pinneado); se activa
   con `enabled: true`.
3. **Servidores no recuperables**: se conserva la definición, se marca
   `enabled: false` (V1) y `disabled: true` (V2) con el comando de
   reinstalación documentado en el PR.
4. **Compatibilidad**: `enabled`/`disabled` conviven; V1 lee `enabled`, V2
   nativo lee `disabled`.

## 5. Criterios de aceptación

- **AC-1** `savia-vaults` aparece conectado en `opencode mcp list`.
- **AC-2** `codegraph` y `codebase-memory-mcp` aparecen desactivados sin error
  de spawn.
- **AC-3** Ninguna ruta de comando depende de `~/.nvm`.
- **AC-4** El build de vaults es reproducible con `npm ci` y `npm run build`.
- **AC-5** El health check reporta el estado MCP sin fallar por servidores
  desactivados.

## 6. Verificación

```bash
opencode mcp list
bash scripts/opencode-health-check.sh
```

## 7. Riesgos

- `codegraph` y `codebase-memory-mcp` quedan sin funcionalidad hasta que se
  reinstalen; se documenta el comando y el impacto (navegación de callers).
- El build de vaults requiere red la primera vez (`npm ci`).

## OpenCode Implementation Plan

### Bindings touched

| Componente | Claude Code | OpenCode 1 | OpenCode 2 |
|---|---|---|---|
| MCP | `.mcp.json` (si existe) | `mcp.<name>` | `mcp.<name>` (deprecated) o `mcp.servers` |
| Estado | n/a | `enabled` | `disabled` |
| Vaults | n/a | proceso local | proceso local |

### Verification protocol

- [x] `opencode mcp list` ejecutado tras el cambio
- [x] Build de vaults verificado (`dist/cli/index.js`)
- [ ] Conexión de vaults validada por tools reales (requiere sesión)

### Portability classification

- [x] **PURE_BASH** para el build; **DUAL_BINDING** para la configuración
      (mismas claves locales en ambos runtimes).
