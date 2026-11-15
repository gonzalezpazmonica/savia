#!/usr/bin/env bats
# SE-518 S0: prototipo de Pulse/Soul, sonda de macOS sin administrador y medidas.
# Comprueba que el prototipo enseña lo que prometen las escenas E1–E5, E7, E8 y E10 en lenguaje
# llano (D3: «observar» por defecto; D7: sin reanudar por chat), que la sonda decide con la
# regla fail-closed (UNKNOWN nunca es PASS) y que el documento de medidas suma lo que dice.
# La sonda se prueba en Linux con escenarios simulados y con órdenes de macOS simuladas
# (uname, python3, launchctl…); un Mac real queda fuera y el documento lo dice.
# Ref: docs/specs/SE-518-pulse-latido.spec.md (slice S0)
# Ref: docs/specs/assets/prototipo-SE-518-medidas.md

setup() {
  cd "$BATS_TEST_DIRNAME/.."
  SPEC="docs/specs/SE-518-pulse-latido.spec.md"
  PROTO="docs/specs/assets/SE-518-prototipo.html"
  MED="docs/specs/assets/prototipo-SE-518-medidas.md"
  PROBE="scripts/pulse-probe-macos.sh"
}

# ── Prototipo ────────────────────────────────────────────────────────────────

@test "prototipo: la spec lo apunta y sus estados coinciden con los del HTML" {
  run python3 - "$SPEC" "$PROTO" <<'PY'
import re, sys
spec = open(sys.argv[1], encoding="utf-8").read()
src = open(sys.argv[2], encoding="utf-8").read()
m = re.search(r"prototipo: `([^`]+)` \(estados `\?s=([a-z|]+)`\)", spec)
assert m and m.group(1) == "docs/specs/assets/SE-518-prototipo.html", "la spec no apunta al prototipo"
wanted = m.group(2).split("|")
om = re.search(r"const order=\[([^\]]*)\]", src)
order = re.findall(r'"(\w+)"', om.group(1)) if om else []
assert order == wanted, f"{order} != {wanted}"
for k in wanted:
    assert re.search(r"\b%s:\{t:" % re.escape(k), src), f"falta el estado {k}"
print("ok", len(wanted))
PY
  [ "$status" -eq 0 ]
  [[ "$output" == "ok 9" ]]
}

@test "prototipo: sin jerga interna en el texto visible" {
  run python3 - "$PROTO" <<'PY'
import re, sys
src = open(sys.argv[1], encoding="utf-8").read()
visible = re.sub(r"<style>.*?</style>", "", src, flags=re.S)
visible = re.sub(r"<[^>]+>", " ", visible)
bad = [p for p in [r"\bSE-\d+", r"\bAC-\d+", r"\bD\d\b", r"\bledger\b", r"\btiers?\b", r"\bforge\b",
                   r"\blatido\b", r"\bSAM\b", r"\bWIP\b", r"\btokens?\b", r"\bflock\b",
                   r"\bsystemd\b", r"\blaunchd\b", r"\bLaunchAgent\b", r"\bsudo\b", r"\bfail-closed\b",
                   r"\bidempot", r"\bcanal de control\b"]
       if re.search(p, visible, re.I)]
assert not bad, f"jerga visible: {bad}"
print("limpio")
PY
  [ "$status" -eq 0 ]
  [[ "$output" == "limpio" ]]
}

@test "prototipo E1: la tarjeta de la mañana tiene como mucho tres asuntos, cada uno con su porqué" {
  run python3 - "$PROTO" <<'PY'
import re, sys
src = open(sys.argv[1], encoding="utf-8").read()
m = re.search(r"manana:\{t:.*?\n(.*?)`\},\ntermina:", src, re.S)
assert m, "no encuentro el estado de la mañana"
estado = m.group(1)
asuntos = re.findall(r"<details.*?</details>", estado, re.S)
assert 1 <= len(asuntos) <= 3, f"{len(asuntos)} asuntos"
for a in asuntos:
    assert "<b>Por qué:</b>" in a, "un asunto sin su porqué"
print(len(asuntos))
PY
  [ "$status" -eq 0 ]
  [[ "$output" == "3" ]]
}

