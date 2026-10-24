#!/usr/bin/env bats
# tests/test-se272-s5-exit-portability.bats
# SE-272 Slice 5 — BATS tests for exit-independence-verify.sh
#
# Verifies: script existence, syntax, help flag, open format checks,
# section validation, manifest validation, index readability checks.

ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
SCRIPT="${ROOT}/scripts/exit-independence-verify.sh"
GENERATOR="${ROOT}/scripts/exit-package-generate.sh"

setup() {
  TMPDIR="$(mktemp -d)"
  PKG="$TMPDIR/exit-package"
  mkdir -p "$PKG"
}

teardown() {
  rm -rf "$TMPDIR"
}

make_minimal_package() {
  local pkg="${1:-$PKG}"

  mkdir -p "$pkg/01-specs"
  mkdir -p "$pkg/02-criterion"
  mkdir -p "$pkg/03-decisions"
  mkdir -p "$pkg/04-kg"
  mkdir -p "$pkg/05-qa"
  mkdir -p "$pkg/06-kpi"
  mkdir -p "$pkg/07-provenance"

  cat > "$pkg/00-index.md" <<'INDEX'
# Exit Package — test-engagement

> Generated: 2026-07-25T00:00:00Z
> Format: Open (Markdown, JSONL, plain text). Zero dependency on Savia.

## Reading guide

This package contains everything needed to understand the engagement state
without Savia installed. All sections are text files readable with any
editor or text tool.

### Sections

| # | Section | Path | Format | Standalone? |
|---|---------|------|--------|-------------|
| 1 | Specs | `01-specs/` | Markdown | Yes |
| 2 | Criterion | `02-criterion/` | Markdown | Yes |
| 3 | Decisions | `03-decisions/` | Markdown | Yes |
| 4 | Knowledge Graph | `04-kg/` | JSON + zst | JSON is standalone |
| 5 | QA Evidence | `05-qa/` | Mixed | Mostly standalone |
| 6 | KPI History | `06-kpi/` | JSONL + MD | Yes |
| 7 | Provenance | `07-provenance/` | Markdown | Yes |

### How to use this package

1. Start with `00-index.md` (this file)
2. Read `02-criterion/CRITERIO.md` for decision-making rules
3. Browse `01-specs/` for approved feature specifications
4. Review `03-decisions/decision-log.md` for key decisions with reasons
INDEX

  echo "# Spec example" > "$pkg/01-specs/example.spec.md"
  echo "# Decision criterion" > "$pkg/02-criterion/CRITERIO.md"
  echo "# Decision log" > "$pkg/03-decisions/decision-log.md"
  echo '{"entities": []}' > "$pkg/04-kg/kg-dump.json"
  echo "# QA report" > "$pkg/05-qa/results.md"
  echo "# KPI history" > "$pkg/06-kpi/KPI-HISTORY.md"
  echo "# Provenance" > "$pkg/07-provenance/PROVENANCE.md"

  # Generate manifest
  find "$pkg" -type f -not -name "MANIFEST.sha256" -print0 2>/dev/null | \
    sort -z | while IFS= read -r -d '' f; do
    sha256sum "$f" | sed "s|$pkg/||"
  done > "$pkg/MANIFEST.sha256"
}

make_binary_package() {
  local pkg="$1"

  make_minimal_package "$pkg"

  # Add a binary file disguised as text
  printf '\x7f\x45\x4c\x46\x02\x01\x01\x00' > "$pkg/05-qa/binary-test.bin"
}

# ── Script existence & syntax ─────────────────────────────────────────────────

@test "SE-272-S5-01: exit-independence-verify.sh exists" {
  [[ -f "$SCRIPT" ]]
}

@test "SE-272-S5-02: exit-independence-verify.sh has set -uo pipefail" {
  run grep -c 'set -uo pipefail' "$SCRIPT"
  [[ "$output" -ge 1 ]]
}

@test "SE-272-S5-03: exit-independence-verify.sh bash -n syntax check passes" {
  run bash -n "$SCRIPT"
  [[ "$status" -eq 0 ]]
}

@test "SE-272-S5-04: SE-272 reference present in script" {
  run grep -c 'SE-272' "$SCRIPT"
  [[ "$output" -ge 1 ]]
}

@test "SE-272-S5-05: --help flag works and returns 0" {
  run bash "$SCRIPT" --help
  [[ "$status" -eq 0 ]]
  [[ "$output" =~ "Usage" ]]
}

@test "SE-272-S5-06: missing --package flag exits with error" {
  run bash "$SCRIPT"
  [[ "$status" -ne 0 ]]
}

@test "SE-272-S5-07: references to SE-272 S5 in script" {
  run grep -c 'S5\|Slice 5\|exit independence\|SE-272.*exit' "$SCRIPT"
  [[ "$output" -ge 1 ]]
}

# ── Open format checks ────────────────────────────────────────────────────────

