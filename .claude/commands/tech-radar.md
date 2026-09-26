---
name: tech-radar
description: Radar tecnológico del proyecto — librerías, versiones, adopt/trial/hold/retire
developer_type: all
agent: task
context_cost: high
model_tier: mid
tier: core
---

# /tech-radar

> 🦉 Savia mapea tu stack tecnológico y te ayuda a tomar decisiones informadas.

---

## Cargar perfil de usuario

Grupo: **Architecture & Debt** — cargar:

- `identity.md` — nombre, rol
- `projects.md` — proyecto target
- `preferences.md` — detail_level

---

## Subcomandos

- `/tech-radar` — radar completo del proyecto
- `/tech-radar {proyecto}` — radar de un proyecto específico
- `/tech-radar --outdated` — solo dependencias desactualizadas

---

## Flujo

### Paso 1 — Escanear dependencias

Detectar package manager y leer dependencias:
npm/yarn (package.json), pip (requirements.txt/pyproject.toml), dotnet (*.csproj),
go (go.mod), cargo (Cargo.toml), composer (composer.json), bundler (Gemfile).

### Paso 2 — Clasificar cada dependencia

| Categoría | Criterio |
|---|---|
| 🟢 Adopt | Versión actual, mantenido activamente, sin CVEs |
| 🔵 Trial | Recientemente adoptada, <3 meses en proyecto |
| 🟡 Hold | Versión desactualizada >6 meses o CVE medio |
| 🔴 Retire | Deprecated, sin mantenimiento, o CVE crítico |

### Paso 3 — Generar radar

```
🦉 Tech Radar — {proyecto}

📊 Stack: {N} dependencias · {N} adopt · {N} trial · {N} hold · {N} retire

🔴 RETIRE ({N}):
  {lib}@{version} — deprecated, última release {fecha}
  {lib}@{version} — CVE-2026-XXXX (critical)

🟡 HOLD ({N}):
  {lib}@{version} — {N} versions behind, latest: {latest}
  {lib}@{version} — CVE-2026-XXXX (medium)

🔵 TRIAL ({N}):
  {lib}@{version} — adoptada hace {N} días

🟢 ADOPT ({N}):
  {top 5 por uso}

💡 Acciones recomendadas:
  1. Migrar {lib} de {old} a {new} — esfuerzo: {bajo|medio|alto}
  2. Evaluar alternativa a {lib} — {razón}
```

---

## Modo agente (role: "Agent")

```yaml
status: ok
action: tech_radar
total_deps: 45
adopt: 32
trial: 3
hold: 7
retire: 3
critical_cves: 1
```

---

## Restricciones

- **NUNCA** actualizar dependencias automáticamente
- **NUNCA** eliminar dependencias sin confirmación
- Indicar esfuerzo estimado de cada migración
