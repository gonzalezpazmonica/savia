#!/bin/bash
set -uo pipefail
# install-git-hooks.sh — Instala hooks de Git para PM‑Workspace en OpenCode
# Ejecutar desde el directorio raíz del repositorio (donde está .git/)
#
# --hooks-path [--repo <dir>]: activa los hooks versionados del repo (.githooks/, entre ellos el
# pre-commit que rechaza commits en main/master) con `git config core.hooksPath .githooks`.
# Relativo: cada worktree ejecuta su propia copia de .githooks/. Idempotente. Si ya hay otro
# core.hooksPath, no lo pisa (exit 1). Con core.hooksPath activo, git deja de leer .git/hooks.

if [ "${1:-}" = "--hooks-path" ]; then
    repo="$PWD"
    [ "${2:-}" = "--repo" ] && repo="${3:?--repo necesita un directorio}"
    top="$(git -C "$repo" rev-parse --show-toplevel 2>/dev/null)" \
        || { echo "Error: $repo no es un repositorio git." >&2; exit 1; }
    [ -f "$top/.githooks/pre-commit" ] \
        || { echo "Error: $top/.githooks/pre-commit no existe." >&2; exit 1; }
    current="$(git -C "$top" config --get core.hooksPath)"
    if [ "$current" = ".githooks" ]; then
        echo "core.hooksPath ya es .githooks en $top — sin cambios."
        exit 0
    fi
    if [ -n "$current" ]; then
        echo "Error: core.hooksPath ya vale '$current' en $top; no se pisa." >&2
        echo "  Para cambiarlo a mano: git -C \"$top\" config core.hooksPath .githooks" >&2
        exit 1
    fi
    git -C "$top" config core.hooksPath .githooks || exit 1
    echo "✅ core.hooksPath = .githooks en $top (pre-commit: nunca commit en main/master)."
    exit 0
fi

CLAUDE_PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HOOKS_DIR="$CLAUDE_PROJECT_DIR/.claude/hooks"
OPENCODE_HOOKS_DIR="$CLAUDE_PROJECT_DIR/.opencode/scripts/opencode-hooks"
GIT_HOOKS_DIR="$CLAUDE_PROJECT_DIR/.git/hooks"

if [ ! -d "$GIT_HOOKS_DIR" ]; then
    echo "Error: No se encuentra .git/hooks. Ejecuta desde la raíz del repositorio Git." >&2
    exit 1
fi

# Función para crear un hook combinado (preserva hook existente si hay)
install_hook() {
    local hook_name="$1"
    local hook_file="$GIT_HOOKS_DIR/$hook_name"
    local new_content="$2"
    
    if [ -f "$hook_file" ]; then
        # Backup
        mv "$hook_file" "$hook_file.backup.$(date +%Y%m%d%H%M%S)"
        echo "⚠️  Hook $hook_name existente respaldado."
    fi
    
    cat > "$hook_file" <<EOF
#!/bin/bash
set -uo pipefail
# Hook de PM‑Workspace para OpenCode (instalado automáticamente)
# Ejecuta validaciones de seguridad y calidad antes de operaciones Git.

$new_content
EOF
    chmod +x "$hook_file"
    echo "✅ Hook $hook_name instalado."
}

# ─── pre‑commit ──────────────────────────────────────────────────────────
PRE_COMMIT_CONTENT='
# Validación de calidad pre‑commit
CLAUDE_PROJECT_DIR="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$CLAUDE_PROJECT_DIR" || exit 1
export CLAUDE_PROJECT_DIR
HOOKS_DIR="$CLAUDE_PROJECT_DIR/.claude/hooks"

# 1. Revisión automática de código
"$HOOKS_DIR/pre-commit-review.sh" < /dev/null

# 2. Detección de secrets en cambios staged
"$HOOKS_DIR/stop-quality-gate.sh" < /dev/null

# Si algún hook falla (exit 2), bloqueamos el commit.
# Los hooks anteriores solo emiten warnings (exit 0), pero mantenemos la estructura.
'

# ─── pre‑push ────────────────────────────────────────────────────────────
PRE_PUSH_CONTENT='
# Validación de seguridad pre‑push
CLAUDE_PROJECT_DIR="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$CLAUDE_PROJECT_DIR" || exit 1
export CLAUDE_PROJECT_DIR
OPENCODE_HOOKS_DIR="$CLAUDE_PROJECT_DIR/.opencode/scripts/opencode-hooks"

# Obtener el comando git push completo a partir de los argumentos
# Git pasa los argumentos: <remote> <url>
REMOTE="$1"
URL="$2"

# Simular el comando "git push" (sin opciones adicionales) para el hook.
# El hook block‑force‑push.sh espera un JSON con tool_input.command.
# Usamos el wrapper run‑hook.sh para generarlo.
if [ -f "$OPENCODE_HOOKS_DIR/run-hook.sh" ]; then
    "$OPENCODE_HOOKS_DIR/run-hook.sh" block-force-push Bash "git push $REMOTE" || exit 1
else
    echo "⚠️  run‑hook.sh no encontrado. Omitiendo validación de force‑push."
fi
'

# ─── commit‑msg ──────────────────────────────────────────────────────────
COMMIT_MSG_CONTENT='
# Validación de mensaje de commit
CLAUDE_PROJECT_DIR="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$CLAUDE_PROJECT_DIR" || exit 1
export CLAUDE_PROJECT_DIR
OPENCODE_HOOKS_DIR="$CLAUDE_PROJECT_DIR/.opencode/scripts/opencode-hooks"
COMMIT_MSG_FILE="$1"

# El hook prompt‑hook‑commit.sh espera un JSON con tool_input.file_path.
# Simulamos que es una operación Edit sobre el fichero de mensaje.
if [ -f "$OPENCODE_HOOKS_DIR/run-hook.sh" ]; then
    "$OPENCODE_HOOKS_DIR/run-hook.sh" prompt-hook-commit Edit "$COMMIT_MSG_FILE" || exit 1
else
    echo "⚠️  run‑hook.sh no encontrado. Omitiendo validación de mensaje de commit."
fi
'

# Instalar hooks
install_hook "pre-commit" "$PRE_COMMIT_CONTENT"
install_hook "pre-push" "$PRE_PUSH_CONTENT"
install_hook "commit-msg" "$COMMIT_MSG_CONTENT"

echo ""
echo "🎉 Hooks de Git instalados correctamente."
echo "   A partir de ahora, cada commit/push será validado por PM‑Workspace."
echo ""
echo "   Para desinstalar, elimina los ficheros de $GIT_HOOKS_DIR/pre-commit,"
echo "   $GIT_HOOKS_DIR/pre-push y $GIT_HOOKS_DIR/commit-msg."