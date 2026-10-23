#!/usr/bin/env bats
# savia-env.sh — capa de entorno agnóstica de proveedor (SPEC-127 Slice 1, SE-332, SE-388)
# Ref: docs/rules/domain/autonomous-safety.md, SPEC-127
# Cada prueba corre en `env -i` con HOME y workspace temporales: ninguna lee la
# configuración real de la persona usuaria.

SCRIPT="scripts/savia-env.sh"

setup() {
  cd "$BATS_TEST_DIRNAME/.." || exit 1
  REPO="$(pwd)"
  T="$(mktemp -d)"
  export T
  mkdir -p "$T/home/.savia" "$T/ws"
  git -C "$T/ws" init -q
  git -C "$T/ws" -c user.name=t -c user.email=t@t.t commit -q --allow-empty -m base
}

teardown() {
  rm -rf "$T"
}

# envrun VAR=val ... -- 'comando bash'  → entorno vacío + HOME y workspace temporales
envrun() {
  local vars=()
  while [[ "$1" != "--" ]]; do vars+=("$1"); shift; done
  shift
  env -i PATH="$PATH" HOME="$T/home" SAVIA_WORKSPACE_DIR="$T/ws" "${vars[@]}" \
    bash -c "cd '$T/ws'; $1"
}

# direct VAR=val ... -- modo   → invocación directa del script, sin workspace por defecto
direct() {
  local vars=()
  while [[ "$1" != "--" ]]; do vars+=("$1"); shift; done
  shift
  env -i PATH="$PATH" HOME="$T/home" "${vars[@]}" bash "$REPO/$SCRIPT" "$@"
}

prefs() { cat > "$T/home/.savia/preferences.yaml"; }

# ── workspace ────────────────────────────────────────────────────────────────

@test "workspace: SAVIA_WORKSPACE_DIR gana sobre CLAUDE_PROJECT_DIR y OPENCODE_PROJECT_DIR" {
  run direct SAVIA_WORKSPACE_DIR=/a CLAUDE_PROJECT_DIR=/b OPENCODE_PROJECT_DIR=/c -- workspace
  [ "$status" -eq 0 ]
  [ "$output" = "/a" ]
}

@test "workspace: CLAUDE_PROJECT_DIR gana sobre OPENCODE_PROJECT_DIR" {
  run direct CLAUDE_PROJECT_DIR=/b OPENCODE_PROJECT_DIR=/c -- workspace
  [ "$output" = "/b" ]
}

@test "workspace: OPENCODE_PROJECT_DIR se usa si no hay las anteriores" {
  run direct OPENCODE_PROJECT_DIR=/c -- workspace
  [ "$output" = "/c" ]
}

@test "workspace: sin variables cae a la raíz git del cwd" {
  run env -i PATH="$PATH" HOME="$T/home" bash -c "cd '$T/ws' && bash '$REPO/$SCRIPT' workspace"
  [ "$status" -eq 0 ]
  [ "$output" = "$(cd "$T/ws" && pwd -P)" ]
}

@test "workspace: fuera de git y sin variables → pwd (último recurso)" {
  mkdir -p "$T/plano"
  run env -i PATH="$PATH" HOME="$T/home" GIT_CEILING_DIRECTORIES="$T" bash -c "cd '$T/plano' && bash '$REPO/$SCRIPT' workspace"
  [ "$output" = "$(cd "$T/plano" && pwd -P)" ]
}

# ── proveedor ────────────────────────────────────────────────────────────────

@test "provider: SAVIA_PROVIDER explícito gana sobre cualquier señal" {
  run direct SAVIA_PROVIDER=custom COPILOT_TOKEN=x ANTHROPIC_BASE_URL=http://localhost:1 -- provider
  [ "$output" = "custom" ]
}

@test "provider: ANTHROPIC_BASE_URL local (localhost, 127.0.0.1, localai) → localai" {
  for u in http://localhost:8080 http://127.0.0.1:9 http://localai.lan; do
    run direct ANTHROPIC_BASE_URL="$u" -- provider
    [ "$output" = "localai" ]
  done
}

