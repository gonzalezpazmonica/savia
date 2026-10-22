#!/usr/bin/env bats
# Todos los workflows de GitHub Actions son YAML válido. Uno inválido no arranca (0 jobs) y falla
# en silencio en cada push: dependency-audit.yml lo hizo desde SE-442 por un «: » sin comillas
# dentro de un run de una línea.

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
}

@test "cada workflow de .github/workflows se parsea como YAML" {
  run python3 - "$ROOT/.github/workflows" <<'PY'
import pathlib, sys, yaml
malos = []
for f in sorted(pathlib.Path(sys.argv[1]).glob("*.y*ml")):
    try:
        doc = yaml.safe_load(f.read_text())
        if not isinstance(doc, dict) or "jobs" not in doc:
            malos.append(f"{f.name}: sin jobs")
    except yaml.YAMLError as e:
        malos.append(f"{f.name}: {str(e).splitlines()[0]}")
print("\n".join(malos))
sys.exit(1 if malos else 0)
PY
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "el detector falla con un workflow roto (mutación)" {
  d="$BATS_TEST_TMPDIR/wf"; mkdir -p "$d"
  printf 'on: push\njobs:\n  a:\n    steps:\n      - run: pip install --only-binary=:all: x\n' > "$d/roto.yml"
  run python3 -c "import yaml,sys; yaml.safe_load(open(sys.argv[1]))" "$d/roto.yml"
  [ "$status" -ne 0 ]
}
