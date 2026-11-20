#!/usr/bin/env bats
# BATS tests for projects/savia-vaults/scripts/index-docs.sh y scripts/vaults-freshness.sh
# Causa del parón de la cúpula savia-docs (agosto 2026): index-docs.sh se ejecutó una vez a
# mano, copiaba también ficheros sin versionar, no borraba lo retirado, `vaults dome index` le
# pasaba la cúpula como raíz del repo y vaults-freshness.sh fallaba con «variable sin asignar»
# y comparaba contra el último commit del repo entero, no contra docs/.
# Ref: docs/rules/domain/context-placement-confirmation.md (a savia-docs solo va lo público)

SYNC="projects/savia-vaults/scripts/index-docs.sh"
FRESH="scripts/vaults-freshness.sh"
VAULTS="projects/savia-vaults/scripts/vaults"

setup() {
  cd "$BATS_TEST_DIRNAME/.."
  REPO="$(pwd)"
  T="$(mktemp -d -t vds.XXXXXX)"
  SRC="$T/src"; VAULT="$T/vault"
  mkdir -p "$SRC/docs/specs" "$VAULT"
  git -C "$SRC" init -q -b main
  git -C "$SRC" config user.email t@local; git -C "$SRC" config user.name t
  echo "regla publica" > "$SRC/docs/a.md"
  echo "spec uno" > "$SRC/docs/specs/SE-1.spec.md"
  echo "claude" > "$SRC/CLAUDE.md"
  echo "docs/ignorado.md" > "$SRC/.gitignore"
  git -C "$SRC" add -A
  GIT_COMMITTER_DATE="2026-01-01T00:00:00" GIT_AUTHOR_DATE="2026-01-01T00:00:00" git -C "$SRC" commit -qm "init"
  git -C "$VAULT" init -q -b master
  git -C "$VAULT" config user.email v@local; git -C "$VAULT" config user.name v
  mkdir -p "$VAULT/navigation"; echo "nota a mano" > "$VAULT/navigation/n.md"
  git -C "$VAULT" add -A; git -C "$VAULT" commit -qm "nota a mano"
  export SAVIA_ROOT="$SRC"
  export HOME="$T/home"; mkdir -p "$HOME"
}

teardown() { [[ -n "${T:-}" ]] && rm -rf "$T"; cd /; }

sync_vault() { bash "$SYNC" "$SRC" "$VAULT" "$@"; }

# commit en SRC tocando $1 con fecha $2
src_commit() {
  mkdir -p "$(dirname "$SRC/$1")"; echo "$RANDOM" >> "$SRC/$1"
  git -C "$SRC" add -A
  GIT_COMMITTER_DATE="$2" GIT_AUTHOR_DATE="$2" git -C "$SRC" commit -qm "cambio $1"
}

# ── Sincronización ───────────────────────────────────────────────────────────

@test "sync: copia lo versionado, deja Source-Commit y respeta las notas a mano" {
  run sync_vault
  [ "$status" -eq 0 ]
  [ -f "$VAULT/docs/a.md" ]
  [ -f "$VAULT/docs/specs/SE-1.spec.md" ]
  [ -f "$VAULT/root/CLAUDE.md" ]
  [ -f "$VAULT/navigation/n.md" ]
  git -C "$VAULT" log -1 --format=%B | grep -q "^Source-Commit: $(git -C "$SRC" rev-parse HEAD)$"
  git -C "$VAULT" log -1 --format=%s | grep -q "^index: Savia documentation snapshot"
}

@test "sync negativo: un fichero sin versionar o ignorado NO llega a la cúpula" {
  echo "borrador privado" > "$SRC/docs/borrador-sin-versionar.md"
  echo "ignorado" > "$SRC/docs/ignorado.md"
  run sync_vault
  [ "$status" -eq 0 ]
  [ -f "$VAULT/docs/a.md" ]
  [ ! -e "$VAULT/docs/borrador-sin-versionar.md" ]
  [ ! -e "$VAULT/docs/ignorado.md" ]
}

