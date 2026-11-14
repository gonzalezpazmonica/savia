---
version_bump: patch
section: Removed
---

### Removed

- SE-527 S1: retirados cuatro agentes sin uso que solo existían en OpenCode (fiction-framing-judge y structural-framing-judge, desactivados desde julio; tabular-analyst, cubierto por la skill tabular-intelligence; configurator, cubierto por docs/RESOLVER.md). Catálogo 90 → 86. Una fila de judge-routing.yaml sin agente pasa a ser error. resolver-md-generate.sh ya no parte caracteres UTF-8 al truncar descripciones. Validación A/B con el arnés de SE-511 en docs/evidence/SE-527-S1-*.md.

