---
entity: {type: spec, id: se-343}
title: "SE-343 — Operator Grant: switch determinista para autonomía y merge"
doc_type: spec
status: PROPOSED
confidentiality: N2
tags: [spec, autonomous-safety, double-optin, merge, grants, operator]
created_at: 2026-08-24
---

# Spec: SE-343 — Operator Grant: switch determinista para autonomía y merge

**Task ID:**        SE-343
**PBI padre:**      SE-343 — Eliminar la fricción manual del doble opt-in y del merge
**Sprint:**         2026-08
**Fecha creacion:** 2026-08-24
**Creado por:**     Savia (decisión de la operadora, sesión 2026-08-24)

**Developer Type:** agent-single
**Asignado a:**     typescript-developer (bash+pytest)
**Estado:**         PROPOSED

**Effort Estimation (Dual Model):**

| Dimension | Value |
|---|---|
| Agent effort | 4 h |
| Human effort | 2 h (revisión de reglas) |
| Review effort | 40 min |
| Context risk | low |
| Agent-capable | yes |
| Fallback | Si agente falla: humano necesita 3h |

---

> **Enmienda propuesta (SE-433, D7, 2026-10-04):** el grant `merge` se unificará con el modelo de
> autorización de merge-sprint, que registra la pregunta y la respuesta literales de la operadora, la
> sesión y el hash. Un grant sin ese registro dejará de bastar para `push-pr.sh --merge`. Ver `docs/specs/SE-433-merge-sprint.spec.md` §2.11. Pendiente de spec propia.
>
> **Arreglo P1 (2026-10-26, decisión de la operadora):** `grant --scope merge` ya no se emite sin
> prueba de persona. Exige la terminal de la operadora (`source: tty`) o el ticket de un solo uso que
> deja `operator-grant.sh guard` al pedir el diálogo de permisos del arnés
> (`source: harness-ask`), y el grant se firma con HMAC-SHA256 (patrón Yema F4). `check` rechaza un
> grant de merge sin firma válida. El `source` deja de ser un literal. Detalle:
> `docs/rules/domain/autonomous-safety-merge-grant.md`.

## 1. Origen y problema

La operadora detectó fricción repetida en dos gates del workspace:

1. **Doble opt-in (SPEC-186):** el gate de skills autónomas exige una variable de
   entorno persistente (`OVERNIGHT_SPRINT_ENABLED=true`) configurada A MANO por
   la operadora. Cuando pide a Savia trabajar de forma autónoma, Savia no puede
   activar el modo porque la variable no está seteada — la noche del 23-08-2026
   se perdió la sesión nocturna por esto. El bug es de **disponibilidad**: la
   intención de la operadora es la autorización, pero el gate la obliga a tocar
   el entorno a mano (tarea técnica que le corresponde a Savia).

2. **Merge:** la regla `autonomous-safety.md` dice "NUNCA merge de ninguna rama"
   en términos absolutos. Pero el criterio real de la operadora es: **de base no
   mergeas; solo mergeas si te lo pido expresamente**. La regla actual no tiene
   switch: o siempre prohibido (y entonces el permiso expreso de la operadora no
   se puede ejecutar), o --merge en push-pr.sh sin registro de quién autorizó.
   El 23-08-2026 la operadora pidió merge expreso y Savia no pudo (regla
   binaria); el 24-08-2026 confirmó que el modelo correcto es "nunca salvo
   permiso expreso y registrado".

**Objetivo**: sustituir la fricción manual por un **ledger de grants local**,
escrito por Savia cuando la operadora pide expresamente (autonomía o merge), que
actúa como factor determinista y auditable:

- **Autonomía:** el factor "intención previa" del doble opt-in puede satisfacerse
  con un grant vigente (`autonomy:<skill>`) emitido a petición expresa de la
  operadora, sin necesidad de tocar env vars a mano.
- **Merge:** `push-pr.sh --merge` exige un grant `merge` vigente emitido a
  petición expresa; sin él, aborta.

El ledger vive en `~/.savia/grants/` — infraestructura local, fuera del repo
público (CRIT-001/ART-07), legible solo por la operadora.

## 2. Contrato técnico

### 2.1 Ledger de grants

Ruta: `~/.savia/grants/` (CREAR si no existe). Cada grant es un fichero JSON:

```
~/.savia/grants/<scope>@<expires>.json
```

Contenido:
```json
{
  "scope": "autonomy:overnight-sprint",
  "grantor": "<operadora>",
  "source": "express-request",
  "request_context": "sesion 2026-08-24 — pedido autonomo nocturno",
  "issued_at": "2026-08-24T09:00:00Z",
  "expires_at": "2026-08-25T09:00:00Z",
  "nonce": "8f7a..."
}
```

**Scopes válidos:**
- `autonomy:<skill>` — habilita el factor "intención previa" del doble opt-in
  para la skill (overnight-sprint, code-improvement-loop, adversarial-security,
  tech-research-agent, savia-dual).
- `merge` — habilita el merge de PRs.

### 2.2 `scripts/operator-grant.sh`