@test "prototipo E3: reanudar no se ofrece como botón y el chat no reanuda" {
  run python3 - "$PROTO" <<'PY'
import re, sys
src = open(sys.argv[1], encoding="utf-8").read()
m = re.search(r"freno:\{t:.*?\n(.*?)`\},\nvolante:", src, re.S)
assert m, "no encuentro el estado del freno"
e = m.group(1)
botones = re.findall(r"<button[^>]*>(.*?)</button>", e, re.S)
assert botones == ["Para todo"], f"botones del freno: {botones}"
assert not any("reanud" in b.lower() for b in botones), "hay un botón de reanudar"
assert re.search(r'<div class="user"><p>reanuda</p></div>\s*<div class="bot"><p>Eso no lo puedo hacer desde el chat', e), "falta el rechazo del chat"
assert "Ningún agente ni programa puede reanudar" in e, "falta el rechazo a otro agente"
assert "desde tu ordenador" in e and "aprobación formal" in e
print("ok")
PY
  [ "$status" -eq 0 ]
  [[ "$output" == "ok" ]]
}

@test "prototipo E4: el volante dice qué cambia antes de aplicar y rechaza ampliar" {
  run python3 - "$PROTO" <<'PY'
import re, sys
src = open(sys.argv[1], encoding="utf-8").read()
m = re.search(r"volante:\{t:.*?\n(.*?)`\},\nred:", src, re.S)
e = m.group(1)
i_cambia = e.index("lo que cambiaría")
i_aplicar = e.index(">Aplicar<")
assert i_cambia < i_aplicar, "el botón aparece antes de decir qué cambia"
assert "caduca" in e
assert re.search(r"Sube el presupuesto.*?Eso no puedo\. Redirigir solo quita o aplaza, nunca da más permiso", e, re.S)
print("ok")
PY
  [ "$status" -eq 0 ]
  [[ "$output" == "ok" ]]
}

@test "prototipo E7: la tarjeta de decisión lleva las cinco cosas y no da permiso de fusión" {
  run python3 - "$PROTO" <<'PY'
import re, sys
src = open(sys.argv[1], encoding="utf-8").read()
m = re.search(r"decision:\{t:.*?\n(.*?)`\},\ninstalacion:", src, re.S)
e = m.group(1)
card = e.split("<h2>De noche</h2>")[0]
assert re.search(r"<h3>¿Fusionas ahora", card), "falta qué se decide"
for etiqueta in ["Por qué ahora:", "Si no contestas:", "Si aplazas:", "Vale hasta:"]:
    assert f"<b>{etiqueta}</b>" in card, f"falta {etiqueta}"
assert "No pasa nada malo" in card
m2 = re.search(r'data-a="decno" data-msg="([^"]+)">Quiero fusionar', card)
assert m2, "falta el botón de fusionar"
assert "aprobación formal" in m2.group(1) and "no vale" in m2.group(1)
assert "Nunca elige una opción por ti si callas" in e
print("ok")
PY
  [ "$status" -eq 0 ]
  [[ "$output" == "ok" ]]
}

@test "prototipo E8: observar es el único modo marcado de partida y el modo efectivo se explica" {
  run python3 - "$PROTO" <<'PY'
import re, sys
src = open(sys.argv[1], encoding="utf-8").read()
m = re.search(r"instalacion:\{t:.*?\n(.*?)`\},\nrespaldo:", src, re.S)
e = m.group(1)
radios = re.findall(r'<input type="radio" name="m" value="(\w+)"( checked)?>', e)
assert [r[0] for r in radios] == ["observar", "proponer", "actuar"], radios
assert [r[0] for r in radios if r[1]] == ["observar"], "debe haber un único modo marcado: observar"
assert 'id="sinmotor"' in e and "ningún motor de inferencia" in e
assert 'const ef=s.checked?"observar":m.value;' in src
assert "queda en Observar y te lo digo al terminar" in e
assert "13:00 y las 15:00" in e and "40 %" in e
print("ok")
PY
  [ "$status" -eq 0 ]
  [[ "$output" == "ok" ]]
}

