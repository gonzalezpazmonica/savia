#!/usr/bin/env bash
# agent-git-discipline.sh — SE-266: Block destructive git + shell ops for concurrent agent safety
# Extended from PR #906 to cover rm -rf, rm without confirmation, and other destructive ops.
# Inspired by Pi (earendil-works/pi AGENTS.md)
set -uo pipefail

INPUT=""
if INPUT=$(timeout 3 cat 2>/dev/null); then
  :
fi

# SE-453 S2: sin jq se degrada a un parseo con grep; si tampoco se puede evaluar, sale 2 (nunca 0 sin evaluar).
# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/lib/hook-input.sh"
hook_extract_command "$INPUT" || exit 2
COMMAND="$HOOK_COMMAND"

[[ -z "$COMMAND" ]] && exit 0

# SE-326 S5: env-scrub validation — solo con SAVIA_SCRUB_ENV=1, NUNCA bloquea.
# Detecta comandos que inyectan secretos por env (warning en stderr).
if [[ "${SAVIA_SCRUB_ENV:-}" == "1" ]]; then
  SCRUB_SCRIPT="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}/scripts/env-scrub.sh"
  if [[ -x "$SCRUB_SCRIPT" ]]; then
    bash "$SCRUB_SCRIPT" check "$COMMAND" 2>&1 || true
  fi
fi

NORMALIZED=$(echo "$COMMAND" | sed 's/^[[:space:]]*//')

# Ancla de inicio de orden: principio de línea, separador (; & |), subshell ( o $(,
# espacios y prefijos que no cambian la orden (VAR=x, env, command, sudo, nohup, time, exec).
# Una mención dentro de un mensaje de commit o de un echo no queda anclada y no bloquea. La comilla
# invertida no ancla: en texto markdown (cuerpos de PR, heredocs) es una mención, no una subshell.
AT='(^|[;&|(]|\$\()[[:space:]]*(([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*|env|command|sudo|nohup|time|exec)[[:space:]]+)*'
GIT_AT="${AT}"'git(([[:space:]]+(-C|-c|--git-dir|--work-tree)[[:space:]]+("[^"]*"|'"'"'[^'"'"']*'"'"'|[^[:space:]]+))|([[:space:]]+--?[A-Za-z][A-Za-z-]*(=[^[:space:]]+)?))*[[:space:]]+'
# Tramo de una orden hasta el siguiente separador: las exenciones (-i, dry-run, rutas seguras)
# valen solo para su propia orden, no para toda la línea.
SEG='[^;&|`)]*'
INTERACTIVE='(^|[[:space:]])(-i|--interactive)([[:space:]]|$)'

