#!/usr/bin/env bash
set -uo pipefail
# setup-opencode-permissions.sh — Genera settings.local.json con permisos recomendados
#
# Uso:
#   bash scripts/setup-opencode-permissions.sh          # genera si no existe
#   bash scripts/setup-opencode-permissions.sh --force   # regenera (backup previo)
#   bash scripts/setup-opencode-permissions.sh --check   # solo valida
#
# Salida: .claude/settings.local.json
#
# Este fichero es local (está en .gitignore) y contiene:
#   - Patrones glob de permisos para herramientas comunes
#   - Variables de entorno de Android SDK (auto-detectadas)
#   - Deny list de operaciones destructivas
#
# NOTA sobre sintaxis de permisos de Claude Code:
#   - "Bash(cmd *)" → matchea comandos que empiezan por "cmd " (espacio)
#   - "Bash(cmd*)"  → matchea "cmd" + cualquier cosa (sin espacio, ej: cmd_foo)
#   - "Bash(cmd && *)" → matchea "cmd && " seguido de cualquier cosa
#   - Claude Code es shell-aware: "Bash(cmd *)" NO permite "cmd && evil"
#   - Para comandos compuestos con && hay que hacer patrones explícitos
#   - La sintaxis legacy ":*" está deprecada, usar " *" (espacio)
#
# Cada usuario puede añadir excepciones propias sobre esta base.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TARGET="$ROOT/.claude/settings.local.json"

# Colors
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()  { echo -e "  🔍 $*"; }
ok()    { echo -e "  ${GREEN}✅${NC} $*"; }
warn()  { echo -e "  ${YELLOW}⚠️${NC}  $*"; }
fail()  { echo -e "  ${RED}❌${NC} $*"; }

# --- Auto-detect Android SDK ---------------------------------------------------
detect_android() {
  local sdk=""
  local java=""
  local adb=""

  # Android SDK
  if [[ -n "${ANDROID_HOME:-}" && -d "$ANDROID_HOME" ]]; then
    sdk="$ANDROID_HOME"
  elif [[ -d "$HOME/Android/Sdk" ]]; then
    sdk="$HOME/Android/Sdk"
  elif [[ -d "$HOME/Library/Android/sdk" ]]; then
    sdk="$HOME/Library/Android/sdk"
  fi

  # JAVA_HOME
  if [[ -n "${JAVA_HOME:-}" && -d "$JAVA_HOME" ]]; then
    java="$JAVA_HOME"
  elif [[ -d "/snap/android-studio/current/jbr" ]]; then
    java="/snap/android-studio/current/jbr"
  elif command -v java &>/dev/null; then
    local java_bin
    java_bin="$(readlink -f "$(which java)" 2>/dev/null || true)"
    if [[ -n "$java_bin" ]]; then
      java="$(dirname "$(dirname "$java_bin")")"
    fi
  fi

  # ADB
  if [[ -n "$sdk" && -x "$sdk/platform-tools/adb" ]]; then
    adb="$sdk/platform-tools/adb"
  elif command -v adb &>/dev/null; then
    adb="$(which adb)"
  fi

  echo "$sdk|$java|$adb"
}

# --- Check mode ----------------------------------------------------------------
if [[ "${1:-}" == "--check" ]]; then
  if [[ -f "$TARGET" ]]; then
    if python3 -m json.tool "$TARGET" > /dev/null 2>&1; then
      ok "settings.local.json exists and is valid JSON"
      perms=$(python3 -c "import json; d=json.load(open('$TARGET')); print(len(d.get('permissions',{}).get('allow',[])))" 2>/dev/null || echo "0")
      echo "     Permissions allow: $perms patterns"
      denys=$(python3 -c "import json; d=json.load(open('$TARGET')); print(len(d.get('permissions',{}).get('deny',[])))" 2>/dev/null || echo "0")
      echo "     Permissions deny: $denys patterns"
      exit 0
    else
      fail "settings.local.json exists but is NOT valid JSON"
      exit 1
    fi
  else
    warn "settings.local.json does not exist"
    echo "     Run: bash scripts/setup-opencode-permissions.sh"
    exit 1
  fi
fi

# --- Force mode: backup existing ------------------------------------------------
if [[ "${1:-}" == "--force" && -f "$TARGET" ]]; then
  BACKUP="$TARGET.backup.$(date +%Y%m%d-%H%M%S)"
  cp "$TARGET" "$BACKUP"
  warn "Existing settings backed up to $(basename "$BACKUP")"
elif [[ -z "${1:-}" && -f "$TARGET" ]]; then
  ok "settings.local.json already exists — use --force to regenerate"
  exit 0
fi

# --- Detect environment ---------------------------------------------------------
IFS='|' read -r ANDROID_SDK JAVA_DIR ADB_BIN <<< "$(detect_android)"

info "Detected Android SDK: ${ANDROID_SDK:-not found}"
info "Detected JAVA_HOME:   ${JAVA_DIR:-not found}"
info "Detected ADB:         ${ADB_BIN:-not found}"

