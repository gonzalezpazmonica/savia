#!/usr/bin/env bats
# nightly: serial (recorre el repo real con check-pinned-installs.sh)
# Ref: docs/evidence/graduacion-s27/SE-442-triaje-alertas.md (alertas reales medias)
# Ref: docs/specs/SE-465-pinned-install-dependencies.spec.md (S1-S4)
# Un test por alerta de code scanning clasificada como real: reproduce el
# defecto en el árbol y pasa cuando el arreglo está aplicado.

ROOT="$BATS_TEST_DIRNAME/.."
CHECKER="$ROOT/scripts/check-pinned-installs.sh"
LIB="$ROOT/scripts/lib/verified-installer.sh"

setup_file() {
  # Una sola pasada del checker para todas las aserciones estructurales.
  export FINDINGS="$BATS_FILE_TMPDIR/findings.txt"
  bash "$CHECKER" --root "$ROOT" --no-exceptions > "$FINDINGS" 2>&1 || true
}

setup() {
  T="$(mktemp -d)"
}
teardown() { rm -rf "$T"; }

no_finding() { # ruta KIND
  ! grep -q "^$1:[0-9]*: $2:" "$FINDINGS"
}

# ------------------------------------------------------------- #71 (G1)
@test "#71 containment/Dockerfile.base fija la imagen base por digest" {
  no_finding containment/Dockerfile.base FROM_UNPINNED
  grep -Eq '^FROM node:22-alpine@sha256:[0-9a-f]{64}$' "$ROOT/containment/Dockerfile.base"
}

# -------------------------------------------------- #79, #81 (G4 a)
@test "#81 install.sh instala las dependencias de scripts/ con npm ci contra el lock" {
  no_finding install.sh NPM_INSTALL
  grep -q 'npm ci' "$ROOT/install.sh"
  git -C "$ROOT" ls-files --error-unmatch scripts/package-lock.json >/dev/null
}
@test "#79 .opencode/install.sh instala las dependencias de scripts/ con npm ci" {
  no_finding .opencode/install.sh NPM_INSTALL
  grep -q 'npm ci' "$ROOT/.opencode/install.sh"
}

# ------------------------------------------------- #80, #95 (G4 c)
@test "#80 install.sh instala OpenCode con versión exacta, la misma que opencode-install.sh" {
  no_finding install.sh NPM_G_UNPINNED
  v1="$(grep -E '^DEFAULT_V1=' "$ROOT/scripts/opencode-install.sh" | cut -d'"' -f2)"
  v2="$(grep -E '^DEFAULT_V2=' "$ROOT/scripts/opencode-install.sh" | cut -d'"' -f2)"
  grep -q "OC_NPM_VER=\"$v1\"" "$ROOT/install.sh"
  grep -q "OC_NPM_VER=\"$v2\"" "$ROOT/install.sh"
  grep -q "npm install -g opencode-ai@$v1" "$ROOT/install.sh"
  grep -q "npm install -g @opencode/cli@$v2" "$ROOT/install.sh"
}
@test "#95 savia-travel-ops.sh instala Claude Code con versión exacta" {
  no_finding scripts/savia-travel-ops.sh NPM_G_UNPINNED
  grep -Eq 'npm install -g "?@anthropic-ai/claude-code@[0-9]+\.[0-9]+\.[0-9]+' "$ROOT/scripts/savia-travel-ops.sh"
}

# ---------------------------------------------------------------- #83
@test "#83 savia-vaults se instala desde su fuente con lock, no del registro sin versión" {
  no_finding projects/savia-vaults/scripts/install.sh NPM_G_UNPINNED
  no_finding projects/savia-vaults/scripts/install.sh NPM_INSTALL
  grep -q 'npm ci' "$ROOT/projects/savia-vaults/scripts/install.sh"
  grep -q 'npm link' "$ROOT/projects/savia-vaults/scripts/install.sh"
}
@test "#83 savia-vaults/install.sh define SCRIPT_DIR (bajo set -u no aborta)" {
  grep -Eq '^SCRIPT_DIR=' "$ROOT/projects/savia-vaults/scripts/install.sh"
}

