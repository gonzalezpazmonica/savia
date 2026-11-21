# S32 — restos de specs con entregas parciales (2026-11-21)

Inventario de lo que falta en SE-426, SE-500, SE-501 y SE-470, medido sobre `origin/main` 7321af6b7.
Criterio de decisión: se hace un resto si es pequeño (≤ 300 líneas), sin funcionalidad nueva y sin tocar
`scripts/merge-sprint.sh` ni `scripts/risk-tier.py`. No se cambia el estado de ninguna spec.

**Resultado: no hay ningún resto que cumpla los tres requisitos. No se abre ninguna PR de código.**
Lo pendiente es una acción de la operadora, una consolidación que el encargo prohíbe a un worker, una
observación con fecha y una slice nueva.

## Resumen

| Spec | Resto | Decisión | Quién lo cierra |
|---|---|---|---|
| SE-426 | AC5: observar el re-firmado del bot | Descartar: ya no existe qué observar | Operadora: pasar la spec a IMPLEMENTED con esta nota |
| SE-500 | Consolidar 54 fragmentos de planificación y 78 de LOG; AC-16 (métricas) | Dejar: consolidación fuera del encargo; AC-16 es observación | Orquestadora (consolidar), operadora (AC-16) |
| SE-501 | Check requerido `Confidentiality scan (PR)` en `main`; AC-16 | Dejar: acción de la operadora | Operadora |
| SE-470 | S1 (paso de CI `eval-integrity`) y AC4 (recuento sobre recibos reales) | Dejar: S1 es funcionalidad nueva en un workflow (tier 4); AC4 usa recibos privados | Operadora decide D1 y D2; worker nuevo para S1 |

## SE-426 — firma con secreto de CI

Pasos 1–3 integrados (resultados en la spec). Único AC abierto: **AC5**, «el re-firmado del bot queda por
observar en el próximo auto-rebase».

Evidencia de que el AC ya no tiene objeto:

- SE-501 sacó la firma de las PR. `git ls-files .confidentiality-signature` está vacío en `main`.
- `auto-rebase-open-prs.yml` (línea 11) declara «No re-sign: the signature is no longer versioned».
- `tests/test-se501-derived.bats`, AC-12 («ningún script ni workflow escribe la firma… sign retirado») y
  AC-15 («ningún workflow de PR referencia la clave HMAC») cubren lo que AC5 quería garantizar con otro
  mecanismo.
- `gh run list --workflow auto-rebase-open-prs.yml`: los últimos 8 runs, hasta hoy, en `success`, sin re-firma.

Decisión: **descartar AC5**. Rehacer el re-firmado del bot sería reintroducir lo que SE-501 retiró. Las
partes 1–2 (HMAC por stdin, modo exigente) siguen vigentes en `confidentiality-sign.sh`, que queda para
verificar firmas históricas. Cambiar el `status` de la spec no es de este encargo.

## SE-500 — merge-sprint sin realineación

