#!/usr/bin/env bats
# SE-453 S6 (HOLD de la revisión de la PR #1672) — la lista SH01 no rebaja por prefijo ni por caja.
# Antes del arreglo había sufijos abiertos (`(HTTPS?|REST|API|SDK)[A-Za-z0-9]*`, `${_I}`, `${_D}`) y
# la comparación era sin mayúsculas (grep -ixE): apellidos como «Restrepo» o «Apiano» pasaban por código.
# Unitario sobre sh01_all_code_like (0 = se rebaja, 1 = bloquea) y dos casos por el hook real.
# Nombres y datos sintéticos o apellidos corrientes, sin datos de personas reales.

LIB="scripts/lib/sh01-code-allowlist.sh"

setup() {
  cd "$BATS_TEST_DIRNAME/.."
  # shellcheck source=/dev/null
  source "$LIB"
}

# una <tipo> <texto> → JSON del daemon con una sola entidad
una() { jq -nc --arg t "$1" --arg x "$2" '{verdict:"BLOCK",entities:[{type:$t,text:$x}]}'; }

# no_rebaja <tipo> <texto>... → falla si alguna entidad se rebaja
no_rebaja() {
  local tipo="$1" t; shift
  for t in "$@"; do
    if sh01_all_code_like "$(una "$tipo" "$t")"; then
      echo "se rebajó: $tipo «$t»"; return 1
    fi
  done
}

# rebaja <texto>... → falla si algún token de código legítimo deja de rebajarse
rebaja() {
  local t
  for t in "$@"; do
    sh01_all_code_like "$(una ORG "$t")" || { echo "no se rebajó: «$t»"; return 1; }
  done
}

# ── Casos de la revisora: deben bloquear ───────────────────────────────────
@test "siglas con sufijo abierto: Restrepo, Resti, Apiano, Sdkova, Httpson bloquean" {
  no_rebaja PERSON "Restrepo" "Resti" "Apiano" "Sdkova" "Httpson"
}
@test "palabra clave + apellido: From Garcia, Return Lopez bloquean" {
  no_rebaja PERSON "From Garcia" "Return Lopez" "from Garcia" "return Lopez" "import Garcia"
}
@test "caja: Terror y MariaUrl bloquean" {
  no_rebaja PERSON "Terror" "MariaUrl"
}
@test "espacio de nombres + apellido: Amazon.Garcia, System.Lopez, Azure.Restrepo bloquean" {
  no_rebaja PERSON "Amazon.Garcia" "System.Lopez" "Azure.Restrepo" "Microsoft.Perez"
}
@test "clave=número fuera de la lista cerrada: dni, pin, cvv, nif bloquean" {
  no_rebaja CARDINAL "dni=12345" "pin=1234" "cvv=123" "nif=12345"
}
@test "minúsculas o mayúsculas de una sigla no son la sigla: http, api, Api, Json no se cuelan con sufijo" {
  no_rebaja PERSON "httpson" "apiano" "Apiano" "restrepo" "RESTREPO"
}
@test "prefijo de navegador o herramienta + apellido bloquea" {
  no_rebaja PERSON "Chromecki" "Dedupova" "githubgarcia" "page.Garcia" "Hierarchygarcia"
}
@test "excepción con mayúscula inicial no es Error: Mirror es literal, Herror no" {
  no_rebaja PERSON "Herror" "Lerror"
}
@test "control: un apellido solo bloquea" {
  no_rebaja PERSON "Garcia"
}

# ── Positivos: los términos de código legítimos siguen rebajándose ─────────
@test "positivo: siglas solas y con sufijo técnico" {
  rebaja "HTTP" "HTTPS" "API" "REST" "SDK" "HTTPError" "HTTPSConnection" "APIKey" "RESTClient" "SDKVersion"
}
@test "positivo: palabras clave + identificador de código" {
  rebaja "from os" "import json" "from os.path" "return self" "def main" "await fetch_data" \
         "class Foo" "throw TypeError" "catch HTTPError" "import urllib.parse"
}
@test "positivo: espacios de nombres conocidos" {
  rebaja "Microsoft" "Microsoft.VSTS.Scheduling.Effort" "Microsoft.VSTS.Common.Priority" \
         "System.AssignedTo" "System.IterationPath" "System.State" "Azure.Identity" "Google" "Amazon"
}
@test "positivo: clave=número de la lista cerrada y literales" {
  rebaja "timeout=5" "retries=3" "default=10" "port=8080" "debug=True" "verbose=False" "max_retries=5"
}
@test "positivo: excepciones, Url, navegadores y herramientas" {
  rebaja "ValueError" "RuntimeError" "UserWarning" "Exception" "BaseUrl" "tenantUrl" "DedupKey" \
         "Chrome" "Chromium" "ChromeDriver" "page.goto" "ws.send" "github" "github.com" "GitHub" \
         "websocket" "Hierarchy" "HierarchyLevel"
}

# ── En un proceso aparte, como lo carga el hook ──
@test "proceso aparte: PERSON Restrepo bloquea" {
  run bash -c 'source "$1"; sh01_all_code_like "$2"' _ "$LIB" "$(una PERSON Restrepo)"
  [ "$status" -eq 1 ]
}