# -------------------------------------------- #84, #89, #93 (G2)
@test "#84 emergency-setup.sh no canaliza un instalador remoto a sh" {
  no_finding scripts/emergency-setup.sh PIPE_SHELL
  grep -q 'verified-installer.sh' "$ROOT/scripts/emergency-setup.sh"
}
@test "#93 savia-shield-setup.sh no canaliza un instalador remoto a sh" {
  no_finding scripts/savia-shield-setup.sh PIPE_SHELL
  grep -q 'verified-installer.sh' "$ROOT/scripts/savia-shield-setup.sh"
}
@test "#93 (mismo defecto) setup-savia-dual.sh no canaliza un instalador remoto a sh" {
  no_finding scripts/setup-savia-dual.sh PIPE_SHELL
}
@test "#89 opencode-install.sh v1 no ejecuta opencode.ai/install: usa npm con versión" {
  no_finding scripts/opencode-install.sh PIPE_SHELL
  ! grep -q 'opencode.ai/install' "$ROOT/scripts/opencode-install.sh"
  run env SAVIA_HOME="$T/h" bash "$ROOT/scripts/opencode-install.sh" --flavor v1 --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"npm install opencode-ai@1.19.3"* ]]
}

# instalador verificado: comportamiento con curl simulado
mk_curl() { # contenido del instalador servido
  mkdir -p "$T/bin"
  printf '%s\n' "$1" > "$T/served.sh"
  cat > "$T/bin/curl" <<EOF
#!/usr/bin/env bash
out=""
while [ \$# -gt 0 ]; do case "\$1" in -o) out="\$2"; shift 2 ;; *) shift ;; esac; done
[ -n "\$out" ] || exit 99
cp "$T/served.sh" "\$out"
EOF
  chmod +x "$T/bin/curl"
}
@test "#84/#93 el instalador con hash distinto al fijado no se ejecuta" {
  mk_curl "touch '$T/EJECUTADO'"
  run env PATH="$T/bin:$PATH" bash -c "source '$LIB'; savia_run_verified_installer https://example.invalid/i.sh $(printf '0%.0s' {1..64})"
  [ "$status" -ne 0 ]
  [ ! -e "$T/EJECUTADO" ]
  [[ "$output" == *"SHA-256"* ]]
}
@test "#84/#93 el instalador con el hash fijado se ejecuta y recibe sus variables" {
  mk_curl "echo \"v=\$OLLAMA_VERSION\" > '$T/EJECUTADO'"
  sha="$(sha256sum "$T/served.sh" | cut -d' ' -f1)"
  run env PATH="$T/bin:$PATH" bash -c "source '$LIB'; savia_run_verified_installer https://example.invalid/i.sh $sha OLLAMA_VERSION=9.9.9"
  [ "$status" -eq 0 ]
  [ "$(cat "$T/EJECUTADO")" = "v=9.9.9" ]
}
@test "#84/#93 un hash fijado malformado es error, no se descarga nada" {
  mk_curl "touch '$T/EJECUTADO'"
  run env PATH="$T/bin:$PATH" bash -c "source '$LIB'; savia_run_verified_installer https://example.invalid/i.sh abc"
  [ "$status" -ne 0 ]
  [ ! -e "$T/EJECUTADO" ]
}
@test "#84/#93 ollama fijado: versión exacta, URL de una etiqueta y hash de 64 hex" {
  run bash -c "source '$LIB'; echo \"\$OLLAMA_PINNED_VERSION|\$OLLAMA_INSTALLER_URL|\$OLLAMA_INSTALLER_SHA256\""
  [ "$status" -eq 0 ]
  IFS='|' read -r ver url sha <<<"$output"
  [[ "$ver" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
  [[ "$url" == "https://raw.githubusercontent.com/ollama/ollama/v$ver/scripts/install.sh" ]]
  [[ "$sha" =~ ^[0-9a-f]{64}$ ]]
}

# ------------------------------------------------------------ #94 (G5)
@test "#94 savia-shield-setup.sh instala Presidio con --require-hashes contra un lock" {
  no_finding scripts/savia-shield-setup.sh PIP_NO_HASHES
  lock="$ROOT/scripts/requirements/shield-presidio.lock.txt"
  [ -f "$lock" ]
  grep -Eq '^presidio-analyzer==' "$lock"
  grep -Eq '^presidio-anonymizer==' "$lock"
  # cada requisito lleva al menos un hash
  ! awk '/^[a-z0-9]/ && !/\\$/' "$lock" | grep -q .
}

# ---------------------------------------------------------------- #59
@test "#59 SECURITY.md enlaza el reporte privado de vulnerabilidades" {
  grep -q 'https://github.com/gonzalezpazmonica/savia/security/advisories/new' "$ROOT/SECURITY.md"
}
