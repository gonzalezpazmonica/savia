#!/bin/bash
set -uo pipefail
_si_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
source "${_si_dir}/../../scripts/savia-env.sh"
export CLAUDE_PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$SAVIA_WORKSPACE_DIR}"
# session-init.sh — Arranque garantizado: sin red, sin jq, fallo = salida limpia

# ── Safety net: timeout global ────────────────────────────────────────────────
SCRIPT_START=$SECONDS
MAX_SECONDS=5

check_timeout() {
  if (( SECONDS - SCRIPT_START > MAX_SECONDS )); then
    printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"PM-Workspace Init (timeout):\\n- Savia lista (init parcial)"}}\n'
    exit 0
  fi
}

# ── Fallback: si algo falla, salida limpia ────────────────────────────────────
trap 'printf "{\"hookSpecificOutput\":{\"hookEventName\":\"SessionStart\",\"additionalContext\":\"PM-Workspace Init (ERR line %s):\\n- Savia lista\"}}\n" "$LINENO"; exit 1' ERR

# ── Model capability detection (Era 100) ────────────────────────────────────
for rpath in "$HOME/claude/scripts/model-capability-resolver.sh" "./scripts/model-capability-resolver.sh"; do
  if [ -f "$rpath" ]; then
    while IFS= read -r _l; do
      case "$_l" in export\ SAVIA_*) declare "${_l#export }" 2>/dev/null ;; esac
    done < <(echo '' | bash "$rpath" 2>/dev/null || true)
    break
  fi
done

# ── Context snapshot recovery (Era 100.2) ───────────────────────────────────
SNAPSHOT_PROJ=""
for spath in "$HOME/claude/scripts/context-snapshot.sh" "./scripts/context-snapshot.sh"; do
  if [ -x "$spath" ]; then
    SNAPSHOT_PROJ=$(echo '' | bash "$spath" load 2>/dev/null | grep -o '"project":"[^"]*"' | cut -d'"' -f4) || true
    break
  fi
done

# ── Arrays de contexto ────────────────────────────────────────────────────────
ITEMS=()

# ── SE-335: prioridad de descubrimiento de conocimiento ───────────────────────
# Directiva fija, sin I/O. Orden: cupulas -> memoria -> grafo de codigo -> grep.
ITEMS+=("Prioridad: cupulas (SaviaVaults) -> memoria -> grafo de codigo -> grep")

# ── Detectar modo agente ──────────────────────────────────────────────────────
AGENT_MODE="false"
if [ "${PM_CLIENT_TYPE:-}" = "agent" ] || [ "${AGENT_MODE:-}" = "true" ]; then
  AGENT_MODE="true"
fi

# ── PAT status (solo check fichero local, sin red) ───────────────────────────
check_timeout
PAT_FILE="$HOME/.azure/devops-pat"
if [ -f "$PAT_FILE" ] && [ -s "$PAT_FILE" ]; then
  ITEMS+=("PAT ok")
else
  ITEMS+=("PAT no configurado — \$HOME/.azure/devops-pat")
fi

# ── External memory bootstrap (SPEC-110) ─────────────────────────────────────
check_timeout
MEMORY_MODE=""
for mb_path in "$HOME/claude/scripts/savia-memory-bootstrap.sh" "./scripts/savia-memory-bootstrap.sh"; do
  if [ -f "$mb_path" ]; then
    MEMORY_OUT=$(bash "$mb_path" 2>/dev/null | tail -1)
    MEMORY_MODE=$(echo "$MEMORY_OUT" | grep -oE '"mode":"[^"]+"' | cut -d'"' -f4)
    break
  fi
done
case "$MEMORY_MODE" in
  canonical)     ITEMS+=("Memoria: ../.savia-memory (canónico)") ;;
  repo-local)    ITEMS+=("Memoria: repo/.savia-memory (fallback)") ;;
  home-fallback) ITEMS+=("Memoria: \$HOME/.savia-memory (fallback)") ;;
esac

