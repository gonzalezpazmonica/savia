#!/usr/bin/env bats
# SCL-010 — reconciliación de lecciones (3-bucket sobre SaviaLearning)
# Spec: docs/specs/SCL-010-reconciliacion-lecciones.spec.md
# Los fixtures usan un vault temporal; nunca tocan vaults/SaviaLearning real.

SCRIPT="scripts/learning-reconcile.sh"
REPORT=output/learning-loop/reconcile.jsonl

setup() {
  cd "$(dirname "$BATS_TEST_FILENAME")/.." || exit 1
  FIXDIR=$(mktemp -d)
  mkdir -p "$FIXDIR/learning"
  # backup real report si existe
  BABK="${BATS_TEST_TMPDIR:-/tmp}/reconcile.bak"
  [[ -f "$REPORT" ]] && cp "$REPORT" "$BABK" || true
  rm -f "$REPORT"
}

teardown() {
  rm -rf "$FIXDIR"
  BABK="${BATS_TEST_TMPDIR:-/tmp}/reconcile.bak"
  [[ -f "$BABK" ]] && cp "$BABK" "$REPORT" || rm -f "$REPORT"
  rm -f "$BABK"
}

# Crea una LP sintética en el vault temporal.
# $1=id $2=provenance $3=target $4=change $5=evidence_hash
make_lp() {
  local id="$1" prov="$2" tgt="$3" chg="$4" hash="${5:-ev-$1}"
  cat > "$FIXDIR/learning/${id}.md" << EOF
---
  id: $id
  type: learning_proposal
  provenance: $prov
  lifecycle: proposed
  target: $tgt
  evidence_hash: $hash
---
# Learning Proposal $id

## Diagnóstico
diagnóstico de prueba para $id

## Cambio propuesto
$chg
EOF
}

@test "AC-01: --detect detecta par con mismo target y alta similitud" {
  make_lp LP-D1 INFERRED criterio "siempre consultar las cúpulas primero antes de grep" ev-1
  make_lp LP-D2 INFERRED criterio "consultar las cúpulas de conocimiento antes de buscar en ficheros" ev-2
  run bash "$SCRIPT" --vault "$FIXDIR" --detect
  [[ "$status" -eq 0 ]]
  echo "$output" | grep -q "LP-D1"
  echo "$output" | grep -q "LP-D2"
}

@test "AC-02: mismo evidence_hash no reporta par (RN-03, idempotencia)" {
  make_lp LP-I1 INFERRED criterio "mismo principio" ev-shared
  make_lp LP-I2 INFERRED criterio "mismo principio" ev-shared
  run bash "$SCRIPT" --vault "$FIXDIR" --detect
  [[ "$status" -eq 0 ]]
  if echo "$output" | grep -q "PAIR"; then false; fi
}

@test "AC-03: human_authored vs INFERRED → auto-resolve" {
  make_lp LP-A1 human_authored criterio "principio X" ev-a
  make_lp LP-A2 INFERRED criterio "principio X" ev-b
  run bash "$SCRIPT" --vault "$FIXDIR" --classify LP-A1 LP-A2
  [[ "$status" -eq 0 ]]
  echo "$output" | grep -q '"bucket":"auto-resolve"'
  echo "$output" | grep -q "a-wins"
}

@test "AC-03b: INFERRED vs human_authored → auto-resolve b-wins" {
  make_lp LP-B1 INFERRED criterio "principio Y" ev-c
  make_lp LP-B2 human_authored criterio "principio Y" ev-d
  run bash "$SCRIPT" --vault "$FIXDIR" --classify LP-B1 LP-B2
  [[ "$status" -eq 0 ]]
  echo "$output" | grep -q '"bucket":"auto-resolve"'
  echo "$output" | grep -q "b-wins"
}

@test "AC-04: mismo target, ambos INFERRED, alta similitud → evolution" {
  make_lp LP-E1 INFERRED skill "acceder primero a las cúpulas de conocimiento" ev-e
  make_lp LP-E2 INFERRED skill "acceder primero a las cúpulas de conocimiento persistido" ev-f
  run bash "$SCRIPT" --vault "$FIXDIR" --classify LP-E1 LP-E2
  [[ "$status" -eq 0 ]]
  echo "$output" | grep -q '"bucket":"evolution"'
}

@test "AC-05: mismo target, INFERRED, baja similitud, misma autoridad → conflict-doc" {
  make_lp LP-C1 INFERRED criterio "principio completamente distinto uno" ev-g
  make_lp LP-C2 INFERRED criterio "otro tema sin relación ninguna con el anterior" ev-h
  run bash "$SCRIPT" --vault "$FIXDIR" --classify LP-C1 LP-C2
  [[ "$status" -eq 0 ]]
  echo "$output" | grep -q '"bucket":"conflict-doc"'
}

