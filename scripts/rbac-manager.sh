#!/usr/bin/env bash
# rbac-manager.sh — RBAC backend for Savia Enterprise multi-tenant
# SPEC: SPEC-SE-002 Multi-Tenant & RBAC
#
# Subcommands:
#   grant  <role> <user>          Add user to role (idempotent)
#   revoke <role> <user>          Remove user from role (no-op if absent)
#   list                          Print roles + commands + members
#   check  <user> <command>       Exit 0 if allowed, 1 if denied
#
# Common flags:
#   --tenant <slug>               Target tenant (default: resolved)
#   --project-dir <path>          Project root (default: CLAUDE_PROJECT_DIR or pwd)
#
# Writes tenants/<slug>/rbac.yaml atomically (temp + mv). Uses a minimal
# pure-bash YAML parser sufficient for the declared schema.

set -uo pipefail

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
TENANT=""
ACTION=""
ARGS=()

usage() {
  cat >&2 <<EOF
Usage:
  rbac-manager.sh grant  <role> <user> [--tenant <slug>]
  rbac-manager.sh revoke <role> <user> [--tenant <slug>]
  rbac-manager.sh list [--tenant <slug>]
  rbac-manager.sh check  <user> <command> [--tenant <slug>]
EOF
}

# Parse
while [[ $# -gt 0 ]]; do
  case "$1" in
    --tenant) TENANT="${2:-}"; shift 2 ;;
    --project-dir) PROJECT_DIR="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    grant|revoke|list|check)
      if [[ -z "$ACTION" ]]; then ACTION="$1"; shift
      else ARGS+=("$1"); shift
      fi
      ;;
    *) ARGS+=("$1"); shift ;;
  esac
done

if [[ -z "$ACTION" ]]; then
  usage; exit 2
fi

# Resolve tenant if not explicit
if [[ -z "$TENANT" ]]; then
  RESOLVER="$PROJECT_DIR/.claude/enterprise/hooks/tenant-resolver.sh"
  if [[ -f "$RESOLVER" ]]; then
    # shellcheck source=/dev/null
    source "$RESOLVER"
    TENANT=$(tenant_resolve)
  fi
fi

if [[ -z "$TENANT" ]]; then
  echo "rbac-manager: no active tenant (set \$SAVIA_TENANT or pass --tenant)" >&2
  exit 2
fi

# El tenant es un nombre de directorio: sin "/" ni "..", o rbac.yaml se escribe fuera de tenants/.
if [[ ! "$TENANT" =~ ^[A-Za-z0-9][A-Za-z0-9_-]*$ ]]; then
  echo "rbac-manager: tenant inválido (solo letras, cifras, '_' y '-')" >&2
  exit 2
fi

RBAC_FILE="$PROJECT_DIR/tenants/$TENANT/rbac.yaml"

# Roles y usuarios se guardan en una lista YAML separada por comas y se recorren por palabras:
# un espacio, una coma o un corchete en el valor crearía miembros que nadie pidió.
valid_role() { [[ "$1" =~ ^[A-Za-z_][A-Za-z0-9_-]*$ ]]; }
valid_user() { [[ "$1" =~ ^[A-Za-z0-9_.@-]+$ ]]; }

ensure_file() {
  if [[ ! -f "$RBAC_FILE" ]]; then
    mkdir -p "$(dirname "$RBAC_FILE")" 2>/dev/null || true
    cat > "$RBAC_FILE" <<'EOF'
roles:
  reader:
    commands: [sprint-status, help, memory-recall]
    members: []
  developer:
    inherits: reader
    commands: [spec-*, pbi-*, dev-session-*]
    members: []
  admin:
    inherits: developer
    commands: [tenant-*, rbac-*, backup-*]
    members: []
    gates: [confirm_destructive]
EOF
  fi
}

