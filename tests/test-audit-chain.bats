#!/usr/bin/env bats
# BATS tests for audit-chain scripts (SE-275 S1 / SE-313 S6).
# Ref: docs/propuestas/SE-275-trust-gated-audit-trail.md

setup() {
  cd "$BATS_TEST_DIRNAME/.."
  export CLAUDE_PROJECT_DIR="$BATS_TEST_TMPDIR/ws"
  mkdir -p "$CLAUDE_PROJECT_DIR"
  rm -rf "$CLAUDE_PROJECT_DIR/output/audit" 2>/dev/null || true
}

teardown() {
  cd /
}

@test "audit-chain-append.sh existe y es ejecutable" {
  [[ -f scripts/audit-chain-append.sh ]]
  [[ -x scripts/audit-chain-append.sh ]]
}

@test "audit-chain-verify.sh existe y es ejecutable" {
  [[ -f scripts/audit-chain-verify.sh ]]
  [[ -x scripts/audit-chain-verify.sh ]]
}

@test "append crea cadena con prev_hash encadenado" {
  bash scripts/audit-chain-append.sh court-20260809-001 correctness-judge verdict verdict=pass >/dev/null
  bash scripts/audit-chain-append.sh court-20260809-001 cognitive-judge verdict verdict=pass >/dev/null
  F="$CLAUDE_PROJECT_DIR/output/audit/court-20260809-001.jsonl"
  [[ -f "$F" ]]
  SEQ1=$(head -1 "$F" | jq -r '.seq')
  SEQ2=$(tail -1 "$F" | jq -r '.seq')
  [[ "$SEQ1" == "1" ]]
  [[ "$SEQ2" == "2" ]]
  # prev_hash de la entrada 2 = entry_hash de la entrada 1
  PH2=$(tail -1 "$F" | jq -r '.prev_hash')
  EH1=$(head -1 "$F" | jq -r '.entry_hash')
  [[ "$PH2" == "$EH1" ]]
}

@test "verify pasa con cadena íntegra" {
  bash scripts/audit-chain-append.sh truth-20260809-001 factuality-judge verdict verdict=pass >/dev/null
  bash scripts/audit-chain-append.sh truth-20260809-001 coherence-judge verdict verdict=pass >/dev/null
  run bash scripts/audit-chain-verify.sh
  [ "$status" -eq 0 ]
  [[ "$output" == *"íntegra"* ]]
}

@test "verify detecta corrupción (entry modificado)" {
  bash scripts/audit-chain-append.sh court-20260809-002 judge-a verdict verdict=pass >/dev/null
  bash scripts/audit-chain-append.sh court-20260809-002 judge-b verdict verdict=pass >/dev/null
  F="$CLAUDE_PROJECT_DIR/output/audit/court-20260809-002.jsonl"
  python3 -c "
import json
lines=open('$F').read().splitlines()
d=json.loads(lines[1]); d['verdict']='tampered'
lines[1]=json.dumps(d)
open('$F','w').write('\n'.join(lines)+'\n')
"
  run bash scripts/audit-chain-verify.sh
  [ "$status" -eq 1 ]
  [[ "$output" == *"CORRUPT"* ]]
}

@test "verify detecta seq salto (entrada eliminada)" {
  bash scripts/audit-chain-append.sh court-20260809-003 judge-a verdict verdict=pass >/dev/null
  bash scripts/audit-chain-append.sh court-20260809-003 judge-b verdict verdict=pass >/dev/null
  bash scripts/audit-chain-append.sh court-20260809-003 judge-c verdict verdict=pass >/dev/null
  F="$CLAUDE_PROJECT_DIR/output/audit/court-20260809-003.jsonl"
  # Eliminar la entrada del medio (seq 2)
  sed -i '2d' "$F"
  run bash scripts/audit-chain-verify.sh
  [ "$status" -eq 1 ]
  [[ "$output" == *"seq"* ]]
}

@test "prune no falla sin cadenas" {
  run bash scripts/audit-chain-prune.sh
  [ "$status" -eq 0 ]
}

