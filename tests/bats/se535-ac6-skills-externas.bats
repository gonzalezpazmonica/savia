#!/usr/bin/env bats
# SE-535 AC-6 (RESTO-535-a) — ningún guion enlaza con `ln -s` un directorio de
# skills ni clona un repositorio de skills sin commit fijado (40 hex en la misma
# orden o en la línea siguiente). El detector se prueba sobre casos sembrados y
# después sobre los guiones versionados del repositorio.
# Ref: docs/specs/SE-535-*.spec.md (AC-6)

setup_file() {
  REPO_ROOT="$(git rev-parse --show-toplevel)"
  export REPO_ROOT
}

# detect <fichero...> → imprime `ruta:línea: KIND` por hallazgo; sale 1 si hay alguno.
detect() {
  python3 -I - "$@" <<'PYEOF'
import re, sys
POS = r"(?:^|[;&|(`\s]|\$\()"
LN = re.compile(POS + r"ln\s+-[A-Za-z]*s[A-Za-z]*\s.*skills?(?:[/\s\"']|$)")
CLONE = re.compile(POS + r"git(?:\s+-C\s+\S+)?\s+clone\s.*skill")
SHA = re.compile(r"\b[0-9a-f]{40}\b")
SKIP = re.compile(r"^(?:#|(?:echo|printf|log_[a-z_]+)\s)")
found = False
for path in sys.argv[1:]:
    try:
        lines = open(path, encoding="utf-8", errors="replace").read().splitlines()
    except OSError as e:
        print(f"{path}: ERROR {e}"); found = True; continue
    for i, raw in enumerate(lines):
        line = raw.strip()
        if SKIP.match(line):
            continue
        if LN.search(line):
            print(f"{path}:{i+1}: SKILL_SYMLINK"); found = True
        if CLONE.search(line) and not SHA.search(line):
            nxt = lines[i + 1].strip() if i + 1 < len(lines) else ""
            if not SHA.search(nxt):
                print(f"{path}:{i+1}: SKILL_CLONE_UNPINNED"); found = True
sys.exit(1 if found else 0)
PYEOF
}

@test "AC-6 sembrado: ln -s hacia .claude/skills se detecta" {
  f="$BATS_TEST_TMPDIR/a.sh"
  printf '#!/bin/bash\nln -s "$SRC/foo" "$HOME/.claude/skills/foo"\n' > "$f"
  run detect "$f"
  [ "$status" -eq 1 ]
  [[ "$output" == *"a.sh:2: SKILL_SYMLINK"* ]]
}

@test "AC-6 sembrado: git clone de un repo de skills sin commit fijado se detecta" {
  f="$BATS_TEST_TMPDIR/b.sh"
  printf '#!/bin/bash\nset -e\ngit clone https://example.invalid/acme/agent-skills "$D"\necho ok\n' > "$f"
  run detect "$f"
  [ "$status" -eq 1 ]
  [[ "$output" == *"b.sh:3: SKILL_CLONE_UNPINNED"* ]]
}

@test "AC-6 sembrado: clone en la última línea del fichero también se detecta" {
  f="$BATS_TEST_TMPDIR/c.sh"
  printf 'cd /tmp && git -C /tmp clone https://example.invalid/skills.git x' > "$f"
  run detect "$f"
  [ "$status" -eq 1 ]
  [[ "$output" == *"SKILL_CLONE_UNPINNED"* ]]
}

@test "AC-6 limpio: clone con checkout de 40 hex en la línea siguiente no se reporta" {
  f="$BATS_TEST_TMPDIR/d.sh"
  printf 'git clone https://example.invalid/skills.git x\ngit -C x checkout 0123456789abcdef0123456789abcdef01234567\n' > "$f"
  run detect "$f"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "AC-6 limpio: comentarios, echo y enlaces ajenos a skills no se reportan" {
  f="$BATS_TEST_TMPDIR/e.sh"
  printf '# ln -s x ~/.claude/skills/y\nln -s a b\necho "usa git clone de skills"\n' > "$f"
  run detect "$f"
  [ "$status" -eq 0 ]
}

@test "AC-6 repositorio: ningún guion versionado enlaza o clona skills sin fijar" {
  cd "$REPO_ROOT"
  mapfile -t files < <(git ls-files '*.sh' '*.bash')
  [ "${#files[@]}" -gt 0 ]
  run detect "${files[@]}"
  echo "$output"
  [ "$status" -eq 0 ]
}