@test "AC-06: --report consolida JSONL con campos del contrato" {
  make_lp LP-R1 INFERRED criterio "mismo principio revisado" ev-r1
  make_lp LP-R2 INFERRED criterio "mismo principio revisado" ev-r2
  run bash "$SCRIPT" --vault "$FIXDIR" --classify LP-R1 LP-R2
  [[ "$status" -eq 0 ]]
  [[ -f "$REPORT" ]]
  cat "$REPORT" | python3 -c "
import json, sys
d = json.loads(sys.stdin.read())
for k in ['ts','id_a','id_b','bucket','proposal']:
    assert k in d, k
"
}

@test "AC-07: hashes de CRITERIO.md y CONSTITUCION.md invariantes" {
  local h1 h2
  h1=$(sha256sum CRITERIO.md | cut -d' ' -f1)
  h2=$(sha256sum .claude/CONSTITUCION.md | cut -d' ' -f1)
  make_lp LP-V1 INFERRED criterio "principio invariante" ev-v1
  make_lp LP-V2 human_authored criterio "principio invariante" ev-v2
  bash "$SCRIPT" --vault "$FIXDIR" --classify LP-V1 LP-V2 >/dev/null
  [[ "$(sha256sum CRITERIO.md | cut -d' ' -f1)" == "$h1" ]]
  [[ "$(sha256sum .claude/CONSTITUCION.md | cut -d' ' -f1)" == "$h2" ]]
}

@test "AC-08 + RN-04: sin vendor names, bash -n, sistema OK (sin LLM, sin red)" {
  bash -n "$SCRIPT"
  run grep -niE "openai|anthropic|gpt-|gemini|qwen|deepseek" "$SCRIPT"
  [[ "$status" -ne 0 ]]
}

@test "RN-01: classify nunca modifica CRITERIO ni levanta provenance" {
  make_lp LP-N1 INFERRED criterio "principio N" ev-n
  make_lp LP-N2 INFERRED criterio "principio N" ev-n2
  # capturar lifecycle/provenance antes
  local prov_before
  prov_before=$(grep -m1 '^  provenance: ' CRITERIO.md 2>/dev/null || echo ok)
  bash "$SCRIPT" --vault "$FIXDIR" --classify LP-N1 LP-N2 >/dev/null
  # el cambio de un LP en el vault NO se toca (solo lectura)
  grep -q '^  provenance: INFERRED$' "$FIXDIR/learning/LP-N1.md"
}

@test "input inválido → exit 2 (classify sin args)" {
  run bash "$SCRIPT" --classify
  [[ "$status" -eq 2 ]]
}

@test "vault ausente → exit 3" {
  run bash "$SCRIPT" --vault /nonexistent --detect
  [[ "$status" -eq 3 ]]
}
# --- S03c: ramas del árbol 3-bucket sin cubrir (SPEC-183) ---

@test "classify: mismo evidence_hash → skip-idempotent aunque difieran provenance y texto" {
  make_lp LP-S1 human_authored criterio "texto uno" ev-same
  make_lp LP-S2 INFERRED skill "texto totalmente otro" ev-same
  run bash "$SCRIPT" --vault "$FIXDIR" --classify LP-S1 LP-S2
  [[ "$status" -eq 0 ]]
  echo "$output" | grep -q '"bucket":"skip-idempotent"'
  echo "$output" | grep -q '"proposal":"same-evidence"'
}

@test "classify: targets distintos con texto idéntico → conflict-doc (no evolution)" {
  make_lp LP-T1 INFERRED criterio "acceder primero a las cúpulas" ev-t1
  make_lp LP-T2 INFERRED skill "acceder primero a las cúpulas" ev-t2
  run bash "$SCRIPT" --vault "$FIXDIR" --classify LP-T1 LP-T2
  [[ "$status" -eq 0 ]]
  echo "$output" | grep -q '"bucket":"conflict-doc"'
  echo "$output" | grep -q 'escalate-human'
}

@test "classify: ambas human_authored y mismo target nunca es auto-resolve" {
  make_lp LP-H1 human_authored criterio "principio uno distinto" ev-h1
  make_lp LP-H2 human_authored criterio "otra cosa sin relación alguna aquí" ev-h2
  run bash "$SCRIPT" --vault "$FIXDIR" --classify LP-H1 LP-H2
  [[ "$status" -eq 0 ]]
  if echo "$output" | grep -q 'auto-resolve'; then false; fi
  echo "$output" | grep -q '"bucket":"conflict-doc"'
}

@test "classify: el JSON registra provenance de ambas lecciones" {
  make_lp LP-J1 human_authored criterio "principio J" ev-j1
  make_lp LP-J2 INFERRED criterio "principio J" ev-j2
  run bash "$SCRIPT" --vault "$FIXDIR" --classify LP-J1 LP-J2
  [[ "$status" -eq 0 ]]
  echo "$output" | python3 -c "
import json, sys
d = json.loads(sys.stdin.read())
assert d['prov_a'] == 'human_authored', d
assert d['prov_b'] == 'INFERRED', d
assert d['id_a'] == 'LP-J1' and d['id_b'] == 'LP-J2', d"
}

