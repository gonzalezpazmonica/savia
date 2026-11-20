#!/usr/bin/env bats
# Ref: docs/specs/SE-465-pinned-install-dependencies.spec.md (S5, AC1-AC3)
# Contrato de scripts/check-pinned-installs.sh: un fixture por patron que debe fallar,
# los casos legitimos de descarga a python (G3) no fallan y los positivos simetricos si.
# CHECKER se puede sobrescribir para demostrar que los tests fallan sin el checker.

CHECKER="${CHECKER:-scripts/check-pinned-installs.sh}"
SHA="sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"

setup() {
  R="$(mktemp -d)"
  mkdir -p "$R/.github/workflows"
}
teardown() { chmod -R u+rwx "$R" 2>/dev/null || true; rm -rf "$R"; }

mk() { mkdir -p "$R/$(dirname "$1")"; printf '%s\n' "$2" > "$R/$1"; }
check() { run bash "$CHECKER" --root "$R" --no-exceptions; }

# ---------------------------------------------------------------- FROM (G1)
@test "FROM python:3.11-slim falla con fichero y linea" {
  mk Dockerfile $'# base\nFROM python:3.11-slim'
  check
  [ "$status" -eq 1 ]
  [[ "$output" == *"Dockerfile:2: FROM_UNPINNED: FROM python:3.11-slim"* ]]
}
@test "FROM con digest no falla" {
  mk Dockerfile "FROM python:3.11-slim@$SHA"
  check
  [ "$status" -eq 0 ]
}
@test "FROM con digest corto o malformado falla" {
  mk Dockerfile "FROM python:3.11-slim@sha256:abc123"
  check
  [ "$status" -eq 1 ]
  [[ "$output" == *"FROM_UNPINNED"* ]]
}
@test "FROM scratch y alias de una etapa previa no fallan; la etapa sin digest si" {
  mk Dockerfile "FROM node:22@$SHA AS build
FROM build AS test
FROM scratch
FROM alpine:3"
  check
  [ "$status" -eq 1 ]
  [[ "$output" == *"Dockerfile:4: FROM_UNPINNED"* ]]
  [[ "$output" != *"Dockerfile:2"* ]]
  [[ "$output" != *"Dockerfile:3"* ]]
}
@test "FROM con variable de ARG no se puede clasificar: falla (fail-closed)" {
  mk Dockerfile $'ARG BASE=python\nFROM ${BASE}'
  check
  [ "$status" -eq 1 ]
  [[ "$output" == *"Dockerfile:2: FROM_UNPINNED"* ]]
}
@test "FROM en un .sh (SQL, Modelfile) no es una imagen y no falla" {
  mk q.sh $'#!/bin/bash\nFROM api_keys'
  check
  [ "$status" -eq 0 ]
}
@test "Dockerfile.base en subcarpeta tambien se analiza" {
  mk containment/Dockerfile.base "FROM node:22-alpine"
  check
  [ "$status" -eq 1 ]
  [[ "$output" == *"containment/Dockerfile.base:1: FROM_UNPINNED"* ]]
}

