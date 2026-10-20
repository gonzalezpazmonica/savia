#!/bin/bash
set -uo pipefail
# block-infra-destructive.sh — Bloquea operaciones destructivas de infraestructura
# Usado por: infrastructure-agent (PreToolUse hook)
# Profile tier: security

LIB_DIR="$(dirname "${BASH_SOURCE[0]}")/lib"
if [[ -f "$LIB_DIR/profile-gate.sh" ]]; then
  # shellcheck source=/dev/null
  source "$LIB_DIR/profile-gate.sh" && profile_gate "security"
fi

# Read stdin with timeout to avoid hanging if no input arrives
# Uses timeout+cat to handle input that may lack trailing newline
INPUT=""
if INPUT=$(timeout 3 cat 2>/dev/null); then
  :
fi

# Parse command from JSON
# SE-453 S2: sin jq se degrada a un parseo con grep; si tampoco se puede evaluar, sale 2 (nunca 0 sin evaluar).
# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/lib/hook-input.sh"
hook_extract_command "$INPUT" || exit 2
COMMAND="$HOOK_COMMAND"

if [ -z "$COMMAND" ]; then
  exit 0
fi

# Bloquear terraform destroy sin excepción
if echo "$COMMAND" | grep -iE 'terraform\s+destroy' > /dev/null; then
  echo "BLOQUEADO: terraform destroy requiere aprobación humana directa. No ejecutar desde agente." >&2
  exit 2
fi

# Bloquear terraform apply en PRE/PRO (detectar por variable o directorio)
if echo "$COMMAND" | grep -iE 'terraform\s+apply' > /dev/null; then
  if echo "$COMMAND" | grep -iE '(^|[[:space:]/=])(pre|production|prod|staging)([[:space:]/=\.]|$)|(^|[[:space:]/=])pro([[:space:]/=\.]|$)' > /dev/null; then
    echo "BLOQUEADO: terraform apply en PRE/PRO requiere aprobación humana. Solo permitido en DEV." >&2
    exit 2
  fi
fi

# Bloquear eliminación de resource groups completos
if echo "$COMMAND" | grep -iE 'az\s+group\s+delete' > /dev/null; then
  echo "BLOQUEADO: Eliminación de Resource Group requiere aprobación humana." >&2
  exit 2
fi

# Bloquear aws cloudformation delete-stack
if echo "$COMMAND" | grep -iE 'aws\s+cloudformation\s+delete-stack' > /dev/null; then
  echo "BLOQUEADO: delete-stack requiere aprobación humana." >&2
  exit 2
fi

# Bloquear kubectl delete namespace
if echo "$COMMAND" | grep -iE 'kubectl\s+delete\s+namespace' > /dev/null; then
  echo "BLOQUEADO: Eliminación de namespace Kubernetes requiere aprobación humana." >&2
  exit 2
fi

exit 0