@test "classify: lección inexistente → exit 3 y no escribe informe" {
  make_lp LP-X1 INFERRED criterio "principio X" ev-x1
  run bash "$SCRIPT" --vault "$FIXDIR" --classify LP-X1 LP-NOPE
  [[ "$status" -eq 3 ]]
  echo "$output" | grep -q "lesson not found: LP-NOPE"
  [[ ! -s "$REPORT" ]]
}

@test "classify: umbral SCL_RECONCILE_THRESHOLD=0.99 degrada evolution a conflict-doc" {
  make_lp LP-U1 INFERRED skill "acceder primero a las cúpulas de conocimiento" ev-u1
  make_lp LP-U2 INFERRED skill "acceder primero a las cúpulas de conocimiento persistido" ev-u2
  SCL_RECONCILE_THRESHOLD=0.99 run bash "$SCRIPT" --vault "$FIXDIR" --classify LP-U1 LP-U2
  [[ "$status" -eq 0 ]]
  echo "$output" | grep -q '"bucket":"conflict-doc"'
  SCL_RECONCILE_THRESHOLD=0.10 run bash "$SCRIPT" --vault "$FIXDIR" --classify LP-U1 LP-U2
  echo "$output" | grep -q '"bucket":"evolution"'
}

@test "detect: targets distintos no forman par aunque el texto coincida" {
  make_lp LP-P1 INFERRED criterio "consultar las cúpulas antes de grep" ev-p1
  make_lp LP-P2 INFERRED skill "consultar las cúpulas antes de grep" ev-p2
  run bash "$SCRIPT" --vault "$FIXDIR" --detect
  [[ "$status" -eq 0 ]]
  [[ -z "$output" ]]
}

@test "detect: lecciones sin evidence_hash se ignoran (vault vacío → sin salida)" {
  run bash "$SCRIPT" --vault "$FIXDIR" --detect
  [[ "$status" -eq 0 ]]
  [[ -z "$output" ]]
  cat > "$FIXDIR/learning/LP-NH.md" <<'EOT'
---
  id: LP-NH
  provenance: INFERRED
  target: criterio
---
## Cambio propuesto
algo
EOT
  cp "$FIXDIR/learning/LP-NH.md" "$FIXDIR/learning/LP-NH2.md"
  run bash "$SCRIPT" --vault "$FIXDIR" --detect
  [[ -z "$output" ]]
}

@test "detect: la línea PAIR incluye similitud, provenance y target" {
  make_lp LP-Q1 INFERRED criterio "siempre consultar las cúpulas primero antes de grep" ev-q1
  make_lp LP-Q2 human_authored criterio "consultar las cúpulas primero antes de buscar con grep" ev-q2
  run bash "$SCRIPT" --vault "$FIXDIR" --detect
  [[ "$status" -eq 0 ]]
  echo "$output" | grep -qE '^PAIR LP-Q1 LP-Q2 sim=0\.[0-9]{3} prov=INFERRED/human_authored target=criterio$'
}

@test "report: cuenta pares por bucket tras varios classify" {
  make_lp LP-Y1 human_authored criterio "p" ev-y1
  make_lp LP-Y2 INFERRED criterio "p" ev-y2
  make_lp LP-Y3 INFERRED criterio "q totalmente aparte" ev-y3
  bash "$SCRIPT" --vault "$FIXDIR" --classify LP-Y1 LP-Y2 >/dev/null
  bash "$SCRIPT" --vault "$FIXDIR" --classify LP-Y2 LP-Y3 >/dev/null
  run bash "$SCRIPT" --vault "$FIXDIR" --report
  [[ "$status" -eq 0 ]]
  echo "$output" | grep -q "pairs=2"
  echo "$output" | grep -q "'auto-resolve': 1"
  echo "$output" | grep -q "'conflict-doc': 1"
}

@test "report: sin informe previo avisa y sale 0 (caso vacío)" {
  run bash "$SCRIPT" --vault "$FIXDIR" --report
  [[ "$status" -eq 0 ]]
  echo "$output" | grep -q "no report yet"
}

@test "report: ignora líneas corruptas del JSONL sin fallar" {
  mkdir -p "$(dirname "$REPORT")"
  printf '%s\n' 'no es json' '{"bucket":"evolution"}' > "$REPORT"
  run bash "$SCRIPT" --vault "$FIXDIR" --report
  [[ "$status" -eq 0 ]]
  echo "$output" | grep -q "pairs=1"
}

@test "sin modo → exit 2 con uso" {
  run bash "$SCRIPT" --vault "$FIXDIR"
  [[ "$status" -eq 2 ]]
  echo "$output" | grep -q "usage"
}

@test "el script declara set -uo pipefail" {
  grep -q '^set -uo pipefail' "$SCRIPT"
}