@test "prototipo E10: el aviso de respaldo se marca y Soul no lo repite" {
  run python3 - "$PROTO" <<'PY'
import re, sys
src = open(sys.argv[1], encoding="utf-8").read()
m = re.search(r"respaldo:\{t:.*?\n(.*?)`\},\nestado:", src, re.S)
e = m.group(1)
assert "aviso por canal de respaldo" in e.lower()
assert "No lo repito" in e
assert "Pulse no da señales desde las 14:30" in e
print("ok")
PY
  [ "$status" -eq 0 ]
  [[ "$output" == "ok" ]]
}

@test "prototipo: pulse status en texto y con el latido vencido no dice que todo va bien" {
  run python3 - "$PROTO" <<'PY'
import re, sys
src = open(sys.argv[1], encoding="utf-8").read()
m = re.search(r"estado:\{t:.*?\n(.*?)`\}\n\};", src, re.S)
bloques = re.findall(r"<pre>(.*?)</pre>", m.group(1), re.S)
assert len(bloques) == 3, len(bloques)
assert "Pulse: funcionando" in bloques[0] and "Freno:" in bloques[0] and "Esperan tu respuesta" in bloques[0]
assert "Pulse: sin señales desde las 14:30" in bloques[1]
assert "funcionando" not in bloques[1] and "No puedo decirte que todo va bien" in bloques[1]
assert "Modo: observar (elegido: actuar)" in bloques[2] and "Motivo:" in bloques[2]
print("ok")
PY
  [ "$status" -eq 0 ]
  [[ "$output" == "ok" ]]
}

@test "prototipo: el script de la página es JavaScript válido" {
  command -v node >/dev/null || skip "node no está instalado"
  python3 - "$PROTO" > "$BATS_TEST_TMPDIR/p.js" <<'PY'
import re, sys
print(re.search(r"<script>(.*)</script>", open(sys.argv[1], encoding="utf-8").read(), re.S).group(1))
PY
  run node --check "$BATS_TEST_TMPDIR/p.js"
  [ "$status" -eq 0 ]
}

# ── Sonda: prueba seca ───────────────────────────────────────────────────────

@test "sonda --plan: imprime el procedimiento sin sudo y no ejecuta nada" {
  run bash "$PROBE" --plan
  [ "$status" -eq 0 ]
  [[ "$output" == *"sin sudo"* ]]
  [[ "$output" == *"--active"* ]]
  [[ "$output" != *"CHECK "* ]]
}

@test "sonda simulada ok-activo: observar y proponer permitidos, actuar sin determinar" {
  run bash "$PROBE" --simulate ok-activo
  [ "$status" -eq 0 ]
  [[ "$output" == *"MODO observar PERMITIDO"* ]]
  [[ "$output" == *"MODO proponer PERMITIDO"* ]]
  [[ "$output" == *"MODO actuar NO_DETERMINADO sin dato: push_prueba"* ]]
  [[ "$output" == *"C sigue en pie"* ]]
}

@test "sonda simulada pasivo: sin cargar un servicio nada es PERMITIDO (fail-closed)" {
  run bash "$PROBE" --simulate pasivo
  [ "$status" -eq 2 ]
  [[ "$output" == *"MODO observar NO_DETERMINADO sin dato: servicio_carga"* ]]
  [[ "$output" != *"PERMITIDO"* ]]
  [[ "$output" == *"no se decide entre C y A"* ]]
}

@test "sonda simulada shim-clt: atajo de Command Line Tools es UNKNOWN, no PASS" {
  run bash "$PROBE" --simulate shim-clt
  [ "$status" -eq 2 ]
  [[ "$output" == *"CHECK interprete UNKNOWN"* ]]
  [[ "$output" == *"CHECK git UNKNOWN"* ]]
}

@test "sonda simulada python-viejo: falla un requisito instalable y no decide entre C y A" {
  run bash "$PROBE" --simulate python-viejo
  [ "$status" -eq 1 ]
  [[ "$output" == *"MODO observar NO_PERMITIDO falla: interprete"* ]]
  [[ "$output" == *"no decide entre C y A"* ]]
  [[ "$output" != *"A (contratos sobre el bucle actual) puede bastar"* ]]
}

@test "sonda simulada bloquea-servicio: sin servicio de usuario, A puede bastar" {
  run bash "$PROBE" --simulate bloquea-servicio
  [ "$status" -eq 1 ]
  [[ "$output" == *"MODO observar NO_PERMITIDO falla: servicio_carga"* ]]
  [[ "$output" == *"A (contratos sobre el bucle actual) puede bastar"* ]]
}

