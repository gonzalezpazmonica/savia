#!/usr/bin/env bats
# tests/scripts/test-install-ps1-gitbash.bats — SE-487 R4 (AC-4, AC-5)
# install.ps1 localiza bash.exe de Git for Windows y fija CLAUDE_CODE_GIT_BASH_PATH.
# No hay PowerShell en Linux: se analiza el bloque de detección con grep estructurado
# y se comprueba que cada aserción puede fallar mutando una copia del script.
# Ref: docs/specs/SE-487-clean-clone-neutral-and-windows.spec.md

ROOT="$BATS_TEST_DIRNAME/../.."
PS1="$ROOT/install.ps1"

# Bloque de detección: de "function Find-GitBash" hasta el paso 3.
block() { sed -n '/^function Find-GitBash/,/^# --- Step 3/p' "$1"; }

# Devuelve 0 solo si el bloque tiene todas las piezas exigidas por R4.
check_block() {
  local b; b="$(block "$1")"
  [ -n "$b" ] || return 1
  grep -qF 'Git\bin\bash.exe' <<<"$b" || return 1
  grep -qF '$env:ProgramFiles' <<<"$b" || return 1
  grep -qF '${env:ProgramFiles(x86)}' <<<"$b" || return 1
  grep -qF 'Programs\Git\bin\bash.exe' <<<"$b" || return 1
  grep -qF 'Get-Command git' <<<"$b" || return 1
  grep -qF "[Environment]::SetEnvironmentVariable('CLAUDE_CODE_GIT_BASH_PATH', \$GitBashPath, 'User')" <<<"$b" || return 1
  grep -q 'Open a NEW terminal' <<<"$b" || return 1
  grep -q 'Git Bash (bash.exe) not found' <<<"$b" || return 1
  grep -q 'https://git-scm.com/downloads/win' <<<"$b" || return 1
  grep -qE '^\s*exit 1' <<<"$b" || return 1
}

@test "AC-4: install.ps1 contiene la detección de bash.exe y la variable de usuario" {
  run check_block "$PS1"
  [ "$status" -eq 0 ]
}

@test "AC-4: la detección va antes de OpenCode y tras comprobar Git" {
  local det git step3
  det="$(grep -n '^\$GitBashPath = Find-GitBash' "$PS1" | cut -d: -f1)"
  git="$(grep -n "^if (\$Missing -eq 1)" "$PS1" | cut -d: -f1)"
  step3="$(grep -n '^# --- Step 3' "$PS1" | cut -d: -f1)"
  [ -n "$det" ] && [ -n "$git" ] && [ -n "$step3" ]
  [ "$git" -lt "$det" ]
  [ "$det" -lt "$step3" ]
}

@test "AC-4: sin bash.exe el instalador termina con error, no con aviso" {
  local after
  after="$(sed -n '/^if (-not \$GitBashPath)/,/^}/p' "$PS1")"
  grep -q 'Write-Fail' <<<"$after"
  grep -q 'exit 1' <<<"$after"
  run grep -q 'Write-Warn' <<<"$after"
  [ "$status" -ne 0 ]
}

@test "AC-4: el paso de enlaces reutiliza el bash encontrado, no deriva otro" {
  grep -qF '$gitBash = $GitBashPath' "$PS1"
  run grep -qF "\$gitBash = if (\$gitCmd)" "$PS1"
  [ "$status" -ne 0 ]
}

@test "AC-4 (negativo): sin SetEnvironmentVariable la comprobación falla" {
  local m="$BATS_TEST_TMPDIR/m.ps1"
  grep -v 'SetEnvironmentVariable' "$PS1" > "$m"
  run check_block "$m"
  [ "$status" -ne 0 ]
}

@test "AC-4 (negativo): sin el error de bash.exe ausente la comprobación falla" {
  local m="$BATS_TEST_TMPDIR/m.ps1"
  sed 's/Git Bash (bash.exe) not found/Git Bash missing/' "$PS1" > "$m"
  run check_block "$m"
  [ "$status" -ne 0 ]
}

@test "AC-4 (negativo): sin la ruta LOCALAPPDATA la comprobación falla" {
  local m="$BATS_TEST_TMPDIR/m.ps1"
  sed 's/Programs\\Git/Programs\\Other/' "$PS1" > "$m"
  run check_block "$m"
  [ "$status" -ne 0 ]
}

@test "AC-4: sintaxis válida según pwsh (si está instalado)" {
  command -v pwsh >/dev/null || skip "pwsh no instalado: sintaxis sin validar"
  run pwsh -NoProfile -Command "[ScriptBlock]::Create((Get-Content -Raw '$PS1')) | Out-Null"
  [ "$status" -eq 0 ]
}

@test "AC-5: todos los README con instalador de Windows citan el requisito y la solución" {
  local f n=0
  for f in "$ROOT"/README*.md; do
    grep -q 'install.ps1' "$f" || continue
    n=$((n+1))
    grep -q 'Git for Windows' "$f"
    grep -q "Git Bash wasn't found" "$f"
    grep -q 'CLAUDE_CODE_GIT_BASH_PATH' "$f"
  done
  [ "$n" -ge 9 ]
}

@test "AC-5 (negativo): un README sin la variable no pasa la comprobación" {
  local m="$BATS_TEST_TMPDIR/R.md"
  grep -v 'CLAUDE_CODE_GIT_BASH_PATH' "$ROOT/README.md" > "$m"
  run grep -q 'CLAUDE_CODE_GIT_BASH_PATH' "$m"
  [ "$status" -ne 0 ]
}

@test "R4: CLAUDE.md lleva la línea de arranque y no pasa de 150 líneas" {
  grep -q "Git Bash wasn't found" "$ROOT/CLAUDE.md"
  grep -q 'bash no se reconoce' "$ROOT/CLAUDE.md"
  grep -q 'CLAUDE_CODE_GIT_BASH_PATH' "$ROOT/CLAUDE.md"
  [ "$(wc -l < "$ROOT/CLAUDE.md")" -le 150 ]
}

@test "R4: windows-links.sh no contiene rutas personales y es no-op fuera de Windows" {
  run grep -qE '/home/[a-z]+/|C:\\Users\\[A-Za-z]+' "$ROOT/scripts/windows-links.sh"
  [ "$status" -ne 0 ]
  run env OSTYPE=linux-gnu bash "$ROOT/scripts/windows-links.sh" check
  [ "$status" -eq 0 ]
  [[ "$output" == *"no aplica"* ]]
}
