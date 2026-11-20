#!/usr/bin/env bats
# Contrato guards-fp-tests (2026-11-20): G1 firmantes, G2 destino git, G3 pytest, G4 medición.
# Estrategia: interfaz PreToolUse real (JSON por stdin), pares allow/block y controles negativos.
# Las órdenes del evento NUNCA se ejecutan. Solo se invocan los guards copiados a /tmp.
# Ejecutar: bats tests/test-guards-falsos-positivos.bats
# G2 complementa tests/test-guards-commit-target.bats; esa suite debe seguir pasando.
# G4 fija el ejemplo del encargo como contrato: output/guard-decisions/<guard>.jsonl,
# campos ts (ISO-8601 con zona), guard, verdict (allow|block), reason (código/frase corta).
# No se exige el texto exacto del motivo ni una implementación concreta del analizador.

setup() {
  SOURCE_ROOT="${HOOKS_ROOT:-$(cd "$BATS_TEST_DIRNAME/.." && pwd)}"
  # BATS_TEST_TMPDIR puede contener /test/: el gate TDD exime esa ruta y daría falsos verdes.
  CASE_ROOT=$(mktemp -d /tmp/savia-guards-fp.XXXXXX)
  MAIN="$CASE_ROOT/savia"
  WT="$CASE_ROOT/worktree-agent"
  mkdir -p "$MAIN/.claude/hooks" "$MAIN/config" "$MAIN/src" "$MAIN/docs"
  cp -R "$SOURCE_ROOT/scripts" "$MAIN/scripts"
  cp -R "$SOURCE_ROOT/.claude/hooks/." "$MAIN/.claude/hooks/"
  G1="$MAIN/scripts/operator-grant.sh"
  G2="$MAIN/.claude/hooks/validate-bash-global.sh"
  G3="$MAIN/.claude/hooks/tdd-gate.sh"
  SIGNERS="$MAIN/config/operator-grant-signers"
  printf '# fixture sin claves\n' > "$SIGNERS"
  printf 'dato\n' > "$MAIN/config/otro"
  printf 'entrada\n' > "$MAIN/x"
  # Evitar que el entorno Git del runner redirija las operaciones al repo real.
  unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_INDEX_FILE
  export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null
  git -C "$MAIN" init -q -b main
  git -C "$MAIN" -c user.name=fixture -c user.email=fixture@example.invalid \
    commit -q --allow-empty -m fixture
  git -C "$MAIN" worktree add -q -b agent/fixture "$WT"
  export CLAUDE_PROJECT_DIR="$MAIN" SAVIA_WORKSPACE_DIR="$MAIN"
  export SAVIA_GRANTS_DIR="$CASE_ROOT/grants"
  export SAVIA_ACTIVE_USER_FILE="$CASE_ROOT/absent-profile.md"
  export SAVIA_HOOK_PROFILE=standard
  unset SAVIA_ALLOW_MAIN_COMMIT SAVIA_GH_BIN SAVIA_GRANT_TEST_MODE
  LOG_DIR="$MAIN/output/guard-decisions"
  cd "$MAIN"
}

teardown() {
  cd /tmp
  if [[ -n "${CASE_ROOT:-}" && "$CASE_ROOT" == /tmp/savia-guards-fp.* ]]; then
    rm -rf -- "$CASE_ROOT"
  fi
}

# Siempre JSON por stdin, con cwd consistente con el cwd efectivo del proceso.
bash_event() {
  jq -nc --arg c "$1" --arg d "$PWD" \
    '{hook_event_name:"PreToolUse",tool_name:"Bash",cwd:$d,tool_input:{command:$c}}'
}

file_event() {
  jq -nc --arg t "$1" --arg f "$2" --arg d "$PWD" \
    '{hook_event_name:"PreToolUse",tool_name:$t,cwd:$d,
      tool_input:{file_path:$f,content:"FP_FILE_CONTENT_SENTINEL",old_string:"antes",new_string:"despues"}}'
}

