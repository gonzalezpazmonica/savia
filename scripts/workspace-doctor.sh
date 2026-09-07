#!/usr/bin/env bash
# workspace-doctor.sh — Health check pm-workspace (SPEC-031)
# Uso: bash scripts/workspace-doctor.sh [--quick]
# Exit: 0=OK, 1=warnings, 2=fails
set -uo pipefail

QUICK=false
[ "${1:-}" = "--quick" ] && QUICK=true
if [ "${1:-}" = "--codex-autonomy" ]; then
  exec python3 "$(dirname "$0")/dual-cli/autonomy_doctor.py"
fi

OK=0; WARN=0; FAIL=0; RESULTS=()
ok()   { ((OK++));   RESULTS+=("OK   | $1 | $2"); }
warn() { ((WARN++)); RESULTS+=("WARN | $1 | $2"); }
fail() { ((FAIL++)); RESULTS+=("FAIL | $1 | $2"); }

# ── CRITICOS (1-5) ──────────────────────────────────────────────────────────

# 1. Git repo
if git rev-parse --is-inside-work-tree &>/dev/null; then
  ok "git_repo" "Repositorio git detectado"
else
  fail "git_repo" "No es un repositorio git — ejecuta: git init"
fi

# 2. Rama != main — SE-388 F: resultado según intención/riesgo.
#    read-only sobre main => WARN; mutación sobre main => FAIL (protección intacta).
INTENT="${SAVIA_INTENT:-mutating}"
BRANCH=$(git branch --show-current 2>/dev/null || echo "unknown")
if [[ "$BRANCH" == "main" || "$BRANCH" == "master" ]]; then
  if [[ "$INTENT" == "read-only" ]]; then
    warn "branch_main_readonly" "Rama $BRANCH con intención read-only — permitido con aviso (SE-388 F)"
  else
    fail "branch_not_main" "Rama actual: $BRANCH — operación con mutación exige rama/worktree (git checkout -b feat/...)"
  fi
else
  ok "branch_not_main" "Rama: $BRANCH"
fi

# 3. settings.json valido
if python3 -c "import json; json.load(open('.claude/settings.json'))" &>/dev/null; then
  ok "settings_json" ".claude/settings.json es JSON valido"
else
  fail "settings_json" ".claude/settings.json no parseable — regenerar"
fi

# 4. CLAUDE.md existe
if [[ -f "CLAUDE.md" ]]; then
  ok "claude_md_exists" "CLAUDE.md presente"
else
  fail "claude_md_exists" "CLAUDE.md no encontrado"
fi

# 5. CLAUDE.md <= 150 lineas
if [[ -f "CLAUDE.md" ]]; then
  LINES=$(wc -l < CLAUDE.md)
  if (( LINES <= 150 )); then
    ok "claude_md_size" "CLAUDE.md: $LINES lineas (limite: 150)"
  else
    warn "claude_md_size" "CLAUDE.md: $LINES lineas — refactorizar con @imports"
  fi
fi

# ── IMPORTANTES (6-10) — solo si no es --quick ──────────────────────────────

if ! $QUICK; then

  # 6. PAT Azure DevOps
  if [[ -f "$HOME/.azure/devops-pat" ]]; then
    ok "azure_pat" "PAT Azure DevOps presente"
  else
    warn "azure_pat" "PAT no encontrado — crear en dev.azure.com > User Settings > PATs"
  fi

  # 7. CLI gh
  if command -v gh &>/dev/null; then
    ok "cli_gh" "gh instalado"
  else
    warn "cli_gh" "gh no instalado — sudo apt install gh"
  fi

  # 8. CLI jq
  if command -v jq &>/dev/null; then
    ok "cli_jq" "jq instalado"
  else
    warn "cli_jq" "jq no instalado — sudo apt install jq"
  fi

  # 9. Perfil activo
  ACTIVE_MD=".claude/profiles/active-user.md"
  if [[ -f "$ACTIVE_MD" ]] && grep -q 'active_slug:' "$ACTIVE_MD" 2>/dev/null; then
    SLUG=$(grep 'active_slug:' "$ACTIVE_MD" | awk '{print $2}' | tr -d '"')
    ok "active_profile" "Perfil activo: $SLUG"
  else
    warn "active_profile" "Sin perfil activo — ejecuta: /profile-setup"
  fi

  # 10. Hooks registrados
  if python3 -c "import json; d=json.load(open('.claude/settings.json')); assert 'hooks' in d" &>/dev/null; then
    ok "hooks_registered" "Hooks declarados en settings.json"
  else
    warn "hooks_registered" "Sin hooks en settings.json"
  fi

fi

# ── RECOMENDADOS (11-14) — solo si no es --quick ────────────────────────────

if ! $QUICK; then

  # 11. Scripts ejecutables
  NON_EXEC=$(find scripts/ -name '*.sh' ! -executable 2>/dev/null | wc -l)
  if (( NON_EXEC == 0 )); then
    ok "scripts_executable" "Todos los scripts .sh son ejecutables"
  else
    warn "scripts_executable" "$NON_EXEC scripts sin permiso — chmod +x scripts/*.sh"
  fi

  # 12. tests/run-all.sh existe
  if [[ -f "tests/run-all.sh" ]]; then
    ok "bats_available" "tests/run-all.sh presente"
  else
    warn "bats_available" "tests/run-all.sh no encontrado"
  fi

  # 13. CHANGELOG sin conflictos
  if [[ -f "CHANGELOG.md" ]]; then
    CONFLICTS=$(grep -cE '^(<<<<<<<|=======|>>>>>>>)' CHANGELOG.md 2>/dev/null || true)
    CONFLICTS=${CONFLICTS:-0}
    if (( CONFLICTS == 0 )); then
      ok "changelog_clean" "CHANGELOG.md sin marcadores de conflicto"
    else
      fail "changelog_clean" "CHANGELOG.md tiene $CONFLICTS conflictos — resolver"
    fi
  fi

  # 14. Backup reciente (< 7 dias)
  BACKUP_DIR="$HOME/.pm-workspace/backups"
  if [[ -d "$BACKUP_DIR" ]]; then
    RECENT=$(find "$BACKUP_DIR" -name '*.enc' -mtime -7 2>/dev/null | wc -l)
    if (( RECENT > 0 )); then
      ok "backup_recent" "Backup reciente encontrado"
    else
      warn "backup_recent" "Sin backup en 7 dias — /backup now"
    fi
  else
    warn "backup_recent" "Sin directorio de backups — /backup now"
  fi

fi

# ── RESUMEN ──────────────────────────────────────────────────────────────────

echo ""; for r in "${RESULTS[@]}"; do echo "$r"; done; echo ""
echo "RESUMEN: $OK/$(( OK + WARN + FAIL )) OK | $WARN warnings | $FAIL fails"
if (( FAIL > 0 )); then exit 2; fi
if (( WARN > 0 )); then exit 1; fi
exit 0