@test "sync: lo retirado del origen se retira de la cúpula (docs/ y root/) sin tocar lo demás" {
  sync_vault
  git -C "$SRC" rm -q docs/a.md CLAUDE.md
  git -C "$SRC" commit -qm "retira"
  run sync_vault
  [ "$status" -eq 0 ]
  [ ! -e "$VAULT/docs/a.md" ]
  [ ! -e "$VAULT/root/CLAUDE.md" ]
  [ -f "$VAULT/docs/specs/SE-1.spec.md" ]
  [ -f "$VAULT/navigation/n.md" ]
}

@test "sync: idempotente, la segunda pasada sin cambios no crea commit" {
  sync_vault
  local n1; n1=$(git -C "$VAULT" rev-list --count HEAD)
  run sync_vault
  [ "$status" -eq 0 ]
  [ "$(git -C "$VAULT" rev-list --count HEAD)" = "$n1" ]
}

@test "sync --branch: commitea en la rama y deja master y el árbol vivo intactos" {
  local master_before; master_before=$(git -C "$VAULT" rev-parse master)
  run sync_vault --branch agent/docs-test
  [ "$status" -eq 0 ]
  [ "$(git -C "$VAULT" rev-parse master)" = "$master_before" ]
  [ "$(git -C "$VAULT" rev-parse --abbrev-ref HEAD)" = "master" ]
  [ ! -e "$VAULT/docs/a.md" ]
  git -C "$VAULT" show agent/docs-test:docs/a.md | grep -q "regla publica"
  [ "$(git -C "$VAULT" worktree list | wc -l)" -eq 1 ]
}

@test "sync: un destino que no existe como repo se crea sin tocar el repo origen" {
  run bash "$SYNC" "$SRC" "$T/nuevo"
  [ "$status" -eq 0 ]
  [ -f "$T/nuevo/docs/a.md" ]
  [ -z "$(git -C "$SRC" status --porcelain)" ]
}

@test "sync negativo: una edición sin commitear de un fichero versionado NO llega; llega lo del commit" {
  echo "borrador privado sobre doc publico" > "$SRC/docs/a.md"
  echo "nuevo solo staged" > "$SRC/docs/staged.md"; git -C "$SRC" add docs/staged.md
  run sync_vault
  [ "$status" -eq 0 ]
  [ "$(cat "$VAULT/docs/a.md")" = "regla publica" ]
  [ ! -e "$VAULT/docs/staged.md" ]
  git -C "$VAULT" log -1 --format=%B | grep -q "^Source-Commit: $(git -C "$SRC" rev-parse HEAD)$"
}

@test "sync negativo: un symlink versionado NO se sigue (no copia contenido sin versionar)" {
  mkdir -p "$SRC/output"; echo "secreto sin versionar" > "$SRC/output/privado.md"
  echo "output/" >> "$SRC/.gitignore"
  ln -s ../output/privado.md "$SRC/docs/enlace.md"
  git -C "$SRC" add .gitignore docs/enlace.md; git -C "$SRC" commit -qm symlink
  run sync_vault
  [ "$status" -eq 0 ]
  [ ! -e "$VAULT/docs/enlace.md" ]
  run grep -rq "secreto" "$VAULT/docs"
  [ "$status" -eq 1 ]
}

@test "sync: sin documentos raíz versionados (sin root/) igualmente commitea docs/" {
  git -C "$SRC" rm -q CLAUDE.md; git -C "$SRC" commit -qm "sin raiz"
  run bash "$SYNC" "$SRC" "$T/nuevo"
  [ "$status" -eq 0 ]
  [[ "$output" != *"Sin cambios"* ]]
  git -C "$T/nuevo" ls-files --error-unmatch docs/a.md
  git -C "$T/nuevo" log -1 --format=%s | grep -q "^index: Savia documentation snapshot"
}

@test "sync --branch negativo: la rama del árbol vivo se rechaza y no se commitea en ella" {
  local master_before; master_before=$(git -C "$VAULT" rev-parse master)
  run sync_vault --branch master
  [ "$status" -ne 0 ]
  [[ "$output" == *"árbol vivo"* ]]
  [ "$(git -C "$VAULT" rev-parse master)" = "$master_before" ]
}