g1_bash() { bash_event "$1" | bash "$G1" guard; }
g1_file() { file_event "$1" "$2" | bash "$G1" guard; }
g2_bash() { bash_event "$1" | bash "$G2"; }
g3_file() { file_event "$1" "$2" | bash "$G3"; }

assert_g1_block() {
  [ "$status" -eq 2 ]
  [[ "$output" == *"operator-grant"*"raíz de confianza"* ]]
}

assert_g2_block() {
  [ "$status" -eq 2 ]
  [[ "$output" == *"BLOQUEADO: rama 'main'"* || "$output" == *"fail-closed"* ]]
}

assert_g3_block() {
  [ "$status" -eq 2 ]
  [[ "$output" == *"TDD GATE: No se encontraron tests para"* ]]
}

# G1: reproduce la forma del incidente sin mencionar los firmantes. Las llaves y
# comodines son datos Python de un heredoc entre comillas, no expansiones de Bash.
@test "G1 allow: python heredoc reescribe judge-routing con llaves y f-string" {
  run g1_bash "$(cat <<'COMMAND'
python3 - <<'PY'
from pathlib import Path
# Conserva patrones del script generado: {a,b} config/*
target = Path('scripts/judge-routing-verify.sh')
a, b = 'uno', 'dos'
replacement = f'''#!/usr/bin/env bash
# variantes {{a,b}}: {a}, {b}
for rule in config/*; do
  printf '%s\\n' "$rule"
done
'''
patterns = {'{a,b}', '*.sh', 'config/*', '[a-z]?'}
target.write_text(replacement + '\n'.join(sorted(patterns)))
PY
COMMAND
)"
  [ "$status" -eq 0 ]
}

@test "G1 allow: heredoc Python con diccionario y glob config/* como datos" {
  run g1_bash $'python3 - <<\'PY\'\nfrom pathlib import Path\ndata = {"glob": "config/*", "brace": "{a,b}"}\nPath("scripts/judge-routing-verify.sh").write_text(str(data))\nPY'
  [ "$status" -eq 0 ]
}

@test "G1 allow: cp con llaves que solo alcanzan ficheros ordinarios" {
  run g1_bash 'cp x config/{otro,nuevo}'
  [ "$status" -eq 0 ]
}

@test "G1 allow: glob de scripts no alcanza config/operator-grant-signers" {
  run g1_bash 'sed -i s/antes/despues/ scripts/*.sh'
  [ "$status" -eq 0 ]
}

@test "G1 allow: nombre parecido con sufijo no es la raíz de confianza" {
  run g1_file Write "$MAIN/config/operator-grant-signers-notes.md"
  [ "$status" -eq 0 ]
}

@test "G1 allow: Read permite consultar los firmantes públicos" {
  run g1_file Read "$SIGNERS"
  [ "$status" -eq 0 ]
}

@test "G1 block: Write relativo a los firmantes" {
  run g1_file Write config/operator-grant-signers
  assert_g1_block
}

@test "G1 block: Edit absoluto a los firmantes" {
  run g1_file Edit "$SIGNERS"
  assert_g1_block
}

@test "G1 block: Edit normaliza segmentos padre de la ruta" {
  run g1_file Edit "$MAIN/src/../config/operator-grant-signers"
  assert_g1_block
}

@test "G1 block: Write en la copia de otro worktree temporal" {
  mkdir -p "$WT/config"
  run g1_file Write "$WT/config/operator-grant-signers"
  assert_g1_block
}

@test "G1 block: redirección de truncado hacia firmantes" {
  run g1_bash 'printf x > config/operator-grant-signers'
  assert_g1_block
}

@test "G1 block: redirección append hacia firmantes" {
  run g1_bash 'printf x >> config/operator-grant-signers'
  assert_g1_block
}

@test "G1 block: mv hacia firmantes" {
  run g1_bash 'mv x config/operator-grant-signers'
  assert_g1_block
}

@test "G1 block: ln hacia firmantes" {
  run g1_bash 'ln -sf x config/operator-grant-signers'
  assert_g1_block
}