@test "append con usage inválido falla" {
  run bash scripts/audit-chain-append.sh
  [ "$status" -eq 2 ]
}

# ── Comportamiento: valores exactos, ramas y estado en disco ─────────────────

_chain() { echo "$CLAUDE_PROJECT_DIR/output/audit/$1.jsonl"; }

@test "append: primera entrada enlaza con el sha256 de la cadena vacía" {
  export SAVIA_AUDIT_KEY="$BATS_TEST_TMPDIR/nokey"
  run bash scripts/audit-chain-append.sh c-gen agent-a act
  [ "$status" -eq 0 ]
  [ "$output" = "$(_chain c-gen)" ]
  [ "$(jq -r .prev_hash "$(_chain c-gen)")" = "sha256:$(printf '' | sha256sum | cut -d' ' -f1)" ]
  [ "$(jq -r .seq "$(_chain c-gen)")" = "1" ]
}

@test "append: agent, action y tier por defecto mid quedan en la entrada" {
  export SAVIA_AUDIT_KEY="$BATS_TEST_TMPDIR/nokey"
  bash scripts/audit-chain-append.sh c-t agent-x do-it >/dev/null
  F=$(_chain c-t)
  [ "$(jq -r .agent "$F")" = "agent-x" ]
  [ "$(jq -r .action "$F")" = "do-it" ]
  [ "$(jq -r .agent_tier "$F")" = "mid" ]
  [ "$(jq -r .chain_id "$F")" = "c-t" ]
}

@test "append: --tier y tier=k=v fijan el nivel; tier no se duplica como atributo" {
  export SAVIA_AUDIT_KEY="$BATS_TEST_TMPDIR/nokey"
  bash scripts/audit-chain-append.sh c-t2 a x --tier heavy >/dev/null
  bash scripts/audit-chain-append.sh c-t2 a x tier=fast >/dev/null
  F=$(_chain c-t2)
  [ "$(sed -n 1p "$F" | jq -r .agent_tier)" = "heavy" ]
  [ "$(sed -n 2p "$F" | jq -r .agent_tier)" = "fast" ]
  [ "$(sed -n 2p "$F" | jq -r 'has("tier")')" = "false" ]
}

@test "append: --input de un fichero guarda el sha256 de su contenido" {
  export SAVIA_AUDIT_KEY="$BATS_TEST_TMPDIR/nokey"
  printf 'hola' > "$BATS_TEST_TMPDIR/in.txt"
  bash scripts/audit-chain-append.sh c-in a x --input "$BATS_TEST_TMPDIR/in.txt" --output "$BATS_TEST_TMPDIR/in.txt" >/dev/null
  EXP=$(printf 'hola' | sha256sum | cut -d' ' -f1)
  [ "$(jq -r .input_hash "$(_chain c-in)")" = "sha256:$EXP" ]
  [ "$(jq -r .output_hash "$(_chain c-in)")" = "sha256:$EXP" ]
}

@test "append: referencia sha256:<64 hex> se conserva y texto libre se hashea" {
  export SAVIA_AUDIT_KEY="$BATS_TEST_TMPDIR/nokey"
  H=$(printf 'z' | sha256sum | cut -d' ' -f1)
  bash scripts/audit-chain-append.sh c-ref a x --input "sha256:$H" --output "texto libre" >/dev/null
  F=$(_chain c-ref)
  [ "$(jq -r .input_hash "$F")" = "sha256:$H" ]
  [ "$(jq -r .output_hash "$F")" = "sha256:$(printf 'texto libre' | sha256sum | cut -d' ' -f1)" ]
}

@test "append: sha256: con longitud incorrecta se trata como texto y se hashea" {
  export SAVIA_AUDIT_KEY="$BATS_TEST_TMPDIR/nokey"
  bash scripts/audit-chain-append.sh c-short a x --input "sha256:abc123" >/dev/null
  [ "$(jq -r .input_hash "$(_chain c-short)")" = "sha256:$(printf 'sha256:abc123' | sha256sum | cut -d' ' -f1)" ]
}

