---
name: legal-audit
description: Auditoría de compliance legal contra legislación española (legalize-es)
agent: legal-compliance
context_cost: medium
argument-hint: "[--project PROJECT] [--scope rules|contract|architecture|policy|pbi|full] [--domain DOMAIN] [--ccaa CCAA]"
tier: core
---

# /legal-audit [--project PROJECT] [--scope SCOPE] [--domain DOMAIN] [--ccaa CCAA] [--format FORMAT]

> Cruza las reglas de negocio, contratos, políticas o arquitectura del proyecto contra la legislación española vigente usando legalize-es.

## Parámetros

- `--project` — Proyecto a auditar (default: proyecto activo)
- `--scope` — Qué auditar: `rules` (default), `contract`, `architecture`, `policy`, `pbi`, `full`
- `--domain` — Dominio legal: `datos`, `comercio`, `laboral`, `consumo`, `accesibilidad`, `ciber`, `facturacion`, `ia`, `financiero`, `sanidad`, `educacion`, `propiedad-intelectual`, `all` (default: auto-detectar)
- `--ccaa` — Comunidad autónoma: `es-an`, `es-ct`, `es-md`, `es-pv`, etc. (default: solo estatal)
- `--format` — Nivel de detalle: `summary`, `detailed` (default), `executive`

## Prerequisitos

1. Verificar legalize-es instalado:
   ```bash
   bash scripts/legalize-es.sh status
   ```
   Si sale con exit 3 (corpus no disponible), NO auditar: mostrar
   ```
   legalize-es no instalado: sin corpus no hay fuente para evaluar cumplimiento.
      Ejecuta: bash scripts/legalize-es.sh install
      (Clona las normas consolidadas del BOE; requiere red)
   ```

2. Cargar skill: `@.opencode/skills/legal-compliance/SKILL.md`

3. Cargar términos de dominio: `@.opencode/skills/legal-compliance/references/domain-terms.md`

## Ejecución

### Paso 1 — Identificar input según scope

| Scope | Fichero(s) a leer |
|-------|-------------------|
| rules | `projects/{proyecto}/reglas-negocio.md` o `projects/{proyecto}/business-rules/` |
| contract | Documento indicado por el usuario o en `projects/{proyecto}/docs/` |
| architecture | `projects/{proyecto}/ARCHITECTURE.md` + specs |
| policy | Política de privacidad, cookies, EULA del proyecto |
| pbi | PBI description + acceptance criteria |
| full | Todos los anteriores |

Si el fichero no existe, informar y sugerir crearlo.

### Paso 2 — Clasificar dominios legales

Extraer términos clave del input. Mapear contra `domain-terms.md`.
Si `--domain` especificado, usar ese. Si no, auto-detectar.

### Paso 3 — Buscar legislación

Para cada dominio detectado:
1. Buscar en normas conocidas (BOE identifiers de domain-terms.md)
2. Si hay CCAA: buscar también en `es-{ccaa}/`
3. Filtrar por `legal_status: vigente`
4. Cargar solo artículos relevantes

### Paso 4 — Analizar compliance

Cruzar cada regla/cláusula del input contra artículos encontrados.
Evaluar: CUMPLE / NO CUMPLE / PARCIAL / NO APLICA.
Clasificar por severidad.

### Paso 5 — Generar informe

Guardar en: `output/legal/{YYYYMMDD}-legal-audit-{proyecto}.md`

Mostrar resumen en chat (máx 15 líneas):
```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
⚖️ /legal-audit — {proyecto}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Scope: {scope} | Dominio: {dominios detectados}
Hallazgos: N total (X críticos, Y altos, Z medios, W info)
Cobertura: X% reglas con base legal identificada

Top hallazgos:
  🔴 {hallazgo crítico 1}
  🟠 {hallazgo alto 1}

📄 Informe completo: output/legal/{fecha}-legal-audit-{proyecto}.md
⚡ /compact
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

## Notas

- El análisis NO modifica ficheros del proyecto — solo lee y reporta
- Requiere legalize-es clonado localmente (~500MB)
- Funciona offline si legalize-es ya está clonado
- Para actualizar legislación: `bash scripts/legalize-es.sh update`