# ── Perfil activo ────────────────────────────────────────────────────────────
check_timeout
# FIX: Try multiple possible profile locations (CI may use different $HOME)
ACTIVE_USER_FILE=""
for profile_base in "$HOME/claude/.claude/profiles" "$HOME/.claude/profiles" "./.claude/profiles"; do
  candidate="$profile_base/active-user.md"
  if [ -f "$candidate" ] 2>/dev/null; then
    ACTIVE_USER_FILE="$candidate"
    break
  fi
done

if [ -f "$ACTIVE_USER_FILE" ]; then
  # BSD grep (macOS) has no -P; single awk pass (faster than grep|sed|tr pipeline)
  ACTIVE_SLUG=$(awk '/^active_slug:/{gsub(/[",]/,""); sub(/^[^:]*:[[:space:]]*/,""); print; exit}' "$ACTIVE_USER_FILE" 2>/dev/null || echo "")
  PROFILE_DIR=$(dirname "$ACTIVE_USER_FILE")
  USERS_DIR="$PROFILE_DIR/users"

  if [ -n "$ACTIVE_SLUG" ] && [ -d "$USERS_DIR/$ACTIVE_SLUG" ]; then
    PROFILE_NAME=$(awk '/^name:/{gsub(/[",]/,""); sub(/^[^:]*:[[:space:]]*/,""); print; exit}' "$USERS_DIR/$ACTIVE_SLUG/identity.md" 2>/dev/null || echo "")
    [ -n "$PROFILE_NAME" ] || PROFILE_NAME="$ACTIVE_SLUG"
    PROFILE_ROLE=$(awk '/^role:/{gsub(/[",]/,""); sub(/^[^:]*:[[:space:]]*/,""); print; exit}' "$USERS_DIR/$ACTIVE_SLUG/identity.md" 2>/dev/null || echo "")
    PROFILE_LANG=$(awk '/^language:/{gsub(/[",]/,""); sub(/^[^:]*:[[:space:]]*/,""); print; exit}' "$USERS_DIR/$ACTIVE_SLUG/preferences.md" 2>/dev/null || echo "")
    if [ "$PROFILE_ROLE" = "Agent" ]; then
      AGENT_MODE="true"
      ITEMS+=("Perfil: $PROFILE_NAME (Agent)")
    else
      ITEMS+=("Perfil: $PROFILE_NAME")
    fi
    [ -n "$PROFILE_LANG" ] && ITEMS+=("Idioma: $PROFILE_LANG")

    # ── ND Profile detection (SPEC-061) ──────────────────────────────────────
    ND_FILE="$USERS_DIR/$ACTIVE_SLUG/neurodivergent.md"
    if [ -f "$ND_FILE" ] 2>/dev/null; then
      # Check if any dimension is active (not all commented out)
      if grep -qE '^\s*(adhd|autism|dyslexia|giftedness|dyscalculia):' "$ND_FILE" 2>/dev/null && \
         grep -qE 'present:\s*true' "$ND_FILE" 2>/dev/null; then
        if [ -n "${CLAUDE_ENV_FILE:-}" ]; then
          echo "export SAVIA_ND_ACTIVE=true" >> "$CLAUDE_ENV_FILE"
        fi
        # Run auto-config in background (ND→accessibility mapping)
        for nd_script in "$HOME/claude/scripts/nd-autoconfig.sh" "./scripts/nd-autoconfig.sh"; do
          if [ -f "$nd_script" ]; then
            bash "$nd_script" "$ND_FILE" "$USERS_DIR/$ACTIVE_SLUG/accessibility.md" >/dev/null 2>&1 &
            break
          fi
        done
      fi
    fi
  else
    ITEMS+=("Sin perfil — /profile-setup")
  fi
else
  ITEMS+=("Sin perfil — /profile-setup")
fi

# ── Rama git ──
check_timeout
BRANCH=""
for repo_path in "$HOME/claude" "$HOME/.claude" "." "$PWD"; do
  if [ -d "$repo_path/.git" ] 2>/dev/null; then
    BRANCH=$(git -C "$repo_path" branch --show-current 2>/dev/null || true)
    [ -n "$BRANCH" ] && break
  fi
done
BRANCH="${BRANCH:-N/A}"
ITEMS+=("Rama: $BRANCH")

