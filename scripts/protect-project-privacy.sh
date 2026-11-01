#!/usr/bin/env bash
# protect-project-privacy.sh — Barrera de protección contra publicación accidental de proyectos
#
# PROPÓSITO: Detectar y BLOQUEAR cualquier intento de añadir proyectos nuevos al repositorio
# git sin confirmación humana explícita. Actúa como mecanismo de defensa INDEPENDIENTE
# de las reglas de Savia, para proteger contra errores de contexto de la IA.
#
# USO:
#   Como pre-commit hook:  Se invoca automáticamente antes de cada commit
#   Manual:                bash scripts/protect-project-privacy.sh [--check | --authorize <proyecto>]
#
# FUNCIONAMIENTO:
#   1. Examina los cambios staged (git diff --cached)
#   2. Detecta si .gitignore fue modificado para añadir whitelist de proyectos (!projects/...)
#   3. Detecta si hay archivos staged dentro de projects/ que no están en la whitelist actual
#   4. Si detecta cualquiera de los dos → BLOQUEA el commit y pide confirmación humana
#   5. El humano debe ejecutar --authorize <proyecto> para crear un permiso temporal
#
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AUTHORIZED_FILE="$ROOT/.claude/.project-authorizations"
MODE="${1:---hook}"

# ─── Colores ──────────────────────────────────────────────────
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
BOLD='\033[1m'
NC='\033[0m'

# ─── Funciones ────────────────────────────────────────────────

die() {
    echo -e "${RED}${BOLD}🛑 BLOQUEADO: $1${NC}" >&2
    echo -e "${YELLOW}   Motivo: Protección de privacidad de proyectos${NC}" >&2
    echo "" >&2
    echo -e "   Para autorizar un proyecto público, ejecuta:" >&2
    echo -e "   ${GREEN}bash scripts/protect-project-privacy.sh --authorize <nombre-proyecto>${NC}" >&2
    echo "" >&2
    echo -e "   ${RED}⚠️  NUNCA autorices un proyecto de cliente o con datos sensibles.${NC}" >&2
    exit 1
}

is_authorized() {
    local project="$1"
    [ -f "$AUTHORIZED_FILE" ] && grep -qx "$project" "$AUTHORIZED_FILE" 2>/dev/null
}

get_whitelisted_projects() {
    grep -E '^!projects/' "$ROOT/.gitignore" 2>/dev/null | sed 's|^!projects/||; s|/$||'
}

# ─── Modo: Autorizar un proyecto ──────────────────────────────

if [[ "$MODE" == "--authorize" ]]; then
    PROJECT="${2:-}"
    if [[ -z "$PROJECT" ]]; then
        echo "Uso: bash scripts/protect-project-privacy.sh --authorize <nombre-proyecto>"
        exit 1
    fi

    echo -e "${YELLOW}${BOLD}⚠️  ADVERTENCIA: Vas a autorizar la publicación del proyecto '$PROJECT'${NC}"
    echo ""
    echo "   Esto permitirá que el proyecto se añada al repositorio git PÚBLICO."
    echo "   Antes de continuar, confirma que:"
    echo ""
    echo "   ✅ El proyecto NO contiene datos de clientes"
    echo "   ✅ El proyecto NO contiene información confidencial"
    echo "   ✅ El proyecto NO está bajo NDA o acuerdo de confidencialidad"
    echo "   ✅ Tienes autorización para publicar este contenido"
    echo ""

    read -r -p "¿Confirmas que '$PROJECT' puede ser PÚBLICO? (escribe 'SÍ PÚBLICO' para confirmar): " CONFIRM

    if [[ "$CONFIRM" == "SÍ PÚBLICO" || "$CONFIRM" == "SI PUBLICO" || "$CONFIRM" == "YES PUBLIC" ]]; then
        mkdir -p "$(dirname "$AUTHORIZED_FILE")"
        echo "$PROJECT" >> "$AUTHORIZED_FILE"
        echo -e "${GREEN}✅ Proyecto '$PROJECT' autorizado para publicación.${NC}"
        echo "   Ahora puedes modificar .gitignore y hacer commit."
    else
        echo -e "${RED}❌ Autorización cancelada. El proyecto '$PROJECT' permanece privado.${NC}"
        exit 1
    fi
    exit 0
fi

# ─── Modo: Check (verificación sin bloqueo) ──────────────────

if [[ "$MODE" == "--check" ]]; then
    echo "=== Verificación de privacidad de proyectos ==="
    echo ""
    echo "Proyectos en whitelist (.gitignore):"
    get_whitelisted_projects | while read -r p; do
        if is_authorized "$p"; then
            echo -e "  ${GREEN}✅ $p (autorizado)${NC}"
        else
            echo -e "  ${YELLOW}⚠️  $p (en whitelist pero sin autorización explícita)${NC}"
        fi
    done
    echo ""
    echo "Autorizaciones registradas:"
    if [ -f "$AUTHORIZED_FILE" ]; then
        while read -r p; do echo "  ✅ $p"; done < "$AUTHORIZED_FILE"
    else
        echo "  (ninguna)"
    fi
    exit 0
fi

# ─── Modo: Hook pre-commit ────────────────────────────────────

# Verificación 1: ¿Se ha modificado .gitignore para añadir whitelist de proyecto?
if git diff --cached --name-only 2>/dev/null | grep -q "^\.gitignore$"; then
    NEW_WHITELISTS=$(git diff --cached -- .gitignore 2>/dev/null \
        | grep "^+" | grep -v "^+++" \
        | grep -E '^\+!projects/' \
        | sed 's|^\+!projects/||; s|/$||' || true)

    if [[ -n "$NEW_WHITELISTS" ]]; then
        while IFS= read -r project; do
            if ! is_authorized "$project"; then
                die "Intento de añadir proyecto '$project' al whitelist de .gitignore sin autorización.

   Se detectó que .gitignore fue modificado para incluir: !projects/$project/
   Esto publicaría el proyecto en el repositorio git público.

   Si este proyecto DEBE ser público, primero autorízalo:
   bash scripts/protect-project-privacy.sh --authorize $project"
            fi
        done <<< "$NEW_WHITELISTS"
    fi
fi

# Verificación 2: ¿Hay archivos staged en projects/ de un proyecto no whitelisteado?
# R incluido: un `git mv` hacia projects/<x>/ también publica (con ACM pasaba sin bloqueo).
STAGED_PROJECTS=$(git diff --cached --name-only --diff-filter=ACMR 2>/dev/null \
    | grep "^projects/" \
    | sed 's|^projects/||; s|/.*||' \
    | sort -u || true)

if [[ -n "$STAGED_PROJECTS" ]]; then
    CURRENT_WHITELIST=$(get_whitelisted_projects)
    while IFS= read -r project; do
        if ! echo "$CURRENT_WHITELIST" | grep -qx "$project"; then
            # Proyecto no está en whitelist pero hay archivos staged → alguien usó git add -f
            die "Intento de añadir archivos del proyecto '$project' que NO está en el whitelist.

   Se detectaron archivos staged en projects/$project/ pero este proyecto
   está ignorado por .gitignore. Esto indica un 'git add -f' forzado.

   Si este proyecto DEBE ser público, primero autorízalo:
   bash scripts/protect-project-privacy.sh --authorize $project"
        fi
    done <<< "$STAGED_PROJECTS"
fi

# Todo OK
exit 0
