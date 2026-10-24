#!/usr/bin/env bats
# SE-453 S3 (por demanda, tanda 2) — resultado clean/findings/unknown en los escáneres que seguían sin
# gate-result: prompt-security-scan, mcp-security-audit, iac-security-scan, security-audit-all y
# confidentiality-scan. Cada caso «unknown» era antes un verde (o un falso hallazgo).
# Spec: docs/specs/SE-453-gate-result-contract.spec.md · Contrato: docs/rules/domain/gate-result-contract.md
bats_require_minimum_version 1.5.0

setup_file() {
  # PATH aislado: todo /usr/bin menos las herramientas que se quieren ausentes.
  mkpath() {
    local dir="$1"; shift
    local f name skip x
    mkdir -p "$dir"
    for f in /usr/bin/*; do
      name="${f##*/}"; skip=0
      for x in "$@"; do [[ "$name" == "$x" ]] && skip=1; done
      [[ $skip -eq 1 ]] && continue
      [[ -x "$f" ]] && ln -sf "$f" "$dir/$name"
    done
  }
  export NOPY="$BATS_FILE_TMPDIR/nopy" NOTRIVY="$BATS_FILE_TMPDIR/notrivy"
  mkpath "$NOPY" python3
  mkpath "$NOTRIVY" trivy docker
}

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  WORK="$(mktemp -d -p "$BATS_TEST_TMPDIR")"
  PROJ="$WORK/proj"
  mkdir -p "$PROJ/scripts" "$PROJ/.claude/hooks/lib" "$WORK/bin" "$WORK/md"
  cp "$REPO_ROOT/scripts/prompt-security-scan.sh" "$REPO_ROOT/scripts/mcp-security-audit.sh" \
     "$REPO_ROOT/scripts/iac-security-scan.sh" "$REPO_ROOT/scripts/security-audit-all.sh" \
     "$REPO_ROOT/scripts/confidentiality-scan.sh" "$PROJ/scripts/"
  cp "$REPO_ROOT/.claude/hooks/lib/gate-result.sh" "$PROJ/.claude/hooks/lib/"
  printf '# agente\nmodel: x\nTexto inocuo.\n' > "$WORK/md/a.md"
}

last_result() { printf '%s\n' "$output" | grep '^gate-result: ' | tail -1 | sed 's/^gate-result: //'; }
is_last_line() { [ "$(printf '%s\n' "$output" | tail -1)" = "gate-result: $1" ]; }
# has_gap <result> <check> <reason>
has_gap() { python3 -c 'import json,sys; d=json.loads(sys.argv[1]); assert d["result"]==sys.argv[2] and {"check":sys.argv[3],"reason":sys.argv[4]} in d["gaps"], d' "$(last_result)" "$@"; }
is_result() { python3 -c 'import json,sys; d=json.loads(sys.argv[1]); assert d["result"]==sys.argv[2], d' "$(last_result)" "$1"; }
unmeasured() { grep -q "\"hook\":\"$1\"" "$PROJ/output/unmeasured-gates.jsonl"; }

# ── prompt-security-scan ─────────────────────────────────────────────────────

@test "prompt: fichero inocuo ⇒ clean, exit 0 y gate-result en la última línea" {
  run bash "$PROJ/scripts/prompt-security-scan.sh" "$WORK/md"
  [ "$status" -eq 0 ]
  is_result clean
  is_last_line "$(last_result)"
}

@test "prompt: carácter de anchura cero ⇒ findings (PS-11 sigue detectando con el path por argv)" {
  printf 'hola\xe2\x80\x8bmundo\n' > "$WORK/md/b.md"
  run bash "$PROJ/scripts/prompt-security-scan.sh" "$WORK/md"
  [ "$status" -eq 1 ]
  [[ "$output" == *"PS-11"* ]]
  is_result findings
}

@test "prompt: sin python3 ⇒ unknown/PS-11:missing_tool (antes clean) y registrado" {
  run env PATH="$NOPY" /usr/bin/bash "$PROJ/scripts/prompt-security-scan.sh" "$WORK/md"
  [ "$status" -eq 0 ]
  has_gap unknown PS-11 missing_tool
  unmeasured prompt-security-scan
}