# --- Build env block ------------------------------------------------------------
ENV_ENTRIES=""
[[ -n "$ANDROID_SDK" ]] && ENV_ENTRIES+="    \"ANDROID_HOME\": \"$ANDROID_SDK\","$'\n'
[[ -n "$JAVA_DIR" ]]    && ENV_ENTRIES+="    \"JAVA_HOME\": \"$JAVA_DIR\","$'\n'
[[ -n "$ADB_BIN" ]]     && ENV_ENTRIES+="    \"ADB_PATH\": \"$ADB_BIN\","$'\n'

# Build ADB permission patterns (modern syntax: space instead of legacy :)
ADB_PERMS=""
if [[ -n "$ADB_BIN" ]]; then
  ADB_PERMS+="      \"Bash(adb *)\","$'\n'
  ADB_PERMS+="      \"Bash(adb_*)\","$'\n'
  ADB_PERMS+="      \"Bash($ADB_BIN *)\","$'\n'
  # adb-run.sh: single-command wrapper that avoids && chains
  # Claude Code is shell-aware: * doesn't cross && || ; operators.
  # adb-run.sh wraps source + functions into one simple command.
  ADB_PERMS+="      \"Bash(./scripts/adb-run.sh *)\","$'\n'
  ADB_PERMS+="      \"Bash(bash scripts/adb-run.sh *)\","$'\n'
fi
if [[ -n "$ANDROID_SDK" ]]; then
  ADB_PERMS+="      \"Read(//$ANDROID_SDK/**)\","$'\n'
fi
if [[ -n "$JAVA_DIR" ]]; then
  ADB_PERMS+="      \"Read(//$JAVA_DIR/**)\","$'\n'
fi

# --- Generate settings.local.json -----------------------------------------------
mkdir -p "$(dirname "$TARGET")"

cat > "$TARGET" << ENDJSON
{
  "env": {
${ENV_ENTRIES}    "AZURE_DEVOPS_EXT_PAT": "\$(cat \$HOME/.azure/devops-pat 2>/dev/null || echo 'PAT_NOT_CONFIGURED')"
  },
  "permissions": {
    "allow": [
      "Bash(az devops *)",
      "Bash(az boards *)",
      "Bash(az repos *)",
      "Bash(az pipelines *)",
      "Bash(az account *)",

      "Bash(ls *)",
      "Bash(cat *)",
      "Bash(find *)",
      "Bash(grep *)",
      "Bash(echo *)",
      "Bash(head *)",
      "Bash(tail *)",
      "Bash(wc *)",
      "Bash(sort *)",
      "Bash(uniq *)",
      "Bash(diff *)",
      "Bash(mkdir *)",
      "Bash(cp *)",
      "Bash(mv *)",
      "Bash(touch *)",
      "Bash(date *)",
      "Bash(sleep *)",
      "Bash(test *)",
      "Bash(stat *)",
      "Bash(file *)",
      "Bash(realpath *)",
      "Bash(dirname *)",
      "Bash(basename *)",
      "Bash(xargs *)",
      "Bash(tee *)",
      "Bash(tr *)",
      "Bash(cut *)",
      "Bash(sed *)",
      "Bash(awk *)",
      "Bash(env *)",
      "Bash(which *)",
      "Bash(type *)",
      "Bash(ps *)",
      "Bash(pgrep *)",
      "Bash(ss *)",
      "Bash(lsof *)",

      "Bash(node *)",
      "Bash(npm *)",
      "Bash(npx *)",
      "Bash(python3 *)",
      "Bash(python *)",
      "Bash(pip *)",
      "Bash(pip3 *)",
      "Bash(jq *)",
      "Bash(curl *)",
      "Bash(bash *)",
      "Bash(sh *)",
      "Bash(claude *)",
      "Bash(timeout *)",

      "Bash(git *)",
      "Bash(gh *)",

${ADB_PERMS}
      "Bash(export PATH=*)",
      "Bash(export ANDROID_HOME=*)",
      "Bash(export JAVA_HOME=*)",
      "Bash(ANDROID_HOME=*)",
      "Bash(JAVA_HOME=*)",
      "Bash(CLAUDECODE=*)",

      "Bash(cd *)",
      "Bash(cd * && *)",
      "Bash(cd * || *)",
      "Bash(source * && *)",
      "Bash(. * && *)",
      "Bash(ip *)",
      "Bash(ifconfig *)",
      "Bash(hostname *)",
      "Bash(./gradlew *)",
      "Bash(./scripts/*)",

      "Bash(kill *)",
      "Bash(pkill *)",

      "WebSearch",
      "WebFetch(domain:support.claude.com)"
    ],
    "deny": [
      "Bash(rm -rf /*)",
      "Bash(chmod 777 *)",
      "Bash(sudo rm *)",
      "Bash(dd if=*)",
      "Bash(mkfs *)"
    ]
  }
}
ENDJSON

# Validate JSON
if python3 -m json.tool "$TARGET" > /dev/null 2>&1; then
  ok "Generated settings.local.json"
  perms=$(python3 -c "import json; d=json.load(open('$TARGET')); print(len(d.get('permissions',{}).get('allow',[])))" 2>/dev/null || echo "?")
  echo "     → $perms allow patterns, auto-detected environment"
  echo "     → File: .claude/settings.local.json (gitignored)"
  echo "     → Add your own patterns as needed"
else
  fail "Generated file has invalid JSON — check the output manually"
  exit 1
fi