# ------------------------------------------------- instalador remoto (G2)
@test "curl -fsSL x | sh falla con fichero y linea" {
  mk i.sh $'#!/bin/bash\nset -e\ncurl -fsSL https://example.test/install.sh | sh'
  check
  [ "$status" -eq 1 ]
  [[ "$output" == *"i.sh:3: PIPE_SHELL: curl -fsSL https://example.test/install.sh | sh"* ]]
}
@test "curl | bash, wget | sudo bash y bash - en un RUN fallan" {
  mk a.sh "curl -fsSL https://example.test/a | bash"
  mk b.sh "wget -qO- https://example.test/b | sudo bash"
  mk Dockerfile "FROM x@$SHA
RUN curl -fsSL https://example.test/c | bash - && echo ok"
  check
  [ "$status" -eq 1 ]
  [[ "$output" == *"a.sh:1: PIPE_SHELL"* ]]
  [[ "$output" == *"b.sh:1: PIPE_SHELL"* ]]
  [[ "$output" == *"Dockerfile:2: PIPE_SHELL"* ]]
}
@test "bash <(curl ...) y sh -c \"\$(curl ...)\" fallan" {
  mk a.sh 'bash <(curl -fsSL https://example.test/a)'
  mk b.sh 'sh -c "$(curl -fsSL https://example.test/b)"'
  check
  [ "$status" -eq 1 ]
  [[ "$output" == *"a.sh:1: PIPE_SHELL"* ]]
  [[ "$output" == *"b.sh:1: PIPE_SHELL"* ]]
}
@test "instalador entre comillas de run \"...\" y con variables de entorno por delante falla" {
  mk a.sh 'run "curl -fsSL https://example.test/a | sh"'
  mk b.sh 'if ! V=1 curl -fsSL https://example.test/b 2>/dev/null | bash >/dev/null 2>&1; then echo x; fi'
  check
  [ "$status" -eq 1 ]
  [[ "$output" == *"a.sh:1: PIPE_SHELL"* ]]
  [[ "$output" == *"b.sh:1: PIPE_SHELL"* ]]
}
@test "descarga canalizada en varias lineas con barra invertida falla en la primera linea" {
  mk a.sh $'echo start\ncurl -fsSL https://example.test/a \\\n  | sh'
  check
  [ "$status" -eq 1 ]
  [[ "$output" == *"a.sh:2: PIPE_SHELL"* ]]
}
@test "curl a fichero y luego sha256sum -c no es canalizado y no falla" {
  mk a.sh $'curl -fsSLo /tmp/x https://example.test/x\necho "h  /tmp/x" | sha256sum -c -\ncurl -s https://example.test/y | tee /tmp/y | wc -l'
  check
  [ "$status" -eq 0 ]
}
@test "descarga canalizada a shell dentro de un comentario, un echo o un patron entre comillas no falla" {
  mk a.sh $'# Usage: curl -fsSL https://example.test/i | bash\necho "  curl -fsSL https://example.test/i | sh"\ngrep -nE \'(curl|wget)[^|]*\\|[[:space:]]*(bash|sh)\' f'
  check
  [ "$status" -eq 0 ]
}

# ------------------------- G3: descarga a python (falsos positivos de Scorecard)
@test "G3: 8 descargas legitimas a python -c literal o -m json.tool no fallan" {
  mk g3a.sh "curl -s https://api.example.test/v1 | python3 -c 'import sys,json; print(json.load(sys.stdin)[\"n\"])'"
  mk g3b.sh 'curl -s https://api.example.test/v1 | python3 -c "import sys,json; print(json.load(sys.stdin)[\"n\"])"'
  mk g3c.sh 'curl -s https://api.example.test/v1 | python3 -m json.tool'
  mk g3d.sh 'curl -s -H "Accept: application/json" https://api.example.test/v1 2>/dev/null | python3 -m json.tool 2>/dev/null || true'
  mk g3e.sh $'curl -s https://api.example.test/v1 \\\n  | python3 -c "import sys,json; print(json.load(sys.stdin))"'
  mk g3f.sh 'N=$(curl -s https://api.example.test/v1 | python3 -c "import sys,json; print(json.load(sys.stdin)[0])")'
  mk g3g.sh 'wget -qO- https://api.example.test/v1 | jq . | python3 -m json.tool'
  mk .github/workflows/g3h.yml $'jobs:\n  j:\n    steps:\n      - run: |\n          curl -s https://api.example.test/v1 | python3 -c "import sys,json; print(json.load(sys.stdin))"'
  check
  echo "$output"
  [ "$status" -eq 0 ]
  [[ "$output" == *"SUMMARY G1=0 G2=0 G4=0 G5=0 total=0"* ]]
}
@test "G3 simetrico: curl x | python3 falla" {
  mk a.sh "curl -s https://example.test/x | python3"
  check
  [ "$status" -eq 1 ]
  [[ "$output" == *"a.sh:1: PIPE_PYTHON: curl -s https://example.test/x | python3"* ]]
}
@test "G3 simetrico: curl x | python3 - falla" {
  mk a.sh "curl -s https://example.test/x | python3 -"
  check
  [ "$status" -eq 1 ]
  [[ "$output" == *"a.sh:1: PIPE_PYTHON"* ]]
}
@test "G3 simetrico: curl x | python3 /dev/stdin falla" {
  mk a.sh "curl -s https://example.test/x | python3 /dev/stdin"
  check
  [ "$status" -eq 1 ]
  [[ "$output" == *"a.sh:1: PIPE_PYTHON"* ]]
}
@test "G3 limite: -c con variable, -m distinto de json.tool, python sin version y sudo python fallan" {
  mk a.sh 'curl -s https://example.test/x | python3 -c "$CODE"'
  mk b.sh 'curl -s https://example.test/x | python3 -m http.server'
  mk c.sh 'curl -s https://example.test/x | python -c "$(cat /tmp/p)"'
  mk d.sh 'wget -qO- https://example.test/x | sudo python3 -'
  check
  [ "$status" -eq 1 ]
  [[ "$output" == *"a.sh:1: PIPE_PYTHON"* ]]
  [[ "$output" == *"b.sh:1: PIPE_PYTHON"* ]]
  [[ "$output" == *"c.sh:1: PIPE_PYTHON"* ]]
  [[ "$output" == *"d.sh:1: PIPE_PYTHON"* ]]
}
@test "G3: python - sin descarga delante no se reporta" {
  mk a.sh 'echo "{}" | python3 -'
  check
  [ "$status" -eq 0 ]
}

