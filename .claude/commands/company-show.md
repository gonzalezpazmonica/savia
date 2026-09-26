---
name: company-show
description: Mostrar perfil consolidado de la empresa — resumen ejecutivo del contexto organizacional
developer_type: all
agent: none
context_cost: low
model_tier: fast
tier: core
---

# /company-show

> 🦉 Savia muestra el perfil completo de tu empresa.

---

## Cargar perfil de usuario

Grupo: **Infrastructure** — cargar:

- `identity.md` — nombre, rol

---

## Subcomandos

- `/company-show` — resumen ejecutivo consolidado
- `/company-show {sección}` — detalle de una sección específica
- `/company-show --gaps` — detectar información faltante o desactualizada

---

## Flujo

### Paso 1 — Cargar todos los ficheros del company profile

Leer los 6 ficheros de `.claude/profiles/company/`.

### Paso 2 — Presentar resumen ejecutivo

```
🏢 Perfil de Empresa — {nombre}

  📋 Identidad:
    Sector: {sector} | Tamaño: {N} personas | Fundada: {año}
    Misión: {misión resumida}

  🏗️ Estructura:
    Áreas: {N} | Equipos dev: {N} | Proyectos activos: {N}

  🎯 Estrategia:
    OKRs activos: {N} | Iniciativas: {N}
    Prioridad Q1: {prioridad principal}

  📜 Políticas:
    Política IA: {sí/no/parcial}
    Compliance: {frameworks activos}

  💻 Tecnología:
    Stack: {principales tecnologías}
    Cloud: {provider}
    PM Tool: {herramienta}

  🏭 Vertical:
    Industria: {sector específico}
    Regulaciones: {lista}
    Certificaciones: {lista}
```

### Paso 3 — Detectar gaps (si --gaps)

```
⚠️ Información faltante o desactualizada:

  1. strategy.md sin OKRs definidos → /company-edit strategy
  2. policies.md sin política de IA → /company-edit policies
  3. vertical.md sin regulaciones → /company-edit vertical
```

---

## Modo agente (role: "Agent")

```yaml
status: ok
action: company_show
sections_complete: 5
sections_incomplete: 1
gaps: ["policies.ai_policy"]
```

---

## Restricciones

- **NUNCA** mostrar datos marcados como confidenciales
- **NUNCA** exponer información de estructura a usuarios sin rol adecuado
- Solo lectura — no modifica ningún fichero
