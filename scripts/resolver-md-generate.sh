#!/usr/bin/env bash
# resolver-md-generate.sh — SE-160
#
# Generates docs/RESOLVER.md from .opencode/skills/*/SKILL.md and
# .opencode/agents/*.md. RESOLVER.md is the explicit dispatch table from
# canonical intent → skill/agent. Two sections:
#
#   ## AUTO (auto-generated from frontmatter — managed-content marked)
#   ## OVERRIDE (hand-curated synonyms / aliases — preserved across regen)
#
# The AUTO block is replaced atomically; OVERRIDE is preserved verbatim.
#
# Usage:
#   bash scripts/resolver-md-generate.sh           # print to stdout (dry-run)
#   bash scripts/resolver-md-generate.sh --apply   # write atomically, preserve OVERRIDE
#   bash scripts/resolver-md-generate.sh --check   # exit 1 if AUTO block drifts
#
# Exit codes: 0 ok | 1 drift | 2 usage | 3 source dir missing
#
# Reference: SE-160 (docs/ROADMAP.md), GBrain RESOLVER.md pattern.

set -uo pipefail
export LC_ALL=C  # deterministic sort + truncation across environments

ROOT="${PROJECT_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
SKILLS_DIR="${SKILLS_DIR:-${ROOT}/.opencode/skills}"
AGENTS_DIR="${AGENTS_DIR:-${ROOT}/.opencode/agents}"
TARGET="${RESOLVER_MD:-${ROOT}/docs/RESOLVER.md}"
MODE="generate"
AUTO_BEGIN="<!-- AUTO_BEGIN — do not edit; regenerate via scripts/resolver-md-generate.sh -->"
AUTO_END="<!-- AUTO_END -->"

usage() {
  cat <<USG
Usage: resolver-md-generate.sh [--apply | --check]
  (default)  Print full content to stdout
  --apply    Replace AUTO block atomically, preserve OVERRIDE block
  --check    Exit 1 if AUTO block on disk differs from generated
USG
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --apply) MODE="apply"; shift ;;
    --check) MODE="check"; shift ;;
    --help|-h) usage; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; usage >&2; exit 2 ;;
  esac
done

[[ -d "$SKILLS_DIR" ]] || { echo "ERROR: skills dir missing: $SKILLS_DIR" >&2; exit 3; }
[[ -d "$AGENTS_DIR" ]] || { echo "ERROR: agents dir missing: $AGENTS_DIR" >&2; exit 3; }

extract_field() {
  local file="$1" field="$2"
  awk -v field="^${field}:" '
    /^---$/ { c++; if (c>=2) exit; next }
    c==1 {
      if ($0 ~ field) {
        sub(field, "")
        sub(/^[[:space:]]+/, "")
        if ($0 ~ /^>/) { collecting = 1; buf = ""; next }
        gsub(/^"|"$/, "")
        print
        exit
      }
      if (collecting) {
        if ($0 ~ /^[[:alpha:]_][^[:space:]]*:/) {
          gsub(/^[[:space:]]+|[[:space:]]+$/, "", buf)
          print buf
          exit
        }
        line = $0
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)
        if (line != "") buf = (buf == "" ? line : buf " " line)
      }
    }
    END {
      if (collecting) {
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", buf)
        print buf
      }
    }
  ' "$file"
}

