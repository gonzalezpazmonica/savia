---
name: meeting-digest
description: >
  Digiere una transcripcion de reunion, actualiza perfiles de equipo, reglas de negocio
  y ejecuta analisis de riesgos cruzando contra el estado del proyecto. Soporta VTT, DOCX y TXT.
argument-hint: "<fichero> [--type one2one|retro|review|refinement|stakeholder] [--project nombre] [--no-risk]"
model_tier: mid
context_cost: high
allowed-tools: [Read, Write, Edit, Glob, Grep, Bash, Task]
tier: core
---

# Digestion de Reuniones

**Fichero:** $ARGUMENTS

> Uso: `/meeting-digest projects/proyecto-alpha/team/one2one/transcripcion.vtt`
> Uso: `/meeting-digest transcripcion.vtt --type retro --project proyecto-alpha`
> Flag: `--no-risk` omite el analisis de riesgos (ahorra tiempo y tokens)

## 1. Cargar contexto

1. Parsear argumentos: fichero (obligatorio), --type (default: one2one), --project (auto-detectar), --no-risk (default: false)
2. Verificar que el fichero existe y es legible
3. Auto-detectar proyecto: buscar en la ruta del fichero `projects/{nombre}/`
4. Leer:
   - `projects/{proyecto}/CLAUDE.md`
   - `projects/{proyecto}/team/members/member-template.md` (estructura de campos)
   - `projects/{proyecto}/reglas-negocio.md` (si existe, para enriquecer y cruzar)
   - `projects/{proyecto}/team/team.md` (contexto de equipo existente)

Si falta el proyecto o el fichero no existe -> error con sugerencia.

## 2. Invocar agente meeting-digest (Sonnet — extraccion + confidencialidad + riesgos)

Delegar al agente `meeting-digest` con Task:

- Fichero de transcripcion completo
- Tipo de reunion
- Template de miembro (para estructura de campos)
- Contexto de equipo existente (team.md)
- Instruccion: devolver 4 bloques (PERFIL, NEGOCIO, NOTAS PM, RIESGOS)

El agente ejecuta internamente 3 fases:
1. **Extraccion** — lee transcripcion, marca secciones confidenciales, extrae bloques
2. **Juicio de confidencialidad** — delega a `meeting-confidentiality-judge` (Opus) para validar
   que ningun dato confidencial/sensible se filtre a los bloques de escritura
3. **Analisis de riesgos** — delega a `meeting-risk-analyst` (Opus) con bloques ya filtrados

Si `--no-risk`: omitir fase 3. La fase 2 (confidencialidad) NUNCA se omite.

## 3. Procesar resultados

### 3a. Crear/actualizar ficha de miembro (one2one)

1. Del bloque PERFIL, extraer el handle
2. Si `projects/{proyecto}/team/members/{handle}.md` existe -> actualizar campos vacios o desactualizados
3. Si no existe -> crear desde template con los datos extraidos
4. Actualizar `data_source` con la referencia a la transcripcion

### 3b. Actualizar reglas de negocio

1. Del bloque NEGOCIO, identificar informacion nueva no presente en `reglas-negocio.md`
2. Si hay informacion nueva -> anadir seccion o actualizar existente
3. Anadir entrada al changelog de fuentes al final del fichero

### 3c. Guardar informe de riesgos (si no --no-risk)

1. Del bloque RIESGOS, guardar en `output/meeting-risks/{proyecto}/YYYYMMDD-{handle|tipo}.md`
2. Si hay alertas CRITICAS -> mostrar en pantalla inmediatamente
3. Si hay alertas con accion sugerida sobre risk-register.md -> proponer actualizacion

### 3d. Mostrar notas para la PM

1. Del bloque NOTAS PM, mostrar en pantalla (no guardar en fichero)
2. Incluir: riesgos detectados, puntos de seguimiento, observaciones
3. Si hay CRITICAS en el bloque RIESGOS, mostrarlas en rojo al final

## 4. Banner de finalizacion

```
---
Reunion digerida: {nombre_fichero}
Tipo: {type}
Confidencialidad: {N datos bloqueados | N ambiguos} — filtro Opus aplicado
Perfil: {creado|actualizado|n/a} — projects/{proyecto}/team/members/{handle}.md
Reglas de negocio: {actualizado|sin cambios}
Riesgos: {N criticas | N alertas | N avisos} — output/meeting-risks/...
---
```

## Ejemplo

```
/meeting-digest projects/alpha/team/one2one/one2one-alice-bob.vtt

---
Reunion digerida: one2one-alice-bob.vtt
Tipo: one2one
Perfil actualizado: projects/alpha/team/members/alice.smith.md
Reglas de negocio: actualizado (stakeholders, deuda tecnica)
Riesgos: 0 criticas | 2 alertas | 1 aviso
---

Notas PM:
- Equipo necesita refuerzo en testing: capacidad al 110%
- Sprint delivery en riesgo por dependencia externa bloqueada

Alertas de riesgo:
- [ALERTA] Sobrecarga equipo: >110% capacidad 2 sprints consecutivos
- [ALERTA] Dependencia externa sin resolver desde hace 5 dias
```
