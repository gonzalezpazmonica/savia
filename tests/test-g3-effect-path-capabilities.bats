#!/usr/bin/env bats
# Ref: hueco G3 (P1) — capacidades declaradas NATIVE/PASS sin estar en el camino del efecto.
# Cubre: scripts/frontend-probe.sh (matriz SE-388 y modo --wired),
#        scripts/coherence-gates.sh (cierre del harness y eval-coverage L4),
#        scripts/egress-gate.sh (fail-closed ante YAML malformado y dominio por argv).

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  TMPDIR=$(mktemp -d)
  # Raíz falsa: frontend-probe.sh y coherence-gates.sh derivan ROOT de su ruta.
  FAKE="$TMPDIR/root"
  mkdir -p "$FAKE/scripts" "$FAKE/output" "$FAKE/.claude" "$FAKE/.opencode/plugins" "$FAKE/tests/chaos"
  cp "$REPO_ROOT/scripts/frontend-probe.sh" "$REPO_ROOT/scripts/coherence-gates.sh" "$FAKE/scripts/"
  # Aislamiento del egress-gate: sus logs van a la raíz temporal.
  export PROJECT_ROOT="$TMPDIR/eg"
  mkdir -p "$PROJECT_ROOT/output"
}

teardown() {
  rm -rf "$TMPDIR"
}

# Escribe un settings.json con un hook PreToolUse por cada comando dado.
write_settings() {
  local f="$1"; shift
  python3 - "$f" "$@" <<'PYEOF'
import json, sys
f, cmds = sys.argv[1], sys.argv[2:]
pre = [{"matcher": "Bash", "hooks": [{"type": "command", "command": c}]} for c in cmds]
post = [{"matcher": ".*", "hooks": [{"type": "command", "command": "\"$CLAUDE_PROJECT_DIR\"/.opencode/hooks/edit-ledger-record.sh"}]}]
json.dump({"hooks": {"PreToolUse": pre, "PostToolUse": post}}, open(f, "w"))
PYEOF
}

cap() { # $1=json $2=frontend $3=capability
  python3 -c "import json,sys; print(json.load(open(sys.argv[1]))[sys.argv[2]]['capabilities'][sys.argv[3]])" "$1" "$2" "$3"
}

# ═══════════════════════════════════════════════════════════════════
# frontend-probe.sh — matriz contra el .claude/settings.json real
# ═══════════════════════════════════════════════════════════════════

@test "probe/real: cada capacidad de control NATIVE de Claude tiene su hook en el settings.json real" {
  FRONTEND_PROBE_SETTINGS="$REPO_ROOT/.claude/settings.json" run bash "$FAKE/scripts/frontend-probe.sh"
  [ "$status" -eq 0 ]
  # Cálculo independiente de qué mecanismos están registrados de verdad.
  run python3 - "$REPO_ROOT/.claude/settings.json" "$FAKE/output/frontend-capability-matrix.json" <<'PYEOF'
import json, re, sys
s = json.load(open(sys.argv[1])); m = json.load(open(sys.argv[2]))["claude"]["capabilities"]
pre = [h["command"] for x in s["hooks"].get("PreToolUse", []) for h in x["hooks"] if h.get("command")]
allc = [h["command"] for arr in s["hooks"].values() for x in arr for h in x["hooks"] if h.get("command")]
mech = {
  "network_policy": any(re.search(r"egress-gate\.sh", c) for c in pre),
  "credential_policy": any(re.search(r"block-credential-leak\.sh", c) for c in pre),
  "external_effect_control": any(re.search(r"operator-grant\.sh\s+guard", c) for c in pre),
  "durable_handoff": any(re.search(r"validate-handoff[\w-]*\.sh", c) for c in allc),
  "pre_tool_enforcement": any(re.search(r"block-[\w-]+\.sh", c) for c in pre),
}
bad = []
for k, wired in mech.items():
    native = m[k].startswith("NATIVE")
    if native != wired or (not wired and not m[k].startswith("DECLARED")):
        bad.append(f"{k}: matriz={m[k]!r} hook_registrado={wired}")
print("\n".join(bad) or "OK")
sys.exit(1 if bad else 0)
PYEOF
  echo "$output"
  [ "$status" -eq 0 ]
  [ "$output" = "OK" ]
}

