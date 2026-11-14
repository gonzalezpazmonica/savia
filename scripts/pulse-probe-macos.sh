#!/usr/bin/env bash
# pulse-probe-macos.sh — SE-518 S0 medida (a) y (b): ¿puede Pulse correr como servicio de usuario
# en un Mac sin administrador, y qué modos (observar, proponer, actuar) permite ese equipo?
#
# Sin sudo, sin escribir fuera de un directorio temporal propio y sin red, salvo --active, que
# carga y descarga un servicio de usuario de prueba (explícito, reversible).
# Compatible con el bash 3.2 que trae macOS: nada de `declare -A`, `mapfile`, `flock` ni `${x,,}`.
#
# Uso:
#   pulse-probe-macos.sh --plan                 imprime el procedimiento; no ejecuta nada
#   pulse-probe-macos.sh --simulate <escenario> prueba seca: veredicto sobre observaciones simuladas
#   pulse-probe-macos.sh                        sonda pasiva en este equipo (solo lectura)
#   pulse-probe-macos.sh --active               además carga y descarga un servicio de prueba
#   opciones: --soul-runtime <ruta>  cuenta el runtime de Soul como intérprete alternativo
# Escenarios: ok-activo, pasivo, python-viejo, shim-clt, sin-motor, bloquea-servicio, sin-forge
# Salida: líneas «CHECK nombre ESTADO detalle», «MODO m ESTADO motivo» y «VEREDICTO ...».
# Salida de proceso: 0 observar PERMITIDO · 1 observar NO_PERMITIDO · 2 NO_DETERMINADO ·
#                    3 NO_APLICA (no es macOS) · 64 uso incorrecto.
# Fail-closed: un dato que no se puede observar es UNKNOWN y nunca cuenta como PASS.
set -uo pipefail

MODE_RUN=real; SCEN=""; ACTIVE=0; SOUL_RT=""
while [ $# -gt 0 ]; do
  case "$1" in
    --plan) MODE_RUN=plan ;;
    --simulate) MODE_RUN=sim; SCEN="${2:-}"; [ -n "$SCEN" ] || { echo "falta el escenario" >&2; exit 64; }; shift ;;
    --active) ACTIVE=1 ;;
    --soul-runtime) SOUL_RT="${2:-}"; [ -n "$SOUL_RT" ] || { echo "falta la ruta" >&2; exit 64; }; shift ;;
    -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
    *) echo "opción desconocida: $1" >&2; exit 64 ;;
  esac
  shift
done