# ------------------------------------------------------------- npm (G4)
@test "npm install sin -g falla (debe ser npm ci)" {
  mk a.sh $'cd x\nnpm install --silent'
  check
  [ "$status" -eq 1 ]
  [[ "$output" == *"a.sh:2: NPM_INSTALL: npm install --silent"* ]]
}
@test "npm ci, comentarios y echo con npm install no fallan" {
  mk a.sh $'npm ci --ignore-scripts\n# npm install foo\necho "run npm install"'
  mk .github/workflows/c.yml $'jobs:\n  j:\n    steps:\n      - run: npm ci --no-audit'
  check
  [ "$status" -eq 0 ]
}
@test "npm install -g foo (sin version) falla" {
  mk a.sh "npm install -g foo"
  check
  [ "$status" -eq 1 ]
  [[ "$output" == *"a.sh:1: NPM_G_UNPINNED: npm install -g foo"* ]]
}
@test "npm install -g con version exacta, con scope, o npm i --global no fallan" {
  mk a.sh $'npm install -g foo@1.2.3\nnpm i -g @scope/bar@10.0.1-beta.2\nnpm install --global baz@0.0.1 --silent'
  check
  [ "$status" -eq 0 ]
}
@test "npm install -g con @latest, rango, variable o sin paquete falla (fail-closed)" {
  mk a.sh $'npm install -g foo@latest\nnpm install -g foo@^1.2.3\nnpm install -g "$PKG"\nnpm install -g'
  check
  [ "$status" -eq 1 ]
  for n in 1 2 3 4; do [[ "$output" == *"a.sh:$n: NPM_G_UNPINNED"* ]]; done
}
@test "npm install en subshell y tras || se detecta; dos en una linea dan dos hallazgos" {
  mk a.sh $'(cd "$D" && npm install --silent 2>/dev/null) && ok\nnpm install --legacy-peer-deps 2>/dev/null || npm install'
  check
  [ "$status" -eq 1 ]
  [[ "$output" == *"a.sh:1: NPM_INSTALL"* ]]
  [ "$(grep -c 'a.sh:2: NPM_INSTALL' <<<"$output")" -eq 2 ]
}
@test "npm install en un RUN de Dockerfile y en run: de un workflow se detecta" {
  mk Dockerfile "FROM x@$SHA
RUN npm install -g @anthropic-ai/claude-code"
  mk .github/workflows/w.yml $'jobs:\n  j:\n    steps:\n      - name: n\n        run: npm install --prefix .opencode'
  check
  [ "$status" -eq 1 ]
  [[ "$output" == *"Dockerfile:2: NPM_G_UNPINNED"* ]]
  [[ "$output" == *".github/workflows/w.yml:5: NPM_INSTALL"* ]]
}

