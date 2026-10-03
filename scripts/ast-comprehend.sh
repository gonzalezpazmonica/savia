#!/bin/bash
# ast-comprehend.sh — Extractor estructural multi-lenguaje (ast-comprehension skill)
# Uso: ast-comprehend.sh <target> [--surface-only] [--legacy-mode] [--output <path>]
# Salida: JSON unificado en stdout (o en --output si se especifica).
#   Fichero → objeto {meta, structure, complexity, summary}; directorio → array.
# Exit: 0 ok · 1 target ausente o inexistente, o --output no escribible · 2 argumento invalido
#       · 3 algun fichero no se pudo leer o analizar (su structure.error lo dice; el JSON se emite igual).
# Requiere python3 (construye el JSON). tree-sitter, ts-morph y gopls son opcionales.
set -uo pipefail

TARGET="${1:-}"
SURFACE_ONLY=false
LEGACY_MODE=false   # aceptado por compatibilidad; hoy no cambia la extraccion
OUTPUT_FILE=""

usage_error() {
  python3 -c 'import json,sys; print(json.dumps({"error": sys.argv[1]}))' "$1" >&2
  exit 2
}

# Parsear argumentos
shift || true
while [[ $# -gt 0 ]]; do
  case "$1" in
    --surface-only) SURFACE_ONLY=true ;;
    --legacy-mode)  LEGACY_MODE=true ;;
    --output)
      [[ -n "${2:-}" ]] || usage_error "--output requires a path"
      OUTPUT_FILE="$2"; shift ;;
    *) usage_error "Unknown argument: $1" ;;
  esac
  shift
done
export LEGACY_MODE

if [[ -z "$TARGET" ]]; then
  echo '{"error":"No target specified. Usage: ast-comprehend.sh <file|dir>"}' >&2
  exit 1
fi

# ── Utilidades ────────────────────────────────────────────────────────────────

detect_language() {
  local file="$1"
  local ext="${file##*.}"
  case "$ext" in
    cs|csproj|sln) echo "csharp" ;;
    ts|mts|cts)    echo "typescript" ;;
    tsx)           echo "typescript" ;;
    js|jsx|mjs)    echo "javascript" ;;
    py)            echo "python" ;;
    go)            echo "go" ;;
    rs)            echo "rust" ;;
    java)          echo "java" ;;
    php)           echo "php" ;;
    rb)            echo "ruby" ;;
    swift)         echo "swift" ;;
    kt|kts)        echo "kotlin" ;;
    dart)          echo "dart" ;;
    tf|tfvars|hcl) echo "terraform" ;;
    *)             echo "unknown" ;;
  esac
}

count_lines() {
  local n
  n=$(wc -l < "$1" 2>/dev/null) || n=0
  echo "${n// /}"
}

# grep -c imprime 0 y sale con 1 cuando no hay coincidencias: no anadir otro "0".
count_complexity() {
  local n
  n=$(grep -cE \
    "(if[[:space:]]*\(|else if[[:space:]]*\(|for[[:space:]]*\(|while[[:space:]]*\(|switch[[:space:]]*\(|\bcase\b|\bcatch\b|\&\&|\|\||\?[^:])" \
    "$1" 2>/dev/null)
  echo "${n:-0}"
}

# ── Extraccion grep-structural (fallback universal; regex sin gawk) ───────────

