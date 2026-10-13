#!/usr/bin/env bash
# dome-guard.sh — Guard de cúpulas en el motor (SE-436 S5, D30-4). PreToolUse.
# Matcher: Edit|Write|MultiEdit|NotebookEdit|Read|Grep|Glob|LS|Bash
#
# Escritura del motor dentro de una cúpula del registro fusionado de SaviaVaults → ask
# («Usa una propuesta: Guardar como nota»). Lectura de una cúpula N2+ no adjunta con
# proveedor de nube → ask; N3+ → deny. Fuera de las cúpulas no decide nada.
#
# DUAL_BINDING: la misma decisión la toma la regla nativa de savia-gates para OpenCode
# (scripts/opencode-plugin/savia-gates/lib/dome-guard.ts). Paridad:
# tests/hooks/test-dome-guard-parity.bats. Núcleo: lib/dome_guard.py.
#
# Contexto de sesión: quien ejecuta el hook puede añadir al payload
# `dome_context: {cloud, attached[], granted[]}`; sin él, nube y sin adjuntos (falla cerrado).
# Bash: las rutas se resuelven contra `workdir` (o cwd/directory/dir/working_directory/workingDir) si
# lo trae la llamada; un directorio de trabajo dentro de una cúpula hace que toda orden la toque.
# El registro (base y .local) también está protegido: el motor no lo escribe.
# Delegación: SAVIA_DOME_GUARD=space (Savia Space decide con su guard nativo) o
# SAVIA_GATES_PIN=1 (modo mediado, rige SE-434) → el hook no decide.
# Registro: SAVIA_SPACE_DOMES_FILE (si falta el fichero, ilegible) o
# $CLAUDE_PROJECT_DIR/projects/savia-vaults/savia-vaults.domes.json (+ .local.json).
# Límite conocido: es un guard léxico. Una ruta montada en tiempo de ejecución dentro de un guion
# (`python3 -c "open('gall'+'inero/a','w')"`, variables calculadas) no se ve. La defensa en profundidad
# es el sandbox del motor o el modo mediado de Savia Space (SE-434), no este hook.
set -uo pipefail

LIB_DIR="$(dirname "${BASH_SOURCE[0]}")/lib"
if [[ -f "$LIB_DIR/profile-gate.sh" ]]; then
  # shellcheck source=/dev/null
  source "$LIB_DIR/profile-gate.sh" && profile_gate "security"
fi

[[ "${SAVIA_DOME_GUARD:-}" == "space" || "${SAVIA_GATES_PIN:-}" == "1" ]] && exit 0

ROOT="${CLAUDE_PROJECT_DIR:-${SAVIA_WORKSPACE_DIR:-$(pwd)}}"
BASE="$ROOT/projects/savia-vaults/savia-vaults.domes.json"

# 0 solo si el fichero no existe de verdad (ENOENT): `-e` también es falso con un directorio sin permisos,
# así que el ancestro existente más cercano tiene que ser un directorio que se pueda recorrer. Un enlace roto,
# un componente que no es directorio o un directorio cerrado no son «no hay registro»: decide el núcleo.
absent() {
  local f="$1" d
  [[ -e "$f" || -L "$f" ]] && return 1
  d=$(dirname -- "$f")
  while [[ ! -e "$d" && ! -L "$d" && "$d" != "/" && "$d" != "." ]]; do d=$(dirname -- "$d"); done
  [[ -d "$d" && -x "$d" ]]
}

# Camino rápido: sin registro no hay cúpulas que proteger.
if [[ -z "${SAVIA_SPACE_DOMES_FILE:-}" ]] && absent "$BASE" && absent "${BASE%.json}.local.json"; then
  exit 0
fi

# Con registro, un payload vacío o ilegible no pasa: el núcleo pregunta (no se sabe qué toca la llamada).
# El núcleo lee el payload directamente de stdin (sys.stdin.buffer.read): pasarlo por una variable de bash quitaría los NUL y los
# saltos de línea finales, y una llamada ilegible podría volverse legible.

ask() {
  local reason="$1"
  reason="${reason//\\/\\\\}"; reason="${reason//\"/\\\"}"
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"Guard de cúpulas: %s"}}\n' "$reason"
  exit 0
}

# Falla cerrado: con un registro presente, sin núcleo no se sabe qué toca la orden.
command -v python3 >/dev/null 2>&1 || ask "python3 no disponible; no se puede comprobar si la orden toca una cúpula"
if ! OUT=$(timeout 10 python3 "$LIB_DIR/dome_guard.py" --root "$ROOT" --hook 2>/dev/null); then
  ask "el guard falló; no se puede comprobar si la orden toca una cúpula"
fi
[[ -n "$OUT" ]] && printf '%s\n' "$OUT"
exit 0
