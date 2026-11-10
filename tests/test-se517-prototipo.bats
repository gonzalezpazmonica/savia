#!/usr/bin/env bats
# SE-517 S0: el prototipo del login con ChatGPT es lo que la operadora confirma.
# Comprueba que enseña los seis estados que promete la spec, en lenguaje llano,
# con un código de ocho letras como dice la escena 1, que cada botón opuesto
# tiene su propia consecuencia, que `doctor` no da la red por restringida
# (D7: hasta su slice, «sin restringir») y que la spec documenta el método
# de login con su recomendación y el estado de la escena 1.
# Ref: docs/specs/SE-517-space-motor-suscripcion-chatgpt-oauth.spec.md (slice S0)
# Ref: docs/rules/domain/comprehension-gate.md

setup() {
  cd "$BATS_TEST_DIRNAME/.."
  SPEC="docs/specs/SE-517-space-motor-suscripcion-chatgpt-oauth.spec.md"
  PROTO="docs/specs/assets/SE-517-prototipo.html"
  CHECK="$BATS_TEST_TMPDIR/check.py"
  cat > "$CHECK" <<'PY'
import re, sys
spec_path, proto_path = sys.argv[1], sys.argv[2]
try:
    spec = open(spec_path, encoding="utf-8").read()
    src = open(proto_path, encoding="utf-8").read()
except OSError as e:
    print(f"ERROR ilegible: {e}"); sys.exit(2)
errs = []
# 1. La spec apunta a este prototipo y declara los estados ?s=...
m = re.search(r"prototipo: `([^`]+)`", spec)
if not m or m.group(1) != "docs/specs/assets/SE-517-prototipo.html":
    errs.append("la spec no apunta al prototipo")
m = re.search(r"\?s=([a-z|]+)", spec)
if not m:
    errs.append("la spec no declara los estados ?s=")
    wanted = []
else:
    wanted = m.group(1).split("|")
om = re.search(r"const order=\[([^\]]*)\]", src)
order = re.findall(r'"(\w+)"', om.group(1)) if om else []
if not wanted or order != wanted:
    errs.append(f"estados del prototipo {order} != spec {wanted}")
for k in wanted:
    if not re.search(r"\b%s:\{t:" % re.escape(k), src):
        errs.append(f"falta el estado {k}")
# 2. Lenguaje llano: sin siglas ni jerga interna en el texto visible.
visible = re.sub(r"<style>.*?</style>", "", src, flags=re.S)
visible = re.sub(r"<[^>]+>", " ", visible)
for pat in [r"\bOAuth\b", r"\btokens?\b", r"\btiers?\b", r"\bXDG\b", r"\bSE-\d+",
            r"\bAC-\d+", r"\bD\d\b", r"\bopencode\b", r"\bproveedor", r"\bFALLO\b",
            r"espacio del motor", r"\bbwrap\b"]:
    if re.search(pat, visible, re.I):
        errs.append(f"jerga visible: {pat}")
# 3. Escena 1: código de ocho letras, el mismo en app y terminal.
codes = set(re.findall(r'class="code"[^>]*>([^<]+)<', src))
term = set(re.findall(r"Escribe este código: (\S+)", src))
if len(codes) != 1:
    errs.append(f"códigos en la app: {codes}")
else:
    c = codes.pop()
    if not re.fullmatch(r"[A-Z]{4}-[A-Z]{4}", c):
        errs.append(f"el código {c} no son ocho letras")
    if term != {c}:
        errs.append(f"código de la terminal {term} distinto del de la app {c}")
# 4. Botones de respuesta: cada uno con su propio mensaje.
groups = {}
for attrs, text in re.findall(r"<button\b([^>]*)>(.*?)</button>", src, re.S):
    a = dict(re.findall(r'([\w-]+)="([^"]*)"', attrs))
    if "data-a" in a:
        if not a.get("data-msg", "").strip():
            errs.append(f"botón «{text}» sin mensaje")
        groups.setdefault(a["data-a"], []).append(a.get("data-msg"))
if not groups:
    errs.append("no hay botones de respuesta")
for g, msgs in groups.items():
    if len(set(msgs)) != len(msgs):
        errs.append(f"grupo {g}: botones distintos con el mismo mensaje")
if re.search(r"\$\{[^}]*msg[^}]*\}", src):
    errs.append("mensaje interpolado en HTML")
# 5. D7: doctor no presume una red restringida que aún no existe.
if not re.search(r"sin restringir", src):
    errs.append("doctor no dice que la salida a internet está sin restringir")
if re.search(r"\(solo estos\)", src):
    errs.append("doctor da la red por restringida")
# 6. La spec documenta el método de login y el estado de la escena 1.
sec = re.search(r"^### Método de login \(S0\)\n(.*?)(?=^## |\Z)", spec, re.S | re.M)
if not sec:
    errs.append("falta «### Método de login (S0)»")
else:
    body = sec.group(1)
    for mid in ["chatgpt-token-sharing", "chatgpt-headless", "chatgpt-browser", "`key`"]:
        if mid not in body:
            errs.append(f"método {mid} no documentado")
    if not re.search(r"\*\*Recomendación: \((a|b)\)", body):
        errs.append("sin recomendación (a) o (b)")
    if "requiere reconfirmar la escena 1" not in body:
        errs.append("no dice cuándo hay que reconfirmar la escena 1")
conf = re.search(r"^### Confirmación\n(.*?)(?=^#)", spec, re.S | re.M)
if not conf or "respuesta: «Confirmo las escenas»" not in conf.group(1) \
        or "fecha: 2026-11-10" not in conf.group(1):
    errs.append("confirmación de escenas ausente o distinta")
if re.search(r"^status: APPROVED", spec, re.M):
    errs.append("la spec no puede estar APPROVED en S0")
for e in errs:
    print("FAIL:", e)
print(f"errores={len(errs)}")
sys.exit(1 if errs else 0)
PY
  cp "$SPEC" "$BATS_TEST_TMPDIR/spec.md"
  cp "$PROTO" "$BATS_TEST_TMPDIR/proto.html"
}