@test "provider: URL remota no es localai" {
  run direct ANTHROPIC_BASE_URL=https://api.example.com -- provider
  [ "$output" = "unknown" ]
}

@test "provider: token de Copilot → copilot (COPILOT_TOKEN y GITHUB_COPILOT_TOKEN)" {
  run direct COPILOT_TOKEN=t -- provider
  [ "$output" = "copilot" ]
  run direct GITHUB_COPILOT_TOKEN=t -- provider
  [ "$output" = "copilot" ]
}

@test "provider: localai gana sobre copilot en la precedencia" {
  run direct ANTHROPIC_BASE_URL=http://localhost COPILOT_TOKEN=t -- provider
  [ "$output" = "localai" ]
}

@test "provider: OPENCODE_PROVIDER se devuelve tal cual; CLAUDE_PROJECT_DIR → claude" {
  run direct OPENCODE_PROVIDER=deepseek -- provider
  [ "$output" = "deepseek" ]
  run direct CLAUDE_PROJECT_DIR=/x -- provider
  [ "$output" = "claude" ]
}

@test "provider: sin ninguna señal → unknown" {
  run direct -- provider
  [ "$output" = "unknown" ]
}

# ── capacidades ──────────────────────────────────────────────────────────────

@test "capacidades: claude, localai, unknown y otros proveedores tienen hooks y slash" {
  for p in claude localai unknown deepseek; do
    run envrun SAVIA_PROVIDER=$p -- "source '$REPO/$SCRIPT'; savia_has_hooks && savia_has_slash_commands && echo ok"
    [ "$output" = "ok" ]
  done
}

@test "capacidades: copilot no tiene hooks ni slash (error esperado)" {
  run envrun SAVIA_PROVIDER=copilot -- "source '$REPO/$SCRIPT'; savia_has_hooks; echo h=\$?; savia_has_slash_commands; echo s=\$?"
  [[ "$output" == *"h=1"* && "$output" == *"s=1"* ]]
}

@test "json: contiene los seis campos y has_hooks=false con copilot" {
  run direct SAVIA_WORKSPACE_DIR="$T/ws" SAVIA_PROVIDER=copilot SAVIA_PROJECT_SLUG=demo SAVIA_AUTONOMOUS_REVIEWER=@rev -- json
  [ "$status" -eq 0 ]
  echo "$output" | python3 -c "
import json, sys
d = json.load(sys.stdin)
assert d == {'workspace': '$T/ws', 'provider': 'copilot', 'project': 'demo', 'reviewer': '@rev',
             'has_hooks': False, 'has_slash_commands': False}, d"
}

@test "uso: argumento desconocido o vacío → exit 2 con usage" {
  run direct -- bogus
  [ "$status" -eq 2 ]
  echo "$output" | grep -q "Usage: savia-env.sh"
  run direct --
  [ "$status" -eq 2 ]
}

# ── slug de proyecto ─────────────────────────────────────────────────────────

@test "project: SAVIA_PROJECT_SLUG explícito gana" {
  mkdir -p "$T/ws/projects/uno"
  run direct SAVIA_WORKSPACE_DIR="$T/ws" SAVIA_PROJECT_SLUG=forzado -- project
  [ "$output" = "forzado" ]
}

@test "project: rama projects/<slug> y project/<slug> dan el slug" {
  git -C "$T/ws" switch -q -c projects/alfa
  run env -i PATH="$PATH" HOME="$T/home" SAVIA_WORKSPACE_DIR="$T/ws" bash -c "cd '$T/ws' && bash '$REPO/$SCRIPT' project"
  [ "$output" = "alfa" ]
  git -C "$T/ws" switch -q -c project/beta
  run env -i PATH="$PATH" HOME="$T/home" SAVIA_WORKSPACE_DIR="$T/ws" bash -c "cd '$T/ws' && bash '$REPO/$SCRIPT' project"
  [ "$output" = "beta" ]
}

@test "project: un único subdirectorio en projects/ es el proyecto" {
  mkdir -p "$T/ws/projects/solo"
  run envrun -- "bash '$REPO/$SCRIPT' project"
  [ "$output" = "solo" ]
}

