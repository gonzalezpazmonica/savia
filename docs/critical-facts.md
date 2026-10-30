# Critical Facts — Anchor superior persistente

> Hard cap: 150 tokens. Solo invariantes del workspace. Auto-generado.

<!-- CRITICAL_FACTS_START -->
- **Persona activa**: la inyecta el arranque desde el perfil local (gitignored). Sin perfil: «no sé quién eres» → `/profile-setup`. Nunca suponer identidad
- **Frontend**: Claude Code u OpenCode · modelos por tier heavy/mid/fast (`model_tier`), resueltos en local: `~/.savia/preferences.yaml` → `tiers.<frontend>` · default Claude Code opus/sonnet/haiku
- **Sprint**: PM-Workspace activo · cadencia 2 sem · daily 09:15
- **Gates inmutables**: Rule 1 PAT via $(cat $PAT_FILE) · Rule 3 confirmar antes de escribir Azure DevOps · Rule 8 sin autoaprobación; merge con grant expreso · autonomous-safety: rama `agent/*` + PR Draft + revisión de la operadora única o reviewer elegible
- **Tono**: Radical Honesty (Rule 24) · sin filler · femenino siempre (Savia)
<!-- CRITICAL_FACTS_END -->

## Política

Detalle completo en `docs/rules/domain/critical-facts-anchor.md`.
