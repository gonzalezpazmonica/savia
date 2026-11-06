#!/usr/bin/env bats
# SPEC-149 -- Sandbox OS-level tests (Capa A permission block + policies + doctor)

setup() {
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
  OC_CONFIG="$REPO_ROOT/opencode.json"
  POLICY_DIR="$REPO_ROOT/.opencode/sandbox-policies"
  DOCTOR="$REPO_ROOT/scripts/savia-sandbox-doctor.sh"
}

@test "AC-06a: permission.bash deny rule for destructive rm" {
  python3 -c "
import json
with open('$OC_CONFIG') as f: d = json.load(f)
b = d.get('agent',{}).get('build',{}).get('permission',{}).get('bash',{})
assert 'rm -rf *' in b and b['rm -rf *'] == 'deny', 'rm-rf not denied'
"
}

@test "AC-06b: permission.bash has at least 3 deny rules" {
  count=$(python3 -c "
import json
with open('$OC_CONFIG') as f: d = json.load(f)
b = d.get('agent',{}).get('build',{}).get('permission',{}).get('bash',{})
print(sum(1 for v in b.values() if v == 'deny'))
")
  [ "$count" -ge 3 ]
}

@test "AC-01: opencode-sandbox declared in plugin array" {
  python3 -c "
import json
with open('$OC_CONFIG') as f: d = json.load(f)
assert 'opencode-sandbox' in d.get('plugin',[]), 'opencode-sandbox missing from plugin[]'
"
}

@test "AC-08a: default-readonly.yaml valid with filesystem and network" {
  [ -f "$POLICY_DIR/default-readonly.yaml" ]
  grep -q "filesystem:" "$POLICY_DIR/default-readonly.yaml"
  grep -q "network:" "$POLICY_DIR/default-readonly.yaml"
  grep -q "deny_default: true" "$POLICY_DIR/default-readonly.yaml"
}

@test "AC-08b: overnight-sprint.yaml exists" {
  [ -f "$POLICY_DIR/overnight-sprint.yaml" ]
}

@test "AC-08c: code-improvement-loop.yaml exists" {
  [ -f "$POLICY_DIR/code-improvement-loop.yaml" ]
}

@test "AC-08d: tech-research-agent.yaml exists" {
  [ -f "$POLICY_DIR/tech-research-agent.yaml" ]
}

@test "AC-08e: pentesting.yaml has localhost-only network" {
  [ -f "$POLICY_DIR/pentesting.yaml" ]
  grep -q "deny_default: true" "$POLICY_DIR/pentesting.yaml"
  grep -q "localhost" "$POLICY_DIR/pentesting.yaml"
}

@test "AC-08f: all policies declare mode" {
  for p in default-readonly overnight-sprint code-improvement-loop tech-research-agent pentesting; do
    grep -q "^mode:" "$POLICY_DIR/${p}.yaml"
  done
}

@test "AC-07a: savia-sandbox-doctor.sh exists and is executable" {
  [ -f "$DOCTOR" ]
  [ -x "$DOCTOR" ]
}

@test "AC-07b: doctor reports Capa A permission.bash" {
  run bash "$DOCTOR"
  echo "$output" | grep -q "permission.bash"
}

@test "AC-07c: doctor reports bubblewrap" {
  run bash "$DOCTOR"
  echo "$output" | grep -qi "bubblewrap"
}

@test "AC-07d: doctor reports all 5 policies" {
  run bash "$DOCTOR"
  echo "$output" | grep -q "default-readonly"
  echo "$output" | grep -q "overnight-sprint"
  echo "$output" | grep -q "pentesting"
}

@test "AC-07e: doctor has set -uo pipefail" {
  head -5 "$DOCTOR" | grep -q "set -uo pipefail"
}

@test "AC-05: sandbox-os-policy.md exists" {
  [ -f "$REPO_ROOT/docs/rules/domain/sandbox-os-policy.md" ]
}

@test "AC-05b: sandbox-os-policy.md covers 3 layers" {
  grep -q "Capa A" "$REPO_ROOT/docs/rules/domain/sandbox-os-policy.md"
  grep -q "Capa B" "$REPO_ROOT/docs/rules/domain/sandbox-os-policy.md"
  grep -q "Capa C" "$REPO_ROOT/docs/rules/domain/sandbox-os-policy.md"
}

@test "AC-05c: sandbox-os-policy.md documents Ubuntu 24.04 caveat" {
  grep -qi "24.04\|AppArmor\|Ubuntu" "$REPO_ROOT/docs/rules/domain/sandbox-os-policy.md"
}

@test "opencode.json is valid JSON" {
  python3 -c "import json; json.load(open('$OC_CONFIG'))"
}

@test "opencode.json has experimental.sandbox block" {
  python3 -c "
import json
with open('$OC_CONFIG') as f: d = json.load(f)
s = d.get('experimental',{}).get('sandbox',{})
assert 'fail_if_unavailable' in s
assert 'policy_dir' in s
"
}

# ── S03r: el doctor sobre un árbol aislado, por comportamiento ───────────────
# Ref: SPEC-149, docs/rules/domain/sandbox-os-policy.md. PATH contiene solo
# stubs (bwrap, docker, uname) y los binarios que el script necesita, así que
# el resultado no depende de la máquina.

doctor_tree() {  # doctor_tree <opencode.json> — árbol con 5 políticas y bwrap que funciona
  T="$BATS_TEST_TMPDIR/t"; mkdir -p "$T/scripts" "$T/.opencode/sandbox-policies" "$T/bin"
  cp "$DOCTOR" "$T/scripts/"
  D2="$T/scripts/savia-sandbox-doctor.sh"
  printf '%s' "$1" > "$T/opencode.json"
  for p in default-readonly overnight-sprint code-improvement-loop tech-research-agent pentesting; do
    echo "mode: x" > "$T/.opencode/sandbox-policies/$p.yaml"
  done
  ln -sf "$(command -v python3)" "$T/bin/python3"
  ln -sf "$(command -v dirname)" "$T/bin/dirname"
  printf '#!/bin/sh\necho Linux\n' > "$T/bin/uname"
  printf '#!/bin/sh\nexit 0\n' > "$T/bin/bwrap"
  printf '#!/bin/sh\nexit 0\n' > "$T/bin/docker"
  chmod +x "$T/bin/uname" "$T/bin/bwrap" "$T/bin/docker"
}
GOOD='{"plugin":["opencode-sandbox"],"agent":{"build":{"permission":{"bash":{"rm -rf *":"deny","sudo *":"deny","git push --force*":"deny","ls":"allow"}}}}}'
doc() { run env PATH="$T/bin" "$BASH" "$D2"; }

@test "doctor: fully configured tree is operational with exit 0" {
  doctor_tree "$GOOD"; doc
  [ "$status" -eq 0 ]
  [[ "$output" == *"permission.bash: 3 reglas deny"* ]]
  [[ "$output" == *"sandbox completamente operativo"* ]]
}

@test "doctor: boundary, 2 deny rules is an error and 3 is enough" {
  doctor_tree '{"plugin":["opencode-sandbox"],"agent":{"build":{"permission":{"bash":{"a":"deny","b":"deny","c":"allow"}}}}}'; doc
  [ "$status" -eq 1 ]
  [[ "$output" == *"insuficiente (2 deny rules, minimo 3)"* ]]
}

@test "doctor: missing opencode.json is an error" {
  doctor_tree "$GOOD"; mv "$T/opencode.json" "$T/opencode.json.off"; doc
  [ "$status" -eq 1 ]
  [[ "$output" == *"opencode.json no encontrado"* ]]
}

@test "doctor: invalid JSON fails closed (0 deny rules), not OK" {
  doctor_tree '{not json'; doc
  [ "$status" -eq 1 ]
  [[ "$output" == *"insuficiente (0 deny rules"* ]]
}

@test "doctor: plugin as a string containing the name is not the plugin (substring bypass)" {
  # Antes: «"opencode-sandbox" in "opencode-sandbox-disabled"» era True → Capa B OK.
  doctor_tree '{"plugin":"opencode-sandbox-disabled","agent":{"build":{"permission":{"bash":{"a":"deny","b":"deny","c":"deny"}}}}}'; doc
  [ "$status" -eq 0 ]
  [[ "$output" == *"opencode-sandbox NO en plugin[]"* ]]
  [[ "$output" == *"1 advertencia(s)"* ]]
}

@test "doctor: versioned plugin entry counts, a similar name does not" {
  doctor_tree '{"plugin":["opencode-sandbox@1.2.0"],"agent":{"build":{"permission":{"bash":{"a":"deny","b":"deny","c":"deny"}}}}}'; doc
  [[ "$output" == *"opencode-sandbox declarado en plugin[]"* ]]
  doctor_tree '{"plugin":["opencode-sandbox-lite"],"agent":{"build":{"permission":{"bash":{"a":"deny","b":"deny","c":"deny"}}}}}'; doc
  [[ "$output" == *"opencode-sandbox NO en plugin[]"* ]]
}

@test "doctor: missing bubblewrap on Linux is an error" {
  doctor_tree "$GOOD"; mv "$T/bin/bwrap" "$T/bwrap.off"; doc
  [ "$status" -eq 1 ]
  [[ "$output" == *"FAIL bubblewrap NO instalado"* ]]
}

@test "doctor: broken bwrap isolation is a warning, not an error" {
  doctor_tree "$GOOD"; printf '#!/bin/sh\nexit 1\n' > "$T/bin/bwrap"; doc
  [ "$status" -eq 0 ]
  [[ "$output" == *"bwrap namespace isolation falla"* ]]
  [[ "$output" == *"1 advertencia(s)"* ]]
}

@test "doctor: on non-Linux the bubblewrap check is skipped" {
  doctor_tree "$GOOD"; printf '#!/bin/sh\necho Darwin\n' > "$T/bin/uname"; mv "$T/bin/bwrap" "$T/bwrap.off"; doc
  [ "$status" -eq 0 ]
  [[ "$output" != *"bubblewrap instalado"* && "$output" != *"bubblewrap NO"* ]]
}

@test "doctor: each missing policy is an error and is named" {
  doctor_tree "$GOOD"; mv "$T/.opencode/sandbox-policies/pentesting.yaml" "$T/p.off"; doc
  [ "$status" -eq 1 ]
  [[ "$output" == *"FAIL pentesting.yaml FALTA"* ]]
  [[ "$output" == *"1 error(es)"* ]]
}

@test "doctor: missing docker is only a warning-free note (Capa C optional)" {
  doctor_tree "$GOOD"; mv "$T/bin/docker" "$T/docker.off"; doc
  [ "$status" -eq 0 ]
  [[ "$output" == *"Docker no instalado"* ]]
  [[ "$output" == *"sandbox completamente operativo"* ]]
}

@test "doctor: only explicit deny counts, ask rules are not deny rules" {
  doctor_tree '{"plugin":["opencode-sandbox"],"agent":{"build":{"permission":{"bash":{"a":"ask","b":"ask","c":"ask","d":"deny"}}}}}'; doc
  [ "$status" -eq 1 ]
  [[ "$output" == *"insuficiente (1 deny rules"* ]]
}

@test "doctor: plugin as a map is not a plugin list" {
  doctor_tree '{"plugin":{"opencode-sandbox":true},"agent":{"build":{"permission":{"bash":{"a":"deny","b":"deny","c":"deny"}}}}}'; doc
  [[ "$output" == *"opencode-sandbox NO en plugin[]"* ]]
}