# -------------------------------------------------------------- pip (G5)
@test "pip install bar sin --require-hashes falla" {
  mk a.sh $'echo x\npip install bar'
  check
  [ "$status" -eq 1 ]
  [[ "$output" == *"a.sh:2: PIP_NO_HASHES: pip install bar"* ]]
}
@test "pip3, python -m pip, \$PYTHON -m pip, uv pip y venv/bin/pip sin hashes fallan" {
  mk a.sh $'pip3 install a\npython3 -m pip install b\n"$PYTHON" -m pip install c\nuv pip install d\n.venv/bin/pip install e'
  check
  [ "$status" -eq 1 ]
  for n in 1 2 3 4 5; do [[ "$output" == *"a.sh:$n: PIP_NO_HASHES"* ]]; done
}
@test "pip install --require-hashes -r lock no falla, tampoco en varias lineas" {
  mk a.sh $'pip install --require-hashes --only-binary=:all: -r l.txt\npip3 install \\\n  --require-hashes -r l.txt'
  check
  [ "$status" -eq 0 ]
}
@test "pip install en un workflow y en un RUN falla; en un echo no" {
  mk .github/workflows/w.yaml $'jobs:\n  j:\n    steps:\n      - run: pip install pytest 2>/dev/null || true'
  mk Dockerfile "FROM x@$SHA
RUN pip install --no-cache-dir -r requirements.txt"
  mk e.sh 'echo "  pip install bertopic"'
  check
  [ "$status" -eq 1 ]
  [[ "$output" == *".github/workflows/w.yaml:4: PIP_NO_HASHES"* ]]
  [[ "$output" == *"Dockerfile:2: PIP_NO_HASHES"* ]]
  [[ "$output" != *"e.sh"* ]]
}

# ------------------------------------------ recuento por grupo y alcance
@test "recuento por grupo: 5 + 4 + 12 + 5 hallazgos dan G1=5 G2=4 G4=12 G5=5 total=26" {
  for i in 1 2 3 4 5; do mk "d$i/Dockerfile" "FROM img$i:tag"; done
  mk g2.sh $'curl -fsSL https://example.test/a | sh\ncurl -fsSL https://example.test/b | bash\nwget -qO- https://example.test/c | sh\nbash <(curl -fsSL https://example.test/d)'
  mk g4.sh $'npm install\nnpm install --silent\nnpm install --no-audit\nnpm install --prefix a\nnpm install --prefix b\nnpm install --prefix c\nnpm install --prefix d\nnpm install --prefix e\nnpm install -g a\nnpm install -g b@latest\nnpm install -g c\nnpm install -g d'
  mk g5.sh $'pip install a\npip install b\npip3 install c\npython3 -m pip install d\npip install -r r.txt'
  check
  [ "$status" -eq 1 ]
  [[ "$output" == *"SUMMARY G1=5 G2=4 G4=12 G5=5 total=26 "* ]]
}
@test "solo se analizan *.sh, Dockerfile* y .github/workflows: otros ficheros no cuentan" {
  mk README.md "npm install -g foo"
  mk docs/x.txt "npm install -g foo"
  mk src/app.py "pip install bar"
  mk .github/other/x.yml "pip install bar"
  mk ok.sh "true"
  check
  [ "$status" -eq 0 ]
}
@test "node_modules y .git se ignoran fuera de un repo git" {
  mk node_modules/p/i.sh "npm install -g foo"
  mk .git/hooks/h.sh "npm install -g foo"
  mk ok.sh "true"
  check
  [ "$status" -eq 0 ]
}
@test "repo real: el cliente curl de http-query (python -m json.tool) no se reporta" {
  run bash "$CHECKER" --no-exceptions
  [ "$status" -eq 1 ] || [ "$status" -eq 0 ]
  [[ "$output" != *"examples/http-query/client-curl.sh"* ]]
  [[ "$output" == *"SUMMARY "* ]]
}

