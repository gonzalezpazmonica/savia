#!/usr/bin/env bash
# SPEC-149 -- savia-sandbox-doctor.sh
# Verifica las 3 capas de sandbox (application + kernel + Docker).
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ERRORS=0
WARNINGS=0

green()  { printf '\033[32mOK  %s\033[0m\n' "$*"; }
red()    { printf '\033[31mFAIL %s\033[0m\n' "$*"; }
yellow() { printf '\033[33mWARN %s\033[0m\n' "$*"; }
info()   { printf '     %s\n' "$*"; }
section(){ printf '\n[SPEC-149] == %s ==\n' "$*"; }

OC_CONFIG="$REPO_ROOT/opencode.json"

# Capa A
section "Capa A: permission block (opencode.json)"
if [[ ! -f "$OC_CONFIG" ]]; then
  red "opencode.json no encontrado en $REPO_ROOT"
  ERRORS=$((ERRORS+1))
else
  # La ruta va por argv, no interpolada en el código Python.
  DENY_COUNT=$(python3 - "$OC_CONFIG" << 'PYEOF'
import json, sys
with open(sys.argv[1]) as f:
    d = json.load(f)
b = d.get("agent",{}).get("build",{}).get("permission",{}).get("bash",{})
print(sum(1 for v in b.values() if v == "deny") if isinstance(b, dict) else 0)
PYEOF
)
  if [[ "${DENY_COUNT:-0}" -ge 3 ]]; then
    green "permission.bash: $DENY_COUNT reglas deny para comandos destructivos"
  else
    red "permission.bash insuficiente (${DENY_COUNT:-0} deny rules, minimo 3)"
    ERRORS=$((ERRORS+1))
  fi
fi

# Capa B
section "Capa B: kernel sandbox (bubblewrap / Seatbelt)"
if [[ -f "$OC_CONFIG" ]]; then
  # plugin[] debe ser una lista con «opencode-sandbox» (o «opencode-sandbox@versión»).
  # Antes, si plugin era una cadena, «in» buscaba subcadena: «opencode-sandbox-off» daba OK.
  PLUGIN_OK=$(python3 - "$OC_CONFIG" << 'PYEOF'
import json, sys
with open(sys.argv[1]) as f:
    d = json.load(f)
p = d.get("plugin", [])
ok = isinstance(p, list) and any(isinstance(x, str) and (x == "opencode-sandbox" or x.startswith("opencode-sandbox@")) for x in p)
print(1 if ok else 0)
PYEOF
)
  if [[ "${PLUGIN_OK:-0}" == "1" ]]; then
    green "opencode-sandbox declarado en plugin[]"
  else
    yellow "opencode-sandbox NO en plugin[] -- Capa B desactivada"
    WARNINGS=$((WARNINGS+1))
  fi
fi

if [[ "$(uname)" == "Linux" ]]; then
  if command -v bwrap &>/dev/null; then
    green "bubblewrap instalado"
    if bwrap --ro-bind / / --dev /dev --proc /proc -- echo "ok" &>/dev/null 2>&1; then
      green "bwrap namespace isolation funcional"
    else
      yellow "bwrap namespace isolation falla"
      info "Ubuntu 24.04 fix: sudo apt install apparmor-profiles"
      info "  sudo ln -s /etc/apparmor.d/bwrap-userns-restrict /etc/apparmor.d/force-complain/bwrap-userns-restrict"
      info "  sudo apparmor_parser -r /etc/apparmor.d/bwrap-userns-restrict"
      WARNINGS=$((WARNINGS+1))
    fi
  else
    red "bubblewrap NO instalado -- sudo apt install bubblewrap socat"
    ERRORS=$((ERRORS+1))
  fi
fi

# Capa C
section "Capa C: Docker Sandboxes (opcional)"
if command -v docker &>/dev/null; then
  green "Docker disponible"
else
  yellow "Docker no instalado (Capa C inactiva -- no obligatoria)"
fi

# Policies
section "Policies (.opencode/sandbox-policies/)"
POLICY_DIR="$REPO_ROOT/.opencode/sandbox-policies"
for p in default-readonly overnight-sprint code-improvement-loop tech-research-agent pentesting; do
  if [[ -f "$POLICY_DIR/${p}.yaml" ]]; then
    green "${p}.yaml"
  else
    red "${p}.yaml FALTA"
    ERRORS=$((ERRORS+1))
  fi
done

# Resumen
section "Resumen"
if [[ $ERRORS -eq 0 && $WARNINGS -eq 0 ]]; then
  green "sandbox completamente operativo (3 capas activas)"
elif [[ $ERRORS -eq 0 ]]; then
  printf '\033[33m  Capa A funcional. %d advertencia(s) -- Capa B/C opcionales\033[0m\n' "$WARNINGS"
else
  red "$ERRORS error(es), $WARNINGS advertencia(s) -- sandbox NO completamente operativo"
  exit 1
fi
printf '\n'
info "Ref: docs/rules/domain/sandbox-os-policy.md"