@test "sonda simulada sin-motor: observar sigue permitido y proponer y actuar no" {
  run bash "$PROBE" --simulate sin-motor
  [ "$status" -eq 0 ]
  [[ "$output" == *"MODO observar PERMITIDO"* ]]
  [[ "$output" == *"MODO proponer NO_PERMITIDO falla: motor"* ]]
  [[ "$output" == *"MODO actuar NO_PERMITIDO falla: motor"* ]]
}

@test "sonda: escenario desconocido y opción desconocida salen con 64" {
  run bash "$PROBE" --simulate no-existe
  [ "$status" -eq 64 ]
  run bash "$PROBE" --simulate
  [ "$status" -eq 64 ]
  run bash "$PROBE" --otra-cosa
  [ "$status" -eq 64 ]
}

@test "sonda real en un equipo que no es macOS: NO_APLICA y nunca PASS" {
  [ "$(uname -s)" != "Darwin" ] || skip "este test es para equipos que no son macOS"
  run bash "$PROBE"
  [ "$status" -eq 3 ]
  [[ "$output" == *"NO_APLICA"* ]]
  [[ "$output" != *"PERMITIDO"* ]]
}

# ── Sonda: camino real con órdenes de macOS simuladas ────────────────────────

# Monta un PATH con solo las herramientas del sistema que la sonda necesita y órdenes simuladas
# de macOS. Variables: PY (versión de python3 o "ninguno"), PRINT_RC (launchctl print),
# BOOT_RC (launchctl bootstrap), MOTOR (1 = claude presente), FORGE (1 = gh presente).
montar_mac() {
  local b="$BATS_TEST_TMPDIR/bin" t
  rm -rf "$b"
  mkdir -p "$b" "$BATS_TEST_TMPDIR/casa/Library/LaunchAgents"
  for t in mktemp id mkdir rmdir rm sleep cat dirname touch sed cp; do
    ln -sf "$(command -v "$t")" "$b/$t"
  done
  printf '#!/bin/sh\necho Darwin\n' > "$b/uname"
  printf '#!/bin/sh\nexit 0\n' > "$b/xcode-select"
  # PLUTIL_ACTIVE_BAD=1: rechaza solo el plist del ciclo activo, no el de ejemplo
  cat > "$b/plutil" <<EOF
#!/bin/sh
[ "${PLUTIL_ACTIVE_BAD:-0}" = 1 ] && case "\$2" in *ejemplo.plist) exit 0 ;; *) exit 1 ;; esac
exit 0
EOF
  printf '#!/bin/sh\necho "git version 2.40"\n' > "$b/git"
  if [ "${PY:-3.11}" != ninguno ]; then
    printf '#!/bin/sh\necho %s\n' "${PY:-3.11}" > "$b/python3"
  fi
  [ "${MOTOR:-1}" = 1 ] && printf '#!/bin/sh\nexit 0\n' > "$b/claude"
  [ "${FORGE:-1}" = 1 ] && printf '#!/bin/sh\nexit 0\n' > "$b/gh"
  cat > "$b/launchctl" <<EOF
#!/bin/sh
case "\$1" in
  print) exit ${PRINT_RC:-0} ;;
  bootstrap) [ ${BOOT_RC:-0} -ne 0 ] && { echo "Operation not permitted" >&2; exit ${BOOT_RC:-0}; }
    cp "\$3" "$BATS_TEST_TMPDIR/plist.copia"
    echo "bootstrap \$3" >> "$BATS_TEST_TMPDIR/launchctl.log"
    m=\$(sed -n 's|.*<string>\\(/[^<]*marca\\)</string>.*|\\1|p' "\$3" | sed 's|&amp;|\&|g')
    [ ${NOMARK:-0} -eq 0 ] && [ -n "\$m" ] && touch "\$m"; exit 0 ;;
  bootout) echo "bootout \$2" >> "$BATS_TEST_TMPDIR/launchctl.log"; exit 0 ;;
esac
EOF
  for t in uname xcode-select plutil git python3 claude gh launchctl; do [ -f "$b/$t" ] && [ ! -L "$b/$t" ] && chmod +x "$b/$t"; done
  MACPATH="$b"
}

