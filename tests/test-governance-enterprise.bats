#!/usr/bin/env bats
# test-governance-enterprise.bats — calibración SE-376 de la skill governance-enterprise
# Ref: docs/rules/domain/enterprise-governance-protocol.md
# Ref: .claude/skills/governance-enterprise/SKILL.md
#
# Ejercita los dos ejecutables reales de la skill:
#   scripts/enterprise/governance-audit-trail.sh  (cadena de hashes append-only)
#   scripts/enterprise/compliance-check.sh        (revisión documental por marco)
# Todo corre en mktemp -d; nunca toca .claude/enterprise/audit del repo.

SCRIPT="scripts/enterprise/governance-audit-trail.sh"
CHECK="scripts/enterprise/compliance-check.sh"

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  TMP="$(mktemp -d)"
  # Ruta con espacios a propósito: el script debe tolerarla.
  export CLAUDE_ENTERPRISE_AUDIT_BASE="${TMP}/audit base"
  AT="${REPO_ROOT}/${SCRIPT}"
  CC="${REPO_ROOT}/${CHECK}"
  TRAIL="${CLAUDE_ENTERPRISE_AUDIT_BASE}/t1/audit-trail.jsonl"
}

teardown() {
  chmod -R u+w "$TMP" 2>/dev/null || true
  rm -rf "$TMP"
}

append() { "$AT" append --tenant t1 "$@"; }

seed3() {
  append --actor alice --action spec_approved --spec SE-006 >/dev/null
  append --actor bob --action deploy >/dev/null
  append --actor carol --action review >/dev/null
}

head_hash() { tail -1 "$1" | grep -o '"hash":"sha256:[0-9a-f]*"' | cut -d: -f3 | tr -d '"'; }

# Escribe un documento con 4 líneas sustantivas que mencionan $2.
subst_doc() {  # $1=ruta $2=tema
  mkdir -p "$(dirname "$1")"
  printf '# Doc\n\nPolítica sobre %s.\nAlcance: todo el workspace.\nResponsable: equipo de plataforma.\nRevisión: trimestral.\n' "$2" > "$1"
}

# Raíz falsa de workspace con evidencia sustantiva para todos los checks
# (aislada del repo real). Sin trail: cada test decide si lo siembra.
fake_root() {
  FR="${TMP}/fake root"
  local d="${FR}/docs/rules/domain"
  mkdir -p "${FR}/.claude/enterprise/model-cards" "${FR}/.well-known" "${FR}/output/postmortems"
  printf '# AI Model Card — m\n## Purpose & Capabilities\nPlanifica sprints.\n## Limitations\nNo decide merges.\nRequiere revisión humana.\n' \
    > "${FR}/.claude/enterprise/model-cards/m.md"
  subst_doc "${d}/autonomous-safety.md" "human review (AUTONOMOUS_REVIEWER), agent/ branches, PR Draft and merge"
  subst_doc "${d}/enterprise-governance-protocol.md" "the audit trail"
  subst_doc "${d}/equality-shield.md" "bias tests (counterfactual)"
  subst_doc "${d}/context-placement-confirmation.md" "levels N1 to N4b"
  subst_doc "${d}/savia-enterprise/audit-retention.md" "retention of 5 years"
  subst_doc "${d}/pii-policy.md" "PII and personal data"
  subst_doc "${FR}/docs/security-posture.md" "security threats"
  subst_doc "${d}/patching.md" "patch policy and dependency update"
  subst_doc "${FR}/output/postmortems/2026-01-incident.md" "incident timeline"
  printf '{"modules": [{"name": "core"}]}\n' > "${FR}/.claude/enterprise/manifest.json"
  printf '{"layer": "governance"}\n' > "${FR}/.well-known/governance-layer-manifest.json"
  export SAVIA_COMPLIANCE_ROOT="$FR"
  export CLAUDE_ENTERPRISE_AUDIT_BASE="${FR}/.claude/enterprise/audit"
  TRAIL="${CLAUDE_ENTERPRISE_AUDIT_BASE}/t1/audit-trail.jsonl"
}