NAMES=(); STATES=(); DETAILS=(); TMP_PROBE=""
add() { NAMES+=("$1"); STATES+=("$2"); DETAILS+=("$3"); }
state_of() { local i=0; while [ $i -lt ${#NAMES[@]} ]; do [ "${NAMES[$i]}" = "$1" ] && { echo "${STATES[$i]}"; return; }; i=$((i + 1)); done; echo UNKNOWN; }

plan() {
cat <<'EOF'
Procedimiento en un Mac, con tu usuario normal, sin sudo y desde Terminal (no por ssh):
  1. bash scripts/pulse-probe-macos.sh            sonda pasiva, solo lectura.
  2. bash scripts/pulse-probe-macos.sh --active   carga y descarga un servicio de usuario de prueba.
Qué mira cada comprobación (órdenes que ejecuta en el Mac):
  interprete          xcode-select -p; command -v python3; python3 -c 'import sys; ...'  (≥ 3.9)
  git                 xcode-select -p; command -v git
  servicio_escritura  ~/Library/LaunchAgents escribible; plutil -lint de un plist de ejemplo
  servicio_carga      launchctl print gui/<uid>; con --active: launchctl bootstrap y bootout de un plist de prueba
  bloqueo             mkdir atómico en un directorio temporal (sin flock)
  forge_cli           command -v gh o az
  motor               command -v claude, opencode o codex
  push_prueba         nunca se hace aquí: lo confirma la persona con un push a una rama agent/*
Cómo se leen los modos:
  observar  necesita interprete, git, servicio_escritura, servicio_carga, bloqueo y forge_cli
  proponer  observar + motor
  actuar    proponer + push_prueba
  PERMITIDO si todo lo necesario es PASS; NO_PERMITIDO si algo es FAIL; NO_DETERMINADO si nada
  falla pero algo es UNKNOWN. El modo inicial no cambia: sigue siendo observar.
EOF
}

simulate() {
  # Observaciones inventadas de un Mac; no se toca el equipo real.
  local py="PASS" gt="PASS" se="PASS" sc="PASS" lk="PASS" fg="PASS" mo="PASS"
  case "$SCEN" in
    ok-activo) ;;
    pasivo) sc="UNKNOWN" ;;
    python-viejo) py="FAIL" ;;
    shim-clt) py="UNKNOWN"; gt="UNKNOWN" ;;
    sin-motor) mo="FAIL" ;;
    bloquea-servicio) sc="FAIL" ;;
    sin-forge) fg="FAIL" ;;
    *) echo "escenario desconocido: $SCEN" >&2; exit 64 ;;
  esac
  add interprete "$py" "simulado"; add git "$gt" "simulado"
  add servicio_escritura "$se" "simulado"; add servicio_carga "$sc" "simulado"
  add bloqueo "$lk" "simulado"; add forge_cli "$fg" "simulado"
  add motor "$mo" "simulado"; add push_prueba UNKNOWN "lo confirma la persona con un push de prueba"
}

clt_ok() { xcode-select -p >/dev/null 2>&1; }
is_shim() { case "$(command -v "$1" 2>/dev/null)" in /usr/bin/"$1") ! clt_ok ;; *) return 1 ;; esac; }

probe_python() {
  if [ -n "$SOUL_RT" ] && [ -x "$SOUL_RT" ]; then add interprete PASS "runtime de Soul: existe y es ejecutable (si sirve para el núcleo se decide en S1)"; return; fi
  if ! command -v python3 >/dev/null 2>&1; then add interprete FAIL "no hay python3 ni runtime de Soul"; return; fi
  if is_shim python3; then add interprete UNKNOWN "python3 es el atajo de las Command Line Tools sin instalar: ejecutarlo abriría el instalador"; return; fi
  local v maj min
  v="$(python3 -c 'import sys; print("%d.%d" % sys.version_info[:2])' 2>/dev/null)" || v=""
  case "$v" in [0-9]*.[0-9]*) ;; *) add interprete UNKNOWN "no pude leer la versión de python3"; return ;; esac
  maj="${v%%.*}"; min="${v##*.}"
  if [ "$maj" -gt 3 ] || { [ "$maj" -eq 3 ] && [ "$min" -ge 9 ]; }; then add interprete PASS "python $v"; else add interprete FAIL "python $v < 3.9"; fi
}

probe_git() {
  if ! command -v git >/dev/null 2>&1; then add git FAIL "no hay git"; return; fi
  if is_shim git; then add git UNKNOWN "git es el atajo de las Command Line Tools sin instalar"; return; fi
  add git PASS "$(command -v git)"
}

probe_service() {
  local la="$HOME/Library/LaunchAgents" tmp="$1" plist
  if [ -d "$la" ] && [ -w "$la" ]; then :
  elif [ ! -e "$la" ] && [ -d "$HOME/Library" ] && [ -w "$HOME/Library" ]; then :
  else add servicio_escritura FAIL "no puedo escribir en $la"; return; fi
  plist="$tmp/ejemplo.plist"
  printf '%s\n' '<?xml version="1.0" encoding="UTF-8"?>' \
    '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">' \
    '<plist version="1.0"><dict><key>Label</key><string>local.pulse.probe</string>' \
    '<key>ProgramArguments</key><array><string>/usr/bin/true</string></array></dict></plist>' > "$plist"
  if ! command -v plutil >/dev/null 2>&1; then add servicio_escritura UNKNOWN "no hay plutil para validar el plist"; return; fi
  if plutil -lint "$plist" >/dev/null 2>&1; then add servicio_escritura PASS "$la escribible; plist válido"; else add servicio_escritura FAIL "plutil rechaza el plist de ejemplo"; fi
  if ! command -v launchctl >/dev/null 2>&1; then add servicio_carga FAIL "no hay launchctl"; return; fi
  local uid; uid="$(id -u)"
  if ! launchctl print "gui/$uid" >/dev/null 2>&1; then add servicio_carga UNKNOWN "sin sesión gráfica (¿ssh?): ejecútalo desde Terminal en el propio Mac"; return; fi
  if [ "$ACTIVE" -ne 1 ]; then add servicio_carga UNKNOWN "pasivo: usa --active para cargar un servicio de prueba"; return; fi
  active_cycle "$tmp" "$uid"
}

active_cycle() {
  local tmp="$1" uid="$2" label="local.pulse.probe.$$" marker plist="$HOME/Library/LaunchAgents/local.pulse.probe.$$.plist" i=0 err
  marker="$tmp/marca"
  mkdir -p "$HOME/Library/LaunchAgents" 2>/dev/null
  printf '%s\n' '<?xml version="1.0" encoding="UTF-8"?>' \
    '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">' \
    "<plist version=\"1.0\"><dict><key>Label</key><string>$label</string>" \
    "<key>ProgramArguments</key><array><string>/usr/bin/touch</string><string>$marker</string></array>" \
    '<key>RunAtLoad</key><true/></dict></plist>' > "$plist"
  if ! err="$(launchctl bootstrap "gui/$uid" "$plist" 2>&1)"; then
    rm -f "$plist"; add servicio_carga FAIL "launchctl bootstrap rechazado: $err"; return
  fi
  while [ $i -lt 10 ] && [ ! -e "$marker" ]; do sleep 1; i=$((i + 1)); done
  launchctl bootout "gui/$uid/$label" >/dev/null 2>&1; rm -f "$plist"
  if [ -e "$marker" ]; then add servicio_carga PASS "servicio de usuario cargado, ejecutado y descargado sin sudo"
  else add servicio_carga FAIL "cargó pero no se ejecutó en 10 s"; fi
}

probe_lock() {
  local d="$1/candado"
  if mkdir "$d" 2>/dev/null && ! mkdir "$d" 2>/dev/null; then rmdir "$d"; add bloqueo PASS "mkdir atómico (sin flock)"
  else rmdir "$d" 2>/dev/null; add bloqueo FAIL "mkdir no da exclusión mutua"; fi
}

probe_real() {
  TMP_PROBE="$(mktemp -d "${TMPDIR:-/tmp}/pulse-probe.XXXXXX")" || { echo "sin directorio temporal" >&2; exit 64; }
  trap 'rm -rf "$TMP_PROBE"' EXIT
  probe_python; probe_git; probe_service "$TMP_PROBE"; probe_lock "$TMP_PROBE"
  if command -v gh >/dev/null 2>&1 || command -v az >/dev/null 2>&1; then add forge_cli PASS "gh o az presente"; else add forge_cli FAIL "ni gh ni az"; fi
  if command -v claude >/dev/null 2>&1 || command -v opencode >/dev/null 2>&1 || command -v codex >/dev/null 2>&1; then add motor PASS "hay un motor de inferencia en PATH"; else add motor FAIL "ninguno (válido: equivale a observar)"; fi
  add push_prueba UNKNOWN "lo confirma la persona con un push de prueba a una rama agent/*"
}

mode_verdict() {  # mode_verdict <modo> <checks…> → imprime ESTADO motivo
  local m="$1" c s unk="" bad=""; shift
  for c in "$@"; do
    s="$(state_of "$c")"
    case "$s" in PASS) ;; FAIL) bad="$bad $c" ;; *) unk="$unk $c" ;; esac
  done
  if [ -n "$bad" ]; then echo "NO_PERMITIDO falla:${bad}"
  elif [ -n "$unk" ]; then echo "NO_DETERMINADO sin dato:${unk}"
  else echo "PERMITIDO todo lo necesario en PASS"; fi
}

emit() {
  local i=0 o p a
  while [ $i -lt ${#NAMES[@]} ]; do echo "CHECK ${NAMES[$i]} ${STATES[$i]} ${DETAILS[$i]}"; i=$((i + 1)); done
  local base="interprete git servicio_escritura servicio_carga bloqueo forge_cli"
  # shellcheck disable=SC2086
  o="$(mode_verdict observar $base)"
  # shellcheck disable=SC2086
  p="$(mode_verdict proponer $base motor)"
  # shellcheck disable=SC2086
  a="$(mode_verdict actuar $base motor push_prueba)"
  echo "MODO observar $o"; echo "MODO proponer $p"; echo "MODO actuar $a"
  case "$o" in
    PERMITIDO*) echo "VEREDICTO servicio de usuario viable: C sigue en pie en este equipo"; return 0 ;;
    NO_PERMITIDO*)
      if [ "$(state_of servicio_escritura)" = FAIL ] || [ "$(state_of servicio_carga)" = FAIL ]; then
        echo "VEREDICTO el equipo no admite un servicio de usuario ni para observar: A (contratos sobre el bucle actual) puede bastar"
      else
        echo "VEREDICTO falta un requisito instalable (ver CHECK en FAIL): se arregla sin cambiar de camino; no decide entre C y A"
      fi
      return 1 ;;
    *) echo "VEREDICTO sin datos suficientes: no se decide entre C y A"; return 2 ;;
  esac
}

case "$MODE_RUN" in
  plan) plan; exit 0 ;;
  sim) simulate ;;
  real)
    if [ "$(uname -s 2>/dev/null)" != "Darwin" ]; then
      echo "VEREDICTO NO_APLICA: esto no es macOS (usa --simulate para la prueba seca)"; exit 3
    fi
    probe_real ;;
esac
emit
exit $?