@test "prompt: directorio sin ficheros .md ⇒ unknown/files:unreadable, nunca clean" {
  mkdir -p "$WORK/empty"
  run bash "$PROJ/scripts/prompt-security-scan.sh" "$WORK/empty"
  [ "$status" -eq 0 ]
  has_gap unknown files unreadable
}

@test "prompt: fichero ilegible ⇒ unknown/read:unreadable" {
  [ "$(id -u)" -eq 0 ] && skip "root lee ficheros sin permiso"
  printf 'x\n' > "$WORK/md/c.md"; chmod 000 "$WORK/md/c.md"
  run bash "$PROJ/scripts/prompt-security-scan.sh" "$WORK/md"
  chmod 600 "$WORK/md/c.md"
  [ "$status" -eq 0 ]
  has_gap unknown read unreadable
}

@test "prompt: path inexistente ⇒ exit 2 con unknown/path:unreadable" {
  run bash "$PROJ/scripts/prompt-security-scan.sh" "$WORK/no-existe"
  [ "$status" -eq 2 ]
  has_gap unknown path unreadable
}

# ── mcp-security-audit ───────────────────────────────────────────────────────

mcp_cfg() { printf '{"mcpServers":{"s":{"command":"/opt/s","description":"d"%s}}}\n' "${2:-}" > "$1"; }

@test "mcp: sin python3 ⇒ exit 2 y unknown/python3:missing_tool, sin el falso MCP-00 de antes" {
  mcp_cfg "$WORK/m.json"
  run env PATH="$NOPY" /usr/bin/bash "$PROJ/scripts/mcp-security-audit.sh" --config "$WORK/m.json"
  [ "$status" -eq 2 ]
  [[ "$output" != *"MCP-00"* ]]
  has_gap unknown python3 missing_tool
  unmeasured mcp-security-audit
}

@test "mcp: --config a un fichero inexistente ⇒ unknown/config:unreadable (antes PASS)" {
  run bash "$PROJ/scripts/mcp-security-audit.sh" --config "$WORK/no-existe.json"
  [ "$status" -eq 0 ]
  has_gap unknown config unreadable
}

@test "mcp: config sin hallazgos ⇒ clean; con --json, result clean en el propio JSON" {
  mcp_cfg "$WORK/m.json"
  run bash "$PROJ/scripts/mcp-security-audit.sh" --config "$WORK/m.json"
  [ "$status" -eq 0 ]
  is_result clean
  run --separate-stderr bash "$PROJ/scripts/mcp-security-audit.sh" --config "$WORK/m.json" --json
  printf '%s' "$output" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["result"]=="clean" and d["gaps"]==[] and d["verdict"]=="PASS", d'
}

@test "mcp: ruta con comilla simple se audita (antes rompía el python y daba MCP-00)" {
  mcp_cfg "$WORK/a'b.json" ',"autoApprove":true'
  run --separate-stderr bash "$PROJ/scripts/mcp-security-audit.sh" --config "$WORK/a'b.json" --json
  [ "$status" -eq 1 ]
  printf '%s' "$output" | python3 -c 'import json,sys; d=json.load(sys.stdin); r=[f["rule"] for f in d["findings"]]; assert "MCP-02" in r and "MCP-00" not in r and d["result"]=="findings", d'
}

# ── iac-security-scan ────────────────────────────────────────────────────────

# trivy falso: escribe $TRIVY_JSON en stdout y sale con $TRIVY_RC (0 por defecto).
fake_trivy() {
  cat > "$WORK/bin/trivy" <<'STUB'
#!/usr/bin/env bash
[[ "${TRIVY_RC:-0}" -ne 0 ]] && exit "$TRIVY_RC"
printf '%s' "$TRIVY_JSON"
STUB
  chmod +x "$WORK/bin/trivy"
  mkdir -p "$WORK/infra"; printf 'FROM alpine\n' > "$WORK/infra/Dockerfile"
}
MIS='{"Results":[{"Target":"Dockerfile","Misconfigurations":[{"ID":"DS002","AVDID":"AVD-DS-0002","Title":"Root","Severity":"HIGH","Status":"FAIL"}]}]}'