# ─── rm -rf / rm -r (recursive delete) y rm sin confirmación ─────────────
# Matches: rm -r, rm -rf, rm -fr, rm -R, rm --recursive · rm sin -i fuera de rutas seguras
# Does NOT match: rm --interactive, rm -i (those are allowed)
SAFE_PATHS="/tmp/opencode|/tmp/recovery|/tmp/extundelete|/tmp/testdisk"
while IFS= read -r seg; do
  [[ -z "$seg" ]] && continue
  echo "$seg" | grep -qE "$INTERACTIVE" && continue
  if echo "$seg" | grep -qE '\s-[a-zA-Z]*[rR][a-zA-Z]*\b|--recursive'; then
    echo "BLOCKED [agent-git-discipline]: rm recursivo (rm -rf / rm -r)." >&2
    echo "  La eliminación recursiva requiere confirmación humana directa." >&2
    exit 2
  fi
  # La exención vale solo si TODOS los operandos están bajo una ruta segura (prefijo, sin ..):
  # `rm /etc/passwd /tmp/opencode/x` o `rm /tmp/opencode/../../etc/x` no se eximen.
  args=""; [[ "$seg" =~ (^|[[:space:]\;\&\|\(])rm[[:space:]]+(.*)$ ]] && args="${BASH_REMATCH[2]}"
  unsafe=0; operands=0
  read -r -a words <<<"$args"
  for w in "${words[@]}"; do
    [[ "$w" == -* ]] && continue
    w="${w#[\"\']}"; w="${w%[\"\']}"
    operands=$((operands + 1))
    if [[ ! "$w" =~ ^($SAFE_PATHS)(/|$) || "$w" == *..* ]]; then unsafe=1; fi
  done
  if (( unsafe || operands == 0 )); then
    echo "BLOCKED [agent-git-discipline]: rm sin confirmación humana (-i / --interactive)." >&2
    echo "  Usa rm -i o elimina archivos desde tu terminal." >&2
    exit 2
  fi
done < <(echo "$NORMALIZED" | grep -oE "${AT}rm[[:space:]]+${SEG}")

# ─── Truncado destructivo de archivos (> file, :> file) ────────────────
if echo "$NORMALIZED" | grep -qE "${AT}"'(cat[[:space:]]+/dev/null|true|:)[[:space:]]*>[[:space:]]*(~|/home|/etc|/boot|/root)'; then
  echo "BLOCKED [agent-git-discipline]: truncado de archivos del sistema/usuario." >&2
  exit 2
fi

# ─── Escritura directa a dispositivos de bloque ────────────────────────
# Cualquier destino en /dev salvo los pseudodispositivos inocuos: sd, hd, nvme, mmcblk, vd, xvd, md,
# dm-*, mapper/, disk/by-* y los que vengan. Una lista de discos siempre se queda corta.
if echo "$NORMALIZED" | grep -oE "${AT}dd[[:space:]]+${SEG}" | grep -oE 'of=/dev/[^[:space:]]*' \
   | grep -qvE '^of=/dev/(null|zero|stdout|stderr|tty|fd/[0-9]+)$'; then
  echo "BLOCKED [agent-git-discipline]: dd escribiendo a dispositivo de bloque." >&2
  exit 2
fi

if echo "$NORMALIZED" | grep -qE "${AT}"'mkfs\.'; then
  echo "BLOCKED [agent-git-discipline]: mkfs (formateo de disco)." >&2
  exit 2
fi

# ─── chown recursivo sobre home del usuario ────────────────────────────
if echo "$NORMALIZED" | grep -qE "${AT}chown[[:space:]]+-R[[:space:]]+${SEG}"'(~|/home|/root)'; then
  echo "BLOCKED [agent-git-discipline]: chown -R sobre home del usuario." >&2
  exit 2
fi

# ═══════════════════════════════════════════════════════════════════════
# GIT destructive operations (SE-266 original, Pi-inspired)
# ═══════════════════════════════════════════════════════════════════════

if ! echo "$NORMALIZED" | grep -qE "$GIT_AT"; then
  exit 0
fi

# ─── git reset --hard ───────────────────────────────────────────────────
if echo "$NORMALIZED" | grep -qE "${GIT_AT}reset[[:space:]]+${SEG}--hard"; then
  echo "BLOCKED [agent-git-discipline]: git reset --hard — destruye todo el trabajo no commiteado." >&2
  exit 2
fi

# ─── git clean (bloquear todo menos dry-run) ────────────────────────────
while IFS= read -r seg; do
  [[ -z "$seg" ]] && continue
  if ! echo "$seg" | grep -qE 'clean[[:space:]].*(-[a-z]*n[a-z]*|-n|--dry-run)'; then
    echo "BLOCKED [agent-git-discipline]: git clean — elimina archivos no trackeados de todos los agentes." >&2
    echo "  Usa git clean -n o --dry-run para previsualizar primero." >&2
    exit 2
  fi
done < <(echo "$NORMALIZED" | grep -oE "${GIT_AT}clean([[:space:]]${SEG})?")

# ─── git stash ──────────────────────────────────────────────────────────
if echo "$NORMALIZED" | grep -qE "${GIT_AT}stash"; then
  echo "BLOCKED [agent-git-discipline]: git stash oculta cambios staged de otros agentes." >&2
  echo "  Alternativa: commitea a tu rama agent/*." >&2
  exit 2
fi

# ─── git checkout . / git checkout -- . ─────────────────────────────────
if echo "$NORMALIZED" | grep -qE "${GIT_AT}"'checkout[[:space:]]+(--[[:space:]]+)?\.([[:space:]]|$|[;&|)])'; then
  echo "BLOCKED [agent-git-discipline]: git checkout . destruye el working tree de todos los agentes." >&2
  exit 2
fi

# ─── git push --delete / -d / :rama (borrar ramas remotas ajenas) ───────
# autonomous-safety: NUNCA borrar ramas ajenas. Solo se borran en el remoto las ramas agent/*.
while IFS= read -r seg; do
  [[ -z "$seg" ]] && continue
  read -ra toks <<<"${seg#*push}"
  deleting=false
  for t in "${toks[@]}"; do [[ "$t" == "--delete" || "$t" == "-d" ]] && deleting=true; done
  remote="" foreign=()
  for t in "${toks[@]}"; do
    t=${t//[\"\']/}
    [[ "$t" == -* || "$t" == *[\<\>]* || -z "$t" ]] && continue
    [[ -z "$remote" ]] && { remote=$t; continue; }
    if [[ "$t" == :?* ]]; then ref=${t#:}
    elif $deleting; then ref=$t
    else continue
    fi
    ref=${ref#refs/heads/}
    [[ "$ref" == agent/* ]] || foreign+=("$ref")
  done
  if (( ${#foreign[@]} > 0 )); then
    echo "BLOCKED [agent-git-discipline]: borrar ramas remotas ajenas (${foreign[*]})." >&2
    echo "  Un agente solo borra sus ramas agent/*; el resto lo borra la operadora." >&2
    exit 2
  fi
done < <(echo "$NORMALIZED" | grep -oE "${GIT_AT}push([[:space:]]${SEG})?")

# ─── git add -A / git add . (warn, no block) ────────────────────────────
if echo "$NORMALIZED" | grep -qE "${GIT_AT}"'add[[:space:]]+(-A|\.)[[:space:]]*$'; then
  echo "WARN [agent-git-discipline]: git add -A/. stagea archivos de otros agentes." >&2
  echo "  Usa: git add <path1> <path2>" >&2
fi

exit 0