@test "append: sin --input ni --output los hashes quedan vacíos" {
  export SAVIA_AUDIT_KEY="$BATS_TEST_TMPDIR/nokey"
  bash scripts/audit-chain-append.sh c-nohash a x >/dev/null
  [ "$(jq -r .input_hash "$(_chain c-nohash)")" = "" ]
  [ "$(jq -r .output_hash "$(_chain c-nohash)")" = "" ]
}

@test "append: atributos clave=valor se guardan y valores con = conservan el resto" {
  export SAVIA_AUDIT_KEY="$BATS_TEST_TMPDIR/nokey"
  bash scripts/audit-chain-append.sh c-kv a x severity=blocker expr=a=b >/dev/null
  F=$(_chain c-kv)
  [ "$(jq -r .severity "$F")" = "blocker" ]
  [ "$(jq -r .expr "$F")" = "a=b" ]
}

@test "append: un atributo con clave reservada no sobrescribe campos de la cadena" {
  export SAVIA_AUDIT_KEY="$BATS_TEST_TMPDIR/nokey"
  bash scripts/audit-chain-append.sh c-res realagent realaction agent=evil action=evil seq=99 chain_id=otra prev_hash=x timestamp=0 entry_hash=y signature=z >/dev/null
  F=$(_chain c-res)
  [ "$(jq -r .agent "$F")" = "realagent" ]
  [ "$(jq -r .action "$F")" = "realaction" ]
  [ "$(jq -r .seq "$F")" = "1" ]
  [ "$(jq -r .chain_id "$F")" = "c-res" ]
  [ "$(jq -r .signature "$F")" = "null" ]
  run bash scripts/audit-chain-verify.sh
  [ "$status" -eq 0 ]
}

@test "append: faltar solo la acción también es error de uso (2) y no crea la cadena" {
  run bash scripts/audit-chain-append.sh c-u agente
  [ "$status" -eq 2 ]
  [[ "$output" == *"usage"* ]]
  [ ! -e "$(_chain c-u)" ]
  run bash scripts/audit-chain-append.sh c-u "" accion
  [ "$status" -eq 2 ]
  run bash scripts/audit-chain-append.sh "" a b
  [ "$status" -eq 2 ]
}

@test "append: última entrada sin entry_hash corta con 1 y no añade nada" {
  export SAVIA_AUDIT_KEY="$BATS_TEST_TMPDIR/nokey"
  mkdir -p "$CLAUDE_PROJECT_DIR/output/audit"
  echo '{"seq":1,"agent":"a"}' > "$(_chain c-bad)"
  run bash scripts/audit-chain-append.sh c-bad a x
  [ "$status" -eq 1 ]
  [[ "$output" == *"corrupta"* ]]
  [ "$(wc -l < "$(_chain c-bad)")" -eq 1 ]
}

@test "append: con clave local firma la entrada y verify la valida" {
  printf 'clave-local-de-prueba' > "$BATS_TEST_TMPDIR/key"
  export SAVIA_AUDIT_KEY="$BATS_TEST_TMPDIR/key"
  bash scripts/audit-chain-append.sh c-sig a x >/dev/null
  bash scripts/audit-chain-append.sh c-sig a y >/dev/null
  [[ "$(jq -r .signature "$(_chain c-sig)" | head -1)" == hmac-sha256:* ]]
  run bash scripts/audit-chain-verify.sh
  [ "$status" -eq 0 ]
}

@test "append: sin clave o con clave vacía la entrada no lleva firma" {
  export SAVIA_AUDIT_KEY="$BATS_TEST_TMPDIR/nokey"
  bash scripts/audit-chain-append.sh c-ns a x >/dev/null
  [ "$(jq -r .signature "$(_chain c-ns)")" = "null" ]
  : > "$BATS_TEST_TMPDIR/empty-key"
  export SAVIA_AUDIT_KEY="$BATS_TEST_TMPDIR/empty-key"
  bash scripts/audit-chain-append.sh c-ns2 a x >/dev/null
  [ "$(jq -r .signature "$(_chain c-ns2)")" = "null" ]
}