@test "project: ninguno o dos subdirectorios → vacío sin error (borde)" {
  run envrun -- "bash '$REPO/$SCRIPT' project"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  mkdir -p "$T/ws/projects/a" "$T/ws/projects/b"
  run envrun -- "bash '$REPO/$SCRIPT' project"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# ── revisor autónomo ─────────────────────────────────────────────────────────

@test "reviewer: SAVIA_AUTONOMOUS_REVIEWER gana sobre fichero local y preferencias" {
  mkdir -p "$T/ws/.claude/rules"
  echo 'AUTONOMOUS_REVIEWER = "@local"' > "$T/ws/.claude/rules/pm-config.local.md"
  echo 'autonomous_reviewer: @prefs' > "$T/home/.savia/preferences.yaml"
  run direct SAVIA_WORKSPACE_DIR="$T/ws" SAVIA_AUTONOMOUS_REVIEWER=@env -- reviewer
  [ "$output" = "@env" ]
}

@test "reviewer: pm-config.local.md gana sobre preferencias" {
  mkdir -p "$T/ws/.claude/rules"
  echo 'AUTONOMOUS_REVIEWER = "@local"' > "$T/ws/.claude/rules/pm-config.local.md"
  echo 'autonomous_reviewer: "@prefs"' > "$T/home/.savia/preferences.yaml"
  run direct SAVIA_WORKSPACE_DIR="$T/ws" -- reviewer
  [ "$output" = "@local" ]
}

@test "reviewer: el valor @local-user del fichero local se ignora y pasa a preferencias" {
  mkdir -p "$T/ws/.claude/rules"
  echo 'AUTONOMOUS_REVIEWER = "@local-user"' > "$T/ws/.claude/rules/pm-config.local.md"
  echo 'autonomous_reviewer: "@prefs"' > "$T/home/.savia/preferences.yaml"
  run direct SAVIA_WORKSPACE_DIR="$T/ws" -- reviewer
  [ "$output" = "@prefs" ]
}

@test "reviewer: sin config usa git user.email → @parte-local" {
  git -C "$T/ws" config user.email "ana.perez@example.com"
  run direct SAVIA_WORKSPACE_DIR="$T/ws" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null -- reviewer
  [ "$output" = "@ana.perez" ]
}

@test "reviewer: sin nada → @local-user y nunca bloquea (empty fallback)" {
  run direct SAVIA_WORKSPACE_DIR="$T/ws" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null -- reviewer
  [ "$status" -eq 0 ]
  [ "$output" = "@local-user" ]
}

# ── handback ─────────────────────────────────────────────────────────────────

@test "handback: modos autónomos → revisor; tribunales → dev-orchestrator" {
  run envrun SAVIA_AUTONOMOUS_REVIEWER=@rev -- "source '$REPO/$SCRIPT'; savia_handback_chain overnight-sprint; savia_handback_chain court-orchestrator; savia_handback_chain truth-tribunal-orchestrator"
  [ "${lines[0]}" = "@rev" ]
  [ "${lines[1]}" = "dev-orchestrator" ]
  [ "${lines[2]}" = "dev-orchestrator" ]
}

@test "handback: subagente usa SAVIA_HANDBACK_PARENT o 'orquestador' por defecto" {
  run envrun -- "source '$REPO/$SCRIPT'; savia_handback_chain subagent"
  [ "$output" = "orquestador" ]
  run envrun SAVIA_HANDBACK_PARENT=padre-1 -- "source '$REPO/$SCRIPT'; savia_handback_chain delegate"
  [ "$output" = "padre-1" ]
}

@test "handback: modo desconocido o vacío → código 5 (invariante: sin terminal manual)" {
  run envrun -- "source '$REPO/$SCRIPT'; savia_handback_chain inventado; echo rc=\$?; savia_handback_chain; echo rc=\$?"
  [ "${lines[0]}" = "rc=5" ]
  [ "${lines[1]}" = "rc=5" ]
}

# ── resolución de modelos por tier ───────────────────────────────────────────

@test "modelo: sin preferencias, el tier devuelve su propio nombre" {
  run envrun -- "source '$REPO/$SCRIPT'; savia_resolve_model heavy; savia_resolve_model mid; savia_resolve_model fast"
  [ "${lines[0]}" = "heavy" ]
  [ "${lines[1]}" = "mid" ]
  [ "${lines[2]}" = "fast" ]
}

@test "modelo: model_<tier> de preferencias se lee y las comillas se limpian" {
  prefs <<'YAML'
model_heavy: "acme/grande"
model_mid: 'acme/medio'
model_fast: acme/rapido
YAML
  run envrun -- "source '$REPO/$SCRIPT'; savia_resolve_model heavy; savia_resolve_model mid; savia_resolve_model fast"
  [ "${lines[0]}" = "acme/grande" ]
  [ "${lines[1]}" = "acme/medio" ]
  [ "${lines[2]}" = "acme/rapido" ]
}

@test "modelo: alias heredados opus/sonnet/haiku mapean a heavy/mid/fast" {
  prefs <<'YAML'
model_heavy: p/h
model_mid: p/m
model_fast: p/f
YAML
  run envrun -- "source '$REPO/$SCRIPT'; savia_resolve_model opus; savia_resolve_model claude-sonnet-4-6; savia_resolve_model haiku"
  [ "${lines[0]}" = "p/h" ]
  [ "${lines[1]}" = "p/m" ]
  [ "${lines[2]}" = "p/f" ]
}

@test "modelo: SAVIA_MODEL_<TIER> explícito gana sobre preferencias" {
  prefs <<'YAML'
model_heavy: p/h
YAML
  run envrun SAVIA_MODEL_HEAVY=env/modelo -- "source '$REPO/$SCRIPT'; savia_resolve_model heavy"
  [ "$output" = "env/modelo" ]
}

@test "modelo: ID sin prefijo del proveedor configurado se prefija; ajeno se conserva" {
  prefs <<'YAML'
provider: deepseek
model_heavy: deepseek-v4-pro
model_mid: claude-sonnet-x
YAML
  run envrun -- "source '$REPO/$SCRIPT'; savia_resolve_model heavy; savia_resolve_model mid"
  [ "${lines[0]}" = "deepseek/deepseek-v4-pro" ]
  [ "${lines[1]}" = "claude-sonnet-x" ]
}

@test "modelo: nombre fuera de tiers y alias pasa tal cual" {
  run envrun -- "source '$REPO/$SCRIPT'; savia_resolve_model gpt-9"
  [ "$output" = "gpt-9" ]
}

@test "modelo: tiers.<frontend> gana sobre model_<tier> y se limpia el comentario" {
  prefs <<'YAML'
model_heavy: legacy/heavy
tiers:
  opencode:
    heavy: oc/pesado   # comentario
YAML
  run envrun SAVIA_TIER_FRONTEND=opencode -- "source '$REPO/$SCRIPT'; savia_resolve_model heavy"
  [ "$output" = "oc/pesado" ]
}

@test "modelo: en claude-code un valor que no es selector se descarta → opus/haiku" {
  prefs <<'YAML'
model_heavy: legacy/heavy
tiers:
  claude-code:
    heavy: no-es-selector
YAML
  run envrun SAVIA_TIER_FRONTEND=claude -- "source '$REPO/$SCRIPT'; savia_resolve_model heavy; savia_resolve_model fast"
  [ "${lines[0]}" = "opus" ]
  [ "${lines[1]}" = "haiku" ]
}

@test "modelo: en claude-code nunca se filtra el model_<tier> de otro proveedor" {
  prefs <<'YAML'
model_mid: otro/proveedor
YAML
  run envrun SAVIA_TIER_FRONTEND=claude -- "source '$REPO/$SCRIPT'; savia_resolve_model mid"
  [ "$output" = "sonnet" ]
}

# ── frontend ─────────────────────────────────────────────────────────────────

@test "frontend: marcadores Codex > OpenCode > Claude > unknown" {
  run envrun CODEX_HOME=/x OPENCODE_PROVIDER=y CLAUDECODE=1 -- "source '$REPO/$SCRIPT'; savia_frontend"
  [ "$output" = "codex" ]
  run envrun OPENCODE_PROVIDER=y CLAUDECODE=1 -- "source '$REPO/$SCRIPT'; savia_frontend"
  [ "$output" = "opencode" ]
  run envrun CLAUDE_CODE_ENTRYPOINT=cli -- "source '$REPO/$SCRIPT'; savia_frontend"
  [ "$output" = "claude" ]
  run envrun -- "source '$REPO/$SCRIPT'; savia_frontend"
  [ "$output" = "unknown" ]
}

# ── carga de .env y exportaciones al hacer source ────────────────────────────

@test "dotenv: claves válidas se cargan; comentarios, export, comillas y claves inválidas se manejan" {
  cat > "$T/ws/.env" <<'ENV'
# comentario
export UNA=valor1
DOS="con espacios"
TRES='simple'
no es clave valida
9MAL=x
ENV
  run envrun -- "source '$REPO/$SCRIPT'; echo \"[\$UNA][\$DOS][\$TRES][\${MAL:-vacio}]\""
  [ "$output" = "[valor1][con espacios][simple][vacio]" ]
}

@test "dotenv: una variable ya presente en el entorno gana sobre .env" {
  echo 'SAVIA_PROJECT_SLUG=desde-env-file' > "$T/ws/.env"
  echo 'PREEXISTENTE=file' >> "$T/ws/.env"
  run envrun PREEXISTENTE=entorno -- "source '$REPO/$SCRIPT'; echo \$PREEXISTENTE \$SAVIA_PROJECT_SLUG"
  [ "$output" = "entorno desde-env-file" ]
}

@test "dotenv: SAVIA_PROVIDER definido en .env influye en la detección" {
  echo 'SAVIA_PROVIDER=desde-dotenv' > "$T/ws/.env"
  run envrun -- "source '$REPO/$SCRIPT'; echo \$SAVIA_PROVIDER"
  [ "$output" = "desde-dotenv" ]
}

@test "source: exporta workspace, provider, frontend y los pilotos de telemetría en warn" {
  run envrun -- "source '$REPO/$SCRIPT'; env | grep -E '^SAVIA_(WORKSPACE_DIR|PROVIDER|QUALITY_GATE_ADAPTIVE|JUDGE_VERDICT_VALIDATE|FRONTEND)=' | sort"
  echo "$output" | grep -q "^SAVIA_JUDGE_VERDICT_VALIDATE=warn$"
  echo "$output" | grep -q "^SAVIA_QUALITY_GATE_ADAPTIVE=warn$"
  echo "$output" | grep -q "^SAVIA_WORKSPACE_DIR=$T/ws$"
  echo "$output" | grep -q "^SAVIA_PROVIDER=unknown$"
  echo "$output" | grep -q "^SAVIA_FRONTEND=unknown$"
}

@test "source: el valor piloto explícito off no se pisa" {
  run envrun SAVIA_QUALITY_GATE_ADAPTIVE=off -- "source '$REPO/$SCRIPT'; echo \$SAVIA_QUALITY_GATE_ADAPTIVE"
  [ "$output" = "off" ]
}

@test "venv: se activa .venv del workspace salvo que ya haya VIRTUAL_ENV" {
  mkdir -p "$T/ws/.venv/bin"
  echo 'export VENV_MARK=activado' > "$T/ws/.venv/bin/activate"
  run envrun -- "source '$REPO/$SCRIPT'; echo \${VENV_MARK:-no}"
  [ "$output" = "activado" ]
  run envrun VIRTUAL_ENV=/otro -- "source '$REPO/$SCRIPT'; echo \${VENV_MARK:-no}"
  [ "$output" = "no" ]
}

@test "uncertainty: sin router en el workspace devuelve vacío y exit 0 (fail-open)" {
  run envrun -- "source '$REPO/$SCRIPT'; savia_model_by_uncertainty code; echo rc=\$?"
  [ "$output" = $'\nrc=0' ]
}

@test "el script declara set -uo pipefail" {
  grep -q '^set -uo pipefail' "$REPO/$SCRIPT"
}