correr_mac() {  # correr_mac [opciones de la sonda]
  HOME="$BATS_TEST_TMPDIR/casa" PATH="$MACPATH" TMPDIR="$BATS_TEST_TMPDIR" run "$BASH" "$BATS_TEST_DIRNAME/../$PROBE" "$@"
}

@test "sonda real simulada: Python 3.10 pasa (comparación numérica, no de texto) y 3.8 falla" {
  PY=3.10 montar_mac; correr_mac --active
  [[ "$output" == *"CHECK interprete PASS python 3.10"* ]]
  PY=3.9 montar_mac; correr_mac --active
  [[ "$output" == *"CHECK interprete PASS python 3.9"* ]]
  PY=3.8 montar_mac; correr_mac --active
  [[ "$output" == *"CHECK interprete FAIL python 3.8 < 3.9"* ]]
  [ "$status" -eq 1 ]
}

@test "sonda real simulada: sin python3 ni runtime de Soul falla; con runtime de Soul y sin python3 es UNKNOWN" {
  PY=ninguno montar_mac; correr_mac --active
  [[ "$output" == *"CHECK interprete FAIL"* ]]
  [ "$status" -eq 1 ]
  printf '#!/bin/sh\nexit 0\n' > "$BATS_TEST_TMPDIR/soul-rt"; chmod +x "$BATS_TEST_TMPDIR/soul-rt"
  correr_mac --active --soul-runtime "$BATS_TEST_TMPDIR/soul-rt"
  [[ "$output" == *"CHECK interprete UNKNOWN sin python3; runtime de Soul: existe y es ejecutable, pero no se ha ejecutado"* ]]
  [ "$status" -eq 2 ]
  [[ "$output" != *"MODO observar PERMITIDO"* ]]
}

@test "sonda real simulada: un python3 válido decide aunque se pase --soul-runtime (el runtime es solo respaldo)" {
  montar_mac
  printf '#!/bin/sh\nexit 0\n' > "$BATS_TEST_TMPDIR/soul-rt"; chmod +x "$BATS_TEST_TMPDIR/soul-rt"
  correr_mac --active --soul-runtime "$BATS_TEST_TMPDIR/soul-rt"
  [[ "$output" == *"CHECK interprete PASS python 3.11"* ]]
  [ "$status" -eq 0 ]
  PY=3.8 montar_mac; correr_mac --active --soul-runtime "$BATS_TEST_TMPDIR/soul-rt"
  [[ "$output" == *"CHECK interprete UNKNOWN python 3.8 < 3.9; runtime de Soul"* ]]
  [ "$status" -eq 2 ]
  PY=3.8 montar_mac; correr_mac --active
  [[ "$output" == *"CHECK interprete FAIL python 3.8 < 3.9"* ]]
}

@test "sonda real simulada --active: servicio cargado, ejecutado y descargado, con todo presente" {
  montar_mac; correr_mac --active
  [ "$status" -eq 0 ]
  [[ "$output" == *"CHECK servicio_carga PASS servicio de usuario cargado, ejecutado y descargado sin sudo"* ]]
  [[ "$output" == *"CHECK bloqueo PASS"* ]]
  [[ "$output" == *"MODO observar PERMITIDO"* ]]
  [[ "$output" == *"MODO actuar NO_DETERMINADO sin dato: push_prueba"* ]]
  # se deshace: ni plist de prueba ni directorio temporal de la sonda
  [ -z "$(ls "$BATS_TEST_TMPDIR/casa/Library/LaunchAgents")" ]
  [ -z "$(ls -d "$BATS_TEST_TMPDIR"/pulse-probe.* 2>/dev/null)" ]
}

@test "sonda real simulada: sin --active el servicio no se carga y nada es PERMITIDO" {
  montar_mac; correr_mac
  [ "$status" -eq 2 ]
  [[ "$output" == *"CHECK servicio_carga UNKNOWN pasivo"* ]]
  [[ "$output" != *"PERMITIDO"* ]]
}