@test "append: cada cadena es un fichero independiente con su propio seq" {
  export SAVIA_AUDIT_KEY="$BATS_TEST_TMPDIR/nokey"
  bash scripts/audit-chain-append.sh c-A a x >/dev/null
  bash scripts/audit-chain-append.sh c-A a x >/dev/null
  bash scripts/audit-chain-append.sh c-B a x >/dev/null
  [ "$(wc -l < "$(_chain c-A)")" -eq 2 ]
  [ "$(jq -r .seq "$(_chain c-B)")" = "1" ]
}

@test "verify: sin directorio de auditoría da SKIP y sale 0" {
  run bash scripts/audit-chain-verify.sh "$BATS_TEST_TMPDIR/no-existe"
  [ "$status" -eq 0 ]
  [[ "$output" == SKIP* ]]
}

@test "verify: directorio sin cadenas informa y sale 0" {
  mkdir -p "$BATS_TEST_TMPDIR/vacio"
  run bash scripts/audit-chain-verify.sh "$BATS_TEST_TMPDIR/vacio"
  [ "$status" -eq 0 ]
  [[ "$output" == *"sin cadenas"* ]]
}

@test "verify: cuenta las cadenas íntegras" {
  export SAVIA_AUDIT_KEY="$BATS_TEST_TMPDIR/nokey"
  bash scripts/audit-chain-append.sh v-1 a x >/dev/null
  bash scripts/audit-chain-append.sh v-2 a x >/dev/null
  bash scripts/audit-chain-append.sh v-3 a x >/dev/null
  run bash scripts/audit-chain-verify.sh
  [ "$status" -eq 0 ]
  [ "$output" = "OK: 3 cadena(s) íntegra(s)" ]
}

@test "verify: acepta un directorio por argumento y no mira el de por defecto" {
  export SAVIA_AUDIT_KEY="$BATS_TEST_TMPDIR/nokey"
  bash scripts/audit-chain-append.sh v-dflt a x >/dev/null
  mkdir -p "$BATS_TEST_TMPDIR/otro"
  run bash scripts/audit-chain-verify.sh "$BATS_TEST_TMPDIR/otro"
  [[ "$output" == *"sin cadenas"* ]]
}

@test "verify: contenido manipulado informa seq, cuenta violaciones y sale 1" {
  export SAVIA_AUDIT_KEY="$BATS_TEST_TMPDIR/nokey"
  bash scripts/audit-chain-append.sh v-t a x verdict=pass >/dev/null
  bash scripts/audit-chain-append.sh v-t a x verdict=pass >/dev/null
  sed -i '1s/"pass"/"fail"/' "$(_chain v-t)"
  run bash scripts/audit-chain-verify.sh
  [ "$status" -eq 1 ]
  [[ "$output" == *"entry_hash no coincide en seq 1"* ]]
  [[ "$output" == *"FAIL: 1 violación(es) de integridad en 1 cadena(s)"* ]]
}

@test "verify: prev_hash roto con entry_hash recalculado se detecta como prev_hash" {
  export SAVIA_AUDIT_KEY="$BATS_TEST_TMPDIR/nokey"
  bash scripts/audit-chain-append.sh v-p a x >/dev/null
  bash scripts/audit-chain-append.sh v-p a x >/dev/null
  python3 - "$(_chain v-p)" <<'PY'
import json, sys, hashlib
p = sys.argv[1]
ls = open(p).read().splitlines()
d = json.loads(ls[1])
d["prev_hash"] = "sha256:" + "0" * 64
d.pop("entry_hash")
body = json.dumps(d, separators=(",", ":"))
d["entry_hash"] = "sha256:" + hashlib.sha256(body.encode()).hexdigest()
ls[1] = json.dumps(d, separators=(",", ":"))
open(p, "w").write("\n".join(ls) + "\n")
PY
  run bash scripts/audit-chain-verify.sh
  [ "$status" -eq 1 ]
  [[ "$output" == *"prev_hash roto en seq 2"* ]]
  [[ "$output" != *"entry_hash no coincide"* ]]
}

