# S03u — Medición previa: mutantes y auditor antes de elegir

> SE-376 (deuda de calidad con pruebas de comportamiento), roadmap S03 fase A.
> Medido sobre `origin/main` @ `81ab8f624`, el 2026-11-10. Primero se mide y después se elige
> (lo pidió la marca de fin de S03t: 4 de sus 8 ficheros ya mataban casi todos los mutantes).

## Cómo se midió

- **Auditor**: `bash scripts/test-auditor.sh --all --json`. Puntúa por nombres en inglés (PR #1360);
  no se renombra nada para subirlo.
- **Mutantes**: batería manual fuera del repo, sobre una copia aislada de `origin/main` (con su propio
  `.git`). Muta el **script**, no la aserción: un cambio por mutante (`-eq`↔`-ne`, `-lt`↔`-le`,
  `-gt`↔`-ge`, `==`↔`!=`, `&&`↔`||`, `exit`/`return 0`↔`1`, `exit 2`→`0`, `if [[`→`if ! [[`,
  `true`↔`false`, `+ 1`→`+ 0`; en Python además `<`↔`<=`, `and`↔`or`, `not`, `in`↔`not in`,
  `True`↔`False`, `if`→`if not`). Corre todos los tests que nombran el script; si el baseline no
  está en verde, no hay medida (fail-closed). «Muerto» = la suite sale distinta de 0.
- Con más de 40 mutantes o suites lentas se toma una muestra determinista equiespaciada (`n/total
  muestra`). En suites que prueban varios escáneres se filtran los tests por nombre del script.
- Corrección posterior al primer commit: la primera pasada omitía las suites de PRs S03 previas que
  también nombran el script (solo afectaba a mobile: `test-se240-mobile-security`, tratada en S03j).
- Candidatos: tests por debajo de 80 que ejercitan scripts de gates en `scripts/`, excluidos los
  ficheros tocados por las PRs de S03 (#1489, #1491, #1492, #1494, #1495, #1498, #1507 y las que
  devuelve la búsqueda S03), los vetados de S03s y todo `.claude/hooks/`.

## Candidatos medidos

| # | Script (gate) | Riesgo | Test bajo 80 (auditor) | Suites usadas | Mutantes muertos/total |
|---|---|---|---|---|---|
| 1 | `exit-purge-verify.sh` | confidencialidad: certifica que un engagement olvidado no deja rastro | `test-se272-s5-exit-portability` (78) | esa | **0/29** |
| 2 | `opencode-gates-real.py` | arnés de prueba del motor real (no es gate en uso) | `structure/test-opencode-gates-v2` (61) | esa | 3/20 (muestra de 159) |
| 3 | `mobile-security-scan.sh` | seguridad: veredicto clean/findings de un APK | `test-gate-result-ondemand` (63) | + `test-se240-mobile-security` (78, de S03j) | **33/45** (17/45 solo con la primera) |
| 4 | `compliance-eval.py` | regulatorio: ALLOW/BLOCK/UNKNOWN de una política | `bats/compliance-policy` (41) | esa | 11/20 (muestra de 44) |
| 5 | `prompt-security-scan.sh` | seguridad de prompts | `test-gate-result-scanners` (63) | + `scripts/test-prompt-security-scan` (82) | 22/40 (muestra de 71) |
| 6 | `egress-gate.sh` | red: deny-by-default | `test-g3-effect-path-capabilities` (74) | + `test-se273-s3-s7` (88) | 20/29 |
| 7 | `mcp-security-audit.sh` | seguridad de servidores MCP | `test-mcp-osv-check` (57) | + `test-mcp-security-audit` (88), `test-scrapling-mcp-template` | 16/20 (muestra de 104) |
| 8 | `git-history-secret-scan.sh` | secretos en el historial | `test-gate-result-contract` (63) | + `test-git-secret-scanner` (83), `test-gitignore-scanner-exceptions` (87) | 31/38 |
| 9 | `ci-extended-checks.sh` | CI | `test-hook-latency-fork-free` (52) | + `test-ci-extended-ratchet` | sin medida: baseline rojo en la copia aislada (depende del repo completo) |
| 10 | `pre-push-security-gate.sh` | secretos antes del push | `test-gate-result-contract` (63) | + `test-git-secret-scanner` | en curso al commit |
| 11 | `dependency-scan.sh` | CVE en dependencias | `test-gate-result-contract` (63) | + `test-dependency-scanner` (88) | en curso al commit |
| 12 | `vuln-scan.sh` | hooks con `eval` | `test-gate-result-ondemand` (63) | esa (filtrada) | en curso al commit |
| 13 | `security-scan.sh` | secretos en el workspace | `test-gate-result-ondemand` (63) | + iac, scanners (filtradas) | en curso al commit |
| 14 | `mcp-audit.sh` | diseño de herramientas MCP | `test-mcp-tool-design` (64) | + `test-mcp-audit` (94) | en curso al commit |
| — | `merge-sprint.sh` | autoridad (merge) | `test-merge-sprint-se500` (77) | — | no medido: 440 mutantes × 150 s por suite no caben en el time-box; su otra suite tiene 90 |

## Elección (hasta 6)

Criterio: peor proporción de mutantes muertos × riesgo del gate. Un falso verde en un gate de
confidencialidad o seguridad pesa más que en un arnés.

1. **`exit-purge-verify.sh`** — 0/29: ningún test ejerce su comportamiento (solo existe, es
   ejecutable y pasa `bash -n`). Certifica la purga de un cliente: un «CLEAN» falso es una fuga.
2. **`mobile-security-scan.sh`** — 33/45 (73 %) con todas sus suites. Veredicto de seguridad de un APK.
   Tres de sus 12 supervivientes están en el bloque del manifiesto (líneas 140-144): ese código no
   influía en el resultado. Ahí estaba el fallo.
3. **`compliance-eval.py`** — 11/20 (55 %). Decide ALLOW/BLOCK regulatorio; ningún test mira el
   código de salida ni los casos de rol y unknowns críticos.
4. **`egress-gate.sh`** — 20/29 (69 %). Control de red deny-by-default; sobreviven el interruptor
   maestro, la validación de protocolo y de dominio por separado y el recuento de `status`.

Descartados con motivo:
- `opencode-gates-real.py` (3/20): es un arnés que arranca el motor real (opt-in
  `SAVIA_GATES_REAL=1`), no un gate en el camino de nadie; subirlo exigiría el binario del motor.
- `prompt-security-scan.sh` (22/40): 9 de los 18 supervivientes son equivalentes (`|| true`→`|| false`
  al final de una sustitución de proceso); su suite propia ya da 82.
- `git-history-secret-scan.sh` (31/38) y `mcp-security-audit.sh` (16/20): ya matan más del 80 %.
- Los «en curso» se añaden a esta tabla cuando terminen; si alguno sale peor que los elegidos, se
  dice en la PR y queda para el siguiente grupo.