@test "probe/real: network_policy no es NATIVE mientras egress-gate no esté en ningún hook real" {
  grep -q 'egress-gate' "$REPO_ROOT/.claude/settings.json" && skip "egress-gate ya está registrado: el test anterior cubre la coherencia"
  FRONTEND_PROBE_SETTINGS="$REPO_ROOT/.claude/settings.json" run bash "$FAKE/scripts/frontend-probe.sh"
  [ "$status" -eq 0 ]
  run cap "$FAKE/output/frontend-capability-matrix.json" claude network_policy
  [[ "$output" == DECLARED* ]]
}

@test "probe/control positivo: con egress-gate registrado como PreToolUse, network_policy pasa a NATIVE" {
  write_settings "$FAKE/.claude/settings.json" '"$CLAUDE_PROJECT_DIR"/scripts/egress-gate.sh' \
    '"$CLAUDE_PROJECT_DIR"/scripts/operator-grant.sh guard' '"$CLAUDE_PROJECT_DIR"/.opencode/hooks/block-credential-leak.sh'
  run bash "$FAKE/scripts/frontend-probe.sh"
  [ "$status" -eq 0 ]
  [[ "$(cap "$FAKE/output/frontend-capability-matrix.json" claude network_policy)" == NATIVE* ]]
  [[ "$(cap "$FAKE/output/frontend-capability-matrix.json" claude external_effect_control)" == NATIVE* ]]
  [[ "$(cap "$FAKE/output/frontend-capability-matrix.json" claude credential_policy)" == NATIVE* ]]
  # handoff sigue sin hook en el fixture
  [[ "$(cap "$FAKE/output/frontend-capability-matrix.json" claude durable_handoff)" == DECLARED* ]]
}

@test "probe/negativo: egress-gate en un hook PostToolUse no cuenta como enforcement previo" {
  python3 -c "
import json
json.dump({'hooks':{'PostToolUse':[{'matcher':'.*','hooks':[{'type':'command','command':'scripts/egress-gate.sh'}]}]}}, open('$FAKE/.claude/settings.json','w'))"
  run bash "$FAKE/scripts/frontend-probe.sh"
  [ "$status" -eq 0 ]
  [[ "$(cap "$FAKE/output/frontend-capability-matrix.json" claude network_policy)" == DECLARED* ]]
}

@test "probe/fail-closed: settings.json malformado deja todas las capacidades de control en DECLARED" {
  printf '{"hooks": [roto' > "$FAKE/.claude/settings.json"
  run bash "$FAKE/scripts/frontend-probe.sh"
  [ "$status" -eq 0 ]
  J="$FAKE/output/frontend-capability-matrix.json"
  for c in tool_call_hooks pre_tool_enforcement post_tool_receipts network_policy credential_policy external_effect_control durable_handoff; do
    v=$(cap "$J" claude "$c")
    [[ "$v" == DECLARED* ]] || { echo "$c=$v"; return 1; }
  done
  [ "$(python3 -c "import json; print(json.load(open('$J'))['claude']['evidence'])")" = "AUSENTE" ]
  # el resumen Markdown no puede declarar el frontend NATIVE con huecos
  run grep -A3 '^## claude' "$FAKE/output/frontend-capability-matrix.md"
  [[ "$output" == *"status: DECLARED_GAPS"* ]]
}