@test "verify: línea sin seq es corrupta" {
  export SAVIA_AUDIT_KEY="$BATS_TEST_TMPDIR/nokey"
  mkdir -p "$CLAUDE_PROJECT_DIR/output/audit"
  echo '{"agent":"a"}' > "$(_chain v-noseq)"
  run bash scripts/audit-chain-verify.sh
  [ "$status" -eq 1 ]
  [[ "$output" == *"línea sin seq"* ]]
}

@test "verify: líneas en blanco no cuentan como violación" {
  export SAVIA_AUDIT_KEY="$BATS_TEST_TMPDIR/nokey"
  bash scripts/audit-chain-append.sh v-bl a x >/dev/null
  echo "" >> "$(_chain v-bl)"
  run bash scripts/audit-chain-verify.sh
  [ "$status" -eq 0 ]
}

@test "verify: una firma alterada se detecta con clave local y se ignora sin ella" {
  printf 'clave-local-de-prueba' > "$BATS_TEST_TMPDIR/key"
  export SAVIA_AUDIT_KEY="$BATS_TEST_TMPDIR/key"
  bash scripts/audit-chain-append.sh v-s a x >/dev/null
  sed -i 's/"signature":"hmac-sha256:[0-9a-f]*"/"signature":"hmac-sha256:deadbeef"/' "$(_chain v-s)"
  run bash scripts/audit-chain-verify.sh
  [ "$status" -eq 1 ]
  [[ "$output" == *"firma HMAC no coincide en seq 1"* ]]
  export SAVIA_AUDIT_KEY="$BATS_TEST_TMPDIR/nokey"
  run bash scripts/audit-chain-verify.sh
  [ "$status" -eq 0 ]
}

@test "verify: firmada con otra clave no valida" {
  printf 'clave-A' > "$BATS_TEST_TMPDIR/keyA"
  printf 'clave-B' > "$BATS_TEST_TMPDIR/keyB"
  SAVIA_AUDIT_KEY="$BATS_TEST_TMPDIR/keyA" bash scripts/audit-chain-append.sh v-k a x >/dev/null
  SAVIA_AUDIT_KEY="$BATS_TEST_TMPDIR/keyB" run bash scripts/audit-chain-verify.sh
  [ "$status" -eq 1 ]
  [[ "$output" == *"firma HMAC"* ]]
}

@test "prune: archiva en gz la cadena vieja y conserva la reciente" {
  export SAVIA_AUDIT_KEY="$BATS_TEST_TMPDIR/nokey"
  bash scripts/audit-chain-append.sh p-old a x >/dev/null
  bash scripts/audit-chain-append.sh p-new a x >/dev/null
  touch -d '120 days ago' "$(_chain p-old)"
  run bash scripts/audit-chain-prune.sh
  [ "$status" -eq 0 ]
  [[ "$output" == *"archived: p-old.jsonl (>90d)"* ]]
  [ ! -e "$(_chain p-old)" ]
  [ -s "$CLAUDE_PROJECT_DIR/output/audit/archive/p-old.jsonl.gz" ]
  [ -e "$(_chain p-new)" ]
  zcat "$CLAUDE_PROJECT_DIR/output/audit/archive/p-old.jsonl.gz" | jq -e '.chain_id=="p-old"' >/dev/null
}

@test "prune: el umbral de días es el argumento (frontera)" {
  export SAVIA_AUDIT_KEY="$BATS_TEST_TMPDIR/nokey"
  bash scripts/audit-chain-append.sh p-b a x >/dev/null
  touch -d '10 days ago' "$(_chain p-b)"
  run bash scripts/audit-chain-prune.sh 30
  [ "$output" = "OK: nada que podar" ]
  [ -e "$(_chain p-b)" ]
  run bash scripts/audit-chain-prune.sh 5
  [[ "$output" == *"(>5d)"* ]]
  [ ! -e "$(_chain p-b)" ]
}

