#!/usr/bin/env bash
# savia-env.sh — Provider-agnostic environment layer (SPEC-127 Slice 1)
#
# Single source of truth for workspace path and provider detection.
# Hooks, scripts and skills MUST source this instead of hard-coding
# CLAUDE_PROJECT_DIR or assuming a specific provider.
#
# Usage:
#   source scripts/savia-env.sh          # export SAVIA_WORKSPACE_DIR + SAVIA_PROVIDER
#   bash scripts/savia-env.sh workspace  # one-shot: print SAVIA_WORKSPACE_DIR
#   bash scripts/savia-env.sh provider   # one-shot: print SAVIA_PROVIDER
set -uo pipefail

# ── Capability probes ────────────────────────────────────────────────────────
savia_has_hooks() {
  case "${SAVIA_PROVIDER:-}" in
    copilot)  return 1 ;;  # OpenCode-Copilot Enterprise: zero hook surface
    localai)  return 0 ;;  # LocalAI runs under Claude Code / OpenCode shell
    claude)   return 0 ;;  # Full PreToolUse/PostToolUse/Stop surface
    unknown)  return 0 ;;  # Permissive: let downstream gates catch gaps
    *)        return 0 ;;  # OpenCode-Claude: ~25 events via plugin TS
  esac
}

savia_has_slash_commands() {
  case "${SAVIA_PROVIDER:-}" in
    copilot)  return 1 ;;  # Zero slash mechanism
    claude)   return 0 ;;  # Native slash commands
    localai)  return 0 ;;  # AI coding assistant shell
    unknown)  return 0 ;;  # Permissive
    *)        return 0 ;;  # OpenCode-Claude: .opencode/commands/
  esac
}

# ── Resolve workspace dir (fallback chain) ───────────────────────────────────
_resolve_workspace() {
  # 1. Explicit override (any provider)
  if [[ -n "${SAVIA_WORKSPACE_DIR:-}" ]]; then
    echo "$SAVIA_WORKSPACE_DIR"
    return
  fi

  # 2. Claude Code native
  if [[ -n "${CLAUDE_PROJECT_DIR:-}" ]]; then
    echo "$CLAUDE_PROJECT_DIR"
    return
  fi

  # 3. OpenCode v1.14+
  if [[ -n "${OPENCODE_PROJECT_DIR:-}" ]]; then
    echo "$OPENCODE_PROJECT_DIR"
    return
  fi

  # 4. git root
  local git_root
  git_root=$(git rev-parse --show-toplevel 2>/dev/null) || true
  if [[ -n "${git_root:-}" ]]; then
    echo "$git_root"
    return
  fi

  # 5. Last resort
  pwd
}

