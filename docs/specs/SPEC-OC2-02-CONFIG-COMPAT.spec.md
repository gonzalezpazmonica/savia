# Spec: Configuración compatible V1/V2 sin fugas al proveedor

**Task ID:**        SPEC-OC2-02
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

`opencode debug config` con V2 muestra que las claves desconocidas de un agente
se copian a `request.body`. Savia usa `model_tier` en `build`, `plan`,
`explore` y `general`; V2 lo envía al proveedor en cada petición.

Además, la config usa solo la forma V1 (`permission`, `snapshot`, `autoupdate`,
`plugin`) y depende de la normalización en memoria de V2. Esa normalización es
compatible pero deja fuera controles que V2 ya soporta de forma nativa.

## 2. Objetivo

Configuración que V1 entiende y V2 interpreta sin fugas: claves nativas V2
aditivas (V1 las ignora) y tiers fuera del objeto agente.

## 3. Alcance

- Dentro: `opencode.json`, `.opencode/plugins/lib/model-tiers.ts`.
- Fuera: configuración global del usuario (`~/.config/opencode`), que se trata
  como entorno y se reporta aparte.

## 4. Diseño

1. **Tiers**: `x_savia_model_tiers: { build: "fast", … }` en la raíz.
   `applyModelTiers` los mapea a `cfg.agent[name]` y borra `model_tier` después
   de resolver. La forma antigua sigue funcionando como fallback.
2. **Claves V2 aditivas**:
   - `permissions: [{ external_directory: ask }, { subagent: allow }]`
   - `policies`: ver SPEC-OC2-03
   - `subagent_depth: 2`
   - `snapshots: true` (junto a `snapshot: true` de V1)
   - `update: "disable"` (junto a `autoupdate: false` de V1)
3. **Limpieza**: se elimina `opencode-sandbox` y `experimental.sandbox`
   (el plugin falla al cargar en V2 y V2 no tiene sandbox nativo).

## 5. Criterios de aceptación

- **AC-1** `opencode debug config` no muestra `model_tier` ni `x_savia_*` en
  `request.body` de ningún agente.
- **AC-2** La config efectiva contiene `permissions` con
  `external_directory: ask` y `subagent_depth: 2`.
- **AC-3** `snapshots: true` y `update: "disable"` aparecen en la config efectiva.
- **AC-4** `python3 -m json.tool opencode.json` pasa.
- **AC-5** El plugin V1 sigue resolviendo tiers desde
  `~/.savia/preferences.yaml` (smoke con `x_savia_model_tiers`).
- **AC-6** No queda referencia a `opencode-sandbox` ni a `experimental.sandbox`.

## 6. Verificación

```bash
python3 -m json.tool opencode.json >/dev/null
opencode debug config | grep -c model_tier   # esperado: 0
opencode debug config | grep -A3 permissions
```

## 7. Riesgos

- V1 ignora `policies`/`permissions`: no hay doble aplicación, pero tampoco
  protección extra en V1 más allá de los guards.
- `x_savia_model_tiers` es una extensión propia: cualquier frontend que valide
  estrictamente el schema podría rechazarla. Verificado en V2: se ignora.

## OpenCode Implementation Plan

### Bindings touched

| Componente | Claude Code | OpenCode 1 | OpenCode 2 |
|---|---|---|---|
| Tiers | `~/.savia/preferences.yaml` (sin cambios) | `config` hook | sin transform (deuda P4) |
| Permisos | `.claude/settings.json` | `permission` (V1) | `permissions` + `policies` |
| Snapshots | n/a | `snapshot` | `snapshots` |
| Updates | n/a | `autoupdate` | `update` |

### Verification protocol

- [x] `opencode debug config` revisado en V2 real
- [x] JSON válido
- [ ] Verificado en OpenCode 1 real (no instalado)

### Portability classification

- [x] **DUAL_BINDING**: se mantienen las claves V1 y se añaden las V2; ninguna
      sustituye a la otra.