@test "vaults dome index: sincroniza la cúpula con SAVIA_ROOT, no usa la cúpula como repo" {
  mkdir -p "$T/vroot"; mv "$VAULT" "$T/vroot/savia-docs"
  run env SAVIA_VAULT_ROOT="$T/vroot" bash "$VAULTS" dome index savia-docs
  [ "$status" -eq 0 ]
  [ -f "$T/vroot/savia-docs/docs/a.md" ]
  [ ! -e "$SRC/vaults" ]
}

@test "vaults dome index negativo: otra cúpula o un nombre con traversal se rechazan sin tocar nada" {
  mkdir -p "$T/vroot"; mv "$VAULT" "$T/vroot/cliente-n3"
  mkdir -p "$T/vroot/cliente-n3/docs"; echo "dato n3" > "$T/vroot/cliente-n3/docs/n3.md"
  run env SAVIA_VAULT_ROOT="$T/vroot" bash "$VAULTS" dome index cliente-n3
  [ "$status" -ne 0 ]
  [ -f "$T/vroot/cliente-n3/docs/n3.md" ]
  [ ! -e "$T/vroot/cliente-n3/docs/a.md" ]
  mkdir -p "$T/fuera/docs"; echo "x" > "$T/fuera/docs/x.md"
  run env SAVIA_VAULT_ROOT="$T/vroot" bash "$VAULTS" dome index ../fuera
  [ "$status" -ne 0 ]
  [ -f "$T/fuera/docs/x.md" ]
  [ ! -d "$T/fuera/.git" ]
}

@test "vaults dome index negativo: si la sincronización falla, el comando falla (no da verde)" {
  mkdir -p "$T/vroot"; mv "$VAULT" "$T/vroot/savia-docs"
  mkdir -p "$T/sin-git"
  run env SAVIA_VAULT_ROOT="$T/vroot" SAVIA_ROOT="$T/sin-git" bash "$VAULTS" dome index savia-docs
  [ "$status" -ne 0 ]
  [ ! -e "$T/vroot/savia-docs/docs/a.md" ]
}

# ── Frescura ─────────────────────────────────────────────────────────────────

@test "frescura: ruta inexistente = ABSENT (exit 3) sin error de variable sin asignar" {
  run bash "$FRESH" --path "$T/no-existe"
  [ "$status" -eq 3 ]
  [[ "$output" == *"ABSENT"* ]]
  [[ "$output" != *"unbound"* && "$output" != *"sin asignar"* ]]
}

@test "frescura: directorio sin git = UNKNOWN (exit 2), nunca FRESH" {
  mkdir -p "$T/plano"
  run bash "$FRESH" --path "$T/plano"
  [ "$status" -eq 2 ]
  [[ "$output" == *"UNKNOWN"* ]]
  [[ "$output" != *"unbound"* ]]
}

@test "frescura: cúpula con git pero nunca sincronizada = UNKNOWN (exit 2)" {
  run bash "$FRESH" --path "$VAULT"
  [ "$status" -eq 2 ]
  [[ "$output" == *"UNKNOWN"* ]]
  [[ "$output" == *"index-docs.sh"* ]]
}

@test "frescura: recién sincronizada = FRESH (exit 0)" {
  sync_vault
  run bash "$FRESH" --path "$VAULT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"FRESH"* ]]
}

@test "frescura: docs cambió 10 días después de la sincronización = STALE (exit 1) y dice la orden" {
  sync_vault
  src_commit docs/nueva.md "2026-01-11T00:00:00"
  run bash "$FRESH" --path "$VAULT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"STALE"* ]]
  [[ "$output" == *"10"* ]]
  [[ "$output" == *"index-docs.sh"* ]]
}

@test "frescura negativo: un commit fuera de docs/ NO hace STALE la cúpula" {
  sync_vault
  src_commit scripts/otra-cosa.sh "2026-03-01T00:00:00"
  run bash "$FRESH" --path "$VAULT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"FRESH"* ]]
}

@test "frescura límite: 24 h exactas de atraso no son STALE con --max-hours 24; 25 h sí" {
  sync_vault
  src_commit docs/b.md "2026-01-02T00:00:00"
  run bash "$FRESH" --path "$VAULT" --max-hours 24
  [ "$status" -eq 0 ]
  src_commit docs/c.md "2026-01-02T01:00:00"
  run bash "$FRESH" --path "$VAULT" --max-hours 24
  [ "$status" -eq 1 ]
}