# ── Resolve project slug ─────────────────────────────────────────────────────
# Fallback chain:
#   1) $SAVIA_PROJECT_SLUG (explicit operator override)
#   2) git branch matches projects/<slug> or project/<slug>
#   3) $SAVIA_WORKSPACE_DIR/projects/ contains exactly one subdir
#   4) Empty string (workspace without active project is valid)
_resolve_project_slug() {
  # 1. Explicit override
  if [[ -n "${SAVIA_PROJECT_SLUG:-}" ]]; then
    echo "$SAVIA_PROJECT_SLUG"
    return
  fi

  # 2. Branch prefix
  local branch
  branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null) || true
  if [[ -n "${branch:-}" ]]; then
    case "$branch" in
      projects/*) echo "${branch#projects/}"; return ;;
      project/*)  echo "${branch#project/}";  return ;;
    esac
  fi

  # 3. Single subdir in projects/
  local ws
  ws=$(_resolve_workspace)
  if [[ -d "$ws/projects" ]]; then
    local subdirs=()
    local entry
    for entry in "$ws/projects"/*/; do
      [[ -d "$entry" ]] || continue
      subdirs+=("$(basename "$entry")")
    done
    if [[ ${#subdirs[@]} -eq 1 ]]; then
      echo "${subdirs[0]}"
      return
    fi
  fi

  # 4. Empty (not an error)
  echo ""
}

# ── Detect provider (precedence chain) ───────────────────────────────────────
_resolve_provider() {
  # 1. Operator override
  if [[ -n "${SAVIA_PROVIDER:-}" ]]; then
    echo "$SAVIA_PROVIDER"
    return
  fi

  # 2. ANTHROPIC_BASE_URL points to localhost/localai
  local base_url="${ANTHROPIC_BASE_URL:-}"
  if [[ -n "$base_url" ]] && [[ "$base_url" == *"localhost"* || "$base_url" == *"127.0.0.1"* || "$base_url" == *"localai"* ]]; then
    echo "localai"
    return
  fi

  # 3. Copilot tokens present
  if [[ -n "${COPILOT_TOKEN:-}" || -n "${GITHUB_COPILOT_TOKEN:-}" ]]; then
    echo "copilot"
    return
  fi

  # 4. OpenCode provider env
  if [[ -n "${OPENCODE_PROVIDER:-}" ]]; then
    echo "$OPENCODE_PROVIDER"
    return
  fi

  # 5. Claude Code native
  if [[ -n "${CLAUDE_PROJECT_DIR:-}" ]]; then
    echo "claude"
    return
  fi

  # 6. Unknown
  echo "unknown"
}

# ── Tier-based model resolution (SPEC-127 Slice 1) ────────────────────────────
# Resolves a capability tier (heavy/mid/fast) or legacy short name
# (opus/sonnet/haiku) to the user's provider-specific model ID
# declared in ~/.savia/preferences.yaml.
#
# Falls through to preferences.yaml on first call; caches result in
# SAVIA_MODEL_{HEAVY,MID,FAST} env vars for subsequent calls (no
# repeated YAML parsing).
savia_resolve_model() {
  local tier="$1"
  local prefs_file="${HOME}/.savia/preferences.yaml"

  _read_pref() {
    local key="$1"
    awk -v k="^${key}:" '
      $0 ~ k { sub(k, ""); sub(/^[[:space:]]+/, ""); gsub(/^"|"$/, ""); gsub(/^\047|\047$/, ""); print; exit }
    ' "$prefs_file" 2>/dev/null
  }

  # SE-313: provider prefix is mandatory (see section 0 of SE-313 spec).
  # Defensa ante IDs sin prefijo en preferences: si el ID no lleva provider/,
  # se prefija solo cuando el ID corto pertenece al provider configurado
  # (ej. `deepseek-v4-pro` → `deepseek/deepseek-v4-pro`). IDs canónicos de
  # otros vendors (claude-*, gpt-*, ...) se preservan intactos.
  _prefixed() {
    local id="$1"
    [[ -z "$id" ]] && { echo ""; return; }
    if [[ "$id" == */* ]]; then
      echo "$id"
    else
      local provider
      provider="$(_read_pref "provider")"
      [[ -z "$provider" ]] && provider="deepseek"
      if [[ "$id" == "$provider-"* ]]; then
        echo "${provider}/${id}"
      else
        echo "$id"
      fi
    fi
  }

  case "$tier" in
    heavy)
      if [[ -z "${SAVIA_MODEL_HEAVY:-}" && -f "$prefs_file" ]]; then
        export SAVIA_MODEL_HEAVY="$(_read_pref "model_heavy")"
      fi
      [[ -n "${SAVIA_MODEL_HEAVY:-}" ]] && _prefixed "${SAVIA_MODEL_HEAVY}" || echo "heavy"
      ;;
    mid)
      if [[ -z "${SAVIA_MODEL_MID:-}" && -f "$prefs_file" ]]; then
        export SAVIA_MODEL_MID="$(_read_pref "model_mid")"
      fi
      [[ -n "${SAVIA_MODEL_MID:-}" ]] && _prefixed "${SAVIA_MODEL_MID}" || echo "mid"
      ;;
    fast)
      if [[ -z "${SAVIA_MODEL_FAST:-}" && -f "$prefs_file" ]]; then
        export SAVIA_MODEL_FAST="$(_read_pref "model_fast")"
      fi
      [[ -n "${SAVIA_MODEL_FAST:-}" ]] && _prefixed "${SAVIA_MODEL_FAST}" || echo "fast"
      ;;
    opus|claude-opus-4-7|claude-opus-4-5)
      savia_resolve_model heavy
      ;;
    sonnet|claude-sonnet-4-6|claude-sonnet-4-5)
      savia_resolve_model mid
      ;;
    haiku|claude-haiku-4-5-20251001)
      savia_resolve_model fast
      ;;
    *)
      _prefixed "$tier"  # pass-through for non-tier, non-legacy names
      ;;
  esac
}
export -f savia_resolve_model

# ── Main (source mode) ───────────────────────────────────────────────────────
# --------------------------------------------------------------------------
# AUTONOMOUS_REVIEWER resolver (autonomous-safety.md)
#
# Fallback chain:
#   1) $SAVIA_AUTONOMOUS_REVIEWER  (explicit env override)
#   2) .claude/rules/pm-config.local.md  AUTONOMOUS_REVIEWER = "..."
#   3) ~/.savia/preferences.yaml         autonomous_reviewer: ...
#   4) git config user.email             (zero-config common case)
#   5) "@local-user"                     (generic fallback, never blocks)
# --------------------------------------------------------------------------
savia_autonomous_reviewer() {
  if [[ -n "${SAVIA_AUTONOMOUS_REVIEWER:-}" ]]; then
    printf '%s\n' "$SAVIA_AUTONOMOUS_REVIEWER"
    return 0
  fi

  local ws; ws="$(_resolve_workspace)"
  local local_cfg="$ws/.claude/rules/pm-config.local.md"
  if [[ -r "$local_cfg" ]]; then
    local v
    v="$(grep -E '^\s*AUTONOMOUS_REVIEWER\s*=' "$local_cfg" 2>/dev/null \
         | head -n1 \
         | sed -E 's/^[^=]*=\s*"?([^"]*)"?\s*$/\1/' \
         | tr -d '[:space:]')"
    if [[ -n "$v" && "$v" != "@local-user" ]]; then
      printf '%s\n' "$v"
      return 0
    fi
  fi

  local prefs="$HOME/.savia/preferences.yaml"
  if [[ -r "$prefs" ]]; then
    local v
    v="$(grep -E '^\s*autonomous_reviewer\s*:' "$prefs" 2>/dev/null \
         | head -n1 \
         | sed -E 's/^[^:]*:\s*"?([^"]*)"?\s*$/\1/' \
         | tr -d '[:space:]')"
    if [[ -n "$v" ]]; then
      printf '%s\n' "$v"
      return 0
    fi
  fi

  if command -v git >/dev/null 2>&1; then
    local email
    email="$(git -C "$ws" config user.email 2>/dev/null)"
    if [[ -n "$email" ]]; then
      # Convert "user.name@example.com" -> "@user-name"
      printf '@%s\n' "${email%@*}"
      return 0
    fi
  fi

  printf '@local-user\n'
}

# ── Handback chain resolution (SE-332) ───────────────────────────────────────
# Resolves the IMMEDIATE parent of a blocked autonomous instance, per the
# escalation table in autonomous-safety.md (Handback Obligation, SE-332).
# Authority escalation is independent of model escalation and of
# AUTONOMOUS_REVIEWER (which stays as first-level fallback).
#
# Returns:
#   0 + parent name  — parent resolved (chain ends in manual by construction)
#   5               — unknown mode: chain does NOT terminate in manual (invariant)
savia_handback_chain() {
  local modo="${1:-}"
  case "$modo" in
    overnight-sprint|code-improvement-loop|tech-research-agent)
      savia_autonomous_reviewer
      return 0
      ;;
    court-orchestrator|truth-tribunal-orchestrator|recommendation-tribunal-orchestrator)
      printf 'dev-orchestrator\n'
      return 0
      ;;
    subagent|subagente|delegado|delegate)
      printf '%s\n' "${SAVIA_HANDBACK_PARENT:-orquestador}"
      return 0
      ;;
    *)
      # Unknown mode: no guaranteed manual terminal — invariant violation.
      return 5
      ;;
  esac
}

# ── Workspace .env loader ─────────────────────────────────────────────────────
# Loads $SAVIA_WORKSPACE_DIR/.env if it exists. Variables already present in the
# parent environment WIN over .env (precedence: explicit env > .env > defaults).
# This is the canonical place to declare workspace-wide flags like
# SAVIA_HEURISTIC_ENFORCE — opencode.json's "env" key is unsupported and
# Claude Code's / OpenCode's settings.json shouldn't carry workspace-specific runtime flags.
_savia_load_dotenv() {
  local envfile="$1/.env"
  [[ -f "$envfile" ]] || return 0
  local line key val
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line#"${line%%[![:space:]]*}"}"
    [[ -z "$line" || "$line" == \#* ]] && continue
    line="${line#export }"
    [[ "$line" != *=* ]] && continue
    key="${line%%=*}"
    val="${line#*=}"
    [[ "$key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || continue
    if [[ "$val" =~ ^\".*\"$ ]] || [[ "$val" =~ ^\'.*\'$ ]]; then
      val="${val:1:${#val}-2}"
    fi
    if [[ -z "$(printenv "$key" 2>/dev/null)" ]]; then
      export "$key=$val"
    fi
  done < "$envfile"
}

# ── Workspace .venv auto-activator ────────────────────────────────────────────
# If $SAVIA_WORKSPACE_DIR/.venv/bin/activate exists and we're not already in a
# venv, source it so hooks/scripts get celpy/pyyaml/jsonschema without each
# caller having to remember. Idempotent (skips if VIRTUAL_ENV already set).
_savia_activate_venv() {
  [[ -n "${VIRTUAL_ENV:-}" ]] && return 0
  local activate="$1/.venv/bin/activate"
  [[ -f "$activate" ]] || return 0
  # shellcheck disable=SC1090
  source "$activate"
}

if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
  # Sourced from another script: export variables
  export SAVIA_WORKSPACE_DIR="${SAVIA_WORKSPACE_DIR:-$(_resolve_workspace)}"
  # Load workspace .env BEFORE provider detection so .env can influence it
  _savia_load_dotenv "$SAVIA_WORKSPACE_DIR"
  _savia_activate_venv "$SAVIA_WORKSPACE_DIR"
  export SAVIA_PROVIDER="${SAVIA_PROVIDER:-$(_resolve_provider)}"
  export SAVIA_PROJECT_SLUG="${SAVIA_PROJECT_SLUG:-$(_resolve_project_slug)}"
  # ── Telemetry pilot defaults (SPEC-198/200, 30d window from 2026-06-13) ────
  # Defaults to 'warn' so logs are produced without blocking. Override with
  # env var or .env to disable. Promote to 'on' once telemetry data is reviewed.
  export SAVIA_QUALITY_GATE_ADAPTIVE="${SAVIA_QUALITY_GATE_ADAPTIVE:-warn}"
  export SAVIA_JUDGE_VERDICT_VALIDATE="${SAVIA_JUDGE_VERDICT_VALIDATE:-warn}"
else
  # Direct invocation: print requested value
  case "${1:-}" in
    workspace) _resolve_workspace ;;
    provider)  _resolve_provider ;;
    project)   _resolve_project_slug ;;
    reviewer)  savia_autonomous_reviewer ;;
    json)
      printf '{"workspace":"%s","provider":"%s","project":"%s","reviewer":"%s","has_hooks":%s,"has_slash_commands":%s}\n' \
        "$(_resolve_workspace)" \
        "$(_resolve_provider)" \
        "$(_resolve_project_slug)" \
        "$(savia_autonomous_reviewer)" \
        "$(savia_has_hooks && echo true || echo false)" \
        "$(savia_has_slash_commands && echo true || echo false)"
      ;;
    *)
      echo "Usage: savia-env.sh <workspace|provider|project|reviewer|json>" >&2
      exit 2
      ;;
  esac
fi

# --------------------------------------------------------------------------
# SE-346 Slice 2 — savia_model_by_uncertainty: recomendación de modelo por
# incertidumbre del surrogate (advisory; el dispatch real queda en el llamador).
# Consulta scripts/surrogate/llm-router.py --check y devuelve la recomendación
# para un tipo de tarea (routing|code|audit|report). Sin sklearn disponible →
# devuelve vacío (fail-open, nunca bloquea). CRIT-001: local.
# --------------------------------------------------------------------------
savia_model_by_uncertainty() {
  local task_type="${1:-code}"
  local ws; ws="$(_resolve_workspace)"
  local router="$ws/scripts/surrogate/llm-router.py"
  [[ -f "$router" ]] || { echo ""; return 0; }
  local py="$HOME/.savia/venv/bin/python"
  [[ -x "$py" ]] || py="$(command -v python3 || true)"
  [[ -n "$py" ]] || { echo ""; return 0; }
  "$py" -c "import sklearn, scipy" >/dev/null 2>&1 || { echo ""; return 0; }
  local out
  out=$(WORKSPACE_DIR="$ws" "$py" "$router" --check 2>/dev/null || true)
  [[ -n "$out" ]] || { echo ""; return 0; }
  printf '%s' "$out" | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    r = d.get('results', {}).get('$task_type', {})
    model = r.get('model', '')
    std = r.get('std', '')
    verdict = r.get('verdict', '')
    if model:
        print(f'{model}\tstd={std}\t{verdict}')
    else:
        print('')
except Exception:
    print('')"
}
#!/usr/bin/env bash
# savia-env.sh — Provider-agnostic environment layer (SPEC-127 Slice 1)
#
# Single source of truth for workspace path and provider detection.
# Hooks, scripts and skills MUST source this instead of hard-coding
# CLAUDE_PROJECT_DIR or assuming a specific provider.
#
# Usage:
#   source scripts/savia-env.sh          # export SAVIA_WORKSPACE_DIR + SAVIA_PROVIDER
#   bash scripts/savia-env.sh workspace  # one-shot: print SAVIA_WORKSPACE_DIR
#   bash scripts/savia-env.sh provider   # one-shot: print SAVIA_PROVIDER
set -uo pipefail

# ── Capability probes ────────────────────────────────────────────────────────
savia_has_hooks() {
  case "${SAVIA_PROVIDER:-}" in
    copilot)  return 1 ;;  # OpenCode-Copilot Enterprise: zero hook surface
    localai)  return 0 ;;  # LocalAI runs under Claude Code / OpenCode shell
    claude)   return 0 ;;  # Full PreToolUse/PostToolUse/Stop surface
    unknown)  return 0 ;;  # Permissive: let downstream gates catch gaps
    *)        return 0 ;;  # OpenCode-Claude: ~25 events via plugin TS
  esac
}

savia_has_slash_commands() {
  case "${SAVIA_PROVIDER:-}" in
    copilot)  return 1 ;;  # Zero slash mechanism
    claude)   return 0 ;;  # Native slash commands
    localai)  return 0 ;;  # AI coding assistant shell
    unknown)  return 0 ;;  # Permissive
    *)        return 0 ;;  # OpenCode-Claude: .opencode/commands/
  esac
}

# ── Resolve workspace dir (fallback chain) ───────────────────────────────────
_resolve_workspace() {
  # 1. Explicit override (any provider)
  if [[ -n "${SAVIA_WORKSPACE_DIR:-}" ]]; then
    echo "$SAVIA_WORKSPACE_DIR"
    return
  fi

  # 2. Claude Code native
  if [[ -n "${CLAUDE_PROJECT_DIR:-}" ]]; then
    echo "$CLAUDE_PROJECT_DIR"
    return
  fi

  # 3. OpenCode v1.14+
  if [[ -n "${OPENCODE_PROJECT_DIR:-}" ]]; then
    echo "$OPENCODE_PROJECT_DIR"
    return
  fi

  # 4. git root
  local git_root
  git_root=$(git rev-parse --show-toplevel 2>/dev/null) || true
  if [[ -n "${git_root:-}" ]]; then
    echo "$git_root"
    return
  fi

  # 5. Last resort
  pwd
}

# ── Resolve project slug ─────────────────────────────────────────────────────
# Fallback chain:
#   1) $SAVIA_PROJECT_SLUG (explicit operator override)
#   2) git branch matches projects/<slug> or project/<slug>
#   3) $SAVIA_WORKSPACE_DIR/projects/ contains exactly one subdir
#   4) Empty string (workspace without active project is valid)
_resolve_project_slug() {
  # 1. Explicit override
  if [[ -n "${SAVIA_PROJECT_SLUG:-}" ]]; then
    echo "$SAVIA_PROJECT_SLUG"
    return
  fi

  # 2. Branch prefix
  local branch
  branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null) || true
  if [[ -n "${branch:-}" ]]; then
    case "$branch" in
      projects/*) echo "${branch#projects/}"; return ;;
      project/*)  echo "${branch#project/}";  return ;;
    esac
  fi

  # 3. Single subdir in projects/
  local ws
  ws=$(_resolve_workspace)
  if [[ -d "$ws/projects" ]]; then
    local subdirs=()
    local entry
    for entry in "$ws/projects"/*/; do
      [[ -d "$entry" ]] || continue
      subdirs+=("$(basename "$entry")")
    done
    if [[ ${#subdirs[@]} -eq 1 ]]; then
      echo "${subdirs[0]}"
      return
    fi
  fi

  # 4. Empty (not an error)
  echo ""
}

# ── Detect provider (precedence chain) ───────────────────────────────────────
_resolve_provider() {
  # 1. Operator override
  if [[ -n "${SAVIA_PROVIDER:-}" ]]; then
    echo "$SAVIA_PROVIDER"
    return
  fi

  # 2. ANTHROPIC_BASE_URL points to localhost/localai
  local base_url="${ANTHROPIC_BASE_URL:-}"
  if [[ -n "$base_url" ]] && [[ "$base_url" == *"localhost"* || "$base_url" == *"127.0.0.1"* || "$base_url" == *"localai"* ]]; then
    echo "localai"
    return
  fi

  # 3. Copilot tokens present
  if [[ -n "${COPILOT_TOKEN:-}" || -n "${GITHUB_COPILOT_TOKEN:-}" ]]; then
    echo "copilot"
    return
  fi

  # 4. OpenCode provider env
  if [[ -n "${OPENCODE_PROVIDER:-}" ]]; then
    echo "$OPENCODE_PROVIDER"
    return
  fi

  # 5. Claude Code native
  if [[ -n "${CLAUDE_PROJECT_DIR:-}" ]]; then
    echo "claude"
    return
  fi

  # 6. Unknown
  echo "unknown"
}

# ── Tier-based model resolution (SPEC-127 Slice 1) ────────────────────────────
# Resolves a capability tier (heavy/mid/fast) or legacy short name
# (opus/sonnet/haiku) to the user's provider-specific model ID
# declared in ~/.savia/preferences.yaml.
#
# Falls through to preferences.yaml on first call; caches result in
# SAVIA_MODEL_{HEAVY,MID,FAST} env vars for subsequent calls (no
# repeated YAML parsing).
savia_resolve_model() {
  local tier="$1"
  local prefs_file="${HOME}/.savia/preferences.yaml"

  _read_pref() {
    local key="$1"
    awk -v k="^${key}:" '
      $0 ~ k { sub(k, ""); sub(/^[[:space:]]+/, ""); gsub(/^"|"$/, ""); gsub(/^\047|\047$/, ""); print; exit }
    ' "$prefs_file" 2>/dev/null
  }

  # SE-313: provider prefix is mandatory (see section 0 of SE-313 spec).
  # Defensa ante IDs sin prefijo en preferences: si el ID no lleva provider/,
  # se prefija solo cuando el ID corto pertenece al provider configurado
  # (ej. `deepseek-v4-pro` → `deepseek/deepseek-v4-pro`). IDs canónicos de
  # otros vendors (claude-*, gpt-*, ...) se preservan intactos.
  _prefixed() {
    local id="$1"
    [[ -z "$id" ]] && { echo ""; return; }
    if [[ "$id" == */* ]]; then
      echo "$id"
    else
      local provider
      provider="$(_read_pref "provider")"
      [[ -z "$provider" ]] && provider="deepseek"
      if [[ "$id" == "$provider-"* ]]; then
        echo "${provider}/${id}"
      else
        echo "$id"
      fi
    fi
  }

  case "$tier" in
    heavy)
      if [[ -z "${SAVIA_MODEL_HEAVY:-}" && -f "$prefs_file" ]]; then
        export SAVIA_MODEL_HEAVY="$(_read_pref "model_heavy")"
      fi
      [[ -n "${SAVIA_MODEL_HEAVY:-}" ]] && _prefixed "${SAVIA_MODEL_HEAVY}" || echo "heavy"
      ;;
    mid)
      if [[ -z "${SAVIA_MODEL_MID:-}" && -f "$prefs_file" ]]; then
        export SAVIA_MODEL_MID="$(_read_pref "model_mid")"
      fi
      [[ -n "${SAVIA_MODEL_MID:-}" ]] && _prefixed "${SAVIA_MODEL_MID}" || echo "mid"
      ;;
    fast)
      if [[ -z "${SAVIA_MODEL_FAST:-}" && -f "$prefs_file" ]]; then
        export SAVIA_MODEL_FAST="$(_read_pref "model_fast")"
      fi
      [[ -n "${SAVIA_MODEL_FAST:-}" ]] && _prefixed "${SAVIA_MODEL_FAST}" || echo "fast"
      ;;
    opus|claude-opus-4-7|claude-opus-4-5)
      savia_resolve_model heavy
      ;;
    sonnet|claude-sonnet-4-6|claude-sonnet-4-5)
      savia_resolve_model mid
      ;;
    haiku|claude-haiku-4-5-20251001)
      savia_resolve_model fast
      ;;
    *)
      _prefixed "$tier"  # pass-through for non-tier, non-legacy names
      ;;
  esac
}
export -f savia_resolve_model

# ── Main (source mode) ───────────────────────────────────────────────────────
# --------------------------------------------------------------------------
# AUTONOMOUS_REVIEWER resolver (autonomous-safety.md)
#
# Fallback chain:
#   1) $SAVIA_AUTONOMOUS_REVIEWER  (explicit env override)
#   2) .claude/rules/pm-config.local.md  AUTONOMOUS_REVIEWER = "..."
#   3) ~/.savia/preferences.yaml         autonomous_reviewer: ...
#   4) git config user.email             (zero-config common case)
#   5) "@local-user"                     (generic fallback, never blocks)
# --------------------------------------------------------------------------
savia_autonomous_reviewer() {
  if [[ -n "${SAVIA_AUTONOMOUS_REVIEWER:-}" ]]; then
    printf '%s\n' "$SAVIA_AUTONOMOUS_REVIEWER"
    return 0
  fi

  local ws; ws="$(_resolve_workspace)"
  local local_cfg="$ws/.claude/rules/pm-config.local.md"
  if [[ -r "$local_cfg" ]]; then
    local v
    v="$(grep -E '^\s*AUTONOMOUS_REVIEWER\s*=' "$local_cfg" 2>/dev/null \
         | head -n1 \
         | sed -E 's/^[^=]*=\s*"?([^"]*)"?\s*$/\1/' \
         | tr -d '[:space:]')"
    if [[ -n "$v" && "$v" != "@local-user" ]]; then
      printf '%s\n' "$v"
      return 0
    fi
  fi

  local prefs="$HOME/.savia/preferences.yaml"
  if [[ -r "$prefs" ]]; then
    local v
    v="$(grep -E '^\s*autonomous_reviewer\s*:' "$prefs" 2>/dev/null \
         | head -n1 \
         | sed -E 's/^[^:]*:\s*"?([^"]*)"?\s*$/\1/' \
         | tr -d '[:space:]')"
    if [[ -n "$v" ]]; then
      printf '%s\n' "$v"
      return 0
    fi
  fi

  if command -v git >/dev/null 2>&1; then
    local email
    email="$(git -C "$ws" config user.email 2>/dev/null)"
    if [[ -n "$email" ]]; then
      # Convert "user.name@example.com" -> "@user-name"
      printf '@%s\n' "${email%@*}"
      return 0
    fi
  fi

  printf '@local-user\n'
}

# ── Handback chain resolution (SE-332) ───────────────────────────────────────
# Resolves the IMMEDIATE parent of a blocked autonomous instance, per the
# escalation table in autonomous-safety.md (Handback Obligation, SE-332).
# Authority escalation is independent of model escalation and of
# AUTONOMOUS_REVIEWER (which stays as first-level fallback).
#
# Returns:
#   0 + parent name  — parent resolved (chain ends in manual by construction)
#   5               — unknown mode: chain does NOT terminate in manual (invariant)
savia_handback_chain() {
  local modo="${1:-}"
  case "$modo" in
    overnight-sprint|code-improvement-loop|tech-research-agent)
      savia_autonomous_reviewer
      return 0
      ;;
    court-orchestrator|truth-tribunal-orchestrator|recommendation-tribunal-orchestrator)
      printf 'dev-orchestrator\n'
      return 0
      ;;
    subagent|subagente|delegado|delegate)
      printf '%s\n' "${SAVIA_HANDBACK_PARENT:-orquestador}"
      return 0
      ;;
    *)
      # Unknown mode: no guaranteed manual terminal — invariant violation.
      return 5
      ;;
  esac
}

# ── Workspace .env loader ─────────────────────────────────────────────────────
# Loads $SAVIA_WORKSPACE_DIR/.env if it exists. Variables already present in the
# parent environment WIN over .env (precedence: explicit env > .env > defaults).
# This is the canonical place to declare workspace-wide flags like
# SAVIA_HEURISTIC_ENFORCE — opencode.json's "env" key is unsupported and
# Claude Code's / OpenCode's settings.json shouldn't carry workspace-specific runtime flags.
_savia_load_dotenv() {
  local envfile="$1/.env"
  [[ -f "$envfile" ]] || return 0
  local line key val
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line#"${line%%[![:space:]]*}"}"
    [[ -z "$line" || "$line" == \#* ]] && continue
    line="${line#export }"
    [[ "$line" != *=* ]] && continue
    key="${line%%=*}"
    val="${line#*=}"
    [[ "$key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || continue
    if [[ "$val" =~ ^\".*\"$ ]] || [[ "$val" =~ ^\'.*\'$ ]]; then
      val="${val:1:${#val}-2}"
    fi
    if [[ -z "$(printenv "$key" 2>/dev/null)" ]]; then
      export "$key=$val"
    fi
  done < "$envfile"
}

# ── Workspace .venv auto-activator ────────────────────────────────────────────
# If $SAVIA_WORKSPACE_DIR/.venv/bin/activate exists and we're not already in a
# venv, source it so hooks/scripts get celpy/pyyaml/jsonschema without each
# caller having to remember. Idempotent (skips if VIRTUAL_ENV already set).
_savia_activate_venv() {
  [[ -n "${VIRTUAL_ENV:-}" ]] && return 0
  local activate="$1/.venv/bin/activate"
  [[ -f "$activate" ]] || return 0
  # shellcheck disable=SC1090
  source "$activate"
}

if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
  # Sourced from another script: export variables
  export SAVIA_WORKSPACE_DIR="${SAVIA_WORKSPACE_DIR:-$(_resolve_workspace)}"
  # Load workspace .env BEFORE provider detection so .env can influence it
  _savia_load_dotenv "$SAVIA_WORKSPACE_DIR"
  _savia_activate_venv "$SAVIA_WORKSPACE_DIR"
  export SAVIA_PROVIDER="${SAVIA_PROVIDER:-$(_resolve_provider)}"
  export SAVIA_PROJECT_SLUG="${SAVIA_PROJECT_SLUG:-$(_resolve_project_slug)}"
  # ── Telemetry pilot defaults (SPEC-198/200, 30d window from 2026-06-13) ────
  # Defaults to 'warn' so logs are produced without blocking. Override with
  # env var or .env to disable. Promote to 'on' once telemetry data is reviewed.
  export SAVIA_QUALITY_GATE_ADAPTIVE="${SAVIA_QUALITY_GATE_ADAPTIVE:-warn}"
  export SAVIA_JUDGE_VERDICT_VALIDATE="${SAVIA_JUDGE_VERDICT_VALIDATE:-warn}"
else
  # Direct invocation: print requested value
  case "${1:-}" in
    workspace) _resolve_workspace ;;
    provider)  _resolve_provider ;;
    project)   _resolve_project_slug ;;
    reviewer)  savia_autonomous_reviewer ;;
    json)
      printf '{"workspace":"%s","provider":"%s","project":"%s","reviewer":"%s","has_hooks":%s,"has_slash_commands":%s}\n' \
        "$(_resolve_workspace)" \
        "$(_resolve_provider)" \
        "$(_resolve_project_slug)" \
        "$(savia_autonomous_reviewer)" \
        "$(savia_has_hooks && echo true || echo false)" \
        "$(savia_has_slash_commands && echo true || echo false)"
      ;;
    *)
      echo "Usage: savia-env.sh <workspace|provider|project|reviewer|json>" >&2
      exit 2
      ;;
  esac
fi

# --------------------------------------------------------------------------
# SE-346 Slice 2 — savia_model_by_uncertainty: recomendación de modelo por
# incertidumbre del surrogate (advisory; el dispatch real queda en el llamador).
# Consulta scripts/surrogate/llm-router.py --check y devuelve la recomendación
# para un tipo de tarea (routing|code|audit|report). Sin sklearn disponible →
# devuelve vacío (fail-open, nunca bloquea). CRIT-001: local.
# --------------------------------------------------------------------------
savia_model_by_uncertainty() {
  local task_type="${1:-code}"
  local ws; ws="$(_resolve_workspace)"
  local router="$ws/scripts/surrogate/llm-router.py"
  [[ -f "$router" ]] || { echo ""; return 0; }
  local py="$HOME/.savia/venv/bin/python"
  [[ -x "$py" ]] || py="$(command -v python3 || true)"
  [[ -n "$py" ]] || { echo ""; return 0; }
  "$py" -c "import sklearn, scipy" >/dev/null 2>&1 || { echo ""; return 0; }
  local out
  out=$(WORKSPACE_DIR="$ws" "$py" "$router" --check 2>/dev/null || true)
  [[ -n "$out" ]] || { echo ""; return 0; }
  printf '%s' "$out" | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    r = d.get('results', {}).get('$task_type', {})
    model = r.get('model', '')
    std = r.get('std', '')
    verdict = r.get('verdict', '')
    if model:
        print(f'{model}\tstd={std}\t{verdict}')
    else:
        print('')
except Exception:
    print('')"
}


# SE-388 C — identidad efectiva de frontend derivada en runtime.
# Precedencia: marcadores de runtime > env heredado > fallback unknown.
# Invariante: runtime frontend == doctor/probe/context effective frontend.
savia_frontend() {
  if [[ -n "${CODEX_HOME:-}" || -n "${CODEX_SANDBOX:-}" || -n "${CODEX_THREAD_ID:-}" ]]; then
    echo "codex"; return 0
  fi
  if [[ -n "${OPENCODE_PROJECT_DIR:-}" || -n "${OPENCODE_PROVIDER:-}" ]]; then
    echo "opencode"; return 0
  fi
  if [[ -n "${CLAUDECODE:-}" || -n "${CLAUDE_CODE_ENTRYPOINT:-}" ]]; then
    echo "claude"; return 0
  fi
  echo "unknown"
}
export SAVIA_FRONTEND="$(savia_frontend)"
