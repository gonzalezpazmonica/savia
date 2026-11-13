#!/usr/bin/env bash
# SE-529 S0.1/S0.2 — sonda de un solo uso: fuerza /compact con `claude -p` en un directorio
# desechable, con el colector de forma activo y dos marcas aleatorias sin significado
# (una por la salida de PostCompact, otra por la de SessionStart origen compact).
# Pregunta en el turno siguiente qué marcas ve el modelo. No toca settings.json:
# usa --settings con un fichero temporal. Cuesta tokens (modelo haiku por defecto).
# Uso: compaction-shape-probe.sh [--rounds N] [--model M] [--out DIR] [--dry-run]
set -uo pipefail
ROUNDS=3; MODEL=haiku; OUT=""; DRY=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --rounds) ROUNDS="$2"; shift 2 ;;
    --model) MODEL="$2"; shift 2 ;;
    --out) OUT="$2"; shift 2 ;;
    --dry-run) DRY=1; shift ;;
    *) echo "uso: $0 [--rounds N] [--model M] [--out DIR] [--dry-run]" >&2; exit 2 ;;
  esac
done
[[ "$ROUNDS" =~ ^[0-9]+$ ]] || { echo "rounds debe ser entero" >&2; exit 2; }
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COL="$HERE/compaction-shape-collector.py"
OUT="${OUT:-$(mktemp -d)}"; mkdir -p "$OUT/work" "$OUT/hooks"
LOG="$OUT/shape.jsonl"

mk_hook() { # $1 nombre $2 evento $3 fichero-marca|""
  local f="$OUT/hooks/$1.sh"
  {
    echo '#!/bin/bash'
    echo "cat | SAVIA_COMPACT_SHAPE=1 SAVIA_COMPACT_SHAPE_LOG='$LOG' python3 -I '$COL' --event $2 --frontend claude-code"
    [[ -n "$3" ]] && echo "printf 'ZMK-%s\\n' \"\$(cat '$3')\""
  } > "$f"; chmod +x "$f"; echo "$f"
}
M1="$OUT/m1"; M2="$OUT/m2"
H_PRE=$(mk_hook pre PreCompact ""); H_POST=$(mk_hook post PostCompact "$M1")
H_SC=$(mk_hook sc SessionStart "$M2"); H_SS=$(mk_hook ss SessionStart "")
cat > "$OUT/settings.json" <<J
{"hooks":{
"PreCompact":[{"hooks":[{"type":"command","command":"$H_PRE"}]}],
"PostCompact":[{"hooks":[{"type":"command","command":"$H_POST"}]}],
"SessionStart":[{"matcher":"compact","hooks":[{"type":"command","command":"$H_SC"}]},
 {"matcher":"startup","hooks":[{"type":"command","command":"$H_SS"}]},
 {"matcher":"resume","hooks":[{"type":"command","command":"$H_SS"}]}]}}
J
if [[ $DRY -eq 1 ]]; then cat "$OUT/settings.json"; exit 0; fi
command -v claude >/dev/null || { echo "claude no disponible" >&2; exit 1; }
printf 'round\tpostcompact_mark\tsessionstart_compact_mark\n'
for ((i=1;i<=ROUNDS;i++)); do
  openssl rand -hex 6 > "$M1"; openssl rand -hex 6 > "$M2"
  SID=$(python3 -c 'import uuid;print(uuid.uuid4())')
  C=(claude -p --model "$MODEL" --settings "$OUT/settings.json")
  ( cd "$OUT/work" || exit 1
    timeout 150 "${C[@]}" --session-id "$SID" "Responde solo: ok. Dato de prueba: el color es azul." </dev/null >/dev/null 2>&1
    timeout 200 "${C[@]}" --resume "$SID" "/compact" </dev/null >/dev/null 2>&1
    timeout 150 "${C[@]}" --resume "$SID" "Lista cada cadena con patron ZMK- y 12 hex visible en tu contexto, sin adivinar. Si no ves ninguna, di NINGUNA." </dev/null > "$OUT/answer-$i.txt" 2>&1 )
  a=no; b=no
  grep -q "ZMK-$(cat "$M1")" "$OUT/answer-$i.txt" && a=si
  grep -q "ZMK-$(cat "$M2")" "$OUT/answer-$i.txt" && b=si
  printf '%s\t%s\t%s\n' "$i" "$a" "$b"
done
echo "registro de forma: $LOG" >&2