@test "probe/opencode: grants SE-343 y egress sin guard importado por el plugin quedan DECLARED" {
  mkdir -p "$TMPDIR/bin"; printf '#!/bin/sh\nexit 0\n' > "$TMPDIR/bin/opencode"; chmod +x "$TMPDIR/bin/opencode"
  printf 'import { blockForcePush } from "./guards/block-force-push.ts";\nimport { blockCredentialLeak } from "./guards/block-credential-leak.ts";\n"tool.execute.before"\n' \
    > "$FAKE/.opencode/plugins/savia-foundation.ts"
  write_settings "$FAKE/.claude/settings.json" 'x'
  PATH="$TMPDIR/bin:$PATH" run bash "$FAKE/scripts/frontend-probe.sh"
  [ "$status" -eq 0 ]
  J="$FAKE/output/frontend-capability-matrix.json"
  [[ "$(cap "$J" opencode external_effect_control)" == DECLARED* ]]
  [[ "$(cap "$J" opencode network_policy)" == DECLARED* ]]
  [[ "$(cap "$J" opencode pre_tool_enforcement)" == NATIVE* ]]
  [[ "$(cap "$J" opencode credential_policy)" == NATIVE* ]]
}

# ═══════════════════════════════════════════════════════════════════
# frontend-probe.sh --wired (evaluador compartido con coherence-gates)
# ═══════════════════════════════════════════════════════════════════

@test "wired: un nombre referenciado por un hook registrado devuelve 0" {
  write_settings "$FAKE/.claude/settings.json" 'bash "$CLAUDE_PROJECT_DIR"/scripts/checkpoint.sh verify'
  run bash "$FAKE/scripts/frontend-probe.sh" --wired checkpoint.sh
  [ "$status" -eq 0 ]
}

@test "wired/límite: review-checkpoint.sh registrado no cablea checkpoint.sh" {
  write_settings "$FAKE/.claude/settings.json" 'bash "$CLAUDE_PROJECT_DIR"/scripts/review-checkpoint.sh'
  run bash "$FAKE/scripts/frontend-probe.sh" --wired checkpoint.sh
  [ "$status" -eq 1 ]
}

@test "wired: referencia dentro del fichero de un hook registrado cuenta (un nivel)" {
  mkdir -p "$FAKE/.opencode/hooks"
  printf '#!/bin/bash\nbash "$ROOT/scripts/effect-reservation.sh" check\n' > "$FAKE/.opencode/hooks/h.sh"
  write_settings "$FAKE/.claude/settings.json" '"$CLAUDE_PROJECT_DIR"/.opencode/hooks/h.sh'
  CLAUDE_PROJECT_DIR="$FAKE" run bash "$FAKE/scripts/frontend-probe.sh" --wired effect-reservation.sh
  [ "$status" -eq 0 ]
}

@test "wired/fail-closed: settings ilegible o sin nombre → exit 2" {
  printf 'no-json' > "$FAKE/.claude/settings.json"
  run bash "$FAKE/scripts/frontend-probe.sh" --wired checkpoint.sh
  [ "$status" -eq 2 ]
  run bash "$FAKE/scripts/frontend-probe.sh" --wired
  [ "$status" -eq 2 ]
}

# ═══════════════════════════════════════════════════════════════════
# coherence-gates.sh — cierre del harness y eval-coverage L4
# ═══════════════════════════════════════════════════════════════════

# Stubs para todo lo que no es objeto del test; $1 = contenido del JSON de eval
# coverage ("" = el generador falla y no escribe nada).
stub_gates() {
  for s in guardrail-negative-tests.sh debt-budget-check.sh contract-check.sh law-check.sh; do
    printf '#!/bin/bash\nexit 0\n' > "$FAKE/scripts/$s"
  done
  printf '#!/bin/bash\nexit 0\n' > "$FAKE/tests/chaos/run-chaos-suite.sh"
  printf 'import sys\nsys.exit(0)\n' > "$FAKE/scripts/capability-entropy.py"
  printf 'import sys\nsys.exit(0)\n' > "$FAKE/scripts/constitutional-coverage.py"
  for t in grounding-verify.sh validate-handoff.sh validate-handoff-integrity.sh checkpoint.sh effect-reservation.sh debt-burn-down.sh planning-transition.sh report-benchmark.sh; do
    printf '#!/bin/bash\nexit 0\n' > "$FAKE/scripts/$t"; chmod +x "$FAKE/scripts/$t"
  done
  if [[ -n "$1" ]]; then
    printf 'import sys, os\nopen(os.path.join(sys.argv[2], "output", "eval-coverage-matrix.json"), "w").write(%s)\n' "$(python3 -c 'import sys; print(repr(sys.argv[1]))' "$1")" \
      > "$FAKE/scripts/eval-coverage-matrix.py"
  else
    printf 'import sys\nsys.exit(1)\n' > "$FAKE/scripts/eval-coverage-matrix.py"
  fi
  cp /dev/null "$FAKE/scripts/coherence-gate-policy.yaml"
}