@test "sonda real simulada: launchctl rechaza el servicio → FAIL y A puede bastar" {
  BOOT_RC=1 montar_mac; correr_mac --active
  [ "$status" -eq 1 ]
  [[ "$output" == *"CHECK servicio_carga FAIL launchctl bootstrap rechazado: Operation not permitted"* ]]
  [[ "$output" == *"A (contratos sobre el bucle actual) puede bastar"* ]]
  [ -z "$(ls "$BATS_TEST_TMPDIR/casa/Library/LaunchAgents")" ]
}

@test "sonda real simulada: sin sesión gráfica (ssh) es UNKNOWN, no FAIL" {
  PRINT_RC=1 montar_mac; correr_mac --active
  [ "$status" -eq 2 ]
  [[ "$output" == *"CHECK servicio_carga UNKNOWN sin sesión gráfica"* ]]
  [[ "$output" != *"A (contratos"* ]]
}

@test "sonda real simulada: sin motor de inferencia observar sigue permitido; sin CLI del forge no" {
  MOTOR=0 montar_mac; correr_mac --active
  [ "$status" -eq 0 ]
  [[ "$output" == *"MODO observar PERMITIDO"* ]]
  [[ "$output" == *"MODO proponer NO_PERMITIDO falla: motor"* ]]
  FORGE=0 montar_mac; correr_mac --active
  [ "$status" -eq 1 ]
  [[ "$output" == *"MODO observar NO_PERMITIDO falla: forge_cli"* ]]
}

@test "sonda real simulada: sin escribir en LaunchAgents falla el servicio" {
  montar_mac; chmod 555 "$BATS_TEST_TMPDIR/casa/Library/LaunchAgents"
  [ "$(id -u)" -ne 0 ] || skip "root escribe aunque el directorio sea de solo lectura"
  correr_mac --active
  chmod 755 "$BATS_TEST_TMPDIR/casa/Library/LaunchAgents"
  [ "$status" -eq 1 ]
  [[ "$output" == *"CHECK servicio_escritura FAIL no puedo escribir"* ]]
}

# ── Sonda: revisión independiente de la PR #1569 ─────────────────────────────

@test "sonda real: el atajo de las Command Line Tools (en el directorio del atajo, sin CLT) es UNKNOWN" {
  montar_mac
  printf '#!/bin/sh\nexit 1\n' > "$MACPATH/xcode-select"; chmod +x "$MACPATH/xcode-select"
  PULSE_PROBE_SHIM_DIR="$MACPATH" correr_mac --active
  [ "$status" -eq 2 ]
  [[ "$output" == *"CHECK interprete UNKNOWN python3 es el atajo de las Command Line Tools"* ]]
  [[ "$output" == *"CHECK git UNKNOWN git es el atajo de las Command Line Tools"* ]]
  [[ "$output" != *"MODO observar PERMITIDO"* ]]
}

@test "sonda real: con las Command Line Tools instaladas el mismo binario del atajo es PASS" {
  montar_mac
  PULSE_PROBE_SHIM_DIR="$MACPATH" correr_mac --active
  [ "$status" -eq 0 ]
  [[ "$output" == *"CHECK interprete PASS python 3.11"* ]]
  [[ "$output" == *"CHECK git PASS"* ]]
}

@test "sonda real: sin CLT pero fuera del directorio del atajo no es atajo (PASS)" {
  montar_mac
  printf '#!/bin/sh\nexit 1\n' > "$MACPATH/xcode-select"; chmod +x "$MACPATH/xcode-select"
  correr_mac --active
  [[ "$output" == *"CHECK interprete PASS python 3.11"* ]]
  [[ "$output" == *"CHECK git PASS"* ]]
}

@test "sonda real --active: si se interrumpe con TERM entre bootstrap y bootout, descarga y borra el plist" {
  NOMARK=1 montar_mac
  HOME="$BATS_TEST_TMPDIR/casa" PATH="$MACPATH" TMPDIR="$BATS_TEST_TMPDIR" "$BASH" "$BATS_TEST_DIRNAME/../$PROBE" --active >/dev/null 2>&1 &
  local pid=$! i=0
  while [ ! -s "$BATS_TEST_TMPDIR/launchctl.log" ] && [ $i -lt 50 ]; do sleep 0.1; i=$((i + 1)); done
  grep -q '^bootstrap ' "$BATS_TEST_TMPDIR/launchctl.log"
  kill -TERM "$pid"
  local rc=0; wait "$pid" || rc=$?
  [ "$rc" -eq 143 ]
  grep -q '^bootout gui/.*/local.pulse.probe' "$BATS_TEST_TMPDIR/launchctl.log"
  [ -z "$(ls "$BATS_TEST_TMPDIR/casa/Library/LaunchAgents")" ]
  [ -z "$(ls -d "$BATS_TEST_TMPDIR"/pulse-probe.* 2>/dev/null)" ]
}