# --------------------------------------------------- fail-closed y errores
@test "fichero ilegible: sale 2, no PASS" {
  [ "$(id -u)" -ne 0 ] || skip "root lee todo"
  mk a.sh "true"
  chmod 000 "$R/a.sh"
  check
  [ "$status" -eq 2 ]
  [[ "$output" == *"ilegible"* ]]
}
@test "root inexistente: sale 2" {
  run bash "$CHECKER" --root "$R/no-existe" --no-exceptions
  [ "$status" -eq 2 ]
}
@test "ningun fichero que analizar: sale 2, no PASS vacio" {
  mk README.md "hola"
  check
  [ "$status" -eq 2 ]
  [[ "$output" == *"ningún fichero"* ]]
}
@test "opcion desconocida: sale 2" {
  run bash "$CHECKER" --root "$R" --nope
  [ "$status" -eq 2 ]
}
@test "fichero de excepciones inexistente: sale 2" {
  mk a.sh "true"
  run bash "$CHECKER" --root "$R" --exceptions "$R/no-existe.txt"
  [ "$status" -eq 2 ]
}

# ------------------------------------------------------------ excepciones
@test "excepcion con motivo suprime solo la orden indicada" {
  mk a.sh $'npm install --silent\nnpm install --other'
  printf '%s\n' '# comentario' '' 'a.sh :: NPM_INSTALL :: --silent :: pendiente D1: lock sin decidir' > "$R/exc.txt"
  run bash "$CHECKER" --root "$R" --exceptions "$R/exc.txt"
  [ "$status" -eq 1 ]
  [[ "$output" != *"a.sh:1:"* ]]
  [[ "$output" == *"a.sh:2: NPM_INSTALL"* ]]
  [[ "$output" == *"excepciones_aplicadas=1"* ]]
}
@test "excepcion de otro KIND o de otro fichero no suprime" {
  mk a.sh "npm install --silent"
  printf '%s\n' 'a.sh :: PIP_NO_HASHES :: --silent :: motivo' 'b.sh :: NPM_INSTALL :: --silent :: motivo' > "$R/exc.txt"
  run bash "$CHECKER" --root "$R" --exceptions "$R/exc.txt"
  [ "$status" -eq 1 ]
  [[ "$output" == *"a.sh:1: NPM_INSTALL"* ]]
}
@test "excepcion con * cubre todo ese KIND en ese fichero y deja pasar (rc 0)" {
  mk a.sh $'npm install\nnpm install --x'
  printf '%s\n' 'a.sh :: NPM_INSTALL :: * :: repo externo clonado' > "$R/exc.txt"
  run bash "$CHECKER" --root "$R" --exceptions "$R/exc.txt"
  [ "$status" -eq 0 ]
}
@test "excepcion sin motivo es error (2), aunque el motivo sea solo espacios" {
  mk a.sh "npm install"
  printf '%s\n' 'a.sh :: NPM_INSTALL :: npm install :: ' > "$R/exc.txt"
  run bash "$CHECKER" --root "$R" --exceptions "$R/exc.txt"
  [ "$status" -eq 2 ]
  [[ "$output" == *"sin motivo"* ]]
}
@test "excepcion mal formada o con KIND desconocido es error (2)" {
  mk a.sh "npm install"
  printf '%s\n' 'a.sh :: NPM_INSTALL :: npm install' > "$R/exc.txt"
  run bash "$CHECKER" --root "$R" --exceptions "$R/exc.txt"
  [ "$status" -eq 2 ]
  printf '%s\n' 'a.sh :: INVENTADO :: x :: motivo' > "$R/exc2.txt"
  run bash "$CHECKER" --root "$R" --exceptions "$R/exc2.txt"
  [ "$status" -eq 2 ]
}
@test "el fichero de excepciones del repo es valido (el checker no sale 2) y marca D1" {
  run bash "$CHECKER"
  [ "$status" -ne 2 ]
  grep -q 'pendiente D1' scripts/pinned-installs-exceptions.txt
}