L4_OK='{"rows":[{"risk":"L4","covered":true},{"risk":"L4","covered":true},{"risk":"L2","covered":false}]}'

@test "coherence/negativo: scripts de cierre presentes pero sin hook ni CI → DECLARED, nunca PASS" {
  stub_gates "$L4_OK"
  write_settings "$FAKE/.claude/settings.json" 'bash "$CLAUDE_PROJECT_DIR"/scripts/review-checkpoint.sh'
  run bash "$FAKE/scripts/coherence-gates.sh"
  echo "$output"
  [ "$status" -eq 0 ]
  [[ "$output" != *"PASS coherence/harness-closure"* ]]
  [[ "$output" != *"PASS coherence/closure-"* ]]
  [[ "$output" == *"WARN coherence/closure-checkpoint.sh: DECLARED"* ]]
  [[ "$output" == *"WARN coherence/harness-closure: DECLARED"* ]]
}

@test "coherence/control positivo: scripts de cierre referenciados por hook o CI → PASS" {
  stub_gates "$L4_OK"
  write_settings "$FAKE/.claude/settings.json" \
    'bash scripts/grounding-verify.sh' 'bash scripts/validate-handoff.sh' 'bash scripts/validate-handoff-integrity.sh' \
    'bash scripts/checkpoint.sh' 'bash scripts/effect-reservation.sh' 'bash scripts/debt-burn-down.sh'
  mkdir -p "$FAKE/.github/workflows"
  printf 'jobs:\n  x:\n    steps:\n      - run: bash scripts/planning-transition.sh\n      - run: bash tests/self-evolution/report-benchmark.sh\n' > "$FAKE/.github/workflows/ci.yml"
  run bash "$FAKE/scripts/coherence-gates.sh"
  echo "$output"
  [ "$status" -eq 0 ]
  [[ "$output" == *"PASS coherence/harness-closure"* ]]
  [[ "$output" != *"DECLARED"* ]]
}

@test "coherence/fail-closed: sin matriz de eval coverage evaluable → BLOCK y exit 1" {
  stub_gates ""
  write_settings "$FAKE/.claude/settings.json" 'x'
  run bash "$FAKE/scripts/coherence-gates.sh"
  echo "$output"
  [ "$status" -eq 1 ]
  [[ "$output" == *"BLOCK coherence/eval-coverage-L4"* ]]
  [[ "$output" != *"PASS coherence/eval-coverage-L4"* ]]
}

@test "coherence: L4 descubierta → BLOCK; L4 cubiertas → PASS con el recuento real, no un literal" {
  stub_gates '{"rows":[{"risk":"L4","covered":true},{"risk":"L4","covered":false}]}'
  write_settings "$FAKE/.claude/settings.json" 'x'
  run bash "$FAKE/scripts/coherence-gates.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"BLOCK coherence/eval-coverage-L4: capability L4 perdió cobertura (1/2)"* ]]
  stub_gates "$L4_OK"
  run bash "$FAKE/scripts/coherence-gates.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"PASS coherence/eval-coverage-L4: 2/2 cubiertas"* ]]
}

# ═══════════════════════════════════════════════════════════════════
# egress-gate.sh — fail-closed
# ═══════════════════════════════════════════════════════════════════

@test "egress/fail-closed: YAML malformado deniega incluso un dominio conocido" {
  printf 'domains:\n  - domain: github.com\n    protocols: [https\n' > "$TMPDIR/bad.yaml"
  EGRESS_ALLOWLIST="$TMPDIR/bad.yaml" run bash "$REPO_ROOT/scripts/egress-gate.sh" check github.com
  [ "$status" -eq 1 ]
  [[ "$output" == *"fail-closed"* ]]
}