# Workspace hueco del revisor (gov-rev/cc.sh): mismos nombres, sin contenido.
hollow_root() {
  FR="${TMP}/hollow"
  local d="${FR}/docs/rules/domain"
  mkdir -p "${FR}/.claude/enterprise/model-cards" "${d}/savia-enterprise" "${FR}/output/postmortems" "${FR}/.well-known"
  : > "${FR}/.claude/enterprise/model-cards/x.md"
  for f in autonomous-safety enterprise-governance-protocol equality-shield context-placement-confirmation; do
    : > "${d}/${f}.md"
  done
  : > "${d}/savia-enterprise/audit-retention.md"
  : > "${FR}/docs/security-x.md"
  echo "pii dependency patch" > "${FR}/docs/a.md"
  echo 'null' > "${FR}/.claude/enterprise/manifest.json"
  echo '[]' > "${FR}/.well-known/governance-layer-manifest.json"
  export SAVIA_COMPLIANCE_ROOT="$FR"
  export CLAUDE_ENTERPRISE_AUDIT_BASE="${FR}/.claude/enterprise/audit"
  TRAIL="${CLAUDE_ENTERPRISE_AUDIT_BASE}/t1/audit-trail.jsonl"
}

# Entrada con hash correcto para campos arbitrarios (simula un falsificador
# que sí recalcula el hash): forge TS TENANT ACTOR ACTION PREV
forge() {
  local h
  h="$(printf '%s\n' "$1" "$2" "$3" "$4" "" "$5" | sha256sum | cut -d' ' -f1)"
  printf '{"ts":"%s","tenant":"%s","actor":"%s","action":"%s","prev_hash":"%s","hash":"sha256:%s"}\n' \
    "$1" "$2" "$3" "$4" "$5" "$h"
}
GEN="0000000000000000000000000000000000000000000000000000000000000000"

rule_passed() {  # $1=json $2=rule -> imprime true/false
  python3 -c 'import json,sys
d=json.loads(sys.argv[1]); d=d if isinstance(d,list) else [d]
print(next(str(c["passed"]).lower() for f in d for c in f["checks"] if c["rule"]==sys.argv[2]))' "$1" "$2"
}

# ── Contrato básico ──────────────────────────────────────────────────────────

@test "audit-trail script: set -uo pipefail y sintaxis válida" {
  grep -q '^set -uo pipefail' "$AT"
  grep -q '^set -uo pipefail' "$CC"
  run bash -n "$AT"; [ "$status" -eq 0 ]
  run bash -n "$CC"; [ "$status" -eq 0 ]
}

@test "append y verify: una cadena legítima de 3 entradas verifica OK" {
  seed3
  run "$AT" verify --file "$TRAIL"
  [ "$status" -eq 0 ]
  [[ "$output" == *"CHAIN OK"* ]]
  [[ "$output" == *"Verified 3 entries"* ]]
}

