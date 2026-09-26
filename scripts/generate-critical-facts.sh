#!/usr/bin/env bash
# scripts/generate-critical-facts.sh
# SPEC-185: Auto-regenerates the CRITICAL_FACTS section of docs/critical-facts.md
# from authoritative sources (active profile, preferences, CLAUDE.md gates).
# Idempotent: same inputs → same output. Determinism is required for AC4.

set -uo pipefail

# --check: exit 1 if the file is stale; never writes.
CHECK=false
[[ "${1:-}" == "--check" ]] && CHECK=true

FILE="docs/critical-facts.md"
PROFILE_FILE=".claude/profiles/active-user.md"
PREFS_FILE="${HOME}/.savia/preferences.yaml"

# Defaults (fallbacks if sources missing)
LANG="español"
USER_SLUG="unknown"
ACTIVATED="unknown"
FRONTEND="opencode"
SPRINT="PM-Workspace activo · cadencia 2 sem · daily 09:15"

# Active user slug
if [[ -f "$PROFILE_FILE" ]]; then
  USER_SLUG=$(grep -E '^active_slug:' "$PROFILE_FILE" 2>/dev/null | head -1 | sed 's/.*"\([^"]*\)".*/\1/')
  ACTIVATED=$(grep -E '^activated_at:' "$PROFILE_FILE" 2>/dev/null | head -1 | sed 's/.*"\([^"]*\)".*/\1/')
fi

# Preferences
if [[ -f "$PREFS_FILE" ]]; then
  V=$(grep -E '^frontend:' "$PREFS_FILE" | awk '{print $2}'); [[ -n "$V" ]] && FRONTEND="$V"
fi

# Build new section content
read -r -d '' NEW_CONTENT <<EOF || true
- **Idioma activo**: $LANG (perfil \`$USER_SLUG\`)
- **Usuario activo**: $USER_SLUG · profile slug \`$USER_SLUG\` · activated $ACTIVATED
- **Frontend preferido**: $FRONTEND · modelos por tier heavy/mid/fast (\`model_tier\`), resueltos en local: \`~/.savia/preferences.yaml\` → \`tiers.<frontend>\` · default Claude Code opus/sonnet/haiku
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
echo "Regenerated $FILE from active profile + preferences"
