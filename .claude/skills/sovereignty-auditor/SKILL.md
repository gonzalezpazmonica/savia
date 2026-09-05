---
layer: peripheral
name: sovereignty-auditor
description: Usar cuando se audita el grado de dependencia cognitiva del equipo respecto a herramientas de IA.
metadata:
  # --- metadata.savia.* (SE-333) ---
  savia.category: governance
  savia.maturity: stable
  savia.context_cost: medium
  savia.dependencies: 
  savia.maturity: stable
  savia.priority: medium
  savia.summary: "Auditoria de soberania cognitiva: diagnostica lock-in de IA, portabilidad de datos y dependencias de proveedor. Output: score de soberania + plan de mitigacion."
  savia.tags: "sovereignty, lock-in, ai-governance, audit"
---

# Skill: Sovereignty Auditor

> Regla: @docs/rules/domain/ai-governance.md
> Complementa: @.opencode/commands/governance-audit.md (cumplimiento normativo)

## Prerequisitos

- Workspace pm-workspace inicializado
- Para scan completo: acceso a `.claude/`, `scripts/`, `docs/`

## Flujo: Scan

Calcula el Sovereignty Score analizando 5 dimensiones:

### Paso 1 — D1: Portabilidad de datos (25%)
1. Contar ficheros en formatos abiertos (md, csv, json, yaml) vs propietarios
2. Verificar SaviaHub existente (`savia-hub/` o `$SAVIA_HUB_PATH`)
3. Detectar MEMORY.md en `.claude/agent-memory/` (memoria portable)
4. Verificar BacklogGit configurado (snapshots en markdown)
5. Score: % datos en formatos abiertos × presencia de SaviaHub/BacklogGit

### Paso 2 — D2: Independencia LLM (25%)
1. Verificar `scripts/emergency-setup.sh` existe
2. Comprobar si Ollama está mencionado en configuración
3. Analizar smart-frontmatter: ¿hay variedad de modelos? (haiku/sonnet/opus)
4. Buscar dependencias Claude-específicas en prompts
5. Score: emergency_mode_ready × multi_model_usage × prompt_portability

### Paso 3 — D3: Protección del grafo (20%)
1. Verificar `.gitignore` excluye datos sensibles (PAT, credenciales, PII)
2. Detectar Company Savia con cifrado (RSA-4096, AES-256)
3. Comprobar perfiles de cliente en local (no cloud)
4. Verificar hook-pii-gate activo en settings.json
5. Score: gitignore_coverage × encryption_present × pii_protection

### Paso 4 — D4: Gobernanza del consumo (15%)
1. Verificar `company/policies.md` existe (governance policy)
2. Detectar audit-trail configurado (action-log, agent-trace-log)
3. Buscar trazas de ejecución de governance-audit
4. Verificar token tracking (context-budget, scoring-curves)
5. Score: policy_exists × audit_active × tracking_present

### Paso 5 — D5: Opcionalidad de salida (15%)
1. Verificar documentación completa (README, guides, rules en markdown)
2. Buscar exit plan documentado
3. Comprobar backups configurados (backup-encrypt, backup-verify)
4. Verificar datos de empresa separados de herramienta
5. Score: docs_complete × exit_plan × backups × data_separation

### Paso 6 — Score global
1. Calcular: `Score = D1×0.25 + D2×0.25 + D3×0.20 + D4×0.15 + D5×0.15`
2. Clasificar nivel (plena/alta/medio/alto/crítico)
3. Generar gráfico ASCII de barras por dimensión
4. Guardar en `output/sovereignty-scan-YYYYMMDD.md`

## Flujo: Report

1. Cargar último scan de `output/sovereignty-scan-*.md`
2. Si no existe → ejecutar scan primero
3. Cargar scans anteriores para tendencia (si hay)
4. Generar informe ejecutivo:
   - Score global + clasificación
   - Desglose por dimensión con evidencia concreta
   - Tendencia temporal (mejora/empeora/estable)
   - Riesgos priorizados
   - Benchmarks: comparación con configuración ideal
5. Formato: markdown (default) o delegado a skill PDF si --format pdf

## Flujo: Exit Plan

1. Inventariar datos organizacionales:
   - SaviaHub: company/, clients/, users/ (tamaño, items)
   - Perfiles: `.claude/profiles/` (users, teams)
   - Memorias: `.claude/agent-memory/` (MEMORY.md por agente)
   - Backlogs: snapshots en BacklogGit
   - Specs, decisiones, playbooks
2. Listar dependencias del proveedor actual:
   - API Anthropic (Claude Code)
   - Azure DevOps / Jira (si configurado)
   - MCP servers activos
3. Estimar esfuerzo de migración por categoría
4. Generar timeline realista (72h/1 semana/1 mes)
5. Listar alternativas: otros LLMs, herramientas PM, plataformas
6. Output: `output/exit-plan-YYYYMMDD.md`

## Flujo: Recommend

1. Leer último scan
2. Identificar dimensiones con score < 70
3. Para cada gap, mapear a acción concreta:
   - D1 bajo → "Configura SaviaHub: `/savia-hub init`"
   - D2 bajo → "Configura Emergency Mode: `/emergency-mode setup`"
   - D3 bajo → "Activa PII gate: revisa `.claude/settings.json`"
   - D4 bajo → "Crea governance policy: `/governance-policy create`"
   - D5 bajo → "Genera exit plan: `/sovereignty-audit exit-plan`"
4. Ordenar por impacto/esfuerzo (quick wins primero)
5. Presentar como checklist accionable con prioridad

## Errores

| Error | Acción |
|-------|--------|
| Workspace no inicializado | Sugerir `git init` + setup básico |
| Sin datos para scan | Ejecutar scan con defaults (score bajo) |
| Sin scans anteriores | Report sin tendencia, solo snapshot actual |
| Fichero de scan corrupto | Re-ejecutar scan |

## Seguridad

- El scan NUNCA envía datos organizacionales a APIs externas
- Los resultados se guardan localmente en `output/`
- El exit plan no ejecuta ninguna migración, solo documenta
- Las recomendaciones son informativas, no ejecutan comandos automáticamente