@test "egress/fail-closed: YAML válido con estructura inesperada (lista) deniega" {
  printf -- '- github.com\n' > "$TMPDIR/list.yaml"
  EGRESS_ALLOWLIST="$TMPDIR/list.yaml" run bash "$REPO_ROOT/scripts/egress-gate.sh" check github.com
  [ "$status" -eq 1 ]
}

@test "egress/fail-closed: sin PyYAML importable no hay lista de reserva permisiva" {
  mkdir -p "$TMPDIR/noyaml"
  printf 'raise ImportError("simulado")\n' > "$TMPDIR/noyaml/yaml.py"
  PYTHONPATH="$TMPDIR/noyaml" run bash "$REPO_ROOT/scripts/egress-gate.sh" check github.com
  [ "$status" -eq 1 ]
}

@test "egress/argv: un dominio con código Python no se ejecuta ni se permite" {
  printf 'domains:\n  - domain: github.com\n    protocols: [https]\n' > "$TMPDIR/ok.yaml"
  payload="x', '') or sys.exit(0) or ('"
  EGRESS_ALLOWLIST="$TMPDIR/ok.yaml" run bash "$REPO_ROOT/scripts/egress-gate.sh" check "$payload"
  [ "$status" -eq 1 ]
  # el registro de denegación es JSON válido y no arrastra la carga
  run python3 -c "import json,sys; [json.loads(l) for l in open(sys.argv[1])]" "$PROJECT_ROOT/output/egress-denials.jsonl"
  [ "$status" -eq 0 ]
  run grep -c 'sys.exit' "$PROJECT_ROOT/output/egress-denials.jsonl"
  [ "$output" = "0" ]
}

@test "egress/argv: protocolo con código Python se deniega" {
  printf 'domains:\n  - domain: github.com\n    protocols: [https]\n' > "$TMPDIR/ok.yaml"
  EGRESS_ALLOWLIST="$TMPDIR/ok.yaml" run bash "$REPO_ROOT/scripts/egress-gate.sh" check github.com "x' or __import__('sys').exit(0) or '"
  [ "$status" -eq 1 ]
}

@test "egress/control positivo: allowlist válido permite el dominio listado y deniega el resto" {
  printf 'domains:\n  - domain: github.com\n    protocols: [https]\n' > "$TMPDIR/ok.yaml"
  EGRESS_ALLOWLIST="$TMPDIR/ok.yaml" run bash "$REPO_ROOT/scripts/egress-gate.sh" check github.com
  [ "$status" -eq 0 ]
  EGRESS_ALLOWLIST="$TMPDIR/ok.yaml" run bash "$REPO_ROOT/scripts/egress-gate.sh" check pypi.org
  [ "$status" -eq 1 ]
  EGRESS_ALLOWLIST="$TMPDIR/ok.yaml" run bash "$REPO_ROOT/scripts/egress-gate.sh" check github.com http
  [ "$status" -eq 1 ]
}

# S03u — supervivientes de mutación en egress-gate.sh

@test "egress: SAVIA_EGRESS_GATE=off is the documented master switch and exits 0 for any domain" {
  printf 'domains:\n  - domain: github.com\n    protocols: [https]\n' > "$TMPDIR/ok.yaml"
  SAVIA_EGRESS_GATE=off EGRESS_ALLOWLIST="$TMPDIR/ok.yaml" run bash "$REPO_ROOT/scripts/egress-gate.sh" check evil.example
  [ "$status" -eq 0 ]
  [ ! -e "$PROJECT_ROOT/output/egress-denials.jsonl" ]
}

@test "egress: an unknown action is a usage error with exit 2" {
  run bash "$REPO_ROOT/scripts/egress-gate.sh" allow github.com
  [ "$status" -eq 2 ]
  [[ "$output" == *"Usage:"* ]]
}

