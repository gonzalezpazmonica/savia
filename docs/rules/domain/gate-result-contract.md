---
context_tier: L2
token_budget: 900
---

# Contrato de resultado de los gates: limpio, hallazgos y desconocido

> SE-453. Extiende `checker-fail-closed.md` (las reglas de fail-closed viven allí y no se copian aquí).
> Aplica a escáneres (`scripts/*scan*`, `*gate*`) y a hooks de seguridad. Los scripts nuevos lo siguen desde el origen.

## Qué añade

`checker-fail-closed.md` prohíbe que un fallo se lea como pass, pero no fija un vocabulario común: cada script
decidía qué significa su código 2. Este contrato fija el **resultado** que un llamador genérico puede leer.

## Tres estados

| `result` | Significa | Qué hace el llamador |
|---|---|---|
| `clean` | Se ejecutó todo lo pedido y no hay hallazgos | Pasa |
| `findings` | Se ejecutó y hay hallazgos (puede llevar `gaps`) | Falla por hallazgos |
| `unknown` | Algo no pudo ejecutarse o se truncó: no hay veredicto | Ni pasa ni acusa: se trata como no medido |

Regla de oro: un elemento omitido no es un elemento limpio. Un `clean` con algún hueco pasa a `unknown`.

## Salida

La **última línea de stdout** del script es:

```
gate-result: {"result":"unknown","gaps":[{"check":"gitleaks","reason":"missing_tool"}]}
```

- `result`: `clean`, `findings` o `unknown`.
- `gaps[]`: lista de huecos; cada uno con `check` (qué comprobación) y `reason`.
- `reason` ∈ `missing_tool` (herramienta ausente), `limit` (tope de recursos superado), `timeout`,
  `unreadable` (salida o entrada ilegible, o herramienta que falló).
- `unknown` exige al menos un hueco. `clean` no lleva huecos. `findings` puede llevarlos.

Se emite con `.claude/hooks/lib/gate-result.sh` (`gate_result_emit <estado> [check:reason ...]`), que valida los tres
campos. Los hooks que no pueden medir (sin `jq`) lo registran con `gate_unmeasured_record`
(vía `.claude/hooks/lib/hook-input.sh`) en `output/unmeasured-gates.jsonl`, una línea por hook y día.

## Códigos existentes → estado (sin renumerar)

| Script | Código | Estado |
|---|---|---|
| `git-history-secret-scan.sh` | 0 | `clean` |
| | 1 (CRITICAL/HIGH), 2 (MEDIUM/LOW) | `findings` |
| | 3 (`output/` sin ignorar) | `unknown` (configuración) |
| | 4 (gitleaks ausente, fallido, timeout, ilegible o tope de commits) | `unknown` |
| `dependency-scan.sh` | 0 / 1 | `clean` / `findings` |
| | 2 | `unknown` (Trivy o jq ausente, escaneo o SBOM fallido) |
| `iac-security-scan.sh` | 0 / 1 | `clean` (o `NO_IAC`) / `findings` |
| | 2 | `unknown` (python3, Trivy o Docker ausentes, Trivy roto o JSON ilegible) o error de argumentos sin resultado |
| `prompt-security-scan.sh` | 0 / 1 | `clean` / `findings` |
| | 2 | `unknown` (fichero o directorio ilegible) o ruta inexistente sin resultado |
| `ast-quality-gate.sh` | 0 / 1 | `clean` / `findings` |
| | 2 (entorno), 3 (UNVERIFIED) | `unknown` |
| `pre-push-security-gate.sh` | 0 con gitleaks / 1 | `clean` / `findings` |
| | 0 sin gitleaks | `unknown` (registrado; con `SAVIA_GATE_UNKNOWN=block` sale 1) |
| `mcp-security-audit.sh` | 0 / 1 | `clean` / `findings` |
| | 2 | `unknown` (python3 ausente) o error de uso |
| `security-audit-all.sh` | 0 / 1 | bajo / sobre el umbral `--fail-on` (`result` dice `clean` o `findings`) |
| | 2 | `unknown` (un escáner ausente, roto o con salida ilegible) o error de uso |

Con `--json` (`--format json` en `iac-security-scan.sh`), estos llevan `result` y `gaps` dentro del objeto JSON en vez de la línea final.

El 4 de `git-history-secret-scan.sh` sustituye al 1 que antes se daba con gitleaks ausente: el 1 queda
solo para hallazgos críticos. Es el único código que cambia.

## Guards `blocking` (hooks)

Los hooks siguen saliendo solo con 0 o 2 (`hooks-blocking-guards.md`). Un guard `blocking` sin `jq`
degrada a un parseo con `grep` (`hook_extract_command`); si tampoco puede evaluar, sale 2. Nunca sale 0
sin haber evaluado. Los hooks no marcados que salen 0 sin `jq` añaden su línea de no medido.
En OpenCode, `savia-gates` ejecuta los mismos `.sh`; los puertos nativos (`.opencode/plugins/guards/*.ts`)
no usan `jq` y se comparan con el hook bash con las mismas entradas (`tests/test-gate-result-dual-binding.bats`).

## Consumidores

- **CI y `validate-ci-local.sh`**: `unknown` no bloquea el primer ciclo (D3). Se cuenta en
  `config/gate-unknown-baseline.txt`; el contador solo puede bajar y `bash .claude/hooks/lib/gate-result.sh check` falla
  si sube.
- **Hooks**: leen `output/unmeasured-gates.jsonl` como señal de huecos de cobertura.