@test "sonda real --active: un servicio que no se ejecuta en 10 s es UNKNOWN, no FAIL ni «A puede bastar»" {
  NOMARK=1 montar_mac; correr_mac --active
  [ "$status" -eq 2 ]
  [[ "$output" == *"CHECK servicio_carga UNKNOWN cargó pero no se ejecutó en 10 s"* ]]
  [[ "$output" != *"A (contratos"* ]]
  [ -z "$(ls "$BATS_TEST_TMPDIR/casa/Library/LaunchAgents")" ]
}

@test "sonda real --active: un plist de prueba que no pasa plutil es UNKNOWN (fallo de la sonda), no política" {
  PLUTIL_ACTIVE_BAD=1 montar_mac; correr_mac --active
  [ "$status" -eq 2 ]
  [[ "$output" == *"CHECK servicio_carga UNKNOWN el plist de prueba no pasa plutil -lint"* ]]
  [[ "$output" != *"A (contratos"* ]]
  [ ! -e "$BATS_TEST_TMPDIR/launchctl.log" ]
  [ -z "$(ls "$BATS_TEST_TMPDIR/casa/Library/LaunchAgents")" ]
}

@test "sonda real --active: un TMPDIR con & se escapa en el plist y el servicio se ejecuta" {
  montar_mac
  mkdir -p "$BATS_TEST_TMPDIR/a&b"
  HOME="$BATS_TEST_TMPDIR/casa" PATH="$MACPATH" TMPDIR="$BATS_TEST_TMPDIR/a&b" run "$BASH" "$BATS_TEST_DIRNAME/../$PROBE" --active
  [ "$status" -eq 0 ]
  grep -q 'a&amp;b' "$BATS_TEST_TMPDIR/plist.copia"
  run grep -c 'a&b' "$BATS_TEST_TMPDIR/plist.copia"
  [ "$output" = "0" ]
}

@test "sonda real --active: si LaunchAgents no existía, no lo deja creado y el detalle no dice que existe" {
  montar_mac; rmdir "$BATS_TEST_TMPDIR/casa/Library/LaunchAgents"
  correr_mac --active
  [ "$status" -eq 0 ]
  [[ "$output" == *"no existe todavía"* ]]
  [ ! -e "$BATS_TEST_TMPDIR/casa/Library/LaunchAgents" ]
}

@test "sonda real: si no puede crear su directorio temporal es un fallo del entorno (2), no uso incorrecto (64)" {
  montar_mac
  HOME="$BATS_TEST_TMPDIR/casa" PATH="$MACPATH" TMPDIR="$BATS_TEST_TMPDIR/no-existe" run "$BASH" "$BATS_TEST_DIRNAME/../$PROBE"
  [ "$status" -eq 2 ]
}

@test "sonda real --active: no pisa un plist preexistente ni sigue un enlace simbólico en su ruta" {
  montar_mac
  local la="$BATS_TEST_TMPDIR/casa/Library/LaunchAgents" objetivo="$BATS_TEST_TMPDIR/objetivo-ajeno"
  echo intacto > "$objetivo"
  HOME="$BATS_TEST_TMPDIR/casa" PATH="$MACPATH" TMPDIR="$BATS_TEST_TMPDIR" run "$BASH" -c \
    '/usr/bin/ln -s "$1" "$HOME/Library/LaunchAgents/local.pulse.probe.$$.plist"; exec "$2" "$3" --active' _ "$objetivo" "$BASH" "$BATS_TEST_DIRNAME/../$PROBE"
  [ "$(cat "$objetivo")" = intacto ]
  [[ "$output" == *"CHECK servicio_carga UNKNOWN ya existe"* ]]
  [ "$status" -eq 2 ]
}

@test "prototipo: la pestaña se valida con claves propias del objeto, no heredadas" {
  grep -q 'Object.hasOwn(states,k)' "$PROTO"
}

