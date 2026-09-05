---
layer: peripheral
name: orgchart-import
description: Usar cuando se importa un organigrama para extraer la estructura del equipo.
allowed-tools: [Read, Write, Edit, Glob, Grep, Bash]
metadata:
  # --- metadata.savia.* (SE-333) ---
  savia.category: devops
  savia.maturity: stable
  savia.disable-model-invocation: false
  savia.priority: low
  savia.summary: "Importa organigramas (Mermaid, Draw.io XML, Miro) y genera estructura teams/ con departamentos, equipos y miembros. Pipeline de 7 fases. Inverso de diagram-generation orgchart. Pipeline de 7 fases para importar organigramas y generar estructura teams/. Soporta Mermaid, Draw.io XML y Miro. Inverso de diagram-generation orgchart."
  savia.tags: "orgchart, import, teams, hierarchy"
  savia.user-invocable: False
---

# Orgchart Import — Skill

> Importa organigrama → modelo normalizado → estructura teams/.

## Formato source soportados

| Extension | Parser |
|---|---|
| `.mermaid` | `references/mermaid-parser.md` |
| `.drawio`, `.xml` | `references/drawio-parser.md` |
| URL Miro | `references/miro-parser.md` |

## Modelo intermedio

Todos los parsers producen el mismo JSON: `references/org-model-schema.md`

## Pipeline de 7 fases

### Fase 1 — Detectar formato y parsear

1. Si source termina en `.mermaid` → cargar `references/mermaid-parser.md`, aplicar reglas
2. Si source termina en `.drawio` o `.xml` → cargar `references/drawio-parser.md`
3. Si source es URL con `miro.com` → cargar `references/miro-parser.md`
4. Si formato no reconocido → error con formatos soportados

Output: modelo JSON normalizado (org-model-schema).

### Fase 2 — Construir modelo normalizado

Asegurar que el output del parser cumple el schema:
- `department.name` = valor de `--dept`
- `department.responsable` = extraido del diagrama o `null`
- `teams[]` con name, capacity_total, members[]
- `supervisor_links[]` con from/to handles

### Fase 3 — Validar datos parseados

| Validacion | Nivel |
|---|---|
| Dept name no vacio | Error |
| Cada equipo tiene >=1 miembro | Error |
| Sin handles duplicados entre equipos | Warn (capacity > 1.0 implica multi-equipo) |
| Al menos 1 lead por equipo | Warn |
| Capacidades entre 0.1 y 1.0 | Warn |
| @handles sin nombres reales | Warn + pedir handle |

Si hay errores → parar con informe. Si solo warns → continuar con avisos.

### Fase 4 — Detectar conflictos con teams/ existente

Leer `teams/departments.md` y `teams/{dept}/` si existe.

| Modo | Dept existe | Equipo existe | Miembro existe |
|---|---|---|---|
| `create` | Error | Error | Error |
| `merge` | OK, actualizar | OK, agregar nuevos miembros | Skip |
| `overwrite` | OK, reemplazar | OK, reemplazar | OK, reemplazar |

Default: `merge`. `overwrite` requiere flag explicito + confirmacion.

### Fase 5 — Presentar propuesta al PM

Mostrar tabla:

```
Departamento: {dept_name} | Responsable: {resp} | Modo: {mode}

| Equipo | Miembros | Leads | Cap. | Estado |
|---|---|---|---|---|
| squad1 | 3 | @alice | 3.0 | Nuevo |
| squad2 | 2 | @bob | 2.0 | Merge (+1 miembro) |

Ficheros a crear/modificar:
  + teams/{dept}/dept.md
  + teams/{dept}/squad1/team.md
  + teams/{dept}/squad1/deps.md
  ~ teams/{dept}/squad2/team.md (merge)
  + teams/members/@charlie.md
```

Si `--dry-run` → parar aqui con banner informativo.

### Fase 6 — Escribir ficheros (tras confirmacion)

1. **departments.md** — agregar/actualizar fila en tabla
2. **dept.md** — crear `teams/{dept}/dept.md`:
   ```markdown
   # {dept_name}

   - **Mision**: [completar]
   - **Responsable**: {responsable}
   - **Equipos**: {lista equipos}
   - **KPIs**: [completar]
   ```
3. **team.md** por equipo — crear `teams/{dept}/{team}/team.md`:
   ```yaml
   name: "{team_name}"
   department: "{dept_name}"
   lead:
     - "@handle"
   members:
     - handle: "@handle"
       role: {role}
       capacity: {cap}
       projects: []
   capacity_total: {total}
   velocity_avg: 0
   sprint_cadence: 2w
   ```
4. **deps.md** por equipo — crear vacio: `# Dependencias de {team_name}`
5. **member profiles** — para cada miembro nuevo sin fichero existente:
   crear `teams/members/{handle}.md` desde `teams/members/template.md`
   con handle y role pre-rellenados

### Fase 7 — Banner de resumen

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
✅ /orgchart-import — Completado
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📁 Departamento: {dept} ({N} equipos, {M} miembros)
📄 Ficheros creados: {count}
📄 Ficheros modificados: {count}
⚡ /compact — Ejecuta para liberar contexto
💡 Siguiente: /team-orchestrator validate --dept {dept}
```

## PII Safety

- Solo @handles en ficheros tracked por git
- Si diagrama contiene nombres reales sin @: warn + pedir handle al PM
- `teams/members/` esta gitignored: puede contener datos reales
- NUNCA escribir nombres reales en dept.md, team.md, departments.md