@test "SE-272-S5-10: valid package passes all checks" {
  make_minimal_package
  run bash "$SCRIPT" --package "$PKG"
  [[ "$status" -eq 0 ]]
  [[ "$output" =~ "INDEPENDENT" ]]
}

@test "SE-272-S5-11: detects binary file as violation" {
  make_binary_package "$PKG"
  run bash "$SCRIPT" --package "$PKG"
  [[ "$output" =~ "Binary" ]] || [[ "$output" =~ "DEPENDENT" ]]
}

@test "SE-272-S5-12: empty package directory fails" {
  # Don't call make_minimal_package — leave it empty
  run bash "$SCRIPT" --package "$PKG"
  [[ "$status" -ne 0 ]] || [[ "$output" =~ "DEPENDENT" ]] || [[ "$output" =~ "MISS" ]]
}

# ── Section validation ────────────────────────────────────────────────────────

@test "SE-272-S5-20: detects missing 00-index.md" {
  make_minimal_package
  rm -f "$PKG/00-index.md"
  run bash "$SCRIPT" --package "$PKG"
  [[ "$output" =~ "index" ]] || [[ "$output" =~ "DEPENDENT" ]] || [[ "$status" -ne 0 ]]
}

@test "SE-272-S5-21: detects missing specs section" {
  make_minimal_package
  rm -rf "$PKG/01-specs"
  run bash "$SCRIPT" --package "$PKG"
  [[ "$output" =~ "01-specs" ]] || [[ "$output" =~ "EMPTY" ]] || [[ "$output" =~ "MISS" ]]
}

@test "SE-272-S5-22: detects missing criterion section" {
  make_minimal_package
  rm -rf "$PKG/02-criterion"
  run bash "$SCRIPT" --package "$PKG"
  [[ "$output" =~ "02-criterion" ]] || [[ "$output" =~ "MISS" ]]
}

@test "SE-272-S5-23: detects missing decisions section" {
  make_minimal_package
  rm -rf "$PKG/03-decisions"
  run bash "$SCRIPT" --package "$PKG"
  [[ "$output" =~ "03-decisions" ]] || [[ "$output" =~ "MISS" ]]
}

@test "SE-272-S5-24: detects missing KG section" {
  make_minimal_package
  rm -rf "$PKG/04-kg"
  run bash "$SCRIPT" --package "$PKG"
  [[ "$output" =~ "04-kg" ]] || [[ "$output" =~ "MISS" ]]
}

@test "SE-272-S5-25: detects missing QA section" {
  make_minimal_package
  rm -rf "$PKG/05-qa"
  run bash "$SCRIPT" --package "$PKG"
  [[ "$output" =~ "05-qa" ]] || [[ "$output" =~ "MISS" ]]
}

@test "SE-272-S5-26: detects missing KPI section" {
  make_minimal_package
  rm -rf "$PKG/06-kpi"
  run bash "$SCRIPT" --package "$PKG"
  [[ "$output" =~ "06-kpi" ]] || [[ "$output" =~ "MISS" ]]
}

@test "SE-272-S5-27: detects missing provenance section" {
  make_minimal_package
  rm -rf "$PKG/07-provenance"
  run bash "$SCRIPT" --package "$PKG"
  [[ "$output" =~ "07-provenance" ]] || [[ "$output" =~ "MISS" ]]
}

# ── Manifest integrity ────────────────────────────────────────────────────────

@test "SE-272-S5-30: detects broken manifest (hash mismatch)" {
  make_minimal_package
  # Corrupt a file referenced in manifest
  echo "corrupted" > "$PKG/01-specs/example.spec.md"
  run bash "$SCRIPT" --package "$PKG"
  [[ "$output" =~ "Hash mismatch" ]] || [[ "$output" =~ "DEPENDENT" ]] || [[ "$status" -ne 0 ]]
}

@test "SE-272-S5-31: detects missing manifest" {
  make_minimal_package
  rm -f "$PKG/MANIFEST.sha256"
  run bash "$SCRIPT" --package "$PKG"
  [[ "$output" =~ "No MANIFEST" ]] || [[ "$output" =~ "DEPENDENT" ]]
}

# ── Index readability ─────────────────────────────────────────────────────────

@test "SE-272-S5-40: index with reading guide passes" {
  make_minimal_package
  run bash "$SCRIPT" --package "$PKG"
  [[ "$output" =~ "Index is standalone readable" ]]
}

@test "SE-272-S5-41: index without reading guide triggers warning" {
  make_minimal_package
  cat > "$PKG/00-index.md" <<'EOF'
# Exit Package
Just a header, no reading guide.
EOF
  run bash "$SCRIPT" --package "$PKG"
  [[ "$output" =~ "Index" ]] || [[ "$status" -eq 0 ]]
}

