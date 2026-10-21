#!/bin/bash
set -uo pipefail
# block-credential-leak.sh — Detecta credentials en comandos y ficheros
# Usado por: security-guardian (PreToolUse hook)
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

# SE-453 S2: sin jq se degrada a un parseo con grep; si tampoco se puede evaluar, sale 2 (nunca 0 sin evaluar).
# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/lib/hook-input.sh"
hook_extract_command "$INPUT" || exit 2
COMMAND="$HOOK_COMMAND"

if [ -z "$COMMAND" ]; then
  exit 0
fi

# Patrones de secrets comunes
SECRETS_PATTERN='(password|passwd|secret|api[_-]?key|token|bearer|auth[_-]?token|private[_-]?key|connection[_-]?string|client[_-]?secret)=["\x27]?[A-Za-z0-9+/=_-]{8,}'

# Detectar secrets hardcodeados en comandos
if echo "$COMMAND" | grep -iEo "$SECRETS_PATTERN" > /dev/null 2>&1; then
  echo "BLOQUEADO: Posible secret detectado en el comando. Usa variables de entorno o vault." >&2
  exit 2
fi

# Detectar AWS Access Keys (AKIA...)
if echo "$COMMAND" | grep -iE 'AKIA[0-9A-Z]{16}' > /dev/null 2>&1; then
  echo "BLOQUEADO: AWS Access Key detectada. Usa env var AWS_ACCESS_KEY_ID o vault." >&2
  exit 2
fi

# Detectar GitHub tokens (ghp_, ghs_, ghu_)
if echo "$COMMAND" | grep -iE '(ghp_|ghs_|ghu_|ghr_)[A-Za-z0-9]{36,}' > /dev/null 2>&1; then
  echo "BLOQUEADO: GitHub token detectado. Usa variables de entorno o vault." >&2
  exit 2
fi

# Detectar OpenAI keys (sk-)
if echo "$COMMAND" | grep -iE 'sk-[A-Za-z0-9]{48,}' > /dev/null 2>&1; then
  echo "BLOQUEADO: OpenAI API key detectada. Usa variables de entorno o vault." >&2
  exit 2
fi

# Detectar Azure connection strings
if echo "$COMMAND" | grep -iE '(DefaultEndpointsProtocol|AccountKey=|SharedAccessKey=)' > /dev/null 2>&1; then
  echo "BLOQUEADO: Azure connection string detectada. Usa Key Vault o variables de entorno." >&2
  exit 2
fi

# Detectar JWT tokens — formato base64url(header).base64url(payload).base64url(signature)
# JWTs reales empiezan SIEMPRE con eyJ (base64 de '{"' del JSON header/payload).
# Sin esta restricción, cualquier path Python como `importlib.util.spec_from_file_location` matchea.
# Falsos positivos típicos evitados: módulos Python con 3 dotted identifiers, paquetes Java/C#, versiones x.y.z.
if echo "$COMMAND" | grep -E 'eyJ[A-Za-z0-9_-]{10,}\.eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{20,}' > /dev/null 2>&1; then
  echo "BLOQUEADO: JWT token sospechoso detectado. Usa variables de entorno o vault." >&2
  exit 2
fi

# Detectar PAT hardcodeado (Azure DevOps / GitHub)
if echo "$COMMAND" | grep -iE '(pat|token)\s*[:=]\s*["\x27]?[a-z0-9]{40,}' > /dev/null 2>&1; then
  echo "BLOQUEADO: PAT/token hardcodeado detectado. Usa \$(cat \$PAT_FILE) o vault." >&2
  exit 2
fi

# Detectar private keys (PEM headers)
if echo "$COMMAND" | grep -E -- '-----BEGIN.*(RSA |EC |OPENSSH |PGP )?PRIVATE KEY-----' > /dev/null 2>&1; then
  echo "BLOQUEADO: Private key detectada. Usa vault o config.local/." >&2
  exit 2
fi

# Detectar Azure SAS tokens (sv=20XX)
if echo "$COMMAND" | grep -iE 'sv=20[0-9]{2}-[0-9]{2}-[0-9]{2}&s[a-z]=' > /dev/null 2>&1; then
  echo "BLOQUEADO: Azure SAS token detectado. Usa Key Vault o variables de entorno." >&2
  exit 2
fi

# Detectar Google API keys (AIza...)
if echo "$COMMAND" | grep -iE 'AIza[0-9A-Za-z_-]{35}' > /dev/null 2>&1; then
  echo "BLOQUEADO: Google API key detectada. Usa variables de entorno o vault." >&2
  exit 2
fi

# Detectar echo de secrets a ficheros
if echo "$COMMAND" | grep -iE 'echo\s+.*secret.*>>' > /dev/null 2>&1; then
  echo "BLOQUEADO: No escribir secrets en ficheros. Usa config.local/ o vault." >&2
  exit 2