# --- Minimal YAML parser for our schema -------------------------------------
# Supports:
#   roles:
#     <role>:
#       inherits: <name>
#       commands: [a, b, c]
#       members: [x, y]
#       gates: [g1]
# Emits lines on stdout: "role|inherits|commands_csv|members_csv"
parse_yaml() {
  local file="$1"
  awk '
    function trim(s) { sub(/^[ \t]+/,"",s); sub(/[ \t]+$/,"",s); return s }
    function extract_list(s,   a, out, i) {
      gsub(/^\[[ \t]*/,"",s); gsub(/[ \t]*\][ \t]*$/,"",s)
      return s
    }
    /^roles:/ { in_roles=1; next }
    in_roles && /^  [A-Za-z_][A-Za-z0-9_-]*:/ {
      if (role != "") print role "|" inh "|" cmds "|" mems
      role=$1; sub(/:$/,"",role)
      inh=""; cmds=""; mems=""
      next
    }
    in_roles && /^    inherits:/ {
      inh=trim($0); sub(/^inherits:[ \t]*/,"",inh); gsub(/"/,"",inh); gsub(/'\''/,"",inh)
      next
    }
    in_roles && /^    commands:/ {
      line=$0; sub(/^[ \t]*commands:[ \t]*/,"",line)
      cmds=extract_list(line)
      next
    }
    in_roles && /^    members:/ {
      line=$0; sub(/^[ \t]*members:[ \t]*/,"",line)
      mems=extract_list(line)
      next
    }
    in_roles && /^[A-Za-z]/ && !/^roles:/ { in_roles=0 }
    END {
      if (role != "") print role "|" inh "|" cmds "|" mems
    }
  ' "$file"
}

# Rewrite the members list of a given role in-place using awk + atomic mv
rewrite_members() {
  local role="$1"; shift
  local new_members="$*"   # space-separated
  local tmp="$RBAC_FILE.tmp.$$"
  awk -v role="$role" -v mems="$new_members" '
    BEGIN {
      n=split(mems, a, " "); out="["
      for (i=1;i<=n;i++) { if (a[i]=="") continue; if (out!="[") out=out ", "; out=out a[i] }
      out=out "]"
    }
    {
      if ($0 ~ "^  "role":$") { inrole=1; print; next }
      if (inrole && $0 ~ /^  [A-Za-z_][A-Za-z0-9_-]*:$/ && $0 !~ "^  "role":$") { inrole=0 }
      if (inrole && $0 ~ /^    members:/) { print "    members: " out; next }
      print
    }
  ' "$RBAC_FILE" > "$tmp" || { rm -f "$tmp"; return 1; }

  # If the role had no members: line at all, append one
  if ! grep -A3 "^  $role:" "$tmp" 2>/dev/null | grep -q '^    members:'; then
    # Insert after the role line
    local tmp2="$tmp.2"
    awk -v role="$role" -v mems="$new_members" '
      BEGIN {
        n=split(mems, a, " "); out="["
        for (i=1;i<=n;i++) { if (a[i]=="") continue; if (out!="[") out=out ", "; out=out a[i] }
        out=out "]"
      }
      { print
        if ($0 ~ "^  "role":$") { print "    members: " out }
      }
    ' "$tmp" > "$tmp2" && mv "$tmp2" "$tmp"
  fi

  mv "$tmp" "$RBAC_FILE"
}

get_members() {
  local role="$1"
  parse_yaml "$RBAC_FILE" | awk -F'|' -v r="$role" '$1==r {print $4}' | tr ',' ' ' | tr -s ' '
}

cmd_grant() {
  local role="$1" user="$2"
  ensure_file
  local current
  current=$(get_members "$role")
  # Idempotent check
  for m in $current; do
    [[ "$m" == "$user" ]] && return 0
  done
  local updated="$current $user"
  rewrite_members "$role" "$updated"
}

cmd_revoke() {
  local role="$1" user="$2"
  ensure_file
  local current new=""
  current=$(get_members "$role")
  for m in $current; do
    [[ "$m" == "$user" ]] && continue
    new="$new $m"
  done
  rewrite_members "$role" "$new"
}

cmd_list() {
  ensure_file
  echo "Tenant: $TENANT"
  echo "File:   $RBAC_FILE"
  echo
  parse_yaml "$RBAC_FILE" | while IFS='|' read -r role inh cmds mems; do
    [[ -z "$role" ]] && continue
    echo "- role: $role"
    [[ -n "$inh" ]] && echo "    inherits: $inh"
    echo "    commands: [$cmds]"
    echo "    members:  [$mems]"
  done
}

# Recursively collect commands for a role (walks inherits chain)
collect_commands() {
  local role="$1"
  local seen="${2:-}"
  case " $seen " in *" $role "*) return 0 ;; esac
  seen="$seen $role"
  parse_yaml "$RBAC_FILE" | awk -F'|' -v r="$role" '$1==r { print $2"|"$3 }' | while IFS='|' read -r inh cmds; do
    if [[ -n "$inh" ]]; then
      collect_commands "$inh" "$seen"
    fi
    printf '%s\n' "$cmds"
  done
}

# Glob match: "spec-*" matches "spec-generate"
glob_match() {
  local pattern="$1" value="$2"
  case "$value" in
    $pattern) return 0 ;;
    *) return 1 ;;
  esac
}

cmd_check() {
  local user="$1" command="$2"
  ensure_file
  # Find roles that include this user
  local roles=""
  parse_yaml "$RBAC_FILE" | while IFS='|' read -r role inh cmds mems; do
    [[ -z "$role" ]] && continue
    for m in $(printf '%s' "$mems" | tr ',' ' '); do
      m=$(printf '%s' "$m" | tr -d ' ')
      if [[ "$m" == "$user" ]]; then
        echo "$role"
      fi
    done
  done > "$RBAC_FILE.roles.$$"
  roles=$(cat "$RBAC_FILE.roles.$$" 2>/dev/null)
  rm -f "$RBAC_FILE.roles.$$"

  [[ -z "$roles" ]] && return 1

  local allowed=""
  for r in $roles; do
    allowed="$allowed $(collect_commands "$r" | tr ',' ' ')"
  done

  for cmd in $allowed; do
    cmd=$(printf '%s' "$cmd" | tr -d ' ')
    [[ -z "$cmd" ]] && continue
    if glob_match "$cmd" "$command"; then
      return 0
    fi
  done
  return 1
}

case "$ACTION" in
  grant)
    [[ ${#ARGS[@]} -ge 2 ]] || { usage; exit 2; }
    valid_role "${ARGS[0]}" && valid_user "${ARGS[1]}" || { echo "rbac-manager: rol o usuario inválido" >&2; exit 2; }
    cmd_grant "${ARGS[0]}" "${ARGS[1]}"
    ;;
  revoke)
    [[ ${#ARGS[@]} -ge 2 ]] || { usage; exit 2; }
    valid_role "${ARGS[0]}" && valid_user "${ARGS[1]}" || { echo "rbac-manager: rol o usuario inválido" >&2; exit 2; }
    cmd_revoke "${ARGS[0]}" "${ARGS[1]}"
    ;;
  list)
    cmd_list
    ;;
  check)
    [[ ${#ARGS[@]} -ge 2 ]] || { usage; exit 2; }
    # Usuario no válido nunca puede ser miembro: se deniega sin leer el fichero (fail-closed).
    valid_user "${ARGS[0]}" || { echo "DENY"; exit 1; }
    if cmd_check "${ARGS[0]}" "${ARGS[1]}"; then
      echo "ALLOW"; exit 0
    else
      echo "DENY"; exit 1
    fi
    ;;
  *) usage; exit 2 ;;
esac
