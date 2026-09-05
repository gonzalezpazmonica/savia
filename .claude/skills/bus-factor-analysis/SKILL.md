---
layer: peripheral
name: bus-factor-analysis
description: >
  Detecta el Bus Factor por modulo en un repositorio git usando el algoritmo
  CST(change-size-ratio). Genera JSON con BF, owners, riesgo, y avisa cuando
  un solo dev conoce un modulo critico.
metadata:
  # --- metadata.savia.* (SE-333) ---
  savia.category: resilience
  savia.maturity: stable
  savia.context: L2
  savia.maturity: calibrated
  savia.se: SE-252
  savia.summary: Skill de deteccion de riesgo de conocimiento. Analiza git history para identificar modulos con un unico conocedor y genera planes de mitigacion.
  savia.tags: "bus-factor, knowledge-graph, git-analysis, risk, resilience"
---

# Bus Factor Analysis

## Descripcion

Detecta el Bus Factor (BF) de cada modulo de un proyecto analizando el
historial git con el algoritmo CST(change-size-ratio):
- BF=1 → CRITICAL: un solo dev conoce el modulo
- BF=2 → HIGH: dos devs, riesgo elevado
- BF=3 → MEDIUM: tres devs, riesgo moderado
- BF>3 → LOW: riesgo bajo

## Cuando usar

- Pre-sprint si hay devs de vacaciones o baja
- Tras la salida de cualquier miembro del equipo
- Mensualmente como revision de riesgo organizativo
- Cuando un nuevo dev se incorpora (para generar su plan de onboarding)
- Cuando se detecta siloizacion de conocimiento

## Rutas criticas

- Motor Python:   `scripts/bus-factor-scan.py`
- Orquestador:    `scripts/bus-factor-scan.sh`
- Cupulas:        `scripts/context-dome-generate.sh`
- Distribucion:   `scripts/bus-factor-distribute.sh`
- Informe:        `scripts/bus-factor-report.sh`
- Hook PostWrite: `.claude/hooks/bus-factor-warn.sh`
- Protocolo:      `docs/rules/domain/bus-factor-protocol.md`
- DOMAIN:         `.claude/skills/bus-factor-analysis/DOMAIN.md`

## Flujo de uso

```bash
# 1. Escanear proyecto
bash scripts/bus-factor-scan.sh --project <path>

# 2. Generar cupulas para modulos criticos
bash scripts/context-dome-generate.sh --project <path> --min-risk HIGH

# 3. Plan de distribucion para un dev
bash scripts/bus-factor-distribute.sh --project <path> --target <dev-email>

# 4. Informe ejecutivo
bash scripts/bus-factor-report.sh --project <path> --format markdown
```

## Output esperado

JSON en `output/bus-factor/<proyecto>-<timestamp>.json` con estructura:
```json
{
  "project": "...",
  "modules": [{"name": "...", "bus_factor": 1, "risk_level": "CRITICAL", ...}],
  "summary": {"critical": 2, "high": 3, "medium": 1, "low": 5}
}
```

## Configuracion

Variables de entorno (o `.bus-factor.yml` en raiz del proyecto):

| Variable | Default | Descripcion |
|----------|---------|-------------|
| `BF_OWNERSHIP_THRESHOLD` | `0.50` | Score minimo para ser owner |
| `BF_RISK_CRITICAL` | `1` | BF <= N es CRITICAL |
| `BF_RISK_HIGH` | `2` | BF <= N es HIGH |
| `BF_MIN_COMMITS` | `5` | Commits minimos por archivo |
| `BF_MODULE_DEPTH` | `2` | Profundidad de agrupacion |
| `BF_EXCLUDE_PATTERNS` | `vendor/,node_modules/,*.lock` | Patrones a excluir |
| `BF_OUTPUT_DIR` | `output/bus-factor/` | Directorio de salida |

## Limitaciones

1. Git blame mide lineas, no comprension real
2. Rebases y merges distorsionan el historial
3. No detecta conocimiento organizativo (ver org-stakeholder-mapper)
4. Human decides: el script solo genera findings, no actua

## Integraciones

- `context-dome` skill: genera CONTEXT_DOME.md con conocimiento tacito
- `human-code-map` skill: usa el plan de distribucion para onboarding
- `codebase-memory-mcp`: enriquece nodos File con bus_factor property
