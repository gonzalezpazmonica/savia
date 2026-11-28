#!/usr/bin/env bats
# Ref: PR #1676 (revisión, P1-1) — Check 3 de scripts/confidentiality-scan.sh.
# La regex de email tomaba «lib@1.0.0.js» (URL de CDN con versión, en una guía de terceros) por un email
# real y bloqueaba la PR. Arreglo causal: un dominio que empieza por dos o más etiquetas numéricas (forma
# de versión x.y…, también react@18.2.0.min.js) no es un email. Los emails reales, incluidos los de dominio
# con una sola etiqueta numérica (p. ej. 163.com o a@1.servicio.io), siguen detectándose.

REPO="$BATS_TEST_DIRNAME/.."
SCRIPT="scripts/confidentiality-scan.sh"

setup() {
  T="$BATS_TEST_TMPDIR"
  export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
  R="$T/s"; mkdir -p "$R/scripts" "$R/.claude/hooks/lib"
  cp "$REPO/$SCRIPT" "$R/scripts/"
  cp "$REPO/.claude/hooks/lib/gate-result.sh" "$R/.claude/hooks/lib/"
  printf '#!/usr/bin/env bash\necho termino-vetado-xyz\n' > "$R/scripts/generate-blocklist.sh"
  git init -q -b main "$R"; G add -A; G commit -qm base
}

G() { git -C "$R" -c commit.gpgsign=false "$@"; }

# scan_line <texto> — escanea (--staged) un fichero nuevo con esa única línea.
scan_line() {
  G reset -q
  printf '%s\n' "$1" > "$R/doc.md"; G add -f -- doc.md
  run bash "$R/scripts/confidentiality-scan.sh" --staged
}

@test "email negativo: una URL de CDN con versión (lib@1.0.0.js) no es un email" {
  scan_line '<script src="https://cdn.example.com/lib@1.0.0.js" integrity="sha384-x"></script>'
  [[ "$output" != *"Real emails found"* ]]
  [ "$status" -eq 0 ]
  [[ "$output" == *'"result":"clean"'* ]]
}

@test "email negativo: paquetes con versión (pkg@2.3.4, react@18.2.0.min.js, x@1.2.mjs) no son emails" {
  local s
  for s in 'npm i pkg@2.3.4' 'cdn/react@18.2.0.min.js' 'import x from "x@1.2.mjs"' 'lib@10.20.30.js'; do
    scan_line "$s"
    [[ "$output" != *"Real emails found"* ]] || { echo "falso positivo: $s"; false; }
    [ "$status" -eq 0 ]
  done
}

@test "email positivo: los emails reales se siguen detectando" {
  local s
  for s in 'escribe a maria.lopez@acmecorp.es' 'jefe@mail.empresa-real.com' 'x+tag@163.com' \
           'soporte@v2.servicio.io' 'a@1.servicio.io' 'ver lib@1.0.0.js o a juan@realcorp.net'; do
    scan_line "$s"
    [ "$status" -eq 1 ] || { echo "no detectado: $s"; false; }
    [[ "$output" == *"Real emails found"* ]]
    [[ "$output" == *'"result":"findings"'* ]]
  done
}

@test "email positivo: en una línea mixta se informa el email real y no la versión" {
  scan_line 'ver lib@1.0.0.js o a juan@realcorp.net'
  [ "$status" -eq 1 ]
  [[ "$output" == *"FAIL juan@realcorp.net"* ]]
  [[ "$output" != *"FAIL lib@1.0.0.js"* ]]
}