run_check() { run python3 "$CHECK" "$BATS_TEST_TMPDIR/spec.md" "$BATS_TEST_TMPDIR/proto.html"; }

@test "real: spec y prototipo de SE-517 son coherentes" {
  run python3 "$CHECK" "$SPEC" "$PROTO"
  [ "$status" -eq 0 ]
  [[ "$output" == *"errores=0"* ]]
}

@test "fail: falta un estado de los que promete la spec" {
  sed -i 's/,"doctor"\]/]/' "$BATS_TEST_TMPDIR/proto.html"
  run_check
  [ "$status" -eq 1 ]
  [[ "$output" == *"estados del prototipo"* ]]
}

@test "fail: jerga interna visible (token, tiers)" {
  sed -i 's/tu clave de acceso/tu token/' "$BATS_TEST_TMPDIR/proto.html"
  run_check
  [ "$status" -eq 1 ]
  [[ "$output" == *"jerga visible"* ]]
}

@test "fail: código con cifras no son ocho letras (escena 1)" {
  sed -i 's/KQMW-TXRB/K7QF-29XM/g' "$BATS_TEST_TMPDIR/proto.html"
  run_check
  [ "$status" -eq 1 ]
  [[ "$output" == *"no son ocho letras"* ]]
}

@test "fail: código de la terminal distinto del de la app" {
  sed -i 's/Escribe este código: KQMW-TXRB/Escribe este código: ABCD-EFGH/' "$BATS_TEST_TMPDIR/proto.html"
  run_check
  [ "$status" -eq 1 ]
  [[ "$output" == *"distinto del de la app"* ]]
}

@test "fail: cancelar y confirmar el cierre muestran lo mismo" {
  sed -i 's/data-msg="No se ha borrado nada. La sesión sigue activa."/data-msg="Sesión cerrada y borrada de este ordenador. Ajustes › Motor vuelve a decir «ChatGPT · sin sesión»."/' "$BATS_TEST_TMPDIR/proto.html"
  run_check
  [ "$status" -eq 1 ]
  [[ "$output" == *"mismo mensaje"* ]]
}

@test "fail: doctor da la red por restringida (contradice D7)" {
  sed -i 's/Salida a internet del motor: sin restringir todavía/salida red   auth.openai.com, chatgpt.com (solo estos)/' "$BATS_TEST_TMPDIR/proto.html"
  run_check
  [ "$status" -eq 1 ]
  [[ "$output" == *"red por restringida"* ]]
}