fi

# Detectar Kubernetes service account tokens
if echo "$COMMAND" | grep -iE 'eyJhbGciOiJSUzI1NiI' > /dev/null 2>&1; then
  echo "BLOQUEADO: Kubernetes service account token detectado. Usa ServiceAccount o vault." >&2
  exit 2
fi

# Detectar HashiCorp Vault tokens (hvs., s.)
if echo "$COMMAND" | grep -iE '(hvs\.[a-zA-Z0-9_-]{24,}|s\.[a-zA-Z0-9]{24,})' > /dev/null 2>&1; then
  echo "BLOQUEADO: Vault token detectado. Usa VAULT_TOKEN env var." >&2
  exit 2
fi

# Detectar Docker registry credentials
if echo "$COMMAND" | grep -iE '(docker\s+login.*-p\s|--password\s)' > /dev/null 2>&1; then
  echo "BLOQUEADO: Docker password en línea de comandos. Usa --password-stdin o credential helper." >&2
  exit 2
fi

# Detectar Anthropic API keys (sk-ant-)
if echo "$COMMAND" | grep -iE 'sk-ant-[a-zA-Z0-9_-]{20,}' > /dev/null 2>&1; then
  echo "BLOQUEADO: Anthropic API key detectada. Usa ANTHROPIC_API_KEY env var." >&2
  exit 2
fi

# SPEC-SE-036 Slice 3: Detectar PAT-shaped strings en diff/comandos (40+ char hex/base64)
# Patrón: strings de 40+ chars alfanuméricos contiguos que no sean paths, hashes de git,
# ni checksums legítimos. Heurística conservadora: solo bloquea si aparece en contexto
# de asignación (=, :, Bearer, Authorization).
# Refs: SPEC-SE-036 AC-07, docs/rules/domain/savia-enterprise/agent-jwt-mint.md (Slice 3)
if echo "$COMMAND" | grep -iE '(=|:\s*|Bearer\s+|Authorization:\s+)[A-Za-z0-9+/]{40,}[=]{0,2}([^A-Za-z0-9+/]|$)' > /dev/null 2>&1; then
  # Excluir falsos positivos comunes: hashes git (40 hex), SHAs, base64 de ficheros legítimos
  # Solo bloquear si NO es un hash git puro (40 hex lowercase) ni un path
  if ! echo "$COMMAND" | grep -iE '(=|:\s*)[a-f0-9]{40}([^a-f0-9]|$)' > /dev/null 2>&1; then
    echo "BLOQUEADO [SPEC-SE-036]: PAT-shaped string detectada (40+ chars en contexto de autenticación)." >&2
    echo "Usa JWT efímero: jwt-mint.sh --key-stdin --scope <scope> o variable de entorno." >&2
    exit 2
  fi
fi

exit 0

# Detectar PAT-shaped strings (SPEC-SE-036 Slice 3)
# Patrón: strings de 40+ caracteres hex o base64 sin contexto de variable segura.
# Fundamento: Azure DevOps PATs son 52 chars base64; GitHub classic tokens son 40 chars hex.
# Solo aplica a comandos que no sean read/cat de rutas gitignored (evita falsos positivos).
# Changelog: SPEC-SE-036-S3 — añadido 2026-06-24
PAT_SHAPED_PATTERN='[A-Za-z0-9+/]{40,}'
# Exclude safe contexts: $(cat ...), env var assignments with $VAR, and base64 encode/decode ops
SAFE_CONTEXT_PATTERN='\$\(cat |\$\{[A-Z_]+\}|base64 (encode|decode|-d|-e|--decode)'
if echo "$COMMAND" | grep -Eo "$PAT_SHAPED_PATTERN" 2>/dev/null | grep -qv "AKIA\|ghp_\|ghs_\|ghu_\|sk-\|eyJ\|hvs\." 2>/dev/null; then
  # Candidate found — check it's not in a safe context
  if ! echo "$COMMAND" | grep -qE "$SAFE_CONTEXT_PATTERN" 2>/dev/null; then
    # Additional filter: exclude paths (contain / or .) and module names (dots between words)
    CANDIDATE=$(echo "$COMMAND" | grep -Eo "$PAT_SHAPED_PATTERN" | head -1)
    if [[ -n "$CANDIDATE" ]] && ! echo "$CANDIDATE" | grep -qE '\.|/' 2>/dev/null; then
      echo "BLOQUEADO: PAT-shaped string detectada (40+ chars). Usa SAVIA_AGENT_API_KEY o vault en lugar de credenciales inline." >&2
      exit 2
    fi
  fi
fi


exit 0