@test "egress: an invalid protocol is denied even when the allowlist accepts any protocol" {
  printf 'domains:\n  - domain: github.com\n    protocols: ["*"]\n' > "$TMPDIR/any.yaml"
  EGRESS_ALLOWLIST="$TMPDIR/any.yaml" run bash "$REPO_ROOT/scripts/egress-gate.sh" check github.com "ht tp"
  [ "$status" -eq 1 ]
  [[ "$output" == *"formato no válido"* ]]
  EGRESS_ALLOWLIST="$TMPDIR/any.yaml" run bash "$REPO_ROOT/scripts/egress-gate.sh" check github.com ftp
  [ "$status" -eq 0 ]
}

@test "egress: an invalid domain is denied even if the allowlist lists it literally" {
  printf 'domains:\n  - domain: "a..b"\n    protocols: [https]\n' > "$TMPDIR/odd.yaml"
  EGRESS_ALLOWLIST="$TMPDIR/odd.yaml" run bash "$REPO_ROOT/scripts/egress-gate.sh" check "a..b"
  [ "$status" -eq 1 ]
  [[ "$output" == *"formato no válido"* ]]
  run python3 -c 'import json,sys; d=json.loads(open(sys.argv[1]).read().splitlines()[-1]); assert d["domain"]=="<invalid>" and d["verdict"]=="denied", d' "$PROJECT_ROOT/output/egress-denials.jsonl"
  [ "$status" -eq 0 ]
}

@test "egress: isolated mode denies an allowlisted domain and logs the denial" {
  printf 'domains:\n  - domain: github.com\n    protocols: [https]\n' > "$TMPDIR/ok.yaml"
  SAVIA_ISOLATED_MODE=1 EGRESS_ALLOWLIST="$TMPDIR/ok.yaml" run bash "$REPO_ROOT/scripts/egress-gate.sh" check github.com
  [ "$status" -eq 1 ]
  [[ "$output" == *"ISOLATED"* ]]
  run grep -c '"domain":"github.com"' "$PROJECT_ROOT/output/egress-denials.jsonl"
  [ "$output" = "1" ]
}

@test "egress: status reports the real domain count and denial count, one line each" {
  printf 'domains:\n  - domain: github.com\n    protocols: [https]\n  - domain: pypi.org\n    protocols: [https]\n' > "$TMPDIR/two.yaml"
  EGRESS_ALLOWLIST="$TMPDIR/two.yaml" run bash "$REPO_ROOT/scripts/egress-gate.sh" check evil.example
  [ "$status" -eq 1 ]
  EGRESS_ALLOWLIST="$TMPDIR/two.yaml" run bash "$REPO_ROOT/scripts/egress-gate.sh" status
  [ "$status" -eq 0 ]
  [[ "$output" == *$'Domains: 2\nDenials: 1'* ]]
  [[ "$output" != *"Denials: 0"* ]]
}

@test "egress: status with no denials yet reports zero" {
  printf 'domains:\n  - domain: github.com\n    protocols: [https]\n' > "$TMPDIR/ok.yaml"
  EGRESS_ALLOWLIST="$TMPDIR/ok.yaml" run bash "$REPO_ROOT/scripts/egress-gate.sh" status
  [[ "$output" == *$'Domains: 1\nDenials: 0'* ]]
  [[ "$output" != *"Proposals:"* ]]
}

@test "egress: propose records a pending proposal and never edits the allowlist" {
  printf 'domains:\n  - domain: github.com\n    protocols: [https]\n' > "$TMPDIR/ok.yaml"
  before=$(sha256sum "$TMPDIR/ok.yaml")
  EGRESS_ALLOWLIST="$TMPDIR/ok.yaml" run bash "$REPO_ROOT/scripts/egress-gate.sh" propose docs.rs "crates docs"
  [ "$status" -eq 0 ]
  grep -q 'docs.rs' "$PROJECT_ROOT/output/egress-proposals.md"
  grep -q 'PENDING HUMAN APPROVAL' "$PROJECT_ROOT/output/egress-proposals.md"
  [ "$(sha256sum "$TMPDIR/ok.yaml")" = "$before" ]
  EGRESS_ALLOWLIST="$TMPDIR/ok.yaml" run bash "$REPO_ROOT/scripts/egress-gate.sh" check docs.rs
  [ "$status" -eq 1 ]
}
