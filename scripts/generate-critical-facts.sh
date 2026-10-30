#!/usr/bin/env bash
# scripts/generate-critical-facts.sh
# SPEC-185: Auto-regenerates the CRITICAL_FACTS section of docs/critical-facts.md.
# SE-487: the file is versioned in a public repo and imported by CLAUDE.md on
# every turn, so it holds ONLY workspace invariants. It never reads the local
# profile (.claude/profiles/active-user.md) nor ~/.savia/preferences.yaml: the
# active person's facts are injected at startup by session-init.sh from the
# gitignored profile. Same output on any machine (determinism, AC4).

set -uo pipefail

# --check: exit 1 if the file is stale; never writes.
CHECK=false
[[ "${1:-}" == "--check" ]] && CHECK=true

FILE="docs/critical-facts.md"
SPRINT="PM-Workspace activo · cadencia 2 sem · daily 09:15"

# Build new section content (no personal data: no slug, name, language or date)
read -r -d '' NEW_CONTENT <<EOF || true
- **Persona activa**: la inyecta el arranque desde el perfil local (gitignored). Sin perfil: «no sé quién eres» → \`/profile-setup\`. Nunca suponer identidad
- **Frontend**: Claude Code u OpenCode · modelos por tier heavy/mid/fast (\`model_tier\`), resueltos en local: \`~/.savia/preferences.yaml\` → \`tiers.<frontend>\` · default Claude Code opus/sonnet/haiku
- **Sprint**: $SPRINT
- **Gates inmutables**: Rule 1 PAT via \$(cat \$PAT_FILE) · Rule 3 confirmar antes de escribir Azure DevOps · Rule 8 sin autoaprobación; merge con grant expreso · autonomous-safety: rama \`agent/*\` + PR Draft + revisión de la operadora única o reviewer elegible
- **Tono**: Radical Honesty (Rule 24) · sin filler · femenino siempre (Savia)
EOF

# Replace section between markers
TMP=$(mktemp)
# BSD awk (macOS) rejects -v values containing newlines; pass content via file.
CONTENT_TMP=$(mktemp)
printf '%s\n' "$NEW_CONTENT" > "$CONTENT_TMP"
awk -v newfile="$CONTENT_TMP" '
  /<!-- CRITICAL_FACTS_START -->/ { print; while ((getline line < newfile) > 0) print line; in_section=1; next }
  /<!-- CRITICAL_FACTS_END -->/ { in_section=0 }
  !in_section { print }
' "$FILE" > "$TMP"
rm -f "$CONTENT_TMP"

if $CHECK; then
  if cmp -s "$TMP" "$FILE"; then rm -f "$TMP"; echo "OK: $FILE up to date"; exit 0; fi
  diff "$FILE" "$TMP" | head -20; rm -f "$TMP"
  echo "STALE: $FILE — run: bash scripts/generate-critical-facts.sh" >&2
  exit 1
fi
mv "$TMP" "$FILE"
echo "Regenerated $FILE (workspace invariants only, SE-487)"