# ── Nido detection (Savia Nidos — parallel terminal isolation) ──
check_timeout
SAVIA_NIDO=""
NIDOS_BASE=""
case "${OSTYPE:-}" in
  msys*|cygwin*) NIDOS_BASE="${USERPROFILE:-$HOME}/.savia/nidos" ;;
  *)             NIDOS_BASE="$HOME/.savia/nidos" ;;
esac
# Normalize to POSIX path for Git Bash comparison ($PWD is /c/Users/...)
NIDOS_CMP="$NIDOS_BASE"
if command -v cygpath >/dev/null 2>&1; then
  NIDOS_CMP=$(cygpath -u "$NIDOS_BASE" 2>/dev/null) || NIDOS_CMP="$NIDOS_BASE"
elif [[ "${OSTYPE:-}" == msys* || "${OSTYPE:-}" == cygwin* ]]; then
  NIDOS_CMP="${NIDOS_BASE//\\//}"
  if [[ "$NIDOS_CMP" =~ ^([A-Za-z]):/ ]]; then
    _drv=$(echo "${BASH_REMATCH[1]}" | tr '[:upper:]' '[:lower:]')
    NIDOS_CMP="/${_drv}${NIDOS_CMP:2}"
  fi
fi
if [[ "$PWD" == "$NIDOS_CMP"/* ]]; then
  SAVIA_NIDO="${PWD#"$NIDOS_CMP"/}"
  SAVIA_NIDO="${SAVIA_NIDO%%/*}"
  NIDO_BRANCH=$(git branch --show-current 2>/dev/null | tr -d '\r')
  ITEMS+=("Nido: $SAVIA_NIDO | Rama nido: ${NIDO_BRANCH:-N/A}")
  if [ -n "${CLAUDE_ENV_FILE:-}" ]; then
    echo "export SAVIA_NIDO=$SAVIA_NIDO" >> "$CLAUDE_ENV_FILE"
  fi
fi

# ── Recovered context from last session (Era 100.2) ──
if [ -n "$SNAPSHOT_PROJ" ] && [ "$SNAPSHOT_PROJ" != "none" ]; then
  ITEMS+=("Contexto recuperado: $SNAPSHOT_PROJ")
fi

# ── Company Savia inbox ──
check_timeout
COMPANY_CONFIG="$HOME/.pm-workspace/company-repo"
if [ -f "$COMPANY_CONFIG" ]; then
  CS_PATH=$(awk '/^LOCAL_PATH=/{sub(/^[^=]*=/,""); print; exit}' "$COMPANY_CONFIG" 2>/dev/null || echo "")
  CS_HANDLE=$(awk '/^USER_HANDLE=/{sub(/^[^=]*=/,""); print; exit}' "$COMPANY_CONFIG" 2>/dev/null || echo "")
  if [ -n "$CS_PATH" ] && [ -n "$CS_HANDLE" ] && [ -d "$CS_PATH" ]; then
    CS_PERSONAL=0; CS_ANNOUNCE=0
    [ -d "$CS_PATH/team/$CS_HANDLE/savia-inbox/unread" ] && \
      CS_PERSONAL=$(find "$CS_PATH/team/$CS_HANDLE/savia-inbox/unread" -name '*.md' 2>/dev/null | wc -l)
    CS_READ_LOG="$HOME/.pm-workspace/company-inbox-read.log"
    if [ -d "$CS_PATH/company-inbox" ]; then
      CS_TOTAL=$(find "$CS_PATH/company-inbox" -name '*.md' 2>/dev/null | wc -l)
      CS_READ=0; [ -f "$CS_READ_LOG" ] && CS_READ=$(wc -l < "$CS_READ_LOG")
      CS_ANNOUNCE=$((CS_TOTAL - CS_READ)); [ "$CS_ANNOUNCE" -lt 0 ] && CS_ANNOUNCE=0
    fi
    [ "$CS_PERSONAL" -gt 0 ] || [ "$CS_ANNOUNCE" -gt 0 ] && \
      ITEMS+=("📬 ${CS_PERSONAL} mensaje(s) · ${CS_ANNOUNCE} anuncio(s)")
  fi
fi

# ── Context tracking (best-effort, no bloquea) ──────────────────────────────
TRACKER_SCRIPT=""
for script_path in "$HOME/claude/scripts/context-tracker.sh" "$HOME/scripts/context-tracker.sh" "./scripts/context-tracker.sh"; do
  if [ -f "$script_path" ] 2>/dev/null; then
    TRACKER_SCRIPT="$script_path"
    break
  fi
done
if [ -n "$TRACKER_SCRIPT" ]; then
  bash "$TRACKER_SCRIPT" log "session-init" "identity.md" "50" >/dev/null 2>&1 &
fi

# ── Readiness check (ligero: solo verifica stamp) ─────────────────────────────
check_timeout
READINESS_STAMP="$HOME/.pm-workspace/.readiness-stamp"
if [ ! -f "$READINESS_STAMP" ] 2>/dev/null; then
  ITEMS+=("Readiness: no verificado — bash scripts/readiness-check.sh")
else
  STAMP_DATE=$(cat "$READINESS_STAMP" 2>/dev/null || echo "0")
  CURRENT_HASH=$(git -C "${HOME}/claude" rev-parse --short HEAD 2>/dev/null || echo "x")
  if [ "$STAMP_DATE" != "$CURRENT_HASH" ]; then
    ITEMS+=("Readiness: actualizado — bash scripts/readiness-check.sh")
  fi
fi

# ── Servicios locales: Ollama + Shield (Era 149, SPEC-071) ───────────────────
# Arranque blindado: ninguna espera de red en primer plano. El banner muestra el
# resultado del sondeo ANTERIOR (fichero de estado clave=valor, nunca se ejecuta
# con source) y este arranque lanza en segundo plano el sondeo siguiente y la
# pre-carga del modelo de Ollama. Un servicio colgado ya no retrasa la sesión.
check_timeout
PROBE_STATE="${SAVIA_PROBE_STATE:-$HOME/.savia/session-probes.state}"
OLLAMA_URL="${OLLAMA_URL:-http://127.0.0.1:11434}"
SHIELD_PORT="${SAVIA_SHIELD_PORT:-8444}"
SHIELD_PROXY_PORT="${SAVIA_SHIELD_PROXY_PORT:-8443}"
_pr_ts=""; _pr_ollama=""; _pr_daemon=""; _pr_proxy=""
if [ -f "$PROBE_STATE" ]; then
  while IFS='=' read -r _k _v; do
    case "$_k=$_v" in
      ts=[0-9]*)              [[ "$_v" =~ ^[0-9]+$ ]] && _pr_ts="$_v" ;;
      ollama=up|ollama=down)  _pr_ollama="$_v" ;;
      shield_daemon=up|shield_daemon=down) _pr_daemon="$_v" ;;
      shield_proxy=up|shield_proxy=down)   _pr_proxy="$_v" ;;
    esac
  done < "$PROBE_STATE"
fi
if [ -n "$_pr_ts" ]; then
  _pr_age=$(( $(date +%s) - _pr_ts )); [ "$_pr_age" -lt 0 ] && _pr_age=0
  if   [ "$_pr_age" -lt 120 ];  then _pr_when="${_pr_age}s"
  elif [ "$_pr_age" -lt 7200 ]; then _pr_when="$(( _pr_age / 60 ))min"
  else                               _pr_when="$(( _pr_age / 3600 ))h"; fi
  if [ "$_pr_age" -gt 86400 ]; then
    # Un sondeo de más de 24 h no prueba nada sobre el estado actual
    ITEMS+=("Servicios locales: último sondeo caducado (hace $_pr_when); nuevo sondeo en segundo plano")
  else
    [ "$_pr_ollama" = "up" ] && ITEMS+=("Ollama: activo (sondeo de hace $_pr_when; pre-carga en segundo plano)")
    [ "$_pr_daemon" = "up" ] && ITEMS+=("Shield: daemon activo (sondeo de hace $_pr_when)")
    [ "$_pr_proxy" = "up" ]  && ITEMS+=("Shield proxy: activo (localhost:$SHIELD_PROXY_PORT, sondeo de hace $_pr_when)")
  fi
else
  ITEMS+=("Servicios locales: sondeo en segundo plano (resultado en el próximo arranque)")
fi
if command -v curl >/dev/null 2>&1; then
  (
    trap '' HUP
    _o=down; _d=down; _p=down
    if curl -s --max-time 2 "$OLLAMA_URL/api/tags" >/dev/null 2>&1; then
      _o=up
      # Pre-carga del modelo para evitar ~9 s de arranque en frío al clasificar
      curl -s --max-time 3 "$OLLAMA_URL/api/generate" \
        -d '{"model":"qwen2.5:7b","prompt":"hi","stream":false,"options":{"num_predict":1}}' \
        >/dev/null 2>&1 &
    fi
    curl -sf --max-time 2 "http://127.0.0.1:$SHIELD_PORT/health" >/dev/null 2>&1 && _d=up
    curl -sf --max-time 2 "http://127.0.0.1:$SHIELD_PROXY_PORT/health" >/dev/null 2>&1 && _p=up
    mkdir -p "$(dirname "$PROBE_STATE")" 2>/dev/null
    _tmp="$PROBE_STATE.$BASHPID"
    printf 'ts=%s\nollama=%s\nshield_daemon=%s\nshield_proxy=%s\n' \
      "$(date +%s)" "$_o" "$_d" "$_p" > "$_tmp" && mv -f "$_tmp" "$PROBE_STATE"
  ) </dev/null >/dev/null 2>&1 &
fi

# ── Learning recall ready (SPEC-CONSOLIDACION R6) ────────────────────────────
# Ítem informativo: cuántas lecciones activas/human_authored hay disponibles
# para recall (sin inyectar snippets — presupuesto de contexto del banner).
check_timeout
if [ -x "${_si_dir}/../../scripts/learning-recall.sh" ]; then
  LP_ACTIVE=$(grep -rl "lifecycle: active" "${CLAUDE_PROJECT_DIR:-$SAVIA_WORKSPACE_DIR}/docs/learning-proposals/" 2>/dev/null | wc -l)
  if [ "${LP_ACTIVE:-0}" -gt 0 ]; then
    ITEMS+=("SCL: $LP_ACTIVE lección(es) active para recall")
  fi
fi

# ── Automations due-run (SPEC-CONSOLIDACION R2: loops saltan solos) ──────────
# Tras lanzar el sondeo de servicios locales, ejecuta las tareas programadas atrasadas
# (orquestador diario, morning brief, etc.) SIN bloquear el arranque.
# CRIT-001: las tareas usan LLM local (Ollama); si no hay, fallan abierto.
check_timeout
if [ -x "${_si_dir}/../../scripts/savia-automations.sh" ]; then
  timeout 4 bash "${_si_dir}/../../scripts/savia-automations.sh" run-due --max 2 \
    >/dev/null 2>&1 &
  ITEMS+=("Automations: due-run programado (loops autónomos)")
fi

# ── Variables de entorno ─────────────────────────────────────────────────────
if [ -n "${CLAUDE_ENV_FILE:-}" ]; then
  echo "export PM_WORKSPACE_ROOT=$HOME/claude" >> "$CLAUDE_ENV_FILE"
  echo "export PM_SESSION_DATE=$(date +%Y-%m-%d)" >> "$CLAUDE_ENV_FILE"
  if [ -x "$HOME/.savia/node/bin/node" ]; then
    echo "export PATH=$HOME/.savia/node/bin:$PATH" >> "$CLAUDE_ENV_FILE"
  fi
fi

# ── SE-230: focal status en banner ───────────────────────────────────────────
FOCAL_SUMMARY=$(timeout 0.5 bash "${_si_dir}/../../scripts/focal-status.sh" --summary 2>/dev/null || echo "Focal: timeout")
[ -n "$FOCAL_SUMMARY" ] && ITEMS+=("$FOCAL_SUMMARY")

# ── Generar output (bash puro, sin jq) ───────────────────────────────────────
CTX="PM-Workspace Init:"
for item in "${ITEMS[@]}"; do
  CTX="$CTX\\n- $item"
done

# Regenerar manifesto si está desactualizado (skills más nuevos que el manifesto)
MANIFEST=".claude/skill-manifests.json"
if [[ ! -f "$MANIFEST" ]] || find .claude/skills -name "SKILL.md" -newer "$MANIFEST" | grep -q .; then
  bash scripts/build-skill-manifest.sh >/dev/null 2>&1 &
fi

# Regenerar .scm (Savia Capability Map) si hay recursos nuevos/modificados.
# Determinístico: solo corre si algún fichero de commands/skills/agents/scripts
# es más reciente que el INDEX.scm. ENTERAMENTE en background — el find sobre
# 991 ficheros añade ~100ms al hook síncrono, así que el check + regen corren
# juntos en subshell para mantener el hook por debajo del umbral de latencia.
(
  SCM_INDEX=".scm/INDEX.scm"
  if [[ ! -f "$SCM_INDEX" ]] || \
     find .claude/commands .claude/skills .claude/agents scripts \
          \( -name "*.md" -o -name "*.sh" \) -newer "$SCM_INDEX" -print -quit 2>/dev/null | grep -q .; then
    python3 scripts/generate-capability-map.py >/dev/null 2>&1
  fi
) </dev/null >/dev/null 2>&1 &
disown 2>/dev/null || true

# Limpieza de auto-memory en background (SPEC-142, SE-073).
# El path canónico es scripts/memory-hygiene.sh dentro del workspace.
# La cadena de fallback resuelve workspace → cwd → home; primer hit gana.
SI_HYGIENE_PATHS=(
  "${SAVIA_WORKSPACE_DIR:-${CLAUDE_PROJECT_DIR:-}}/scripts/memory-hygiene.sh"
  "$(pwd)/scripts/memory-hygiene.sh"
  "$HOME/savia/scripts/memory-hygiene.sh"
)
for mh_path in "${SI_HYGIENE_PATHS[@]}"; do
  [[ -z "$mh_path" || "$mh_path" == "/scripts/memory-hygiene.sh" ]] && continue
  if [ -f "$mh_path" ]; then
    bash "$mh_path" >/dev/null 2>&1 &
    break
  fi
done

# Memory canary check (SE-073, defensa anti memory-poisoning).
# Solo verifica integridad — no modifica. Background, non-blocking.
SI_CANARY_PATHS=(
  "${SAVIA_WORKSPACE_DIR:-${CLAUDE_PROJECT_DIR:-}}/scripts/memory-canary-check.sh"
  "$(pwd)/scripts/memory-canary-check.sh"
)
for cc_path in "${SI_CANARY_PATHS[@]}"; do
  [[ -z "$cc_path" || "$cc_path" == "/scripts/memory-canary-check.sh" ]] && continue
  if [ -f "$cc_path" ]; then
    bash "$cc_path" >> "${SAVIA_WORKSPACE_DIR:-${CLAUDE_PROJECT_DIR:-/tmp}}/output/memory-canary.log" 2>&1 &
    break
  fi
done

# Memory vector index auto-rebuild (SE-143) — background, non-blocking
for ms_path in "$HOME/claude/scripts/memory-store.sh" "./scripts/memory-store.sh"; do
  if [ -f "$ms_path" ]; then
    (
      # Only rebuild if Level=2 (deps installed) and index is stale
      memory_python="${SAVIA_MEMORY_PYTHON:-$HOME/.savia/venv/bin/python}"
      [[ -x "$memory_python" ]] || memory_python="$HOME/.savia/venv/Scripts/python.exe"
      [[ -x "$memory_python" ]] || exit 0
      "$memory_python" -c "import sentence_transformers; import faiss" 2>/dev/null || exit 0
      SAVIA_MEMORY_PYTHON="$memory_python" bash "$ms_path" rebuild-index >/dev/null 2>&1 || true
    ) </dev/null >/dev/null 2>&1 &
    break
  fi
done

# Context rotation check (SE-033) — async, non-blocking
for cr_path in "$HOME/claude/scripts/context-rotation.sh" "./scripts/context-rotation.sh"; do
  if [ -f "$cr_path" ]; then
    bash "$cr_path" daily >/dev/null 2>&1 &
    DOW=$(date +%u)
    [[ "$DOW" == "1" ]] && bash "$cr_path" weekly >/dev/null 2>&1 &
    DOM=$(date +%d)
    [[ "$DOM" == "01" ]] && bash "$cr_path" monthly >/dev/null 2>&1 &
    break
  fi
done

# Ensure git merge drivers from .gitattributes are wired in local git config.
# Idempotent and silent. Without this, merge=ours in .gitattributes is a no-op.
# Gracefully handles unset CLAUDE_PROJECT_DIR (e.g. when hook is tested in isolation).
_setup_md_dir="${CLAUDE_PROJECT_DIR:-${PWD:-.}}"
if [[ -x "$_setup_md_dir/scripts/setup-merge-drivers.sh" ]]; then
  bash "$_setup_md_dir/scripts/setup-merge-drivers.sh" >/dev/null 2>&1 || true
fi

# ── SE-229: Session Registry integration ─────────────────────────────────────
REGISTRY_SCRIPT=""
for reg_path in "${_si_dir}/../../scripts/session-registry.sh" \
                "${SAVIA_WORKSPACE_DIR:-${CLAUDE_PROJECT_DIR:-}}/scripts/session-registry.sh" \
                "./scripts/session-registry.sh"; do
  [[ -z "$reg_path" || "$reg_path" == "/scripts/session-registry.sh" ]] && continue
  if [[ -x "$reg_path" ]]; then
    REGISTRY_SCRIPT="$reg_path"
    break
  fi
done

# Fallback already covered above via _si_dir
if [[ -z "$REGISTRY_SCRIPT" ]]; then
  _candidate="${_si_dir}/../../scripts/session-registry.sh"
  [[ -x "$_candidate" ]] && REGISTRY_SCRIPT="$_candidate"
fi

if [[ -n "$REGISTRY_SCRIPT" ]]; then
  # List active sessions (timeout 2s to avoid adding latency)
  ACTIVE_SESSIONS=$(timeout 2s bash "$REGISTRY_SCRIPT" list 2>/dev/null || true)
  if [[ -n "$ACTIVE_SESSIONS" ]] && ! grep -q "No active sessions" <<< "$ACTIVE_SESSIONS" 2>/dev/null; then
    ITEMS+=("Sesiones activas:\\n${ACTIVE_SESSIONS}")
  fi

  # Register current session if inside a nido
  if [[ -n "${SAVIA_NIDO:-}" ]]; then
    _SESSION_ID="${CLAUDE_SESSION_ID:-${PPID}-$(date +%s)}"
    _REG_BRANCH="${BRANCH:-N/A}"
    _REG_TASK="${SAVIA_TASK:-nido session}"
    _REG_WORKTREE="${PWD:-}"
    timeout 2s bash "$REGISTRY_SCRIPT" register \
      --session "$_SESSION_ID" \
      --nido    "$SAVIA_NIDO" \
      --branch  "$_REG_BRANCH" \
      --task    "$_REG_TASK" \
      --worktree "$_REG_WORKTREE" \
      >/dev/null 2>&1 || true
    if [[ -n "${CLAUDE_ENV_FILE:-}" ]]; then
      echo "export SAVIA_SESSION_ID=${_SESSION_ID}" >> "$CLAUDE_ENV_FILE"
    fi
  fi
fi

# SE-313 S2: emitir session.started con trace_id raíz (mejor esfuerzo, no bloquea).
if [[ -x "${_si_dir}/../../scripts/otel-emit.sh" ]]; then
  _SE313_MODEL="$(savia_resolve_model mid 2>/dev/null || echo "mid")"
  bash "${_si_dir}/../../scripts/otel-emit.sh" session.started \
    kind=hook status=ok gen_ai_request_model="$_SE313_MODEL" \
    branch="${BRANCH:-N/A}" retention_days=180 >/dev/null 2>&1 || true
fi

printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"%s"}}\n' "$CTX"
