---
name: orgchart-import
description: >
  Importa un organigrama (Mermaid, Draw.io XML o Miro) y genera/actualiza
  la estructura teams/ con departamentos, equipos y miembros.
allowed-tools: [Read, Write, Edit, Glob, Grep, Bash]
model_tier: mid
context_cost: medium
argument-hint: "{source} --dept {name} [--mode create|merge|overwrite] [--dry-run]"
tier: core
---

# Importar Organigrama → Estructura teams/

**Fuente:** $ARGUMENTS

> Uso: `/orgchart-import {source} --dept {name} [--mode create|merge|overwrite] [--dry-run]`

## Parametros

- `{source}` -- ruta a `.mermaid`, `.drawio`/`.xml`, o URL de Miro board
- `--dept {name}` -- nombre del departamento destino (obligatorio)
- `--mode create|merge|overwrite` -- manejo de conflictos (default: `merge`)
- `--dry-run` -- mostrar propuesta sin escribir ficheros

## Contexto requerido

1. `.opencode/skills/orgchart-import/SKILL.md` -- pipeline completo
2. `teams/departments.md` -- departamentos existentes
3. `teams/{dept}/` -- estructura existente del dept (si --mode merge)
4. `docs/rules/domain/diagram-config.md` -- constantes orgchart
5. `teams/members/template.md` -- plantilla de miembros

## Razonamiento

Piensa paso a paso:
1. Primero: detectar formato del source y parsear a modelo normalizado
2. Luego: validar datos y detectar conflictos con teams/ existente
3. Finalmente: presentar propuesta y escribir ficheros tras confirmacion

## Pasos de ejecucion

1. **Banner de inicio**
2. **Verificar prerequisitos**: source existe, --dept proporcionado, teams/ accesible
3. **Invocar skill** `.opencode/skills/orgchart-import/SKILL.md` -- 7 fases:
   - Fase 1: Detectar formato y parsear
   - Fase 2: Construir modelo normalizado (org-model-schema)
   - Fase 3: Validar datos parseados
   - Fase 4: Detectar conflictos con teams/ existente segun --mode
   - Fase 5: Presentar propuesta al PM (si --dry-run: parar aqui)
   - Fase 6: Escribir ficheros tras confirmacion
   - Fase 7: Banner de resumen
4. **Auto-compact**: `⚡ /compact`

## Ejemplo

**Correcto:**
```
/orgchart-import teams/diagrams/local/orgchart-Engineering.mermaid --dept Engineering
→ Parsea Mermaid, detecta 2 equipos con 4 miembros, presenta propuesta, escribe teams/
```

**Incorrecto:**
```
/orgchart-import orgchart.mermaid
→ Error: falta --dept. Uso: /orgchart-import {source} --dept {name}
```

## Restricciones

- NUNCA escribir sin confirmacion explicita del PM
- NUNCA escribir nombres reales en ficheros tracked (solo @handles)
- `--mode overwrite` requiere flag explicito + confirmacion
- Si --dry-run: mostrar propuesta y parar, NO escribir
- Si el diagrama contiene nombres reales sin @handle: warn + pedir handle
- Ficheros member en `teams/members/` (gitignored) pueden tener datos reales