@test "frescura negativo: un Source-Commit que no es un SHA no llega a git como opción" {
  sync_vault
  git -C "$VAULT" commit -q --allow-empty -m "index: Savia documentation snapshot (falso)" \
    -m "Source-Commit: --output=$T/pwned"
  run bash "$FRESH" --path "$VAULT"
  [ ! -e "$T/pwned" ]
  [ "$status" -eq 0 ]
  run bash "$SYNC" "$SRC" "$VAULT"
  [ "$status" -eq 0 ]
  [ ! -e "$T/pwned" ]
}

@test "frescura: resuelve la ruta por SAVIA_VAULTS_DIR cuando no hay --path" {
  mkdir -p "$T/vs"; mv "$VAULT" "$T/vs/savia-docs"
  run env SAVIA_VAULTS_DIR="$T/vs" bash "$FRESH"
  [ "$status" -eq 2 ]
  [[ "$output" == *"$T/vs/savia-docs"* ]]
}

@test "frescura --summary: una sola línea, vacía si FRESH y con la orden si STALE" {
  sync_vault
  run bash "$FRESH" --path "$VAULT" --summary
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  src_commit docs/z.md "2026-02-01T00:00:00"
  run bash "$FRESH" --path "$VAULT" --summary
  [ "$status" -eq 1 ]
  [ "$(echo "$output" | wc -l)" -eq 1 ]
  [[ "$output" == *"savia-docs"* && "$output" == *"index-docs.sh"* ]]
}

@test "frescura: cambio y reversión de docs sin diferencia neta, tras resincronizar, vuelve a FRESH" {
  sync_vault
  echo "extra" > "$SRC/docs/e.md"; git -C "$SRC" add -A
  GIT_COMMITTER_DATE="2026-03-01T00:00:00" GIT_AUTHOR_DATE="2026-03-01T00:00:00" git -C "$SRC" commit -qm add
  git -C "$SRC" rm -q docs/e.md
  GIT_COMMITTER_DATE="2026-03-02T00:00:00" GIT_AUTHOR_DATE="2026-03-02T00:00:00" git -C "$SRC" commit -qm del
  run bash "$FRESH" --path "$VAULT"
  [ "$status" -eq 1 ]
  sync_vault
  run bash "$FRESH" --path "$VAULT"
  [ "$status" -eq 0 ]
}

# ── Punto de llamada: clock-in (validate-ci-local.sh --quick) ────────────────

mk_stale_docs_vault() {
  local v="$T/vaults/savia-docs"; mkdir -p "$v"
  git -C "$v" init -q; git -C "$v" config user.email v@l; git -C "$v" config user.name v
  echo x > "$v/a.md"; git -C "$v" add -A
  GIT_COMMITTER_DATE="$1" GIT_AUTHOR_DATE="$1" git -C "$v" commit -qm "index: Savia documentation snapshot"
  export SAVIA_VAULTS_DIR="$T/vaults"
}

@test "clock-in: validate-ci-local --quick avisa (WARN, sin bloquear) si la cúpula va atrasada" {
  unset SAVIA_ROOT
  export SAVIA_VAULTS_DIR="$T/no-hay"
  run bash scripts/validate-ci-local.sh --quick
  local base_status="$status"
  mk_stale_docs_vault "2026-01-01T00:00:00"
  run bash scripts/validate-ci-local.sh --quick
  [[ "$output" == *"WARN Cúpula savia-docs atrasada"* ]]
  [[ "$output" == *"index-docs.sh"* ]]
  # Sin bloquear: el código de salida es el mismo que sin cúpula.
  [ "$status" -eq "$base_status" ]
}

@test "clock-in negativo: cúpula al día o ausente no añade aviso de cúpula" {
  unset SAVIA_ROOT
  mk_stale_docs_vault "2099-01-01T00:00:00"
  # La cúpula es medible y está al día (no es ausencia de aviso por fallo de la medición).
  run bash "$FRESH" --summary
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  run bash scripts/validate-ci-local.sh --quick
  [[ "$output" != *"Cúpula savia-docs"* ]]
  export SAVIA_VAULTS_DIR="$T/no-hay"
  run bash scripts/validate-ci-local.sh --quick
  [[ "$output" != *"Cúpula savia-docs"* ]]
}