@test "G1 block: cp con expansión operator-grant-{signers,otro}" {
  run g1_bash 'cp x config/operator-grant-{signers,otro}'
  assert_g1_block
}

@test "G1 block: llaves anidadas componen el destino protegido" {
  run g1_bash 'cp x config/{operator-grant-{otro,signers},nuevo}'
  assert_g1_block
}

@test "G1 block: secuencia de llaves alcanza firmantes" {
  run g1_bash 'tee -a config/operator-grant-signer{r..t} < x'
  assert_g1_block
}

@test "G1 block: glob config/* alcanza los firmantes existentes" {
  [ -f "$SIGNERS" ]
  run g1_bash 'sed -i s/antes/despues/ config/*'
  assert_g1_block
}

@test "G1 block: glob con clase de caracteres alcanza firmantes" {
  run g1_bash 'tee -a config/operator-grant-signer[s] < x'
  assert_g1_block
}

@test "G1 block: cd cambia la base del glob peligroso" {
  run g1_bash 'cd config && tee -a o* < ../x'
  assert_g1_block
}

@test "G1 block: comillas partidas no ocultan el nombre protegido" {
  run g1_bash "printf x >> config/operator-grant-''signers"
  assert_g1_block
}

@test "G1 block: heredoc Python escribe directamente los firmantes" {
  run g1_bash $'python3 - <<\'PY\'\nfrom pathlib import Path\nPath("config/operator-grant-signers").write_text("intruso")\nPY'
  assert_g1_block
}

@test "G1 block: heredoc inocuo seguido de escritura con glob sigue protegido" {
  run g1_bash $'cat > notas.md <<\'EOF\'\n{a,b} *.sh\nEOF\nsed -i s/antes/despues/ config/*'
  assert_g1_block
}

@test "G1 block: heredoc de shell ejecuta la escritura con llaves" {
  run g1_bash $'bash <<\'EOF\'\ncp x config/operator-grant-{signers,otro}\nEOF'
  assert_g1_block
}

@test "G1 block: JSON inválido no da permiso por error del analizador" {
  run bash "$G1" guard <<< 'no-json'
  [ "$status" -eq 2 ]
  [[ "$output" == *"entrada no es JSON"* ]]
}

# G2: cada orden tiene un destino. Un cd anterior no puede eclipsar git -C literal.
@test "G2 allow: commit y add son texto en un heredoc de cat" {
  run g2_bash $'cat > f.md <<\'EOF\'\nhaz commit y add\ngit commit -m texto\ngit add .\nEOF'
  [ "$status" -eq 0 ]
}

@test "G2 allow: echo entre comillas solo menciona commit" {
  run g2_bash 'echo "haz commit"'
  [ "$status" -eq 0 ]
}

@test "G2 allow: echo entre comillas menciona git commit y git add" {
  run g2_bash 'echo "haz git commit; git add ."'
  [ "$status" -eq 0 ]
}

@test "G2 allow: git -C literal a agent tras cd al repo main" {
  cd "$WT"
  run g2_bash "cd '$MAIN' && git -C '$WT' commit -m fixture"
  [ "$status" -eq 0 ]
}

@test "G2 allow: add y commit con -C literal conservan su destino tras cd" {
  run g2_bash "cd '$MAIN'; git -C '$WT' add f.md && git -C '$WT' commit -m fixture"
  [ "$status" -eq 0 ]
}

@test "G2 allow: mensaje de commit por heredoc a cat hacia agent" {
  run g2_bash "git -C '$WT' commit -m \"\$(cat <<'EOF'
fixture: commit y add son texto
EOF
)\""
  [ "$status" -eq 0 ]
}

@test "G2 block: git commit real en main" {
  run g2_bash 'git commit -m fixture'
  assert_g2_block
}

@test "G2 block: git add real en main" {
  run g2_bash 'git add f.md'
  assert_g2_block
}

@test "G2 block: -C literal hacia main desde agent" {
  cd "$WT"
  run g2_bash "git -C '$MAIN' commit -m fixture"
  assert_g2_block
}

