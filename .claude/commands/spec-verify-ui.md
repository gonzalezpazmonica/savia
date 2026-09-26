---
name: spec-verify-ui
description: "Verificación spec↔UI — comprueba que el componente implementado cumple su spec SDD"
developer_type: all
agent: task
context_cost: high
model_tier: mid
argument-hint: "[spec-path] [--generate-tests] [--fix] [--lang es|en]"
tier: core
---

# /spec-verify-ui — Verificación Spec↔UI

> 🦉 Savia comprueba que lo programado cumple lo especificado — props, estados, ARIA, tokens.
> Lee el spec SDD y verifica cada requisito contra el componente real.

---

## Cargar perfil de usuario

Grupo: **QA & Testing** — cargar:

- `identity.md` — nombre, rol
- `projects.md` — proyecto target
- `preferences.md` — language

---

## Subcomandos

- `/spec-verify-ui {spec-path}` — verificar un componente contra su spec
- `/spec-verify-ui --generate-tests {spec-path}` — generar tests de verificación
- `/spec-verify-ui --fix {spec-path}` — verificar + auto-corregir divergencias
- `/spec-verify-ui --all` — verificar todos los componentes con spec SDD

---

## Flujo

### Paso 1 — Leer spec SDD

Extraer requisitos verificables del spec:

1. **Props/Inputs** — nombre, tipo, required/optional, defaults
2. **Estados** — los 8 de `frontend-components.md`: Default, Hover, Focus, Active, Disabled, Loading, Error, Success
3. **ARIA** — atributos requeridos según tipo de componente
4. **Keyboard** — navegación esperada (Tab, Enter, Escape, Arrows)
5. **Design tokens** — spacing, typography, colors referenciados
6. **Escenarios** — Given/When/Then del spec

### Paso 2 — Analizar componente implementado

Leer el fichero del componente:

- React: props interface/type, JSX, hooks, className
- Angular: @Input/@Output, template, component class

Extraer:

- Props reales implementadas
- Estilos aplicados (Tailwind classes, CSS modules, inline)
- ARIA attributes en el template/JSX
- Event handlers (keyboard, mouse)
- Conditional rendering (estados)

### Paso 3 — Comparar spec vs. implementación

Para cada requisito del spec:

```
  Requisito               | Estado    | Detalle
  ────────────────────────|───────────|───────────────────
  Props: email (string)   | ✅ OK     | Tipada correctamente
  Props: onSubmit (fn)    | ✅ OK     | Callback presente
  Estado: Default         | ✅ OK     | Renderiza vacío
  Estado: Loading         | ✅ OK     | Spinner + disabled
  Estado: Error           | ❌ FALLA  | Falta aria-invalid
  Estado: Success         | ⚠️ PARCIAL | Sin mensaje confirm.
  Estado: Disabled        | ❌ FALLA  | No aplica opacity 50%
  ARIA: aria-labelledby   | ✅ OK     | Presente en form
  ARIA: aria-invalid      | ❌ FALLA  | Missing en error state
  Keyboard: Tab order     | ✅ OK     | email→password→submit
  Token: spacing-16       | ✅ OK     | gap-4 (16px)
  Token: color-error      | ❌ FALLA  | Usa #ff0000, no var()
```

### Paso 4 — Calcular conformidad

```
Conformidad = requisitos_ok / total_requisitos × 100

  ≥ 95%  → 🟢 CONFORME — listo para review
  80-94% → 🟡 PARCIAL — correcciones menores
  < 80%  → 🔴 NO CONFORME — requiere rehacer
```

### Paso 5 — Generar tests (si `--generate-tests`)

Para cada requisito, generar test con testing-library. Output en `__tests__/{ComponentName}.spec-verify.test.tsx`.

### Paso 6 — Auto-fix (si `--fix`)

Para divergencias auto-corregibles (ARIA faltante, token hardcoded, estado sin opacity), delegar a `frontend-developer` con instrucciones precisas por divergencia.

---

## Modo agente (role: "Agent")

```yaml
status: ok
action: spec_verify_ui
component: "LoginForm"
total_requirements: 12
passed: 8
failed: 3
partial: 1
conformity_pct: 67
conformity_level: "non_compliant"
tests_generated: 12
auto_fixable: 2
```

---

## Integración

| Comando | Relación |
|---|---|
| SDD specs | Fuente de verdad para requisitos |
| `/visual-regression` | Complementa: spec verifica lógica, visual verifica píxeles |
| `/testplan-generate` | spec-verify genera tests más granulares por componente |
| `/check-coherence` | spec-verify es check-coherence específico para UI |
| `frontend-components.md` | Define los 8 estados y tokens a verificar |
| `/a11y-audit` | spec-verify incluye ARIA, a11y-audit cubre WCAG completo |

---

## Restricciones

- **NUNCA** modificar el spec — si hay inconsistencia, reportar
- **NUNCA** auto-fix sin `--fix` explícito
- **NUNCA** aprobar un componente < 80% conformidad
- Si el spec no define estados → usar los 8 de `frontend-components.md`
- Siempre generar informe aunque todo pase (evidencia)