@test "fail: spec sin recomendación de método" {
  sed -i 's/\*\*Recomendación: (a)/**Opciones/' "$BATS_TEST_TMPDIR/spec.md"
  run_check
  [ "$status" -eq 1 ]
  [[ "$output" == *"sin recomendación"* ]]
}

@test "fail: confirmación de escenas pendiente" {
  sed -i 's/respuesta: «Confirmo las escenas»/respuesta: «pendiente»/' "$BATS_TEST_TMPDIR/spec.md"
  run_check
  [ "$status" -eq 1 ]
  [[ "$output" == *"confirmación de escenas"* ]]
}

@test "fail: la spec no puede figurar APPROVED en S0" {
  sed -i 's/^status: PROPOSED/status: APPROVED/' "$BATS_TEST_TMPDIR/spec.md"
  run_check
  [ "$status" -eq 1 ]
  [[ "$output" == *"APPROVED"* ]]
}

@test "error fail-closed: prototipo nonexistent da error, no PASS" {
  run python3 "$CHECK" "$SPEC" "$BATS_TEST_TMPDIR/no-existe.html"
  [ "$status" -eq 2 ]
}

@test "error fail-closed: spec nonexistent da error, no PASS" {
  run python3 "$CHECK" "$BATS_TEST_TMPDIR/no-existe.md" "$PROTO"
  [ "$status" -eq 2 ]
  [[ "$output" == *"ERROR ilegible"* ]]
}

@test "fail: prototipo empty (vacío) no pasa" {
  : > "$BATS_TEST_TMPDIR/proto.html"
  run_check
  [ "$status" -eq 1 ]
  [[ "$output" == *"no hay botones de respuesta"* ]]
}

@test "boundary fail: código de siete letras no basta" {
  sed -i 's/KQMW-TXRB/KQMW-TXR/g' "$BATS_TEST_TMPDIR/proto.html"
  run_check
  [ "$status" -eq 1 ]
  [[ "$output" == *"no son ocho letras"* ]]
}

@test "boundary fail: código de nueve letras sobra" {
  sed -i 's/KQMW-TXRB/KQMW-TXRBA/g' "$BATS_TEST_TMPDIR/proto.html"
  run_check
  [ "$status" -eq 1 ]
  [[ "$output" == *"no son ocho letras"* ]]
}

@test "positivo boundary: otro código de ocho letras exactas pasa" {
  sed -i 's/KQMW-TXRB/ABCD-EFGH/g' "$BATS_TEST_TMPDIR/proto.html"
  run_check
  [ "$status" -eq 0 ]
  [[ "$output" == *"errores=0"* ]]
}

@test "positivo: recomendar (b) también vale si dice cuándo reconfirmar" {
  sed -i 's/\*\*Recomendación: (a)/**Recomendación: (b)/' "$BATS_TEST_TMPDIR/spec.md"
  run_check
  [ "$status" -eq 0 ]
  [[ "$output" == *"errores=0"* ]]
}

@test "fail: spec sin la condición de reconfirmar la escena 1" {
  sed -i 's/requiere reconfirmar la escena 1/requiere revisar/' "$BATS_TEST_TMPDIR/spec.md"
  run_check
  [ "$status" -eq 1 ]
  [[ "$output" == *"reconfirmar la escena 1"* ]]
}

@test "positivo: jerga dentro de <style> no cuenta como texto visible" {
  sed -i 's|</style>|.tier-token{}</style>|' "$BATS_TEST_TMPDIR/proto.html"
  run_check
  [ "$status" -eq 0 ]
  [[ "$output" == *"errores=0"* ]]
}

@test "positivo: los estados se leen de la spec, no están fijos en el test" {
  sed -i 's/?s=none|code|ok|expired|logout|doctor/?s=none|code|ok|expired|logout|doctor|help/' "$BATS_TEST_TMPDIR/spec.md"
  sed -i 's/,"doctor"\]/,"doctor","help"]/; s/^const order=/const extra=1;\nconst order=/' "$BATS_TEST_TMPDIR/proto.html"
  sed -i 's/^doctor:{t:/help:{t:"7 · Ayuda",h:`<p>Ayuda de ejemplo.<\/p>`},\ndoctor:{t:/' "$BATS_TEST_TMPDIR/proto.html"
  run_check
  [ "$status" -eq 0 ]
  [[ "$output" == *"errores=0"* ]]
}