@test "G2 block: -C literal para add hacia main desde agent" {
  cd "$WT"
  run g2_bash "git -C '$MAIN' add f.md"
  assert_g2_block
}

@test "G2 block: heredoc de cat termina y después hay commit real" {
  run g2_bash $'cat > f.md <<\'EOF\'\ncommit y add como texto\nEOF\ngit commit -m fixture'
  assert_g2_block
}

@test "G2 block: cadena entre comillas seguida de git add real" {
  run g2_bash 'echo "haz commit"; git add f.md'
  assert_g2_block
}

@test "G2 block: sustitución ejecutable dentro de echo no es texto inerte" {
  run g2_bash 'echo "$(git commit -m fixture)"'
  assert_g2_block
}

@test "G2 block: heredoc sin comillas ejecuta sustitución git add" {
  run g2_bash $'cat > f.md <<EOF\n$(git add f.md)\nEOF'
  assert_g2_block
}

@test "G2 block: heredoc de bash ejecuta git commit" {
  run g2_bash $'bash <<\'EOF\'\ngit commit -m fixture\nEOF'
  assert_g2_block
}

@test "G2 block: destino variable desconocido falla cerrado desde agent" {
  cd "$WT"
  run g2_bash 'git -C "$X" commit -m fixture'
  assert_g2_block
}

@test "G2 block: git add con destino desconocido falla cerrado desde agent" {
  cd "$WT"
  run g2_bash 'git -C "$X" add f.md'
  assert_g2_block
}

@test "G2 block: alias git de commit conserva protección en main" {
  git -C "$MAIN" config alias.ci commit
  run g2_bash 'git ci -m fixture'
  assert_g2_block
}

@test "G2 block: alias git de add conserva protección en main" {
  git -C "$MAIN" config alias.stagefixture add
  run g2_bash 'git stagefixture f.md'
  assert_g2_block
}

@test "G2 block: continuación de línea dentro de commit" {
  run g2_bash $'git com\\\nmit -m fixture'
  assert_g2_block
}

@test "G2 block: continuación de línea antes de add" {
  run g2_bash $'git \\\nadd f.md'
  assert_g2_block
}

@test "G2 block: argv0 por sustitución echo git falla cerrado desde agent" {
  cd "$WT"
  run g2_bash '$(echo git) commit -m fixture'
  assert_g2_block
}

@test "G2 block: un commit a agent no oculta el segundo commit a main" {
  run g2_bash "git -C '$WT' commit -m primero; git -C '$MAIN' commit -m segundo"
  assert_g2_block
}

@test "G2 block: resolvedor inexistente no permite commit ni add desde agent" {
  mv "$MAIN/scripts/lib/git_op_targets.py" "$CASE_ROOT/resolver.py"
  cd "$WT"
  run g2_bash "git -C '$WT' commit -m fixture"
  assert_g2_block
  run g2_bash "git -C '$WT' add f.md"
  assert_g2_block
}

# G3: x.py no contiene test/spec en el nombre ni en sus directorios ancestros.
@test "G3 allow: Edit de x.py con test_x.py en el mismo directorio" {
  printf 'def value(): return 1\n' > "$MAIN/src/x.py"
  printf 'from x import value\ndef test_value(): assert value() == 1\n' > "$MAIN/src/test_x.py"
  run g3_file Edit "$MAIN/src/x.py"
  [ "$status" -eq 0 ]
}

@test "G3 allow: Write relativo con test_x.py hermano" {
  printf 'from x import value\ndef test_value(): assert value() == 1\n' > "$MAIN/src/test_x.py"
  run g3_file Write src/x.py
  [ "$status" -eq 0 ]
}

@test "G3 block: Edit de producción sin ningún test" {
  printf 'def value(): return 1\n' > "$MAIN/src/x.py"
  run g3_file Edit "$MAIN/src/x.py"
  assert_g3_block
}

@test "G3 block: Write de producción nueva sin tests" {
  run g3_file Write "$MAIN/src/x.py"
  assert_g3_block
}