grep_structural_extract() {
  python3 - "$1" <<'PYEOF'
import json, re, sys

CLASS_RE = re.compile(
    r"^\s*(?:(?:public|private|protected|internal|abstract|sealed|static|final|export|default|data|open|pub(?:\([a-z]+\))?)\s+)*"
    r"(?:class|interface|struct|enum|trait)\s+([A-Za-z_]\w*)")
GO_TYPE_RE = re.compile(r"^\s*type\s+([A-Za-z_]\w*)\s+(?:struct|interface)\b")
FUNC_RE = re.compile(
    r"^\s*(?:(?:public|private|protected|internal|static|async|export|default|pub(?:\([a-z]+\))?|override|final)\s+)*"
    r"(?:def|fn|func|function)\s+(?:\([^)]*\)\s*)?([A-Za-z_]\w*)")
METHOD_RE = re.compile(
    r"^\s*(?:public|private|protected|internal)\s+(?:[\w<>\[\],?]+\s+)*([A-Za-z_]\w*)\s*\(")
IMPORT_RE = re.compile(r"^(?:import|from|require|use|using|include|#include|extern crate)\s+")

classes, functions, imports = [], [], []
with open(sys.argv[1], encoding="utf-8", errors="replace") as fh:
    for lineno, line in enumerate(fh, 1):
        text = line.rstrip("\n")
        m = CLASS_RE.match(text) or GO_TYPE_RE.match(text)
        if m:
            classes.append({"name": m.group(1), "line": lineno})
            continue
        m = FUNC_RE.match(text) or METHOD_RE.match(text)
        if m:
            functions.append({"name": m.group(1), "line": lineno})
            continue
        if IMPORT_RE.match(text):
            imports.append(text.strip())
print(json.dumps({"classes": classes, "functions": functions, "imports": imports}))
PYEOF
}

# ── Extraccion Python (ast module nativo) ─────────────────────────────────────

python_extract() {
  python3 - "$1" 2>/dev/null <<'PYEOF'
import ast, json, sys

def analyze(path):
    with open(path, encoding="utf-8", errors="replace") as f:
        src = f.read()
    try:
        tree = ast.parse(src)
    except SyntaxError as e:
        return {"classes": [], "functions": [], "imports": [], "error": str(e)}

    classes, functions, imports = [], [], []
    for node in ast.walk(tree):
        if isinstance(node, ast.ClassDef):
            methods = [
                {"name": m.name, "line": m.lineno}
                for m in node.body
                if isinstance(m, (ast.FunctionDef, ast.AsyncFunctionDef))
            ]
            classes.append({"name": node.name, "line": node.lineno, "methods": methods})
        elif isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)):
            functions.append({"name": node.name, "line": node.lineno})
        elif isinstance(node, ast.Import):
            for alias in node.names:
                imports.append(alias.name)
        elif isinstance(node, ast.ImportFrom):
            imports.append(f"from {node.module or ''}")
    functions.sort(key=lambda f: f["line"])
    return {"classes": classes, "functions": functions, "imports": imports}

print(json.dumps(analyze(sys.argv[1])))
PYEOF
}

# ── Extraccion TypeScript via ts-morph (falla si no esta instalado) ───────────

typescript_extract() {
  node -e "require('ts-morph')" 2>/dev/null || return 1
  # La ruta viaja por argv, nunca interpolada en el codigo JS.
  node -e '
const { Project } = require("ts-morph");
const p = new Project({ addFilesFromTsConfig: false, skipLoadingLibFiles: true });
const sf = p.addSourceFileAtPath(process.argv[1]);
console.log(JSON.stringify({
  classes: sf.getClasses().map(c => ({
    name: c.getName() || "anonymous",
    line: c.getStartLineNumber(),
    methods: c.getMethods().map(m => ({name: m.getName(), line: m.getStartLineNumber()}))
  })),
  functions: sf.getFunctions().map(f => ({name: f.getName() || "anonymous", line: f.getStartLineNumber()})),
  imports: sf.getImportDeclarations().map(i => i.getModuleSpecifierValue())
}));
' "$1" 2>/dev/null
}

# ── Extraccion Go via gopls (falla si no esta instalado) ──────────────────────