@test "iac: hallazgo bloqueante ⇒ exit 1, findings en la última línea y en el report" {
  fake_trivy
  run env PATH="$WORK/bin:$NOTRIVY" TRIVY_JSON="$MIS" /usr/bin/bash "$PROJ/scripts/iac-security-scan.sh" --path "$WORK/infra"
  [ "$status" -eq 1 ]
  is_result findings
  is_last_line "$(last_result)"
  python3 -c 'import json,sys,glob; d=json.load(open(glob.glob(sys.argv[1]+"/output/security/iac-scan-*.json")[0])); assert d["result"]=="findings" and d["gaps"]==[], d' "$PROJ"
}

@test "iac: sin hallazgos ⇒ clean" {
  fake_trivy
  run env PATH="$WORK/bin:$NOTRIVY" TRIVY_JSON='{"Results":[]}' /usr/bin/bash "$PROJ/scripts/iac-security-scan.sh" --path "$WORK/infra"
  [ "$status" -eq 0 ]
  is_result clean
}

@test "iac: Trivy que falla ⇒ exit 2, unknown/trivy-config:unreadable en salida y report" {
  fake_trivy
  run env PATH="$WORK/bin:$NOTRIVY" TRIVY_RC=1 /usr/bin/bash "$PROJ/scripts/iac-security-scan.sh" --path "$WORK/infra"
  [ "$status" -eq 2 ]
  has_gap unknown trivy-config unreadable
  python3 -c 'import json,sys,glob; d=json.load(open(glob.glob(sys.argv[1]+"/output/security/iac-scan-*.json")[0])); assert d["result"]=="unknown" and d["gaps"][0]["reason"]=="unreadable", d' "$PROJ"
  unmeasured iac-security-scan
}

@test "iac: Trivy cortado por timeout (rc 124) ⇒ unknown/trivy-config:timeout" {
  fake_trivy
  run env PATH="$WORK/bin:$NOTRIVY" TRIVY_RC=124 /usr/bin/bash "$PROJ/scripts/iac-security-scan.sh" --path "$WORK/infra"
  [ "$status" -eq 2 ]
  has_gap unknown trivy-config timeout
}

@test "iac: ni Trivy ni Docker ⇒ exit 2 y unknown/trivy:missing_tool" {
  mkdir -p "$WORK/infra"
  run env PATH="$NOTRIVY" /usr/bin/bash "$PROJ/scripts/iac-security-scan.sh" --path "$WORK/infra"
  [ "$status" -eq 2 ]
  has_gap unknown trivy missing_tool
}

@test "iac: --format json deja stdout como un único JSON con result (sin línea gate-result)" {
  fake_trivy
  run --separate-stderr env PATH="$WORK/bin:$NOTRIVY" TRIVY_JSON="$MIS" /usr/bin/bash "$PROJ/scripts/iac-security-scan.sh" --path "$WORK/infra" --format json
  [ "$status" -eq 1 ]
  [[ "$output" != *"gate-result:"* ]]
  printf '%s' "$output" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["result"]=="findings", d'
}

# ── security-audit-all ───────────────────────────────────────────────────────

# sub-escáner falso: imprime $2 y sale con $3.
fake_sub() { printf '#!/usr/bin/env bash\nprintf "%%s\\n" %q\nexit %s\n' "$2" "$3" > "$PROJ/scripts/$1.sh"; }
clean_subs() {
  local s
  for s in mcp-security-audit permissions-wildcard-audit hook-injection-audit; do
    fake_sub "$s" '{"critical":0,"high":0,"medium":0,"low":0}' 0
  done
  rm -f "$PROJ/scripts/prompt-security-scan.sh"
}

@test "audit-all: sub-escáner que sale 1 con hallazgos se suma (antes se perdía y daba PASS)" {
  clean_subs
  fake_sub mcp-security-audit '{"critical":0,"high":2,"medium":0,"low":0}' 1
  run --separate-stderr bash "$PROJ/scripts/security-audit-all.sh" --json
  [ "$status" -eq 1 ]
  printf '%s' "$output" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["total_high"]==2 and d["verdict"]=="FAIL" and d["result"]=="findings", d'
}

