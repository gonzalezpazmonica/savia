---
name: backlog-groom
description: Grooming asistido — detectar items obsoletos, duplicados, sin criterios de aceptación
developer_type: all
agent: task
context_cost: medium
model_tier: mid
tier: core
---

# /backlog-groom

> 🦉 Savia examina tu backlog para detectar items duplicados, obsoletos o incompletos.

---

## Cargar perfil

Grupo: **Backlog Intelligence** — cargar:

- `CLAUDE.md` — proyecto activo
- `.claude/profiles/active-user.md` — usuario y rol
- `projects/{proyecto}/CLAUDE.md` — config del proyecto
- Backlog items desde Azure DevOps (WIQL query)

---

## Subcomandos

- `/backlog-groom` — análisis interactivo del backlog entero
- `/backlog-groom --top N` — analizar solo los N items más antiguos sin mover
- `/backlog-groom --duplicates` — detección agresiva de duplicados
- `/backlog-groom --incomplete` — items sin criterios de aceptación

---

## Flujo

### Paso 1 — Cargar backlog

La WIQL vive en la Query Library (SE-031). Resolverla inyectando el proyecto activo:

```bash
QUERY=$(bash scripts/query-lib-resolve.sh --id backlog-groom-open --param project="$PROJECT_NAME")
curl -u ":$(cat $PAT_FILE)" -X POST -H "Content-Type: application/json" \
  -d "{\"query\":\"$QUERY\"}" "$ORG_URL/$PROJECT_NAME/_apis/wiql?api-version=7.0"
```

Snippet canonico: `.claude/queries/azure-devops/backlog-groom-open.wiql`. Cambios de schema → editar el snippet, no este doc.

Limitar a los últimos 500 items si el backlog es muy grande.

### Paso 2 — Clasificar items

4 categorías:

**Healthy** (✅): ≥3 líneas desc + ≥3 AC + asignado + modificado < 60d

**Stale** (🟡): No modificado > 90d OR State=New OR sin comentarios

**Incomplete** (⚠️): Desc < 3 líneas OR AC < 3 OR SP sin definir

**Duplicate** (🔴): Título similar (75%+ fuzzy) OR misma descripción OR Epic padre idéntico

### Paso 3 — Generar propuestas

Formato compacto:
```
🟡 #1234 — "Login" | Creado 2025-01-15 | Último cambio 152d atrás
   Problemas: Sin AC, Estado=New, > 90d sin cambios
   Acción: Definir AC o Closed
```

### Paso 4 — Guardar informe

Estructura del informe:

```markdown
# Backlog Grooming Report — {proyecto}

Generado: {fecha}
Analista: Savia

## Resumen

Total items analizados: NNN
✅ Healthy: NNN
🟡 Stale: NNN
⚠️ Incomplete: NNN
🔴 Duplicates: NNN

## Items Healthy (en orden — no requieren acción)

[Lista corta solo IDs y títulos]

## Items Stale — Recomendación: Revisar o Cerrar

[Detalle: ID, título, último cambio, estado actual]
Acción sugerida: Contactar propietario o marcar Closed

## Items Incomplete — Recomendación: Completar o Rechazar

[Detalle: ID, título, qué falta]
Acción sugerida: Añadir AC o rechazar PBI

## Items Duplicate — Recomendación: Consolidar

[Pares detectados: PBI #X ≈ PBI #Y]
Acción sugerida: Merge o marcar uno como duplicado

## Próximos Pasos

1. Revisar items stale con propietarios
2. Pedir completar AC en incomplete
3. Consolidar duplicados con el equipo
4. Ejecutar `/backlog-prioritize` tras grooming
```

---

## Modo agente (role: "Agent")

```yaml
status: ok
action: backlog_grooming
items_analyzed: {n}
healthy_items: {n}
stale_items: {n}
incomplete_items: {n}
duplicate_groups: {n}
file_path: "output/grooming/YYYYMMDD-backlog-groom-{proyecto}.md"
```

---

## Restricciones

- **NUNCA** eliminar items automáticamente — solo sugerir
- **NUNCA** asignar a personas sin confirmación PM
- Máximo fuzzy match 75% para duplicados (evitar falsos positivos)
- Criterio "healthy" es flexible — adaptarse a la madurez del equipo
- Informes > 100 líneas → guardar en fichero, mostrar resumen en chat