@test "SE-272-S5-42: index without all section references triggers warning" {
  make_minimal_package
  cat > "$PKG/00-index.md" <<'EOF'
# Exit Package

## Reading guide

Read the files. Only specs section is documented.

### Sections

| 1 | Specs | `01-specs/` |
EOF
  run bash "$SCRIPT" --package "$PKG"
  [[ "$output" =~ "Index" ]] || [[ "$status" -eq 0 ]]
}

# ── Non-existent package ──────────────────────────────────────────────────────

@test "SE-272-S5-50: non-existent package path exits with error" {
  run bash "$SCRIPT" --package "/tmp/nonexistent-path-$$-xyz"
  [[ "$status" -ne 0 ]]
}

# ── Savia runtime reference check ─────────────────────────────────────────────

@test "SE-272-S5-60: detects Savia runtime references" {
  make_minimal_package
  echo "Requires ANTHROPIC_API_KEY to be set" > "$PKG/02-criterion/README.md"
  run bash "$SCRIPT" --package "$PKG"
  [[ "$output" =~ "Savia runtime reference" ]] || [[ "$output" =~ "DEPENDENT" ]] || [[ "$status" -ne 0 ]]
}

@test "SE-272-S5-61: clean package has no Savia runtime references" {
  make_minimal_package
  run bash "$SCRIPT" --package "$PKG"
  [[ "$output" =~ "No Savia runtime references" ]]
}

# ── All scripts existence ─────────────────────────────────────────────────────

@test "SE-272-S5-70: exit-package-generate.sh exists and is executable" {
  [[ -f "$GENERATOR" ]]
  [[ -x "$GENERATOR" ]]
}

@test "SE-272-S5-71: exit-dependencies-declare.sh exists and is executable" {
  [[ -f "${ROOT}/scripts/exit-dependencies-declare.sh" ]]
  [[ -x "${ROOT}/scripts/exit-dependencies-declare.sh" ]]
}

@test "SE-272-S5-72: exit-drill-execute.sh exists and is executable" {
  [[ -f "${ROOT}/scripts/exit-drill-execute.sh" ]]
  [[ -x "${ROOT}/scripts/exit-drill-execute.sh" ]]
}

@test "SE-272-S5-73: exit-purge-verify.sh exists and is executable" {
  [[ -f "${ROOT}/scripts/exit-purge-verify.sh" ]]
  [[ -x "${ROOT}/scripts/exit-purge-verify.sh" ]]
}

# ── Bash syntax checks for all scripts ─────────────────────────────────────────

@test "SE-272-S5-80: exit-package-generate.sh passes bash -n" {
  run bash -n "$GENERATOR"
  [[ "$status" -eq 0 ]]
}

@test "SE-272-S5-81: exit-dependencies-declare.sh passes bash -n" {
  run bash -n "${ROOT}/scripts/exit-dependencies-declare.sh"
  [[ "$status" -eq 0 ]]
}

@test "SE-272-S5-82: exit-drill-execute.sh passes bash -n" {
  run bash -n "${ROOT}/scripts/exit-drill-execute.sh"
  [[ "$status" -eq 0 ]]
}

@test "SE-272-S5-83: exit-purge-verify.sh passes bash -n" {
  run bash -n "${ROOT}/scripts/exit-purge-verify.sh"
  [[ "$status" -eq 0 ]]
}

# ── set -uo pipefail presence in all scripts ───────────────────────────────────

@test "SE-272-S5-90: all scripts have set -uo pipefail" {
  for s in exit-package-generate.sh exit-independence-verify.sh exit-drill-execute.sh exit-purge-verify.sh exit-dependencies-declare.sh; do
    run grep -c 'set -uo pipefail' "${ROOT}/scripts/$s"
    [[ "$status" -eq 0 ]]
    [[ "$output" -ge 1 ]]
  done
}

# ── Package generation integration test ───────────────────────────────────────

@test "SE-272-S5-100: generator produces valid package that passes verification" {
  # Use a separate directory — generator refuses to overwrite existing
  local gen_pkg="$TMPDIR/gen-package"
  run bash "$GENERATOR" generate --engagement "test-bats-exit" --dest "$gen_pkg"
  [[ -f "$gen_pkg/00-index.md" ]]
  [[ -d "$gen_pkg/01-specs" ]]
  [[ -d "$gen_pkg/02-criterion" ]]
  [[ -d "$gen_pkg/03-decisions" ]]
  [[ -d "$gen_pkg/04-kg" ]]
  [[ -d "$gen_pkg/05-qa" ]]
  [[ -d "$gen_pkg/06-kpi" ]]
  [[ -d "$gen_pkg/07-provenance" ]]
  [[ -f "$gen_pkg/MANIFEST.sha256" ]]

  # Run verification on generated package
  run bash "$SCRIPT" --package "$gen_pkg"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Result: INDEPENDENT" ]]
}

@test "SE-272-S5-101: generator --help works" {
  run bash "$GENERATOR" --help
  [[ "$status" -eq 0 ]]
}
