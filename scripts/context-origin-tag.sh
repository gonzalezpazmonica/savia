#!/usr/bin/env bash
set -uo pipefail
# context-origin-tag.sh — SE-221 Slice 1 — Context Origin Tagging
# Devuelve el tag origin canonico segun N1-N4b para un path dado.
#
# Spec: docs/propuestas/SE-221-inverted-security-patterns-as-context-engineering.md (AC-01)
# Inspiracion: Spotlighting (Hines et al. 2024, arXiv:2403.14720) invertido.
#
# Resuelve por prefijo de path, no por contenido.
# Tags posibles: N1-anchor, N2-eager, N3-active-user, N4a-lazy-ref, N4b-on-demand,
#                N5-external, untrusted, sandbox.
#
# Uso:
#   scripts/context-origin-tag.sh <path>
#   scripts/context-origin-tag.sh --json <path>
#
# Exit codes:
#   0 — tag emitido en stdout
#   2 — argumentos invalidos

JSON=0
PATH_ARG=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --json) JSON=1; shift ;;
    -h|--help) sed -n '2,18p' "$0"; exit 0 ;;
    --) shift; PATH_ARG="${1:-}"; break ;;
    -*)
      echo "ERROR: unknown arg: $1" >&2
      exit 2
      ;;
    *)
      if [[ -z "$PATH_ARG" ]]; then
        PATH_ARG="$1"
        shift
      else
        echo "ERROR: only one path supported" >&2
        exit 2
      fi
      ;;
  esac
done

if [[ -z "$PATH_ARG" ]]; then
  echo "ERROR: missing path argument" >&2
  exit 2
fi

# Resolver workspace (acepta override por env)
WORKSPACE="${SAVIA_WORKSPACE_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"

# Windows (Git Bash): C:\x o C:/x → /c/x. Sin esto una ruta Windows se tomaba
# como relativa, quedaba "dentro" del workspace y heredaba un tier de confianza.
win_to_posix() {
  local p="$1"
  if [[ "$p" =~ ^([A-Za-z]):[\\/] ]]; then
    p="${p//\\//}"
    p="/${BASH_REMATCH[1],,}${p:2}"
  fi
  printf '%s' "$p"
}
WORKSPACE=$(win_to_posix "${WORKSPACE%/}")

# Normalizar a absoluto sin requerir que exista (para tests)
abs_path() {
  local p
  p=$(win_to_posix "$1")
  if [[ "$p" = /* ]]; then
    printf '%s' "$p"
  else
    printf '%s' "$(pwd)/$p"
  fi
}

ABS=$(abs_path "$PATH_ARG")

resolve_tier() {
  local p="$1"

  # Sandbox /tmp/opencode/* — exento, siempre sandbox
  case "$p" in
    /tmp/opencode/*) echo "sandbox"; return ;;
  esac

  # Fuera del workspace → N5-external o untrusted
  # Prefijo por componente: /repo no debe contener /repo-otro.
  if [[ "$p" != "$WORKSPACE"/* ]]; then
    case "$p" in
      "$HOME"/.savia-memory/*|"$HOME"/.savia/*|"$HOME"/.claude/*) echo "N5-external"; return ;;
      "$HOME"/*) echo "N5-external"; return ;;
      *) echo "untrusted"; return ;;
    esac
  fi

  # Dentro del workspace — clasificar por subpath
  local rel="${p#"$WORKSPACE"/}"

  # N1-anchor: docs/critical-facts.md (anchor superior SPEC-185)
  case "$rel" in
    docs/critical-facts.md) echo "N1-anchor"; return ;;
  esac

  # N2-eager: imports criticos del CLAUDE.md (savia, radical-honesty,
  # autonomous-safety, caveman-default, profiles/savia.md)
  case "$rel" in
    .claude/profiles/savia.md) echo "N2-eager"; return ;;
    .claude/profiles/savia-agent-mode.md) echo "N2-eager"; return ;;
    docs/rules/domain/radical-honesty.md) echo "N2-eager"; return ;;
    docs/rules/domain/autonomous-safety.md) echo "N2-eager"; return ;;
    docs/rules/domain/caveman-default.md) echo "N2-eager"; return ;;
    CLAUDE.md|AGENTS.md|SKILLS.md) echo "N2-eager"; return ;;
  esac

  # N3-active-user: perfiles del usuario y memoria activa
  case "$rel" in
    .claude/profiles/active-user.md) echo "N3-active-user"; return ;;
    .claude/profiles/users/*) echo "N3-active-user"; return ;;
    .claude/external-memory/*) echo "N3-active-user"; return ;;
    .claude/rules/pm-config.local.md) echo "N3-active-user"; return ;;
    CLAUDE.local.md) echo "N3-active-user"; return ;;
  esac

  # N4a-lazy-ref: tabla de referencias lazy (CLAUDE.md de proyectos, RESOLVER)
  case "$rel" in
    docs/RESOLVER.md) echo "N4a-lazy-ref"; return ;;
    projects/*/CLAUDE.md) echo "N4a-lazy-ref"; return ;;
  esac

  # N4b-on-demand: rules/skills/agents/commands cargados bajo demanda
  case "$rel" in
    docs/rules/domain/*) echo "N4b-on-demand"; return ;;
    docs/rules/languages/*) echo "N4b-on-demand"; return ;;
    .opencode/skills/*) echo "N4b-on-demand"; return ;;
    .opencode/agents/*) echo "N4b-on-demand"; return ;;
    .opencode/commands/*) echo "N4b-on-demand"; return ;;
    .claude/skills/*) echo "N4b-on-demand"; return ;;
    .claude/agents/*) echo "N4b-on-demand"; return ;;
    .claude/commands/*) echo "N4b-on-demand"; return ;;
    docs/specs/*|docs/propuestas/*) echo "N4b-on-demand"; return ;;
    docs/*) echo "N4b-on-demand"; return ;;
  esac

  # N4-project: datos especificos de proyecto
  case "$rel" in
    projects/*) echo "N4-project"; return ;;
  esac

  # Fallback dentro del workspace
  echo "N4b-on-demand"
}

TIER=$(resolve_tier "$ABS")

if [[ "$JSON" -eq 1 ]]; then
  printf '{"path":"%s","tier":"%s","abs":"%s","workspace":"%s"}\n' \
    "$PATH_ARG" "$TIER" "$ABS" "$WORKSPACE"
else
  printf '%s\n' "$TIER"
fi

exit 0