@test "prune: sin directorio de auditoría no falla" {
  rm -rf "$CLAUDE_PROJECT_DIR/output"
  run bash scripts/audit-chain-prune.sh
  [ "$status" -eq 0 ]
}

@test "append: sha256:<64 hex> seguido de basura no se acepta como hash literal" {
  export SAVIA_AUDIT_KEY="$BATS_TEST_TMPDIR/nokey"
  H=$(printf 'z' | sha256sum | cut -d' ' -f1)
  bash scripts/audit-chain-append.sh c-trail a x --input "sha256:${H}zz" >/dev/null
  [ "$(jq -r .input_hash "$(_chain c-trail)")" = "sha256:$(printf 'sha256:%szz' "$H" | sha256sum | cut -d' ' -f1)" ]
}

@test "append: prev_hash=x como atributo no rompe el enlace de la segunda entrada" {
  export SAVIA_AUDIT_KEY="$BATS_TEST_TMPDIR/nokey"
  bash scripts/audit-chain-append.sh c-ph a x >/dev/null
  bash scripts/audit-chain-append.sh c-ph a x prev_hash=falso timestamp=1999 >/dev/null
  F=$(_chain c-ph)
  [ "$(sed -n 2p "$F" | jq -r .prev_hash)" = "$(sed -n 1p "$F" | jq -r .entry_hash)" ]
  [[ "$(sed -n 2p "$F" | jq -r .timestamp)" == 20* ]]
  run bash scripts/audit-chain-verify.sh
  [ "$status" -eq 0 ]
}

@test "append: un atributo entry_hash=... no invalida la cadena" {
  export SAVIA_AUDIT_KEY="$BATS_TEST_TMPDIR/nokey"
  bash scripts/audit-chain-append.sh c-eh a x entry_hash=falso >/dev/null
  bash scripts/audit-chain-append.sh c-eh a y >/dev/null
  run bash scripts/audit-chain-verify.sh
  [ "$status" -eq 0 ]
}

@test "verify: quitar entry_hash y editar el contenido se detecta" {
  export SAVIA_AUDIT_KEY="$BATS_TEST_TMPDIR/nokey"
  bash scripts/audit-chain-append.sh v-nh a x verdict=pass >/dev/null
  bash scripts/audit-chain-append.sh v-nh a x verdict=pass >/dev/null
  python3 - "$(_chain v-nh)" <<'PY'
import json, sys
p = sys.argv[1]
ls = open(p).read().splitlines()
d = json.loads(ls[0]); d.pop("entry_hash"); d["verdict"] = "fail"
ls[0] = json.dumps(d, separators=(",", ":"))
open(p, "w").write("\n".join(ls) + "\n")
PY
  run bash scripts/audit-chain-verify.sh
  [ "$status" -eq 1 ]
  [[ "$output" == *"sin entry_hash en seq 1"* ]]
}

@test "verify: entradas sin firma se aceptan aunque haya clave local" {
  export SAVIA_AUDIT_KEY="$BATS_TEST_TMPDIR/nokey"
  bash scripts/audit-chain-append.sh v-us a x >/dev/null
  printf 'clave-local-de-prueba' > "$BATS_TEST_TMPDIR/key"
  export SAVIA_AUDIT_KEY="$BATS_TEST_TMPDIR/key"
  run bash scripts/audit-chain-verify.sh
  [ "$status" -eq 0 ]
}

@test "prune: tras archivar no imprime 'nada que podar'" {
  export SAVIA_AUDIT_KEY="$BATS_TEST_TMPDIR/nokey"
  bash scripts/audit-chain-append.sh p-m a x >/dev/null
  touch -d '200 days ago' "$(_chain p-m)"
  run bash scripts/audit-chain-prune.sh
  [[ "$output" != *"nada que podar"* ]]
}