sanitise() {
  local s="$1"
  s=$(echo "$s" | tr -s '[:space:]' ' ' | sed -E 's/^ +| +$//g')
  s="${s//|/\\|}"
  if [[ ${#s} -gt 90 ]]; then
    s="${s:0:87}..."
  fi
  echo "$s"
}

build_skills_table() {
  printf '| Intent (skill) | Target | Cuándo usar |\n'
  printf '|---|---|---|\n'
  while IFS= read -r f; do
    [[ -f "$f" ]] || continue
    local name desc
    name=$(extract_field "$f" "name")
    [[ -z "$name" ]] && continue
    desc=$(extract_field "$f" "description")
    desc=$(sanitise "$desc")
    printf '| `%s` | skill:%s | %s |\n' "$name" "$name" "$desc"
  done < <(find -L "$SKILLS_DIR" -maxdepth 2 -name 'SKILL.md' ! -path '*/_template*/*' | LC_ALL=C sort)
}

build_agents_table() {
  printf '| Intent (agent) | Target | Cuándo usar |\n'
  printf '|---|---|---|\n'
  while IFS= read -r f; do
    [[ -f "$f" ]] || continue
    [[ "$(basename "$f")" == "README.md" ]] && continue
    local name desc
    name=$(extract_field "$f" "name")
    [[ -z "$name" ]] && continue
    desc=$(extract_field "$f" "description")
    desc=$(sanitise "$desc")
    printf '| `%s` | agent:%s | %s |\n' "$name" "$name" "$desc"
  done < <(find -L "$AGENTS_DIR" -maxdepth 1 -type f -name '*.md' | LC_ALL=C sort)
}

build_auto_block() {
  printf '%s\n\n' "$AUTO_BEGIN"
  printf '### Skills (%d)\n\n' "$(find -L "$SKILLS_DIR" -maxdepth 2 -name 'SKILL.md' ! -path '*/_template*/*' | wc -l)"
  build_skills_table
  printf '\n### Agents (%d)\n\n' "$(find -L "$AGENTS_DIR" -maxdepth 1 -type f -name '*.md' ! -name 'README.md' | wc -l)"
  build_agents_table
  printf '\n%s\n' "$AUTO_END"
}

build_full_default() {
  cat <<'HEADER'
# RESOLVER.md — Intent dispatch table

> **Patrón GBrain RESOLVER.md** (SE-160). Tabla explícita intent → skill/agent que reduce la carga del contexto central y hace el routing editable sin prompt engineering.
>
> **Fuente de verdad**: la sección AUTO se regenera desde `.opencode/skills/*/SKILL.md` y `.opencode/agents/*.md`. La sección OVERRIDE es hand-curated y se preserva entre regeneraciones.

## Cómo se usa

1. Buscas el intent (palabra/frase) en la columna izquierda.
2. Saltas al target indicado: `skill:<nombre>` o `agent:<nombre>`.
3. Si tu intent no aparece, busca en OVERRIDE — sinónimos comunes mapeados a mano.
4. Si sigue sin estar, abre PR contra OVERRIDE añadiéndolo.

**No es un router automático**: es un índice. El frontend (Claude Code, OpenCode) selecciona el target final aplicando su propio matcher; esta tabla es la referencia compartida que evita re-explicar el routing en cada turno.

## OVERRIDE — sinónimos y aliases (hand-curated)

> Esta sección NO se auto-genera. Edita libremente. Mapea términos comunes / sinónimos en español/inglés al target canónico.

> Agrupada por capacidad (SE-483): metaorquestación, investigación, conocimiento, desarrollo y proyectos.

### Metaorquestación (harnesses y agentes)

| Sinónimo / alias | Target canónico | Notas |
|---|---|---|
| "orquestar agentes", "harness", "metaharness", "bucle de agentes" | skill:harness-architecture | Diseño antes que ejecución |
| "lanzar en paralelo", "repartir trabajo entre agentes" | skill:parallel-dispatch | |
| "plan con dependencias", "DAG de agentes" | skill:dag-scheduling | |
| "estado del run", "board de runs" | skill:agent-runs-board | |
| "tribunal", "segunda opinión", "validar por panel" | skill:consensus-validation | |
| "revisión por tribunal", "Code Review Court" | agent:court-orchestrator | E1 SIEMPRE humano (Rule 8) |
| "noche autónoma", "overnight", "tareas mientras duermo" | skill:overnight-sprint | Doble opt-in SPEC-186 |
| "Anthropic caído", "failover local", "LocalAI" | skill:emergency-mode | |
| "buscar comando", "qué comando uso", "router" | skill:smart-routing | Para descubrir entre 559+ comandos |

### Investigación

| Sinónimo / alias | Target canónico | Notas |
|---|---|---|
| "investiga", "experimento", "hipótesis", "preregistro" | skill:savia-labs | |
| "investigación técnica", "evaluar herramienta nueva" | skill:tech-research-agent | Doble opt-in SPEC-186 |
| "buscar en la web", "estado del arte" | skill:web-research | |

### Conocimiento

| Sinónimo / alias | Target canónico | Notas |
|---|---|---|
| "cúpula", "vault", "conocimiento gobernado" | skill:savia-vaults | |
| "diseñar cúpula", "auditar cúpula" | agent:context-dome-manager | |
| "memoria de Savia", "recordar", "consolidar memoria" | skill:savia-memory | |
| "grafo de conocimiento", "impacto entre specs" | skill:knowledge-graph | |
| "reunión Teams", "transcripción", "acta" | skill:meeting-transcript-extract | Triage al digester correcto post-extract |

### Desarrollo

| Sinónimo / alias | Target canónico | Notas |
|---|---|---|
| "diseñar arquitectura", "architecture", "decisión técnica" | agent:architect | |
| "implementar en C#", ".NET", "EF Core" | agent:dotnet-developer | Requiere Spec SDD aprobada |
| "implementar en Python", "FastAPI", "Django" | agent:python-developer | |
| "revisar código", "code review", "quality gate" | agent:code-reviewer | E1 SIEMPRE humano (Rule 8) |
| "tests faltantes", "cobertura", "test runner" | agent:test-runner | |
| "antes de commit", "pre-commit", "guardian" | agent:commit-guardian | Bloqueante por defecto |
| "auditar seguridad", "red team / blue team" | skill:adversarial-security | Doble opt-in SPEC-186 |

### Proyectos (dominio de gestión de proyectos)

| Sinónimo / alias | Target canónico | Notas |
|---|---|---|
| "estado del sprint", "sprint status", "cómo va el sprint" | skill:sprint-management | |
| "informe semanal", "weekly", "weekly report" | skill:weekly-report | |
| "imputaciones", "horas", "timesheet" | skill:time-tracking-report | |
| "tabla de horas", "Excel imputación" | skill:time-tracking-report | |
| "facturas", "presupuesto", "coste" | skill:cost-management | |
| "descomponer PBI", "split PBI", "tareas de un PBI" | skill:pbi-decomposition | Antes de descomponer, usar `skill:product-discovery` |
| "PRD", "discovery", "JTBD" | skill:product-discovery | Pre-requisito de pbi-decomposition |

## AUTO — generado desde frontmatter

> Esta sección la regenera `bash scripts/resolver-md-generate.sh --apply`. NO editar a mano.

HEADER
  build_auto_block
}

extract_auto_block() {
  awk -v begin="$AUTO_BEGIN" -v end="$AUTO_END" '
    $0 == begin { inside = 1; print; next }
    $0 == end   { inside = 0; print; exit }
    inside       { print }
  ' "$1"
}

GENERATED_FULL=$(build_full_default)
GENERATED_AUTO=$(printf '%s' "$GENERATED_FULL" | extract_auto_block /dev/stdin 2>/dev/null || build_auto_block)

case "$MODE" in
  generate)
    printf '%s' "$GENERATED_FULL"
    ;;
  apply)
    if [[ -f "$TARGET" ]] && grep -qF "$AUTO_BEGIN" "$TARGET"; then
      tmp=$(mktemp)
      awk -v begin="$AUTO_BEGIN" -v end="$AUTO_END" -v repl="$(build_auto_block)" '
        $0 == begin { print repl; skipping = 1; next }
        skipping && $0 == end { skipping = 0; next }
        !skipping { print }
      ' "$TARGET" > "$tmp"
      mv "$tmp" "$TARGET"
      echo "updated AUTO block in $TARGET"
    else
      tmp=$(mktemp)
      printf '%s' "$GENERATED_FULL" > "$tmp"
      mkdir -p "$(dirname "$TARGET")"
      mv "$tmp" "$TARGET"
      echo "wrote new $TARGET"
    fi
    ;;
  check)
    if [[ ! -f "$TARGET" ]]; then
      echo "drift: $TARGET missing — run --apply" >&2
      exit 1
    fi
    expected=$(build_auto_block)
    actual=$(awk -v begin="$AUTO_BEGIN" -v end="$AUTO_END" '
      $0 == begin { inside=1 }
      inside { print }
      $0 == end { exit }
    ' "$TARGET")
    if [[ "$expected" == "$actual" ]]; then
      echo "in sync"
    else
      echo "drift detected in AUTO block of $TARGET" >&2
      diff <(printf '%s' "$expected") <(printf '%s' "$actual") | head -30 >&2 || true
      exit 1
    fi
    ;;
esac
