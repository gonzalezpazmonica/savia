# Spec: Plugin dual OpenCode 1 / OpenCode 2

**Task ID:**        SPEC-OC2-01
**PBI padre:**      Adaptación de Savia a OpenCode 2
**Sprint:**         2026-42 (nocturno)
**Fecha creación:** 2026-10-18
**Creado por:**     Savia (overnight-sprint)

**Developer Type:** agent-single
**Asignado a:**     agent
**Estimación:**     3h
**Estado:**         Pendiente
**Prioridad:**      CRÍTICA
**Max turns:**      20

---

## 1. Contexto y motivación

OpenCode 2 rompe la API de plugins: V1 exporta una función que devuelve hooks
por clave; V2 exige un default export con `id` y `setup(ctx)` que registra
hooks por dominio (`ctx.tool.hook("execute.before", …)`).

Estado verificado el 2026-10-18: el servicio V2 registra
`failed to load plugin … must export a default definition with an id` para
`savia-foundation.ts`, y los 28 guards de `.opencode/plugins/guards/` no se
ejecutan. Savia opera sin force-push guard, sin bloqueo de credenciales, sin
gate de soberanía y sin ledger de ediciones.

Además, V2 renombró tools: `bash` → `shell` y `task` → `subagent`. Un adaptador
que solo cambie la forma del hook deja los guards de comandos inertes.

## 2. Objetivo

Un único archivo de entrada que funcione en OpenCode 1 (≥1.18.29) y OpenCode 2,
con los guards ejecutándose y evidencia ejecutable de que bloquean.

## 3. Alcance

- Dentro: `.opencode/plugins/savia-foundation.ts`, `.opencode/plugins/lib/v2-compat.ts`, smoke test.
- Fuera: los guards (no cambian), hooks de Claude Code, `.codex/hooks.json`.

## 4. Diseño

1. **Export dual documentado por OpenCode**:
   ```ts
   export default { id: "savia-foundation", setup, server }
   ```
   V2 lee `id` + `setup`; V1 ≥1.18.29 llama `server()` y usa los hooks devueltos.
2. **Adaptador** (`lib/v2-compat.ts`):
   - `execute.before`: `{tool, input}` → `{input:{tool,args}, output:{args}}` con
     `output.args === event.input` (las mutaciones llegan al runtime).
   - `execute.after`: `{status, result}` → `output.output` textual.
   - `normalizeToolName`: `shell→bash`, `subagent→task`.
3. **Saneamiento**: hook `session.model.request` elimina `model_tier` y claves
   `x_savia_*` del cuerpo enviado al proveedor.
4. **after-guards** siguen siendo non-blocking (try/catch por guard).

## 5. Criterios de aceptación

- **AC-1** El default export tiene `id`, `setup` y `server`.
- **AC-2** `normalizeToolName("shell") === "bash"` y `("subagent") === "task"`.
- **AC-3** Un evento V2 `{tool:"shell", input:{command:"git push --force …"}}`
  a través de `setup()` lanza `BLOCKED [force-push]`.
- **AC-4** La ruta V1 (`server()`) bloquea `git push origin main`.
- **AC-5** `toV1Before` mantiene la identidad `output.args === event.input`.
- **AC-6** El hook `model.request` deja el body sin `model_tier`.
- **AC-7** El smoke corre con `node --experimental-strip-types` (sin bun) y sale 0.
- **AC-8** El plugin carga en un servidor V2 real sin `failed to load plugin`.

## 6. Verificación

```bash
node --experimental-strip-types .opencode/plugins/__tests__/v2-compat.smoke.ts
```

## 7. Riesgos

- V1 <1.18.29 no soporta el formulario objeto → baseline declarado, pendiente
  archivo legacy si se necesita esa versión.
- El hook `session.model.request` es best-effort: si el runtime no lo expone,
  el saneamiento no aplica y queda como deuda con evidencia en el health check.

## OpenCode Implementation Plan

### Bindings touched

| Componente | Claude Code | OpenCode 1 | OpenCode 2 |
|---|---|---|---|
| Guards | `.claude/hooks/*.sh` (sin cambios) | `server()` → `tool.execute.before/after` | `setup()` → `ctx.tool.hook("execute.before/after")` |
| Normalización tools | n/a | nombres V1 nativos | `shell→bash`, `subagent→task` |
| Sanitización body | n/a | `config` hook (`applyModelTiers`) | `ctx.session.hook("model.request")` |

### Verification protocol

- [x] Funciona en runtime OpenCode 2 (hook registrado por dominio)
- [x] Funciona en contrato V1 (`server()` invocado en el smoke)
- [ ] Verificado con binario OpenCode 1 real (no instalado en la máquina; el
      contrato está cubierto por smoke; validar en la primera sesión OC1)
- [x] Sin bun: el smoke usa `node --experimental-strip-types`

### Portability classification

- [x] **DUAL_BINDING**: la lógica vive en los guards (TS puro) y el adaptador
      cubre V1 y V2 desde el mismo archivo.
