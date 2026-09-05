---
layer: peripheral
name: prospectiva-basica
description: "Prospectiva sistemica local: micro-MICMAC (variables motrices vs dependientes) y micro-MACTOR (actores, alianzas, divergencias, zona de acuerdo). Usar cuando se analiza un sistema con variables interdependientes, se priorizan palancas de accion, o se mapean actores y conflictos. Triggers: 'micmac', 'mactor', 'analisis estructural', 'variables motrices', 'zona de acuerdo'."
metadata:
  savia.maturity: "incomplete"
  savia.maturity: stable
  savia.context: "standalone"
  savia.context_cost: "low"
  savia.category: "analysis"
  savia.tags: "prospectiva, foresight, micmac, mactor, sistemas"
  savia.priority: "low"
  savia.loop_level: "L1"
  savia.trigger_keywords: "micmac, mactor, prospectiva, variables motrices, analisis estructural"
---

# Prospectiva Básica

Base de skill generada en L30-F1. Análisis estructural 100% local
(stdlib Python, sin red, determinista — CRIT-001).

## Authoritative Paths

| Recurso | Path |
|---|---|
| Micro-MICMAC | `scripts/micmac.py` |
| Micro-MACTOR | `scripts/mactor.py` |
| Fixtures de referencia | `tests/fixtures/l30-prospectiva/` |
| Tests | `tests/bats/test-l30-prospectiva.bats` |
| Preregistro | `labs/roadmaps/l30-prospectiva-sistemica.md` |

## MICMAC — qué variables mover

1. Define 4-20 variables del sistema y su matriz de influencias directas
   (0 = nada, 1 = débil, 2 = media, 3 = fuerte). Filas influyen a columnas.
2. Ejecuta: `python3 scripts/micmac.py --matrix sistema.json`
3. Lee cuadrantes:
   - **Motriz** (influye mucho, depende poco): palanca de acción prioritaria.
   - **Dependiente** (recibe, no influye): indicador de resultado, no palanca.
   - **Enlace** (ambos altos): inestable — amplifica tanto riesgos como mejoras.
   - **Autónomo** (ambos bajos): irrelevante para el sistema actual.

## MACTOR — quién se mueve y con quién

1. Define 2-6 actores con `positions` (0..1 por eje), `stake` (cuánto les
   importa cada eje) y `power` (0..1).
2. Ejecuta: `python3 scripts/mactor.py --actors actores.json`
3. Lee: `divergences` (conflicto latente donde ambos stakes son altos),
   `alliances` (convergencia ≥ 0.7), `agreement_zone` (centroide ponderado
   por poder + spread — el rango negociable real).

## Límites declarados (honestidad de método)

- El encuadre de variables y actores es **input humano**: el método no
  sustituye el juicio de quien define la matriz (R4 del preregistro).
- Análisis estático: no adapta el sistema; complementar con vigilancia (V4).
- Una sola corrida no valida nada: las predicciones se backtestean (L30-F3).

## Related

- Roadmap: `labs/roadmaps/l30-prospectiva-sistemica.md` (F2: caso real, F3: backtesting)
- Mapa de verificación: `docs/harness-map.md` (L28)