go_extract() {
  command -v gopls &>/dev/null || return 1
  gopls symbols "$1" 2>/dev/null | python3 -c '
import json, sys
classes, functions = [], []
for raw in sys.stdin:
    parts = raw.split()
    if len(parts) < 3:
        continue
    name, kind, rng = parts[0], parts[1], parts[2]
    head = rng.split(":")[0]
    line = int(head) if head.isdigit() else 0
    if kind in ("Struct", "Interface", "Class"):
        classes.append({"name": name, "line": line})
    elif kind in ("Function", "Method"):
        functions.append({"name": name.split(".")[-1], "line": line})
if not classes and not functions:
    sys.exit(1)
print(json.dumps({"classes": classes, "functions": functions, "imports": []}))
'
}

# ── Tree-sitter universal ─────────────────────────────────────────────────────

treesitter_extract() {
  command -v tree-sitter &>/dev/null || return 1
  tree-sitter parse "$1" --output json 2>/dev/null | python3 -c '
import sys, json
def extract_structure(node, result):
    node_type = node.get("type", "")
    if node_type in ("class_definition", "class_declaration", "class_specifier"):
        name_node = next((c for c in node.get("children", [])
                         if c.get("type") in ("identifier", "name", "type_identifier")), None)
        if name_node:
            result["classes"].append({
                "name": name_node.get("text", ""),
                "line": node.get("startPosition", {}).get("row", 0) + 1
            })
    if node_type in ("function_definition", "function_declaration",
                     "method_definition", "function_item", "method_declaration"):
        name_node = next((c for c in node.get("children", [])
                         if c.get("type") == "identifier"), None)
        if name_node:
            result["functions"].append({
                "name": name_node.get("text", ""),
                "line": node.get("startPosition", {}).get("row", 0) + 1
            })
    for child in node.get("children", []):
        extract_structure(child, result)
    return result
tree = json.load(sys.stdin)
print(json.dumps(extract_structure(tree, {"classes": [], "functions": [], "imports": []})))
' 2>/dev/null
}

# ── Procesar un fichero ───────────────────────────────────────────────────────

# Emite el objeto JSON del fichero. Devuelve 3 si no se pudo leer ni extraer:
# un analisis imposible nunca se presenta como "0 clases" con exito.
process_file() {
  local file="$1"
  local lang lines tool_used="" structure_json="" result="" rc=0
  lang=$(detect_language "$file")

  if [[ ! -r "$file" ]]; then
    echo "ast-comprehend: no se puede leer $file" >&2
    emit_file_json "$file" "$lang" 0 "none" 0 '{"error": "unreadable"}'
    return 3
  fi
  lines=$(count_lines "$file")

  # Capa 1: tree-sitter. Capa 2: herramienta nativa semantica. Capa 3: grep.
  if [[ "$SURFACE_ONLY" == "false" ]]; then
    if result=$(treesitter_extract "$file") && [[ -n "$result" ]]; then
      structure_json="$result"; tool_used="tree-sitter"
    else
      case "$lang" in
        python)
          if result=$(python_extract "$file") && [[ -n "$result" ]]; then
            structure_json="$result"; tool_used="python-ast"
          fi ;;
        typescript|javascript)
          if result=$(typescript_extract "$file") && [[ -n "$result" ]]; then
            structure_json="$result"; tool_used="ts-morph"
          fi ;;
        go)
          if result=$(go_extract "$file") && [[ -n "$result" ]]; then
            structure_json="$result"; tool_used="gopls"
          fi ;;
      esac
    fi
  fi

  if [[ -z "$structure_json" ]]; then
    tool_used="grep-structural"
    if ! structure_json=$(grep_structural_extract "$file") || [[ -z "$structure_json" ]]; then
      echo "ast-comprehend: la extraccion grep-structural fallo en $file" >&2
      structure_json='{"error": "extraction failed"}'
      rc=3
    fi
  fi

  local complexity
  complexity=$(count_complexity "$file")

  emit_file_json "$file" "$lang" "$lines" "$tool_used" "$complexity" "$structure_json" || rc=3
  return "$rc"
}

