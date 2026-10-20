---
status: PROPOSED
priority: P0
developer_type: agent-single
created: 2026-10-20
author: Savia
phase: A
risk: L2
related_specs: [SE-244, SE-425, SE-451]
origin: output/research/20261020-learnings-inditex.md (L2, L3, L7)
resource: https://github.com/InditexTech/gh-actions
---

# SE-442 — Cadena de suministro de la CI: acciones fijadas por SHA, Dependabot, CodeQL, Scorecard y divulgación coordinada

## Problema

La CI ejecuta código de terceros con el token del repositorio. Medido sobre `main` (a15eae38f):

- `.github/workflows/*.yml` contiene 51 referencias `uses:` externas. 31 están fijadas a un SHA de 40
  hex; **20 no**: `actions/checkout@v4` (6), `actions/github-script@v7` (7),
  `actions/upload-artifact@v4` (5), `actions/setup-python@v5` (1) y `gitleaks/gitleaks-action@v2` (1).
  Dos líneas ya llevan el comentario `# TODO: pin to SHA`: la deuda está reconocida y sin cerrar.
- No existe `.github/dependabot.yml`. SE-244 (`IMPLEMENTED`) cubre vulnerabilidades de dependencias
  (`dependency-audit.yml`: pip-audit y npm audit), pero excluye de forma explícita la actualización
  automática y no mira las acciones de GitHub.
- No hay workflow de CodeQL ni de OpenSSF Scorecard. El repo público tiene hooks de seguridad y
  agentes con permisos de escritura, y ninguna medición externa y reproducible de su postura.
- `SECURITY.md` indica cómo reportar (pestaña Security) pero no fija plazo de embargo, crédito ni
  marcado de las releases de seguridad.

## Valor y evidencia

- Una etiqueta móvil (`@v4`) permite que el autor de la acción, o quien comprometa su cuenta, cambie
  lo que se ejecuta con nuestros permisos sin que haya un cambio en este repo. Fijar el SHA convierte
  ese riesgo en un cambio revisable. Es el vector de cadena de suministro más barato de cerrar.
- Evidencia de práctica: el catálogo de acciones de Inditex Tech exige fijar todo a un SHA inmutable
  (`gh-actions/README.md`: «Consumers must pin every catalog reference to an immutable commit SHA») y
  sus workflows anotan la versión en un comentario. Scorecard y CodeQL aparecen como workflows
  estándar en sus repos `kumoss` y `cerbia` (solo se leyeron los nombres de fichero, no el contenido).
- Esfuerzo bajo, sin dependencias de otras specs, y protege a todos los PRs de la cola.

## Alcance

| Slice | Entrega |
|---|---|
| S1 | Fijar a SHA las 20 referencias, con comentario de versión (`# v4`). Test BATS `tests/test-ci-actions-pinned.bats` que falla si algún `uses:` externo en `.github/workflows/` y `.github/actions/` no termina en 40 hex. Sin script nuevo: el ratchet de entropía de capacidades (`capability-entropy.py --check`) lo desaconseja. |
| S2 | `.github/dependabot.yml` con ecosistema `github-actions`, frecuencia semanal, agrupado en un único PR por ciclo. |
| S3 | Workflows `codeql.yml` (JavaScript/TypeScript y Python) y `scorecard.yml`, con resultados a code scanning, `permissions` mínimos por job y acciones fijadas por SHA (S1). |
| S4 | `SECURITY.md`: plazo de embargo coordinado, crédito al autor del reporte y marcado de la release de seguridad. |

## Fuera de alcance

- Bajar umbrales o silenciar alertas para que pase CodeQL o Scorecard. Cada alerta se resuelve con
  causa raíz o se registra como excepción con motivo (`feedback_root_cause_always`).
- Análisis estático de bash (CodeQL no lo soporta): lo siguen cubriendo shellcheck y los BATS.
- Dependabot para npm y pip (ya hay lockfiles, SE-425): decisión D2.
- Scorecard como gate bloqueante: en esta spec solo mide y publica.

## Criterios de aceptación

| AC | Verificación |
|---|---|
| AC1 | `bats tests/test-ci-actions-pinned.bats` pasa sobre el árbol resultante. |
| AC2 | El mismo test tiene un caso negativo: con un workflow de fixture que contiene `uses: actions/checkout@v4` falla y nombra fichero y línea. Otro caso: `uses: ./.github/actions/x` (local) no falla. |
| AC3 | `grep -rE 'uses: [^./][^ ]*@' .github/workflows \| grep -vE '@[0-9a-f]{40}'` no devuelve líneas. |
| AC4 | `.github/dependabot.yml` es YAML válido (`python3 -c 'import yaml,sys; yaml.safe_load(open(sys.argv[1]))'`) y declara `package-ecosystem: github-actions` con `schedule.interval: weekly` y un `groups` que cubre `*`. |
| AC5 | `codeql.yml` y `scorecard.yml` existen, son YAML válido y cumplen AC1. En el PR, ambos jobs se ejecutan y suben resultados (evidencia: enlace al run; no verificable en local). |
| AC6 | `SECURITY.md` contiene las secciones «Plazo de embargo», «Crédito» y «Releases de seguridad» (`grep -c` = 3). |
| AC7 | `bash scripts/validate-ci-local.sh --quick` termina en verde. |

## Riesgos

- Los PRs de Dependabot consumen cuota de revisión. Mitigación: un único PR agrupado por semana.
- Fijar a SHA congela correcciones de seguridad de la acción hasta que Dependabot proponga el
  cambio. Es el comportamiento buscado; se revisa cada semana.
- Ruido inicial de alertas de CodeQL. Se triagea por lotes; la spec no promete cero alertas, promete
  que ninguna se oculta.
- Si el repo no cumple los requisitos de Scorecard (token, rama protegida), el job fallará de forma
  explícita y se documenta qué comprobaciones no aplican.

## Licencia de lo reutilizado

Solo se copia el patrón (fijar a SHA, Dependabot, workflows estándar), no código. Las acciones
oficiales `ossf/scorecard-action` y `github/codeql-action` se usan como dependencia de CI, no se
redistribuyen. Su licencia no se verificó en el repositorio de cada una: comprobarla en S3 antes de
mergear (el informe de investigación las daba por Apache-2.0 sin contrastarlo). Compatible con la
licencia MIT de Savia en los dos casos habituales.

## Esfuerzo

S: una sesión corta. S1+S2 son mecánicos; S3 depende de que los jobs corran en la CI real.

## Decisiones pendientes de la operadora

- **D1**: plazo de embargo de divulgación: 30 días (valor de referencia observado) u otro.
- **D2**: ampliar Dependabot a npm y pip, agrupado, o dejarlo para una spec posterior.
- **D3**: lenguajes de CodeQL en la primera versión (propuesta: JavaScript/TypeScript y Python).

## Referencias cruzadas

SE-244 (auditoría de dependencias, complementaria), SE-425 (lockfiles de npm, misma familia de riesgo),
SE-451 (gobernanza de contribuciones: comparte `SECURITY.md` y `.github/`).

## OpenCode Implementation Plan

### Bindings touched

Ninguno: workflows de GitHub, configuración de Dependabot y documentación. No toca hooks, agentes ni skills.

### Verification protocol

- [ ] `bats tests/test-ci-actions-pinned.bats` en verde y con su caso negativo.
- [ ] Sin cambios de comportamiento en Claude Code ni en OpenCode.

### Portability classification

- [x] **PURE_BASH**
