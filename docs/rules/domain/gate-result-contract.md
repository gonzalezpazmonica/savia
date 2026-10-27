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
- Si stdout está reservado a un JSON (`--json`, `--format json`), `result` y `gaps` van como campos de ese
  JSON y no hay línea final. `--quiet` suprime también la línea; el exit code y el registro se mantienen.
- Un agregador lee el JSON de cada sub-escáner aunque salga 1; un exit ≥ 2, un JSON ilegible o un
  `result: unknown` del sub-escáner es un hueco suyo (`<sub>:unreadable` o `<sub>/<check>:<reason>`).

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
| `iac-security-scan.sh` | 0 / 1 | `clean` (o `NO_IAC`) / `findings` (línea final o campos del report JSON) |
| | 2 | `unknown` (Trivy/Docker o python3 ausente, Trivy fallido o con timeout, JSON ilegible, argumentos) |
| `prompt-security-scan.sh` | 0 / 1 | `clean` / `findings` |
| | 0 con hueco | `unknown` (python3 ausente para PS-11, fichero ilegible, path sin `.md`; registrado; con `SAVIA_GATE_UNKNOWN=block` sale 2) |
| | 2 | `unknown` (path inexistente) |
| `mcp-security-audit.sh` | 0 / 1 | `clean` / `findings` |
| | 0 con hueco | `unknown` (`--config` inexistente o ilegible, o ninguna config por defecto; registrado; con `SAVIA_GATE_UNKNOWN=block` sale 2) |
| | 2 | `unknown` (python3 ausente o que no arranca; antes salía 1 con un falso MCP-00) o argumentos |
| `security-audit-all.sh` | 0 / 1 | según `result` (hallazgos bajo o sobre `--fail-on`) |
| | 0 con hueco | `unknown` (sub-escáner ≥ 2, ilegible o `unknown`; sin `critical`/`high`/`medium` enteros, exit 1 o `findings_count` > 0 sin ninguna cuenta; `prompt-security-scan.sh` ausente ⇒ `missing_tool`; python3 que no arranca ⇒ `python3:missing_tool`; motivo ajeno al vocabulario ⇒ `unreadable`; con `SAVIA_GATE_UNKNOWN=block` sale 1 siempre que haya hueco, también con hallazgos bajo `--fail-on`) |
| `confidentiality-scan.sh` | 0 / 1 | `clean` / `findings` |
| | 0 con aviso `UNKNOWN` | `unknown` (git no calcula el diff, p. ej. sin `origin/main`; blocklist pedida ilegible o generador ausente o fallido; con `SAVIA_GATE_UNKNOWN=block` sale 2). El Check 4 (ficheros prohibidos) corre aunque no haya líneas añadidas y sin las exclusiones de contenido |
| `ast-quality-gate.sh` | 0 / 1 | `clean` / `findings` |
| | 2 (entorno), 3 (UNVERIFIED) | `unknown` |
| `pre-push-security-gate.sh` | 0 con gitleaks / 1 | `clean` / `findings` |
| | 0 sin gitleaks | `unknown` (registrado; con `SAVIA_GATE_UNKNOWN=block` sale 1) |
| `security-scan.sh`, `vuln-scan.sh` | 0 sin `--ci` | según la línea `gate-result` |
| | `--ci`: 0 / 1 | `clean` / `findings` |
| | `--ci`: 0 con aviso `WARN` | `unknown` (grep ilegible o sin hooks; registrado; con `SAVIA_GATE_UNKNOWN=block` sale 1) |
| `mobile-security-scan.sh` | 0 con informe | según `gate-result` (también en el JSON: `result`, `gaps`); sin apktool, descompilación vacía, modo `dynamic` o informe MobSF sin triaje ⇒ `unknown` |
| | 1 | argumentos inválidos |

Con `--json`, `mcp-security-audit.sh` y `security-audit-all.sh` llevan `result` y `gaps` dentro del
objeto JSON en vez de la línea final.

El 4 de `git-history-secret-scan.sh` sustituye al 1 que antes se daba con gitleaks ausente: el 1 queda
solo para hallazgos críticos. El 2 de `mcp-security-audit.sh` sin python3 sustituye a un 1 por un falso
hallazgo. Son los únicos códigos que cambian.

Fuera del contrato: `transcriptor-scan.sh` (lista reuniones por stdout, una por línea; no es un gate).

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
