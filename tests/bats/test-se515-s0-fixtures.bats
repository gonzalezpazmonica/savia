#!/usr/bin/env bats
# SE-515 S0 — Fixtures de las sondas P10–P15 y del dominio piloto, congelados antes de medir.
# Comprueba que el preregistro y los casos no cambian sin cambiar su hash, que las etiquetas
# salen de un oráculo externo al modelo, que cada sonda trae sus NO-GO, la línea base sin agente
# (B0) y la regla «0/N en esta muestra», y que los oráculos citados existen de verdad.
# Ref: docs/specs/SE-515-aprendizaje-aplicado-obligacion-comprobada.spec.md (S0, AC-2)
# Ref: docs/evidence/SE-515-S0-rebaseline-20261121.md

FIX="tests/fixtures/se515-s0"

setup() {
  cd "$BATS_TEST_DIRNAME/.." || exit 1
  REPO="$PWD"
  WORK="$BATS_TEST_TMPDIR/fix"
  mkdir -p "$WORK"
  cp "$FIX"/prereg.json "$FIX"/pilot-cases.jsonl "$FIX"/SHA256SUMS "$WORK"/
}

# Validador del esquema: imprime un error por línea y sale 1 si hay alguno.
validate() {
  python3 - "$1" "$REPO" <<'PY'
import json, pathlib, re, sys
d = pathlib.Path(sys.argv[1]); repo = pathlib.Path(sys.argv[2]); errs = []
try:
    pre = json.loads((d / "prereg.json").read_text(encoding="utf-8"))
    cases = [json.loads(l) for l in (d / "pilot-cases.jsonl").read_text(encoding="utf-8").splitlines() if l.strip()]
except (OSError, ValueError) as e:
    print(f"ilegible: {e}"); sys.exit(1)
if pre.get("written_before_measuring") is not True:
    errs.append("preregistro sin written_before_measuring")
if "results" in pre:
    errs.append("el preregistro no puede llevar resultados")
if "B0" not in pre.get("baselines", {}):
    errs.append("falta la línea base sin agente B0")
rules = pre.get("common_rules", {})
if "0/N en esta muestra" not in rules.get("zero_rule", ""):
    errs.append("falta la regla 0/N en esta muestra")
if "denominador" not in rules.get("false_denials", ""):
    errs.append("falsos bloqueos sin denominador")
ids = [p.get("id") for p in pre.get("probes", [])]
for want in ("P10", "P11", "P12", "P13", "P14", "P15"):
    if ids.count(want) != 1:
        errs.append(f"sonda {want} ausente o repetida")
for p in pre.get("probes", []):
    nogo = p.get("no_go")
    if not isinstance(nogo, list) or not nogo or not all(isinstance(x, str) and x.strip() for x in nogo):
        errs.append(f"{p.get('id')}: sin condiciones NO-GO")
kinds = [c.get("kind") for c in cases]
if kinds.count("case") != 3:
    errs.append(f"casos útiles: {kinds.count('case')} (se esperan 3)")
if kinds.count("counterexample") != 3:
    errs.append(f"contraejemplos: {kinds.count('counterexample')} (se esperan 3)")
seen = set()
for c in cases:
    cid = c.get("id")
    if cid in seen:
        errs.append(f"{cid}: id repetido")
    seen.add(cid)
    o = c.get("oracle") or {}
    if o.get("type") not in ("test", "gate", "human"):
        errs.append(f"{cid}: oráculo {o.get('type')!r} no es externo al modelo")
    if c.get("expected_applicability") not in ("APPLICABLE", "NOT_APPLICABLE", "UNKNOWN", "CONFLICT"):
        errs.append(f"{cid}: aplicabilidad no válida")
    if c.get("kind") == "counterexample" and c.get("expected_decision") != "PASS":
        errs.append(f"{cid}: un contraejemplo no puede esperar bloqueo")
    if c.get("kind") == "case" and c.get("expected_applicability") != "APPLICABLE":
        errs.append(f"{cid}: un caso útil debe aplicar")
    ref = o.get("ref", "")
    if not (repo / ref).is_file():
        errs.append(f"{cid}: oráculo {ref!r} no existe")
    elif o.get("type") == "test":
        text = (repo / ref).read_text(encoding="utf-8")
        if not re.search(r'@test\s+"' + re.escape(o.get("name", "")) + r'"', text):
            errs.append(f"{cid}: el test oráculo {o.get('name')!r} no está en {ref}")
for e in errs:
    print(e)
sys.exit(1 if errs else 0)
PY
}