S1, S2 y S3 están en `main` (#1468, #1469, #1526). Los AC-1 a AC-20 tienen tests en
`tests/test-se500-planning-fragments.bats` y `tests/test-merge-sprint-se500.bats`. `report` imprime M1, M2
y M3 (AC-16). La regla `autonomous-safety-merge-sprint.md` ya dice «registra con `roadmap.sh register`».
El skill `merge-plan` existe.

Restos:

1. **Consolidación.** La spec fija «más de 30 fragmentos» como disparador. Hoy hay **54** en
   `docs/propuestas/planning.d/` y **78** en `docs/propuestas/LOG.d/`. `bash scripts/roadmap.sh consolidate`
   en una PR ordinaria lo resuelve. No lo hago: reescribe `planning-state.json`, que el encargo común reserva
   a la orquestadora, y borra fragmentos que otras PR abiertas pueden estar referenciando. Es un cambio
   mecánico, sin funcionalidad nueva, y cabe en una PR; falta que la orquestadora lo lance con las PR
   abiertas ordenadas.
2. **Métricas M1–M3 con datos reales.** Líneas base y objetivos están en la spec; la medición de después
   necesita el ledger local de merge-sprint, que no está en el repo. Observación, no código.

Descartado: nada. Fuera de alcance de la spec, y por tanto no son restos: cambiar el workflow de auto-rebase.

## SE-501 — derivados fuera de las PR (opción B)

Entregado (#1472, #1488, #1490): `derived-paths.txt`, `derived.sh` (ensure, drop, verify, migration-check,
`confidentiality-main.yml`, G20, escaneo con el escáner de la base, inventario de lectores,
corte con `git rm --cached` (la fecha del corte en `main` es 2026-11-05/06), y AC-13 en `merge-sprint.sh`.
`tests/test-se501-derived.bats` tiene 67 tests y cubre AC-1 a AC-15.

Restos:

1. **Acción de la operadora en GitHub:** añadir `Confidentiality scan (PR)` a los contextos requeridos de
   `main`. Evidencia hoy:

   ```
   $ bash scripts/derived.sh migration-check
   FAIL: «Confidentiality scan (PR)» no está entre los contextos requeridos de main
         (BATS Hook Tests, Lint Markdown, PR Guardian, Validate workspace)
   PASS: pr-secrets (21 workflow(s))
   ```

   Hasta que esté, el invariante I1 de la spec («ningún commit entra sin escaneo bloqueante») no se cumple
   por protección de rama; el escaneo se ejecuta pero es informativo. La spec lo decía en Riesgos: «el corte
   solo se fusiona si migration-check da PASS». Hoy da FAIL con el corte ya en `main`: es el hallazgo más
   serio de este inventario (no he comprobado si el check requerido existió y se retiró).
2. **AC-16 (medición a 7 días del corte).** Parcial a 2026-11-21 (15 días): 0 commits de `main` desde
   2026-11-06 tocan `.confidentiality-signature`, `.scm/sam.json`, `docs/rules/INDEX.md` o
   `rule-manifest.json` (línea base de la spec: 63, 27, 8 y 19 en 7 días), sobre 125 commits de `main` en
   ese periodo. Falta la mitad del AC: «0 aparcamientos de merge-sprint con D entre los ficheros en
   conflicto», que sale del ledger local.

Descartado: nada.

## SE-470 — integridad de los artefactos de evaluación

Entregado: S2, `scripts/trace-tamper-scan.py` con `tests/python/test_trace_tamper_scan.py` (#1487): AC3.

Restos:

1. **S1 (AC1, AC2): comprobación en CI** que etiqueta la PR `eval-integrity` y comenta si toca
   `.claude/contracts/allowlist.txt`, `tests/evals/**/cases.jsonl` o `tests/evals/baselines/**` sin
   `[contract-add]`, `[contract-remove]` o `[eval-change]` en el título. Es funcionalidad nueva y vive en
   `.github/workflows/` (tier 4, `GOVERNANCE_PREFIXES`). No cumple «sin funcionalidad nueva». Tamaño
   estimado: script + paso de CI + tests, ~150 líneas.
2. **AC4: recuento del detector sobre un lote real de recibos.** Los recibos están fuera del repo
   (privados). Se ejecuta en la máquina de la operadora y se cita solo el número. Su resultado decide la
   condición de la spec: con ≥ 1 evento confirmado sube a P1; con 0 en n ≥ 40 baja a P3.
3. **H4** (reproducir la comprobación sobre los 5 commits citados) decide si S1 es aviso o bloqueo; sin
   hacer.
4. **Decisiones D1 y D2** de la spec siguen pendientes (etiqueta o bloqueo; si merge-sprint trata
   `eval-integrity` como bloqueo del plan). D2 tocaría `merge-sprint.sh`, vetado a agentes.

Descartado: nada.

## Notas de proceso

- El encargo común todavía pide `sam.py generate` + commit de `.scm` y `confidentiality-sign.sh sign` + commit
  en el cierre de PR. Desde SE-501 esos dos ficheros no se versionan (G20 los rechaza en una PR). Se ha
  usado el cierre vigente: `derived.sh ensure` sin commit y `confidentiality-scan.sh --pr` sin firma. El
  texto del encargo común está desfasado (paso 5 de la spec SE-501, «Migración», lo anticipaba).