@test "audit-all: todo limpio ⇒ clean en texto y en JSON" {
  clean_subs
  run bash "$PROJ/scripts/security-audit-all.sh"
  [ "$status" -eq 0 ]
  is_result clean
  is_last_line "$(last_result)"
}

@test "audit-all: sub-escáner con exit 2 o salida ilegible ⇒ unknown, no cero hallazgos" {
  clean_subs
  fake_sub hook-injection-audit 'no es json' 2
  run bash "$PROJ/scripts/security-audit-all.sh"
  [ "$status" -eq 0 ]
  has_gap unknown hook-injection-audit unreadable
  unmeasured security-audit-all
  run env SAVIA_GATE_UNKNOWN=block bash "$PROJ/scripts/security-audit-all.sh"
  [ "$status" -eq 1 ]
}

@test "audit-all: propaga los huecos que declara un sub-escáner" {
  clean_subs
  fake_sub mcp-security-audit '{"critical":0,"high":0,"medium":0,"low":0,"result":"unknown","gaps":[{"check":"config","reason":"unreadable"}]}' 0
  run bash "$PROJ/scripts/security-audit-all.sh"
  [ "$status" -eq 0 ]
  has_gap unknown mcp-security-audit/config unreadable
}

# ── confidentiality-scan ─────────────────────────────────────────────────────

conf_repo() {
  printf '#!/usr/bin/env bash\necho termino-vetado-xyz\n' > "$PROJ/scripts/generate-blocklist.sh"
  git -C "$PROJ" init -q -b main
  git -C "$PROJ" -c user.email=t@example.com -c user.name=t commit -q --allow-empty -m init
}

@test "conf: --pr sin origin/main ⇒ unknown/git-diff:unreadable (antes «No content to scan» y exit 0)" {
  conf_repo
  run bash "$PROJ/scripts/confidentiality-scan.sh" --pr
  [ "$status" -eq 0 ]
  [[ "$output" != *"No content to scan"* ]]
  has_gap unknown git-diff unreadable
  unmeasured confidentiality-scan
  run env SAVIA_GATE_UNKNOWN=block bash "$PROJ/scripts/confidentiality-scan.sh" --pr
  [ "$status" -eq 2 ]
}

@test "conf: --staged con contenido inocuo ⇒ clean" {
  conf_repo
  printf 'texto inocuo\n' > "$PROJ/notas.txt"; git -C "$PROJ" add notas.txt
  run bash "$PROJ/scripts/confidentiality-scan.sh" --staged
  [ "$status" -eq 0 ]
  is_result clean
  is_last_line "$(last_result)"
}

@test "conf: --staged con un .pem ⇒ BLOCKED por Check 4 (antes nunca veía ficheros)" {
  conf_repo
  printf 'contenido\n' > "$PROJ/clave.pem"; git -C "$PROJ" add clave.pem
  run bash "$PROJ/scripts/confidentiality-scan.sh" --staged
  [ "$status" -eq 1 ]
  [[ "$output" == *"Forbidden file types"* ]]
  is_result findings
}

@test "conf: término de la blocklist ⇒ findings" {
  conf_repo
  printf 'hay un termino-vetado-xyz aqui\n' > "$PROJ/notas.txt"; git -C "$PROJ" add notas.txt
  run bash "$PROJ/scripts/confidentiality-scan.sh" --staged
  [ "$status" -eq 1 ]
  is_result findings
}

@test "conf: --blocklist inexistente ⇒ unknown/blocklist:unreadable (antes se saltaba el Check 1)" {
  conf_repo
  printf 'texto inocuo\n' > "$PROJ/notas.txt"; git -C "$PROJ" add notas.txt
  run bash "$PROJ/scripts/confidentiality-scan.sh" --staged --blocklist "$WORK/no-existe.txt"
  [ "$status" -eq 0 ]
  has_gap unknown blocklist unreadable
}