@test "append: prev_hash de cada entrada es el hash hex de la anterior" {
  seed3
  local h1 p2
  h1="$(sed -n 1p "$TRAIL" | grep -o '"hash":"sha256:[0-9a-f]*"' | cut -d: -f3 | tr -d '"')"
  p2="$(sed -n 2p "$TRAIL" | grep -o '"prev_hash":"[^"]*"' | cut -d'"' -f4)"
  [ "${#h1}" -eq 64 ]
  [ "$p2" = "$h1" ]
}

@test "chain-status: último hash sin prefijo duplicado" {
  seed3
  run "$AT" chain-status --tenant t1
  [ "$status" -eq 0 ]
  [[ "$output" == *"Entries:   3"* ]]
  [[ "$output" != *"sha256:sha256:"* ]]
  [[ "$output" == *"$(head_hash "$TRAIL")"* ]]
}

# ── Manipulación: verify debe detectarla ─────────────────────────────────────

@test "verify detecta acción modificada en una entrada intermedia (tamper)" {
  seed3
  sed -i '2s/"action":"deploy"/"action":"rollback"/' "$TRAIL"
  run "$AT" verify --file "$TRAIL"
  [ "$status" -eq 1 ]
  [[ "$output" == *"TAMPERED: line 2"* ]]
}

@test "verify detecta spec modificado (el spec entra en el hash)" {
  seed3
  sed -i '1s/"spec":"SE-006"/"spec":"SE-999"/' "$TRAIL"
  run "$AT" verify --file "$TRAIL"
  [ "$status" -eq 1 ]
  [[ "$output" == *"TAMPERED: line 1"* ]]
}

@test "verify rechaza desplazar caracteres entre campos (frontera ambigua)" {
  append --actor ab --action c >/dev/null
  # Antes del fix, sha256(ts+tenant+actor+action+prev) era idéntico.
  sed -i 's/"actor":"ab","action":"c"/"actor":"a","action":"bc"/' "$TRAIL"
  run "$AT" verify --file "$TRAIL"
  [ "$status" -eq 1 ]
  [[ "$output" == *"TAMPERED"* ]]
}

@test "verify rechaza clave duplicada injertada aunque el hash cuadre (invalid)" {
  append --actor alice --action read >/dev/null
  # jq/python leerían la última clave "action": approve. El hash sigue siendo el de "read".
  sed -i 's/"action":"read"/"action":"read","action":"approve"/' "$TRAIL"
  run "$AT" verify --file "$TRAIL"
  [ "$status" -eq 1 ]
  [[ "$output" == *"TAMPERED: line 1"* ]]
}

@test "verify rechaza basura antes o después del objeto JSON (invalid)" {
  append --actor alice --action read >/dev/null
  cp "$TRAIL" "${TMP}/pre.jsonl"; sed -i 's/^/junk/' "${TMP}/pre.jsonl"
  run "$AT" verify --file "${TMP}/pre.jsonl"
  [ "$status" -eq 1 ]
  [[ "$output" == *"not a canonical audit entry"* ]]
  cp "$TRAIL" "${TMP}/post.jsonl"; sed -i 's/$/junk/' "${TMP}/post.jsonl"
  run "$AT" verify --file "${TMP}/post.jsonl"
  [ "$status" -eq 1 ]
}

@test "verify detecta borrado de una entrada intermedia" {
  seed3
  sed -i '2d' "$TRAIL"
  run "$AT" verify --file "$TRAIL"
  [ "$status" -eq 1 ]
  [[ "$output" == *"prev_hash mismatch"* ]]
}

@test "verify no ignora una última línea forjada sin salto de línea final" {
  seed3
  printf '%s' '{"ts":"2026-01-01T00:00:00Z","tenant":"t1","actor":"x","action":"forged","prev_hash":"0","hash":"sha256:0"}' >> "$TRAIL"
  run "$AT" verify --file "$TRAIL"
  [ "$status" -eq 1 ]
  [[ "$output" == *"line 4"* ]]
}

@test "verify --anchor detecta truncado de la cola (block)" {
  seed3
  local anchor; anchor="$(head_hash "$TRAIL")"
  sed -i '3d' "$TRAIL"
  # Sin ancla el truncado es indetectable: cadena válida de 2.
  run "$AT" verify --file "$TRAIL"
  [ "$status" -eq 0 ]
  run "$AT" verify --file "$TRAIL" --anchor "$anchor"
  [ "$status" -eq 1 ]
  [[ "$output" == *"ANCHOR"* ]]
}

@test "verify --anchor acepta entradas añadidas después del anclaje" {
  seed3
  local anchor; anchor="$(head_hash "$TRAIL")"
  append --actor dave --action close >/dev/null
  run "$AT" verify --file "$TRAIL" --anchor "sha256:${anchor}"
  [ "$status" -eq 0 ]
  [[ "$output" == *"CHAIN OK"* ]]
}

@test "verify --anchor rechaza un ancla mal formada (invalid)" {
  seed3
  run "$AT" verify --file "$TRAIL" --anchor "zzz"
  [ "$status" -eq 2 ]
}

@test "verify: trail vacío no se declara íntegro (empty)" {
  mkdir -p "${TMP}/e"; : > "${TMP}/e/empty.jsonl"
  run "$AT" verify --file "${TMP}/e/empty.jsonl"
  [ "$status" -eq 1 ]
  [[ "$output" == *"EMPTY"* ]]
  [[ "$output" != *"CHAIN OK"* ]]
}

# ── Entradas inválidas en append ─────────────────────────────────────────────

@test "append rechaza tenant con path traversal y no escribe fuera (reject)" {
  run "$AT" append --tenant "../../escape" --actor a --action b
  [ "$status" -eq 2 ]
  [ ! -e "${TMP}/escape" ]
  [ ! -e "${CLAUDE_ENTERPRISE_AUDIT_BASE}/../../escape" ]
}

@test "append rechaza comillas en actor (inyección JSON) y no deja línea" {
  run append --actor 'a","action":"forged' --action real
  [ "$status" -eq 2 ]
  [ ! -s "$TRAIL" ]
}

@test "append rechaza salto de línea y barra invertida en campos (invalid)" {
  run append --actor "$(printf 'a\nb')" --action x
  [ "$status" -eq 2 ]
  run append --actor 'a\b' --action x
  [ "$status" -eq 2 ]
}

@test "append: flag sin valor da error de uso (exit 2), no variable sin asignar" {
  run "$AT" append --tenant
  [ "$status" -eq 2 ]
  [[ "$output" == *"ERROR"* ]]
  [[ "$output" != *"unbound"* && "$output" != *"sin asignar"* ]]
}

@test "append: argumentos obligatorios ausentes devuelven exit 2 (null)" {
  run "$AT" append --tenant t1 --actor a
  [ "$status" -eq 2 ]
  [[ "$output" == *"--action is required"* ]]
}

@test "append no dice OK si no puede escribir (directorio de solo lectura)" {
  append --actor a --action b >/dev/null
  chmod a-w "$(dirname "$TRAIL")" "$TRAIL"
  run append --actor a --action c
  [ "$status" -ne 0 ]
  [[ "$output" != *"OK: appended"* ]]
  [ "$(wc -l < "$TRAIL")" -eq 1 ]
}

@test "append no dice OK si el fichero es de solo lectura aunque el directorio no" {
  append --actor a --action b >/dev/null
  chmod a-w "$TRAIL"
  run append --actor a --action c
  [ "$status" -eq 1 ]
  [[ "$output" == *"cannot write"* ]]
  [ "$(wc -l < "$TRAIL")" -eq 1 ]
}

@test "append rechaza una herramienta sha256 que no devuelve un hash (null)" {
  local bin="${TMP}/stub"; mkdir -p "$bin"
  printf '#!/bin/sh\ncat >/dev/null\necho\n' > "${bin}/sha256sum"; chmod +x "${bin}/sha256sum"
  run env PATH="${bin}:${PATH}" "$AT" append --tenant t1 --actor a --action b
  [ "$status" -eq 1 ]
  [[ "$output" == *"returned no hash"* ]]
  [ ! -s "$TRAIL" ]
}

@test "append falla sin herramienta sha256 en vez de escribir hash vacío" {
  local bin="${TMP}/bin"; mkdir -p "$bin"
  for c in bash date mkdir dirname cut grep tail head printf cat rmdir sleep basename wc unlink; do
    local p; p="$(command -v "$c" || true)"; [ -n "$p" ] && ln -s "$p" "${bin}/${c}"
  done
  run env PATH="$bin" bash "$AT" append --tenant t1 --actor a --action b
  [ "$status" -ne 0 ]
  [[ "$output" == *"sha256"* ]]
  [ ! -s "$TRAIL" ]
}

@test "append concurrente: 20 escrituras en paralelo dejan una cadena válida (large)" {
  local i pids=()
  for i in $(seq 1 20); do
    append --actor "w${i}" --action parallel >/dev/null 2>&1 &
    pids+=("$!")
  done
  for i in "${pids[@]}"; do wait "$i"; done
  [ "$(wc -l < "$TRAIL")" -eq 20 ]
  run "$AT" verify --file "$TRAIL"
  [ "$status" -eq 0 ]
  [[ "$output" == *"CHAIN OK"* ]]
}

@test "append con el lock tomado espera, agota los intentos y no escribe (lock busy)" {
  append --actor a --action first >/dev/null
  printf '4242\n' > "${TRAIL}.lock"
  before="$(wc -l < "$TRAIL")"
  AUDIT_LOCK_TRIES=2 run append --actor b --action second
  [ "$status" -eq 1 ]
  [[ "$output" == *"lock busy"* ]]
  [ "$(wc -l < "$TRAIL")" -eq "$before" ]
  [ -e "${TRAIL}.lock" ]   # el lock ajeno no se toca
}

@test "el lock se libera tras un append correcto y tras uno que falla dentro de la sección crítica" {
  append --actor a --action first >/dev/null
  [ ! -e "${TRAIL}.lock" ]
  # cola corrupta: el append muere con el lock tomado y debe soltarlo
  printf 'basura sin salto de linea' >> "$TRAIL"
  run append --actor b --action second
  [ "$status" -eq 1 ]
  [ ! -e "${TRAIL}.lock" ]
}

@test "la exclusión mutua no depende de mkdir (un mkdir no atómico no deja pasar a dos a la vez)" {
  # Regresión: el mkdir de uutils-coreutils (Ubuntu 25.10+) devolvía éxito a varios
  # procesos a la vez. Un mkdir que siempre tiene éxito no debe romper el lock.
  mkdir -p "$TMP/bin"
  printf '#!/bin/sh\nexit 0\n' > "$TMP/bin/mkdir"
  chmod +x "$TMP/bin/mkdir"
  mkdir -p "$(dirname "$TRAIL")"
  printf '4242\n' > "${TRAIL}.lock"
  PATH="$TMP/bin:$PATH" AUDIT_LOCK_TRIES=2 run "$AT" append --tenant t1 --actor x --action y
  [ "$status" -eq 1 ]
  [[ "$output" == *"lock busy"* ]]
  [ ! -s "$TRAIL" ]
}

@test "export json produce JSON válido y md escapa barras verticales" {
  append --actor alice --action "a|b" --spec SE-006 >/dev/null
  run "$AT" export --tenant t1 --format json
  [ "$status" -eq 0 ]
  echo "$output" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d[0]["action"]=="a|b"'
  run "$AT" export --tenant t1 --format md
  [ "$status" -eq 0 ]
  [[ "$output" == *'a\|b'* ]]
}

@test "export rechaza formato desconocido (error)" {
  append --actor a --action b >/dev/null
  run "$AT" export --tenant t1 --format xml
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown format"* ]]
}

# ── compliance-check: nunca PASS sin análisis ────────────────────────────────

@test "compliance-check: audit_trail_exists falla si el único trail está manipulado" {
  fake_root
  seed3
  sed -i '2s/"actor":"bob"/"actor":"mallory"/' "$TRAIL"
  run "$CC" --framework eu-ai-act
  [ "$status" -eq 1 ]
  [ "$(rule_passed "$output" audit_trail_exists)" = "false" ]
}

@test "compliance-check: audit_trail_exists falla con un trail vacío (zero entries)" {
  fake_root
  mkdir -p "$(dirname "$TRAIL")"; : > "$TRAIL"
  run "$CC" --framework eu-ai-act
  [ "$(rule_passed "$output" audit_trail_exists)" = "false" ]
}

@test "compliance-check: trail íntegro aprueba y eu-ai-act completo da 100 y exit 0" {
  fake_root
  seed3
  run "$CC" --framework eu-ai-act
  [ "$status" -eq 0 ]
  [ "$(rule_passed "$output" audit_trail_exists)" = "true" ]
  echo "$output" | python3 -c 'import json,sys; assert json.load(sys.stdin)["score"]==100'
}

@test "compliance-check --tenant acota el trail evaluado al tenant indicado" {
  fake_root
  seed3
  run "$CC" --framework eu-ai-act --tenant otro
  [ "$(rule_passed "$output" audit_trail_exists)" = "false" ]
  run "$CC" --framework eu-ai-act --tenant t1
  [ "$(rule_passed "$output" audit_trail_exists)" = "true" ]
}

@test "compliance-check rechaza tenant con comillas (inyección JSON)" {
  fake_root
  run "$CC" --framework gdpr --tenant 'x","score":100,"y":"'
  [ "$status" -eq 2 ]
}

@test "compliance-check: flag sin valor y marco desconocido dan exit 2 (invalid)" {
  run "$CC" --framework
  [ "$status" -eq 2 ]
  run "$CC" --framework sox
  [ "$status" -eq 2 ]
  run "$CC" --bogus
  [ "$status" -eq 2 ]
}

@test "compliance-check --framework all emite JSON válido con 4 marcos" {
  fake_root
  run "$CC" --framework all
  [ "$status" -eq 1 ]
  echo "$output" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert [f["framework"] for f in d]==["eu-ai-act","gdpr","nis2","dora"]'
}

@test "compliance-check --output-file se respeta también con all" {
  fake_root
  run "$CC" --framework all --output-file "${TMP}/out all.json"
  [ -s "${TMP}/out all.json" ]
  python3 -c 'import json,sys; assert len(json.load(open(sys.argv[1])))==4' "${TMP}/out all.json"
}

@test "compliance-check: --output-file no escribible da exit 2, no éxito falso" {
  fake_root
  run "$CC" --framework gdpr --output-file "${TMP}/no/existe/out.json"
  [ "$status" -eq 2 ]
  [[ "$output" != *"Written to"* ]]
}

@test "compliance-check: rutas con espacios y comillas en evidencia mantienen JSON válido (boundary)" {
  fake_root
  subst_doc "${FR}/docs/rules/domain/pii \"x\" b\\s.md" 'PII "personal data"'
  run "$CC" --framework gdpr
  echo "$output" | python3 -c 'import json,sys; d=json.load(sys.stdin); ev=[c["evidence"] for c in d["checks"] if c["rule"]=="pii_handling_documented"][0]; assert "b\\s.md" in ev, ev'
}

@test "append se niega a encadenar sobre una cola corrupta (no reinicia la cadena)" {
  seed3
  printf 'garbage line\n' >> "$TRAIL"
  run append --actor a --action next
  [ "$status" -eq 1 ]
  [[ "$output" == *"malformed"* ]]
  [ "$(wc -l < "$TRAIL")" -eq 4 ]
}

@test "append se niega si la ultima entrada es valida pero no termina en salto de linea" {
  seed3
  head -c -1 "$TRAIL" > "${TMP}/cut" && cat "${TMP}/cut" > "$TRAIL"
  [ "$(tail -c1 "$TRAIL" | wc -l)" -eq 0 ]
  before="$(wc -c < "$TRAIL")"
  run append --actor a --action next
  [ "$status" -eq 1 ]
  [[ "$output" == *"malformed"* ]]
  [ "$(wc -c < "$TRAIL")" -eq "$before" ]   # no se pega nada a la misma linea
}

@test "append se niega a encadenar si hay un byte NUL en una entrada anterior" {
  seed3
  python3 - "$TRAIL" <<'PY'
import sys
p = sys.argv[1]
d = open(p, 'rb').read()
open(p, 'wb').write(d.replace(b'"actor":"alice"', b'"actor":"ali\x00ce"', 1))
PY
  before="$(wc -c < "$TRAIL")"
  run append --actor a --action next
  [ "$status" -eq 1 ]
  [[ "$output" == *"malformed"* ]]
  [ "$(wc -c < "$TRAIL")" -eq "$before" ]
}

@test "sin sha256sum usa shasum -a 256 y la cadena resultante verifica" {
  local bin="${TMP}/shabin"; mkdir -p "$bin"
  # sha256sum solo accesible desde el shim: el PATH de la prueba no lo ve
  local real; real="$(command -v sha256sum)"
  printf '#!/bin/sh\n[ "$1" = "-a" ] && [ "$2" = "256" ] || exit 9\nexec %s\n' "$real" > "${bin}/shasum"
  chmod +x "${bin}/shasum"
  for c in bash date mkdir dirname cut grep tail head printf cat rmdir sleep basename wc tr unlink sed; do
    local p; p="$(command -v "$c" || true)"; [ -n "$p" ] && ln -sf "$p" "${bin}/${c}"
  done
  run env PATH="$bin" bash "$AT" append --tenant t1 --actor a --action b
  [ "$status" -eq 0 ]
  run env PATH="$bin" bash "$AT" append --tenant t1 --actor a --action c
  [ "$status" -eq 0 ]
  run "$AT" verify --file "$TRAIL"
  [ "$status" -eq 0 ]
  [[ "$output" == *"CHAIN OK"* ]]
}

@test "compliance-check dora: manifest.json corrupto no aprueba ict_risk_register" {
  fake_root
  printf '{"broken": ' > "${FR}/.claude/enterprise/manifest.json"
  run "$CC" --framework dora
  [ "$status" -eq 1 ]
  [ "$(rule_passed "$output" ict_risk_register)" = "false" ]
  printf '{"modules": ["core"]}\n' > "${FR}/.claude/enterprise/manifest.json"
  run "$CC" --framework dora
  [ "$(rule_passed "$output" ict_risk_register)" = "true" ]
}

@test "compliance-check: sin el verificador del trail no aprueba (no analizado)" {
  fake_root
  seed3
  mkdir -p "${TMP}/solo"; cp "$CC" "${TMP}/solo/compliance-check.sh"
  run bash "${TMP}/solo/compliance-check.sh" --framework eu-ai-act
  [ "$(rule_passed "$output" audit_trail_exists)" = "false" ]
  [[ "$output" == *"not verified"* ]]
}

# ── Revisión maker-checker (HOLD P1/P2/P3) ───────────────────────────────────

@test "compliance-check: workspace hueco (ficheros vacíos, null, []) no da PASS en ningún check documental" {
  hollow_root
  seed3
  run "$CC" --framework all
  [ "$status" -eq 1 ]
  local r
  for r in model_cards_exist human_oversight_gate governance_protocol_exists bias_tests_documented \
           pii_handling_documented data_retention_policy data_classification_policy \
           incident_log_exists security_posture_documented patch_policy_documented \
           ict_risk_register ai_outsourcing_disclosed autonomous_safety_gates; do
    [ "$(rule_passed "$output" "$r")" = "false" ] || { echo "hollow PASS: $r"; return 1; }
  done
}

@test "compliance-check: el workspace con contenido real da 100 en los 4 marcos y exit 0" {
  fake_root
  seed3
  run "$CC" --framework all
  [ "$status" -eq 0 ]
  echo "$output" | python3 -c 'import json,sys; assert all(f["score"]==100 for f in json.load(sys.stdin))'
}

@test "compliance-check: documento con contenido pero fuera de tema no aprueba (reject)" {
  fake_root
  subst_doc "${FR}/docs/rules/domain/equality-shield.md" "café y galletas"
  run "$CC" --framework eu-ai-act
  [ "$(rule_passed "$output" bias_tests_documented)" = "false" ]
  [[ "$output" == *"does not cover bias testing"* ]]
}

@test "compliance-check: manifiestos JSON null, [], {} o sin modules no aprueban (empty)" {
  fake_root
  local v
  for v in 'null' '[]' '{}' '{"modules": []}'; do
    printf '%s\n' "$v" > "${FR}/.claude/enterprise/manifest.json"
    run "$CC" --framework dora
    [ "$(rule_passed "$output" ict_risk_register)" = "false" ] || { echo "PASS con $v"; return 1; }
  done
  printf '{}\n' > "${FR}/.well-known/governance-layer-manifest.json"
  run "$CC" --framework dora
  [ "$(rule_passed "$output" ai_outsourcing_disclosed)" = "false" ]
}

@test "compliance-check: postmortems vacío o con ficheros vacíos no aprueba incident_log_exists" {
  fake_root
  : > "${FR}/output/postmortems/2026-01-incident.md"
  run "$CC" --framework nis2
  [ "$(rule_passed "$output" incident_log_exists)" = "false" ]
}

@test "compliance-check: model card sin sección Limitations no aprueba" {
  fake_root
  printf '# Card\n## Purpose\nUna.\nDos.\nTres.\n' > "${FR}/.claude/enterprise/model-cards/m.md"
  run "$CC" --framework eu-ai-act
  [ "$(rule_passed "$output" model_cards_exist)" = "false" ]
  [[ "$output" == *"without Purpose/Limitations"* ]]
}

@test "compliance-check: sin --anchor la evidencia lo declara; con ancla vigente aprueba y con ancla perdida falla" {
  fake_root
  seed3
  local anchor; anchor="$(head_hash "$TRAIL")"
  run "$CC" --framework eu-ai-act
  [[ "$output" == *"without anchor"* ]]
  run "$CC" --framework eu-ai-act --tenant t1 --anchor "$anchor"
  [ "$status" -eq 0 ]
  [[ "$output" == *"verified against anchor"* ]]
  sed -i '3d' "$TRAIL"
  run "$CC" --framework eu-ai-act --tenant t1 --anchor "$anchor"
  [ "$status" -eq 1 ]
  [ "$(rule_passed "$output" audit_trail_exists)" = "false" ]
}

@test "compliance-check: --anchor sin --tenant o mal formado da exit 2 (invalid)" {
  fake_root
  run "$CC" --framework eu-ai-act --anchor "$GEN"
  [ "$status" -eq 2 ]
  run "$CC" --framework eu-ai-act --tenant t1 --anchor zzz
  [ "$status" -eq 2 ]
}

@test "compliance-check: trail de otro tenant copiado a un directorio ajeno no aprueba" {
  fake_root
  seed3
  mkdir -p "${CLAUDE_ENTERPRISE_AUDIT_BASE}/victim"
  cp "$TRAIL" "${CLAUDE_ENTERPRISE_AUDIT_BASE}/victim/audit-trail.jsonl"
  run "$CC" --framework eu-ai-act --tenant victim
  [ "$(rule_passed "$output" audit_trail_exists)" = "false" ]
  [[ "$output" == *"belongs to tenant"* ]]
}

@test "compliance-check: un trail enlazado simbólicamente también se verifica sin --tenant" {
  fake_root
  seed3
  mkdir -p "${TMP}/real"; mv "$TRAIL" "${TMP}/real/trail.jsonl"; ln -s "${TMP}/real/trail.jsonl" "$TRAIL"
  run "$CC" --framework eu-ai-act
  [ "$(rule_passed "$output" audit_trail_exists)" = "true" ]
  sed -i '2s/"actor":"bob"/"actor":"eve"/' "${TMP}/real/trail.jsonl"
  run "$CC" --framework eu-ai-act
  [ "$(rule_passed "$output" audit_trail_exists)" = "false" ]
}

@test "compliance-check: tenant en la salida es all sin --tenant y el slug con él" {
  fake_root
  run "$CC" --framework gdpr
  echo "$output" | python3 -c 'import json,sys; assert json.load(sys.stdin)["tenant"]=="all"'
  run "$CC" --framework gdpr --tenant t1
  echo "$output" | python3 -c 'import json,sys; assert json.load(sys.stdin)["tenant"]=="t1"'
}

@test "verify rechaza bytes NUL dentro de un campo o tras el objeto (null byte)" {
  seed3
  python3 -c 'import sys; p=sys.argv[1]; b=open(p,"rb").read(); open(p,"wb").write(b.replace(b"\"actor\":\"bob\"", b"\"actor\":\"b\x00ob\"",1))' "$TRAIL"
  run "$AT" verify --file "$TRAIL" --anchor "$(head_hash "$TRAIL")"
  [ "$status" -eq 1 ]
  [[ "$output" == *"NUL"* ]]
}

@test "verify rechaza campo con tabulador o actor vacío aunque el hash cuadre (invalid)" {
  mkdir -p "${TMP}/f"
  forge 2026-01-01T00:00:00Z t1 "$(printf 'a\tb')" act "$GEN" > "${TMP}/f/tab.jsonl"
  run "$AT" verify --file "${TMP}/f/tab.jsonl"
  [ "$status" -eq 1 ]
  [[ "$output" == *"not a canonical"* ]]
  forge 2026-01-01T00:00:00Z t1 "" act "$GEN" > "${TMP}/f/empty.jsonl"
  run "$AT" verify --file "${TMP}/f/empty.jsonl"
  [ "$status" -eq 1 ]
}

@test "verify rechaza ts imposible y ts que retrocede aunque los hashes cuadren (boundary)" {
  mkdir -p "${TMP}/f"
  forge 2026-13-45T99:99:99Z t1 a b "$GEN" > "${TMP}/f/cal.jsonl"
  run "$AT" verify --file "${TMP}/f/cal.jsonl"
  [ "$status" -eq 1 ]
  local l1 h1
  l1="$(forge 2026-05-02T00:00:00Z t1 a b "$GEN")"
  h1="$(printf '%s' "$l1" | grep -o 'sha256:[0-9a-f]*' | cut -d: -f2)"
  { printf '%s\n' "$l1"; forge 2026-05-01T00:00:00Z t1 a c "$h1"; } > "${TMP}/f/back.jsonl"
  run "$AT" verify --file "${TMP}/f/back.jsonl"
  [ "$status" -eq 1 ]
  [[ "$output" == *"backwards"* ]]
}

@test "verify --tenant rechaza entradas de otro tenant" {
  seed3
  run "$AT" verify --file "$TRAIL" --tenant t1
  [ "$status" -eq 0 ]
  run "$AT" verify --file "$TRAIL" --tenant otro
  [ "$status" -eq 1 ]
  [[ "$output" == *"belongs to tenant 't1'"* ]]
}

@test "verify detecta reordenación, CRLF, BOM y línea en blanco final (regresión)" {
  seed3
  local f="${TMP}/m.jsonl"
  { sed -n 1p "$TRAIL"; sed -n 3p "$TRAIL"; sed -n 2p "$TRAIL"; } > "$f"
  run "$AT" verify --file "$f"; [ "$status" -eq 1 ]
  sed 's/$/\r/' "$TRAIL" > "$f"
  run "$AT" verify --file "$f"; [ "$status" -eq 1 ]
  { printf '\xef\xbb\xbf'; cat "$TRAIL"; } > "$f"
  run "$AT" verify --file "$f"; [ "$status" -eq 1 ]
  { cat "$TRAIL"; echo; } > "$f"
  run "$AT" verify --file "$f"; [ "$status" -eq 1 ]
}

@test "append se niega si el reloj es anterior a la última entrada (no escribe)" {
  mkdir -p "$(dirname "$TRAIL")"
  forge 2099-01-01T00:00:00Z t1 a b "$GEN" > "$TRAIL"
  run append --actor a --action c
  [ "$status" -eq 1 ]
  [[ "$output" == *"earlier than the last entry"* ]]
  [ "$(wc -l < "$TRAIL")" -eq 1 ]
}
