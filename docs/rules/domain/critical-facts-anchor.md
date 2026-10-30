---
context_tier: L0
token_budget: 85
---

# Critical Facts Anchor

SPEC-185 hard-cap 150 tokens.

Anchor corto leído cada turno. Contiene solo hechos invariantes del workspace.

SE-487: es un fichero versionado y público. Nunca lleva datos de una persona (slug, nombre, idioma, fecha de activación). La identidad la inyecta `session-init.sh` desde el perfil local gitignored. Guardia: `scripts/validate-critical-facts-cap.sh --clean-clone`.

Auto-generado por generate-critical-facts.sh. Validado por validate-critical-facts-cap.sh.

Solo el contenido entre marcadores cuenta para el cap.

Ref SPEC-185.
