#!/usr/bin/env bash
# scripts/lib/overnight-authority.sh — SE-472 S1: vigencia de la autoridad antes de cada tarea nocturna
#
# Se carga con `source` desde scripts/overnight-sprint-loop.sh.
#
#   check_authority  → exit 0 = el bucle puede arrancar la tarea siguiente
#                      exit 1 = NO arranca; $AUTHORITY_REASON dice por qué:
#                               authority_expired | authority_invalid | authority_missing
#
# Fuente de la autoridad: grants existentes (scripts/operator-grant.sh, SE-343), sin
# formato ni almacén nuevos. Scope: OVERNIGHT_GRANT_SCOPE (por defecto
# autonomy:overnight-sprint, el scope que operator-grant.sh ya acepta para esta skill;
# la spec proponía autonomy:overnight, que operator-grant.sh rechaza como scope inválido).
#
# Fail-closed: "no se pudo comprobar" nunca es "autorizado". Cualquier salida distinta
# de 0 del comprobador, o su ausencia, detiene las tareas nuevas.
#
# OVERNIGHT_GRANT_SCOPE solo admite scopes de esta skill (^autonomy:overnight[a-z0-9-]*$):
# el grant de otra skill (p. ej. autonomy:code-improvement-loop) no autoriza la noche.
# Un valor fuera del patrón (o con saltos de línea) es authority_invalid sin llamar al
# comprobador, y nunca se copia tal cual al audit log.
#
# OVERNIGHT_REQUIRE_GRANT: sin la variable vale true. Solo el valor exacto "false"
# desactiva el control (decisión explícita de la operadora en su configuración local);
# cualquier otro valor ("0", "no", vacío…) lo deja activo.
#
# Ref: SE-472, SE-343, docs/rules/domain/autonomous-safety.md

OVERNIGHT_GRANT_SCOPE_DEFAULT="autonomy:overnight-sprint"
AUTHORITY_REASON=""

# 0 si el control está desactivado de forma explícita, 1 en cualquier otro caso.
authority_check_disabled() {
  [[ "${OVERNIGHT_REQUIRE_GRANT-true}" == "false" ]]
}

# Escribe el scope efectivo en stdout. Sale con 1 (y escribe "<rechazado>") si el
# override no pertenece a esta skill.
authority_scope() {
  local scope="${OVERNIGHT_GRANT_SCOPE:-$OVERNIGHT_GRANT_SCOPE_DEFAULT}"
  if [[ "$scope" =~ ^autonomy:overnight[a-z0-9-]*$ ]]; then
    printf '%s' "$scope"
  else
    printf '<rechazado>'
    return 1
  fi
}

# 0 si se usa un scope distinto del de por defecto (válido o no): debe quedar rastro.
authority_scope_overridden() {
  [[ -n "${OVERNIGHT_GRANT_SCOPE:-}" && "$OVERNIGHT_GRANT_SCOPE" != "$OVERNIGHT_GRANT_SCOPE_DEFAULT" ]]
}

check_authority() {
  AUTHORITY_REASON=""
  authority_check_disabled && return 0

  local scope
  if ! scope="$(authority_scope)"; then
    AUTHORITY_REASON="authority_invalid"
    return 1
  fi
  local grant_script="${SCRIPT_DIR:-}/operator-grant.sh"

  local rc=0
  bash "$grant_script" check --scope "$scope" >/dev/null 2>&1 || rc=$?

  case "$rc" in
    0) return 0 ;;
    1) AUTHORITY_REASON="authority_expired" ;;
    3) AUTHORITY_REASON="authority_missing" ;;
    *) AUTHORITY_REASON="authority_invalid" ;;   # 2, 126, 127, señales…
  esac
  return 1
}