# emit_file_json <file> <lang> <lines> <tool> <complexity> <structure-json>
emit_file_json() {
  STRUCTURE_JSON="$6" python3 -c '
import json, os, sys
file_path, lang, lines, tool, complexity = sys.argv[1:6]
lines, complexity = int(lines or 0), int(complexity or 0)
try:
    structure = json.loads(os.environ.get("STRUCTURE_JSON") or "{}")
except ValueError as e:
    structure = {"error": "invalid extractor output: %s" % e}
for key in ("classes", "functions", "imports"):
    structure.setdefault(key, [])
n_cls, n_fn = len(structure["classes"]), len(structure["functions"])
if structure.get("error") in ("unreadable", "extraction failed"):
    summary = ("No se pudo leer el fichero %s (%s): %s. La estructura vacía no significa "
               "que no tenga símbolos." % (os.path.basename(file_path), lang, structure["error"]))
else:
    summary = ("Fichero %s (%s). %d clase(s), %d función(es). Complejidad ciclomática "
               "aproximada: %d puntos de decisión." % (os.path.basename(file_path), lang,
                                                        n_cls, n_fn, complexity))
print(json.dumps({
    "meta": {"file": file_path, "language": lang, "lines": lines, "tool": tool},
    "structure": structure,
    "complexity": {"total_decision_points": complexity,
                   "hotspots": [{"warn": complexity > 15, "total": complexity}]},
    "summary": summary,
}, ensure_ascii=False, indent=2))
' "$1" "$2" "$3" "$4" "$5"
}

# ── Procesar directorio ───────────────────────────────────────────────────────

process_directory() {
  local dir="$1"
  local results=()
  local extensions="cs|ts|tsx|js|jsx|py|go|rs|java|php|rb|swift|kt|dart|tf"
  local file entry rc=0

  while IFS= read -r -d '' file; do
    entry=$(process_file "$file") || rc=3
    # Una entrada vacia romperia el array ("[,{...}]"): se registra y se omite.
    if [[ -z "$entry" ]]; then
      echo "ast-comprehend: sin salida para $file" >&2
      rc=3
      continue
    fi
    results+=("$entry")
  done < <(find "$dir" -type f -regextype posix-extended \
    -regex ".*\.(${extensions})$" \
    ! -path "*/node_modules/*" \
    ! -path "*/.git/*" \
    ! -path "*/vendor/*" \
    ! -path "*/dist/*" \
    -print0 2>/dev/null | sort -z)

  local joined
  joined=$(IFS=','; echo "${results[*]:-}")
  echo "[${joined}]"
  return "$rc"
}

# ── Punto de entrada principal ────────────────────────────────────────────────

main() {
  local output rc=0
  if [[ -n "$OUTPUT_FILE" && -d "$OUTPUT_FILE" ]]; then
    usage_error "--output is a directory: $OUTPUT_FILE"
  fi
  if [[ -f "$TARGET" ]]; then
    output=$(process_file "$TARGET") || rc=$?
  elif [[ -d "$TARGET" ]]; then
    output=$(process_directory "$TARGET") || rc=$?
  else
    python3 -c 'import json,sys; print(json.dumps({"error": "Target not found: " + sys.argv[1]}))' "$TARGET" >&2
    exit 1
  fi

  if [[ -n "$OUTPUT_FILE" ]]; then
    mkdir -p "$(dirname "$OUTPUT_FILE")"
    # Escritura atomica: tmp en el mismo directorio + mv (escritores concurrentes).
    local tmp
    tmp=$(mktemp "${OUTPUT_FILE}.XXXXXX") || { echo "Cannot write $OUTPUT_FILE" >&2; exit 1; }
    if ! { echo "$output" > "$tmp" && mv -f "$tmp" "$OUTPUT_FILE"; }; then
      rm -f "$tmp"
      echo "Cannot write $OUTPUT_FILE" >&2
      exit 1
    fi
    echo "Comprehension report saved: $OUTPUT_FILE" >&2
  else
    echo "$output"
  fi
  return "$rc"
}

main
exit $?
