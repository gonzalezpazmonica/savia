---
context_tier: L3
spec: SE-532
token_budget: 900
usage: reference-only
---

# Catálogo de agentes: esquema de cabecera y referencias comprobadas (SE-532 S1)

Higiene del catálogo. No cambia ningún permiso, agente ni comportamiento.

## Orden

```
python3 scripts/validate-agent-catalog.py                 # catálogo completo
python3 scripts/validate-agent-catalog.py --retired a b   # además: a y b ya no existen ni se citan
```

Salida 0 todo pasa, 1 errores, 2 uso o entorno (sin PyYAML, sin `.opencode/agents/`, sin esquema).
Cada error nombra fichero y línea. Corre en `scripts/validate-ci-local.sh` y en
`tests/bats/test-se532-agent-catalog.bats`. No añade ningún paso a `ci.yml`.

## Qué comprueba cada regla

| Regla | Falla cuando |
|---|---|
| R1 | Cabecera ausente, sin cerrar, vacía, YAML ilegible o con clave duplicada |
| R2 | Falta una clave obligatoria o un valor sale de su dominio (`model_tier` solo `heavy`/`mid`/`fast`; nunca un modelo) |
| R3 | Clave que no figura en `config/agent-frontmatter.schema.json` |
| R4 | `tools` no es un mapa no vacío de booleanos |
| R5 | `name` distinto del nombre del fichero |
| R6 | Una fila de `config/judge-routing.yaml` cita un agente inexistente |
| R7 | `protected_agents` de `.opencode/protected-jobs.yaml` cita un agente inexistente |
| R8 | Un contrato `agent.<x>.yaml` sin agente `<x>` o con `id` distinto de `agent.<x>` |
| R9 | `decision_tree` apunta a un fichero que no existe bajo `.opencode/agents/` |
| R10 | Con `--retired`: el agente aún tiene fichero o sigue citado (ver abajo) |

Corre además, sin reimplementarlos, `agents-catalog-sync.sh --check` (SE-253) y
`judge-routing-verify.sh` (SE-273). La coherencia nivel-herramientas sigue siendo de
`validate-agent-permissions.sh`.

## R10: qué cuenta como cita viva

Contextual, no por palabra: `subagent_type:`, `agent:`, `Task(x)`, listas de agentes, elementos de lista YAML,
celdas de tabla `| x |`, `handler: agent x`, contratos. En `scripts/` cuenta el nombre literal.
Se escanean `.opencode`, `.claude`, `config`, `contracts`, `scripts`, `docs/rules` y la allowlist de SE-253.
No cuentan `CHANGELOG*`, `docs/specs-archive/`, `docs/evidence/` ni las specs. El nombre se busca como
texto literal (metacaracteres y guion inicial incluidos).

## Excepciones congeladas

`docs/agent-catalog-exceptions.txt`: `agente | regla | detalle | alta | motivo`, solo R1, R2 y R3.
Solo puede encoger. Falla una excepción obsoleta, una nueva respecto a `origin/main`, una de un agente
inexistente, un fichero borrado que existe en la base y una base ilegible (fail-closed). Solo cuando la base
confirma que el fichero no existe (la PR que lo crea) se acepta sin comparar. Un agente nuevo no puede entrar
con excepciones. `--freeze` la genera una sola vez y no sobrescribe.

## Alcance de S1 frente a la lista de retirada de SE-527

Cubre referencias de agente, espejo, routing, protegidos, contratos, allowlist y nombres literales en `scripts/`.
No cubre comandos y skills que despachan por nombre más allá de detectar la cita, los recuentos «90»,
los tests anclados ni capability map/SAM/entropía (ya tienen sus gates).