@test "spec: la frase «C se sostiene» conserva la condición (a), como las medidas" {
  grep -q 'C se sostiene, condicionada a (a)' "$SPEC"
}

# ── Sonda: portabilidad y alcance, estático ──────────────────────────────────

@test "sonda: sin sudo, sin flock, sin construcciones de bash 4 ni de GNU (en el código, no en los comentarios)" {
  [ -f "$PROBE" ]
  run bash -c "grep -vE '^[[:space:]]*#' '$PROBE' | grep -nE '(^|[;&|(]|[$][(]) *(sudo|flock|mapfile|readarray) |declare -A|local -A|[$][{][A-Za-z_]+(,,|[\\^][\\^])[}]|date -d|stat -c|readlink -f'"
  [ "$status" -eq 1 ]
}

@test "sonda: la única redirección a un fichero es el plist de prueba; el resto, /dev/null o stderr" {
  run python3 - "$PROBE" <<'PY'
import re, sys
destinos = set()
for linea in open(sys.argv[1], encoding="utf-8"):
    if linea.lstrip().startswith("#"):
        continue
    for m in re.finditer(r' >>? *("[^"]*"|[^ ]+)', linea):
        d = m.group(1)
        if d.startswith("&"):
            continue
        destinos.add(d)
assert destinos == {'/dev/null', '"$plist"'}, destinos
print("ok")
PY
  [ "$status" -eq 0 ]
  [[ "$output" == "ok" ]]
}

# ── Medidas ──────────────────────────────────────────────────────────────────

@test "medidas: coherencia aritmética del documento (62+34+24=120, 96 = 80 %); no verifica la medida en sí" {
  run python3 - "$MED" <<'PY'
import re, sys
t = open(sys.argv[1], encoding="utf-8").read()
tot = {}
for clase in ("G", "A", "X"):
    row = re.search(r"^\| \*\*%s\*\*[^|]*\| (\d+) \([^)]*\) \| (.*) \|$" % clase, t, re.M)
    assert row, f"falta la fila {clase}"
    declarado = int(row.group(1))
    desglose = sum(int(n) for n in re.findall(r"\((\d+)\)", row.group(2)))
    assert declarado == desglose, f"{clase}: declara {declarado}, el desglose suma {desglose}"
    tot[clase] = declarado
assert sum(tot.values()) == 120, tot
assert tot["G"] + tot["A"] == 96
assert round(100 * 96 / 120) == 80
assert "Total 62 + 34 + 24 = 120" in t and "96 (80 %)" in t
print(tot)
PY
  [ "$status" -eq 0 ]
  [[ "$output" == "{'G': 62, 'A': 34, 'X': 24}" ]]
}

@test "medidas: declaran lo no medido y no presentan (a) ni (b) como resueltos" {
  local f
  for f in 'no ejecutada en un Mac' 'No se ha medido la política de ninguna organización' 'sin datos'; do
    run grep -c -F "$f" "$MED"
    [ "$output" -ge 1 ] || { echo "falta: $f"; return 1; }
  done
  run grep -E 'decisión «C o basta A» es de la operadora' "$MED"
  [ "$status" -eq 0 ]
  run grep -iE 'viable en macOS|probado en macOS|verificado en macOS' "$MED"
  [ "$status" -eq 1 ]
}

@test "medidas y prototipo: nada de datos de instalación ni de personas" {
  local pat="mac""book|accen""ture|m[oó]ni""ca|\.sa""via/|inten""sivo|reconci""liar|SaviaL""abs|/ho""me/"
  run grep -inE "$pat" "$MED" "$PROTO" "$PROBE" "$BATS_TEST_FILENAME"
  [ "$status" -eq 1 ]
}

@test "spec: la confirmación del prototipo sigue pendiente hasta que la operadora la registre ella (no la autora)" {
  run grep -A4 '^### Confirmación del prototipo' "$SPEC"
  [[ "$output" == *"- fecha: pendiente"* ]]
  [[ "$output" == *"- respuesta: pendiente."* ]]
  [[ "$output" != *"Confirmo"* ]]
  run grep -E '^status: APPROVED$' "$SPEC"
  [ "$status" -eq 0 ]
}