@test "integridad: los fixtures coinciden con los hashes congelados en SHA256SUMS" {
  run bash -c "cd '$REPO/$FIX' && sha256sum -c --strict SHA256SUMS"
  [ "$status" -eq 0 ]
  [[ "$output" == *"prereg.json: OK"* ]]
  [[ "$output" == *"pilot-cases.jsonl: OK"* ]]
}

@test "negativo: cambiar una etiqueta sin actualizar el hash rompe la integridad" {
  sed -i 's/"expected_decision":"BLOCK"/"expected_decision":"PASS"/' "$WORK/pilot-cases.jsonl"
  run bash -c "cd '$WORK' && sha256sum -c --strict SHA256SUMS"
  [ "$status" -ne 0 ]
  [[ "$output" == *"pilot-cases.jsonl: FAILED"* ]]
}

@test "esquema: los fixtures del repo pasan el validador" {
  run validate "$REPO/$FIX"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "negativo: una etiqueta puesta por un modelo se rechaza" {
  sed -i '0,/"type":"test"/s//"type":"model"/' "$WORK/pilot-cases.jsonl"
  run validate "$WORK"
  [ "$status" -eq 1 ]
  [[ "$output" == *"no es externo al modelo"* ]]
}

@test "negativo: una sonda sin condiciones NO-GO se rechaza" {
  python3 - "$WORK/prereg.json" <<'PY'
import json, sys
p = sys.argv[1]; d = json.load(open(p, encoding="utf-8"))
d["probes"][2]["no_go"] = []
json.dump(d, open(p, "w", encoding="utf-8"), ensure_ascii=False)
PY
  run validate "$WORK"
  [ "$status" -eq 1 ]
  [[ "$output" == *"P12: sin condiciones NO-GO"* ]]
}

@test "negativo: sin línea base B0 o sin la regla 0/N el preregistro se rechaza" {
  python3 - "$WORK/prereg.json" <<'PY'
import json, sys
p = sys.argv[1]; d = json.load(open(p, encoding="utf-8"))
del d["baselines"]["B0"]
d["common_rules"]["zero_rule"] = "0 fallos = seguro"
json.dump(d, open(p, "w", encoding="utf-8"), ensure_ascii=False)
PY
  run validate "$WORK"
  [ "$status" -eq 1 ]
  [[ "$output" == *"falta la línea base sin agente B0"* ]]
  [[ "$output" == *"falta la regla 0/N en esta muestra"* ]]
}

@test "negativo: un contraejemplo que espera bloqueo se rechaza (falso bloqueo preregistrado)" {
  sed -i '/"id":"X2"/s/"expected_decision":"PASS"/"expected_decision":"BLOCK"/' "$WORK/pilot-cases.jsonl"
  run validate "$WORK"
  [ "$status" -eq 1 ]
  [[ "$output" == *"X2: un contraejemplo no puede esperar bloqueo"* ]]
}

@test "límite: con dos casos útiles en vez de tres el piloto se rechaza" {
  sed -i '/"id":"C3"/d' "$WORK/pilot-cases.jsonl"
  run validate "$WORK"
  [ "$status" -eq 1 ]
  [[ "$output" == *"casos útiles: 2 (se esperan 3)"* ]]
}

@test "negativo: un test oráculo que no existe en su suite se rechaza" {
  sed -i 's/block: head cambiado tras la revisión aparca el PR/block: test inventado/' "$WORK/pilot-cases.jsonl"
  run validate "$WORK"
  [ "$status" -eq 1 ]
  [[ "$output" == *"C2: el test oráculo"* ]]
}

@test "negativo: un preregistro con resultados dentro se rechaza" {
  python3 - "$WORK/prereg.json" <<'PY'
import json, sys
p = sys.argv[1]; d = json.load(open(p, encoding="utf-8"))
d["results"] = {"P10": "sin efecto"}
json.dump(d, open(p, "w", encoding="utf-8"), ensure_ascii=False)
PY
  run validate "$WORK"
  [ "$status" -eq 1 ]
  [[ "$output" == *"no puede llevar resultados"* ]]
}

@test "negativo: fixtures ilegibles no pasan" {
  printf '{roto' > "$WORK/pilot-cases.jsonl"
  run validate "$WORK"
  [ "$status" -eq 1 ]
  [[ "$output" == *"ilegible"* ]]
}