```bash
# Emitir grant (lo hace Savia a petición expresa de la operadora)
bash scripts/operator-grant.sh grant --scope autonomy:overnight-sprint \
  --context "sesion 2026-08-24: pedido autonomo nocturno" [--ttl-hours 24]

bash scripts/operator-grant.sh grant --scope merge \
  --context "PR #1007 merge aprobado por la operadora" [--ttl-hours 6]

# Verificar (determinista, sin LLM)
bash scripts/operator-grant.sh check --scope autonomy:overnight-sprint   # exit 0|1
bash scripts/operator-grant.sh check --scope merge                        # exit 0|1

# Listar / revocar
bash scripts/operator-grant.sh list
bash scripts/operator-grant.sh revoke --scope autonomy:overnight-sprint
```

**Exit codes:** `0` vigente · `1` no vigente/expirado · `2` invalido · `3` sin grant.

**Reglas del grant:**
- `grantor` = slug del usuario activo resuelto en runtime (active-user.md).
- `source` valores: solo `express-request` (emitido por Savia tras petición
  expresa de la operadora). NUNCA `self` — Savia no se auto-concede.
- TTL por defecto: `autonomy:*` = 24h, `merge` = 6h (ventana de merge-post-request).
- **Enforce**: un grant `merge` se consume (revoca automáticamente) tras el
  primer merge exitoso de `push-pr.sh`.
- **Idempotente**: `grant` sobre un scope ya vigente renueva `expires_at`.

### 2.3 Cambio en `savia-double-optin-check.sh`

El factor 1 (intención previa) se amplía: `env var == true` **O** grant vigente
`autonomy:<skill>`. El factor 2 (flag `--confirm-autonomous`) se mantiene.

```bash
HAS_INTENT=0
[[ "${!ENV_NAME:-}" == "true" ]] && HAS_INTENT=1
bash scripts/operator-grant.sh check --scope "autonomy:${SKILL}" >/dev/null 2>&1 \
  && HAS_INTENT=1
[[ $HAS_INTENT -eq 1 && $HAS_FLAG -eq 1 ]] && exit 0   # ambos factores
```

Así, cuando la operadora pide autonomía, Savia hace `operator-grant.sh grant`
(al arrancar la sesión autónoma) y el gate pasa sin que ella toque el entorno.

### 2.4 Cambio en `push-pr.sh`

En el bloque `--merge` (antes de habilitar auto-merge):

```bash
if $MERGE; then
  if ! bash scripts/operator-grant.sh check --scope merge >/dev/null 2>&1; then
    echo "ERROR: merge requiere grant vigente (operator-grant.sh grant --scope merge ...)." >&2
    echo "  Sin permiso expreso registrado, el PR queda en Draft." >&2
    exit 1   # no merge, no marca Draft como listo
  fi
  # tras merge exitoso: consumo del grant
  bash scripts/operator-grant.sh revoke --scope merge >/dev/null 2>&1 || true
fi
```

El flujo correcto queda: operadora pide merge expresamente → Savia emite grant
`merge` con contexto → ejecuta `push-pr.sh --merge` → gate pasa → merge → se
consume el grant. Si el grant no existe (nadie autorizó), aborta.

## 3. Criterios de aceptación

- AC-1. `operator-grant.sh grant --scope autonomy:overnight-sprint` crea el
  fichero y `check` devuelve 0.
- AC-2. Grant expirado → `check` devuelve 1 (y el fichero se ignora).
- AC-3. `savia-double-optin-check.sh --skill overnight-sprint --confirm-autonomous`
  pasa con grant vigente y SIN env var seteada.
- AC-4. `savia-double-optin-check.sh` SIN grant y SIN env → aborta (exit 1).
- AC-5. `push-pr.sh --merge` con grant `merge` → procede; sin grant → exit 1 con
  mensaje claro y NO marca el PR listo.
- AC-6. Tras un merge exitoso, el grant `merge` se consume (check → 1).
- AC-7. `grantor` siempre = slug activo (nunca "self" ni vacío).
- AC-8. Ledger en `~/.savia/grants/`, no en el repo (grep `~/.savia/grants` no
  devuelve nada en `git status`).
- AC-9. Test BATS: los casos AC-1 a AC-8 cubiertos (>=8 tests).
- AC-10. `operator-grant.sh` es PURE_BASH (sin bindings de frontend).

## 4. Fuera de alcance

- NO se elimina el flag `--confirm-autonomous` ni el requisito de dos factores.
- NO se permite `grant --source self` ni grants emitidos sin petición expresa.
- NO se cambia la regla "PR en Draft + reviewer obligatorio" del resto del flujo.
- NO se toca el ledger de memoria (savia-memory) — es un ledger separado.

---

## OpenCode Implementation Plan

### Bindings touched

| Componente | Claude Code | OpenCode v1.14 |
|---|---|---|
| `operator-grant.sh` | `scripts/operator-grant.sh` | Script bash idéntico |
| `savia-double-optin-check.sh` | extendido | Script bash idéntico |
| `push-pr.sh` | extendido | Script bash idéntico |

### Verification protocol

- [x] Funciona en runtime OpenCode (scripts PURE_BASH, sin hooks nuevos)
- [x] Tests BATS cubren ambos paths
- [ ] Si añade hooks: no añade hooks nuevos; solo se extienden scripts existentes

### Portability classification

- [x] **PURE_BASH** — lógica en bash sin bindings de frontend; idéntico en
  cualquier motor. Justificado: es tooling local de gates, no frontend.