@test "G3 block: test_y.py no cubre x.py" {
  touch "$MAIN/src/test_y.py"
  run g3_file Edit "$MAIN/src/x.py"
  assert_g3_block
}

@test "G3 block: directorio llamado test_x.py no es un fichero de test" {
  mkdir "$MAIN/src/test_x.py"
  run g3_file Write "$MAIN/src/x.py"
  assert_g3_block
}

@test "G3 block: test_x.py en otro repo no cubre producción en el destino" {
  printf 'def value(): return 1\n' > "$WT/x.py"
  printf 'from x import value\ndef test_value(): assert value() == 1\n' > "$WT/test_x.py"
  cd "$WT"
  run g3_file Edit "$MAIN/src/x.py"
  assert_g3_block
}

# G4: exactamente una línea POR invocación, también por la salida rápida allow.
# Los sentinelas detectan tanto la orden completa como fugas parciales de datos.
assert_decisions() {
  local guard="$1" expected="$2"
  python3 - "$LOG_DIR/$guard.jsonl" "$guard" "$expected" "$CASE_ROOT" <<'PY'
import datetime
import json
from pathlib import Path
import sys

path, guard, expected, private_path = sys.argv[1:]
assert Path(path).is_file(), f"falta el JSONL de decisiones: {path}"
raw = Path(path).read_text()
lines = raw.splitlines()
assert len(lines) == int(expected), ("líneas por decisión", lines)
rows = [json.loads(line) for line in lines]
for row in rows:
    assert isinstance(row, dict), row
    assert {"ts", "guard", "verdict", "reason"} <= row.keys(), row
    assert row["guard"] == guard, row
    assert row["verdict"] in {"allow", "block"}, row
    assert isinstance(row["ts"], str) and row["ts"].strip(), row
    stamp = datetime.datetime.fromisoformat(row["ts"].replace("Z", "+00:00"))
    assert stamp.utcoffset() is not None, row
    assert isinstance(row["reason"], str) and 0 < len(row["reason"]) <= 200, row
    assert "\n" not in row["reason"], row
    assert not ({"command", "tool_input", "content", "old_string", "new_string"} & row.keys()), row
assert [r["verdict"] for r in rows] == ["allow", "block"][:int(expected)], rows
for forbidden in ("FP_ALLOW_SENTINEL", "FP_BLOCK_SENTINEL", "FP_FILE_CONTENT_SENTINEL",
                  "FP_SOURCE_SENTINEL", "FP_TEST_SENTINEL", private_path,
                  "printf", "git commit", "git add", "def value", "assert value"):
    assert forbidden not in raw, ("fuga de orden/contenido/ruta", forbidden)
PY
}

@test "G4 G1: allow y block añaden una línea cada uno sin órdenes ni contenido" {
  run g1_bash 'printf "%s" FP_ALLOW_SENTINEL'
  [ "$status" -eq 0 ]
  assert_decisions operator-grant 1
  run g1_bash 'printf "%s" FP_BLOCK_SENTINEL >> config/operator-grant-signers'
  assert_g1_block
  assert_decisions operator-grant 2
}

@test "G4 G2: salida rápida allow y commit bloqueado se registran sin la orden" {
  run g2_bash 'printf "%s" FP_ALLOW_SENTINEL'
  [ "$status" -eq 0 ]
  assert_decisions validate-bash-global 1
  run g2_bash 'git commit -m FP_BLOCK_SENTINEL'
  assert_g2_block
  assert_decisions validate-bash-global 2
}

@test "G4 G3: test hermano permite y producción huérfana bloquea sin filtrar contenido" {
  printf '# FP_SOURCE_SENTINEL\ndef value(): return 1\n' > "$MAIN/src/x.py"
  printf '# FP_TEST_SENTINEL\nfrom x import value\ndef test_value(): assert value() == 1\n' > "$MAIN/src/test_x.py"
  run g3_file Edit "$MAIN/src/x.py"
  [ "$status" -eq 0 ]
  assert_decisions tdd-gate 1
  run g3_file Write "$MAIN/src/orphan.py"
  assert_g3_block
  assert_decisions tdd-gate 2
}
