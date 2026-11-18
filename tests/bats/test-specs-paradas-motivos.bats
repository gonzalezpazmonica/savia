#!/usr/bin/env bats
# Motivos de las 10 specs aparcadas (PR #1606): atribución honesta y sin premisas sin comprobar.

IDS="408 447 449 450 452 454 458 463 467 469"

setup() { ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"; }

@test "cada motivo declara quién propone y que falta confirmar" {
  for i in $IDS; do
    for f in "$ROOT/docs/propuestas/planning.d/SE-$i.json" "$ROOT/docs/propuestas/LOG.d/SE-$i-DEFERRED.md" "$ROOT"/docs/specs/SE-$i-*.spec.md; do
      grep -q "propuesta de la orquestadora, pendiente de confirmar por la operadora" "$f" || { echo "falta atribución en $f"; return 1; }
    done
  done
}

# Ficheros de motivo de una spec (uno por línea); falla si falta alguno.
# Los tests lo usan con `ficheros_de N` (que propaga el fallo), nunca dentro de $(...) suelto:
# un fallo perdido dejaría la lista vacía y los tests negativos pasarían en falso.
ficheros() {
  local i="$1" f n=0
  for f in "$ROOT/docs/propuestas/planning.d/SE-$i.json" "$ROOT/docs/propuestas/LOG.d/SE-$i-DEFERRED.md" "$ROOT"/docs/specs/SE-$i-*.spec.md; do
    [ -f "$f" ] || { echo "no existe $f" >&2; return 1; }
    echo "$f"; n=$((n+1))
  done
  [ "$n" -eq 3 ] || { echo "SE-$i: $n ficheros, esperados 3" >&2; return 1; }
}

# Rellena FILES con los ficheros de la spec o devuelve 1 (sin lista vacía silenciosa).
ficheros_de() {
  local out
  out="$(ficheros "$1")" || return 1
  [ -n "$out" ] || return 1
  mapfile -t FILES <<<"$out"
  [ "${#FILES[@]}" -eq 3 ] || return 1
}

@test "el helper falla si falta un fichero de motivo (fail-closed)" {
  run ficheros 99999
  [ "$status" -eq 1 ]
  run ficheros_de 99999
  [ "$status" -eq 1 ]
  ficheros_de 458
  [ "${#FILES[@]}" -eq 3 ]
}

@test "ningún motivo atribuye la decisión a la operadora fuera de la frase de atribución" {
  for i in $IDS; do
    ficheros_de "$i" || { echo "faltan ficheros de SE-$i"; return 1; }
    for f in "${FILES[@]}"; do
      # Se quita la frase de atribución completa; si queda una fórmula que da la decisión por tomada por la operadora, falla.
      resto="$(grep -iE 'deferral|deferred_reason|aparcad' "$f" | sed 's/propuesta de la orquestadora, pendiente de confirmar por la operadora//g' | grep -iE '\(operadora\)|operadora (decid|aprob|acord|pid|quis|prefier)|(decidid|aprobad|acordad|aparcad|pedid)[oa]s? por (la )?operadora|operadora,? 20[0-9]{2}-' || true)"
      [ -z "$resto" ] || { echo "atribución a la operadora en $f: $resto"; return 1; }
    done
  done
}

@test "el campo deferral y deferred_reason empiezan por la fecha y la atribución" {
  for i in $IDS; do
    grep -qE '"deferral": "2026-11-18 \(propuesta de la orquestadora, pendiente' "$ROOT/docs/propuestas/planning.d/SE-$i.json" || { echo "deferral sin formato en SE-$i"; return 1; }
    grep -qE '^deferred_reason: "?2026-11-18 \(propuesta de la orquestadora, pendiente' "$ROOT"/docs/specs/SE-$i-*.spec.md || { echo "deferred_reason sin formato en SE-$i"; return 1; }
  done
}

@test "SE-458 no afirma un límite de PRs activas que el repo no define" {
  ficheros_de 458 || return 1
  run grep -l "ya limita las PRs activas" "${FILES[@]}"
  [ "$status" -eq 1 ]
}

@test "SE-450 no afirma trabajo de rutas Windows sin PR citado" {
  ficheros_de 450 || return 1
  run grep -l "rutas Windows ya entró" "${FILES[@]}"
  [ "$status" -eq 1 ]
}

@test "ninguna referencia activa dice que SE-469 está APPROVED" {
  run grep -c "SE-469 ya APPROVED" "$ROOT/docs/propuestas/planning-state.json"
  [ "$status" -eq 1 ]
  [ "$output" = "0" ]
  run grep -c "SE-469 aparcada" "$ROOT/docs/propuestas/planning-state.json"
  [ "$output" -ge 1 ]
}

@test "la cola no presenta como trabajo vigente las specs aparcadas (planning-state y ROADMAP-CURRENT)" {
  for f in "$ROOT/docs/propuestas/planning-state.json" "$ROOT/docs/propuestas/ROADMAP-CURRENT.md"; do
    [ -f "$f" ] || { echo "no existe $f"; return 1; }
    run grep -cE 'SE-454 invariantes negativos como tests|SE-449 regla y lectura|SE-450 auditoría de instaladores|Último slice: piloto de suite de conformidad|SE-458 \(tope y lotes|SE-443, SE-447|invariantes de SE-454 llevan' "$f"
    [ "$status" -eq 1 ] || { echo "texto de cola obsoleto en $f"; return 1; }
  done
}

# Comprobación estructural (solo las specs de IDS, aparcadas en esta PR): ninguna sesión lista o cita una spec DEFERRED sin marcarla aparcada en su acción.
checkcola() {
  IDS="$IDS" python3 -I - "$1" <<'PY'
import json, re, sys, glob, os
state = sys.argv[1]
root = os.path.dirname(os.path.dirname(os.path.abspath(state)))
deferred = set()
for f in glob.glob(os.path.join(os.path.dirname(os.path.abspath(state)), "planning.d", "SE-*.json")):
    r = json.load(open(f, encoding="utf-8"))
    n = re.sub(r"\D", "", os.path.basename(f))
    if r.get("status") == "DEFERRED" and n in os.environ["IDS"].split():
        deferred.add(n)
if not deferred:
    print("ninguna spec DEFERRED encontrada"); sys.exit(2)
bad = []
for s in json.load(open(state, encoding="utf-8"))["route"]["session_plan"]:
    texto = " ".join(str(s.get(k, "")) for k in ("action", "effort", "dependency_value", "prerequisites"))
    for i in deferred:
        if not (f"SE-{i}" in s.get("initiatives", []) or re.search(rf"SE-{i}\b", texto)):
            continue
        if not re.search(rf"SE-{i}\b[^.]*aparcad", s.get("action", "") + " " + texto):
            bad.append(f"{s['id']}: SE-{i}")
        # en acción y esfuerzo no puede figurar como trabajo a ejecutar
        if re.search(rf"SE-{i} (medio|pequeño|grande)\b|SE-{i}: \d", s.get("action", "") + " " + s.get("effort", "")):
            bad.append(f"{s['id']}: SE-{i} con trabajo asignado")
if bad:
    print("; ".join(bad)); sys.exit(1)
PY
}

@test "ninguna sesión planifica una spec DEFERRED sin marcarla aparcada (comprobación estructural)" {
  run checkcola "$ROOT/docs/propuestas/planning-state.json"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
}

@test "la comprobación estructural falla con el residuo de S19 (SE-469 como trabajo vigente)" {
  mkdir -p "$BATS_TEST_TMPDIR/docs/propuestas"
  cp -r "$ROOT/docs/propuestas/planning.d" "$BATS_TEST_TMPDIR/docs/propuestas/"
  sed 's/SE-469 aparcada, sin esfuerzo asignado/SE-469 medio (M)/' "$ROOT/docs/propuestas/planning-state.json" > "$BATS_TEST_TMPDIR/docs/propuestas/planning-state.json"
  run checkcola "$BATS_TEST_TMPDIR/docs/propuestas/planning-state.json"
  [ "$status" -eq 1 ]
  [[ "$output" == *"S19: SE-469"* ]]
}

@test "ROADMAP-CURRENT.md no tiene residuo de SE-469 con esfuerzo ni acción vigente" {
  run grep -cE "SE-469 medio|SE-469: 30 casos" "$ROOT/docs/propuestas/ROADMAP-CURRENT.md"
  [ "$status" -eq 1 ]
}
