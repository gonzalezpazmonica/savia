#!/bin/bash
set -uo pipefail
# block-force-push.sh — Bloquea git push --force y commits directos a main
# Usado por: commit-guardian (PreToolUse hook)
# Profile tier: security

LIB_DIR="$(dirname "${BASH_SOURCE[0]}")/lib"
if [[ -f "$LIB_DIR/profile-gate.sh" ]]; then
  # shellcheck source=/dev/null
  source "$LIB_DIR/profile-gate.sh" && profile_gate "security"
fi

# Read stdin with timeout to avoid hanging if no input arrives
# Uses timeout+cat to handle input that may lack trailing newline
INPUT=""
if INPUT=$(timeout 3 cat 2>/dev/null); then
  :
fi

# SE-453 S2: sin jq se degrada a un parseo con grep; si tampoco se puede evaluar, sale 2 (nunca 0 sin evaluar).
# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/lib/hook-input.sh"
hook_extract_command "$INPUT" || exit 2
COMMAND="$HOOK_COMMAND"

if [ -z "$COMMAND" ]; then
  exit 0
fi
# Revisión #1355: las continuaciones «\⏎» se unen antes de evaluar (grep evalúa por línea y un
# git push partido en dos líneas pasaba); el puerto TS hace lo mismo y también evalúa por línea.
# Solo continúa la barra impar: en «\\⏎» la barra es literal y el salto separa órdenes (4.ª revisión), así
# que los pares «\\» se apartan antes de unir y se reponen después.
# Revisión #1355 (6.ª): la orden tal cual también se evalúa (ver el final): la unión no siempre es lo que
# hace el shell (un comentario acabado en «\» no continúa y la línea siguiente se ejecuta).
COMMAND_RAW="$COMMAND"
_BS2='\\'
COMMAND="${COMMAND//"$_BS2"/$'\x02'}"
# \⏎ desaparece sin dejar espacio (git comm\⏎it, git pu\⏎sh): se evalúan las dos uniones, con y sin espacio.
COMMAND_NOSP="${COMMAND//$'\\\n'/}"; COMMAND_NOSP="${COMMAND_NOSP//$'\x02'/"$_BS2"}"
COMMAND="${COMMAND//$'\\\n'/ }"; COMMAND="${COMMAND//$'\x02'/"$_BS2"}"

# Inicio de una orden git real: al principio de una línea, tras un separador, al abrir un subshell o
# dentro de `bash -c "…"`/`bash -lc`/`sh -c '…'`/`fish`/`tcsh`/`csh -c`/`script -qc`/`eval`/`su -c '…'`/`ssh host '…'`/
# `find -exec`, con lo que puede ir delante (VAR=valor, los envoltorios env, command, sudo, doas, pkexec, runuser,
# nohup, time, exec, xargs, nice, ionice, stdbuf, setsid, timeout, strace, ltrace, unbuffer y watch con sus opciones
# —`sudo -u x`, `env -i`, `timeout -s KILL 30`—, chroot y flock con su argumento posicional —`chroot /`,
# `flock fichero`—, then, do, if, !, {), una ruta o una barra
# invertida delante de git (`/usr/bin/git`, `\git`) y opciones globales de git (-C dir, -c clave=valor,
# --no-pager…). Una mención dentro de un mensaje o de un echo no casa.
# Sin `\b`: es extensión GNU y BSD grep (macOS) puede no reconocerla; `(^|[^[:alnum:]_])` vale en los dos.
# Una bandera corta combinada con f (`-fu`, `-uf`) fuerza igual que `-f`.
# grep evalúa línea a línea: una orden en la línea 2 de un bloque multilínea también casa (SE-453).
# El puerto TS (.opencode/plugins/guards/block-force-push.ts) lleva la misma gramática con el flag m, escrita
# sin ambigüedades para que V8 no se cuelgue en vueltas atrás (grep no tiene ese problema).
GIT_AT='(^|[;&|(`]|\$\(|[[:space:]]-exec(dir)?[[:space:]]|(^|[^[:alnum:]_])(((ba|z|da|k|t?c|fi)?sh|script)([[:space:]]+-[A-Za-z]+)*[[:space:]]+-[A-Za-z]*c|eval|su([[:space:]]+(-[A-Za-z-]*|[^-[:space:]"'"'"'][^[:space:]]*))*[[:space:]]+(-[A-Za-z]*c|--command)|ssh([[:space:]]+-[^[:space:]]+([[:space:]]+[^-[:space:]][^[:space:]]*)?)*[[:space:]]+[^-[:space:]"'"'"'][^[:space:]]*)[[:space:]]+["'"'"']?)[[:space:]]*(([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*|(env|command|sudo|doas|pkexec|runuser|nohup|time|exec|xargs|nice|ionice|stdbuf|setsid|timeout|strace|ltrace|unbuffer|watch)([[:space:]]+-[^[:space:]]+([[:space:]]+[^-[:space:]][^[:space:]]*)?)*|timeout[[:space:]]+[^[:space:]]+|(flock|chroot)([[:space:]]+-[^[:space:]]+)*[[:space:]]+[^-[:space:]][^[:space:]]*|[0-9][0-9.]*[smhd]?|then|do|else|if|elif|while|until|!|\{)[[:space:]]+)*(\\|[^[:space:]]*/)?git(([[:space:]]+(-C|-c|--git-dir|--work-tree|--namespace|--config-env|--attr-source|--super-prefix)[[:space:]]+(\"[^\"]*\"|'"'"'[^'"'"']*'"'"'|[^-[:space:]][^[:space:]]*))|([[:space:]]+--?[A-Za-z][A-Za-z-]*(=[^[:space:]]+)?))*[[:space:]]+'
# Fin de una opción o de un nombre de rama: espacio, fin de línea, separador o cierre de comillas.
END='([[:space:]]|$|[;&|)"'"'"'`])'
# main/master como destino de un push de esta misma orden (sin cruzar ;, & ni |): palabra suelta o tras
# `:` o `+` de un refspec, o tras refs/heads/ o refs/remotes/<remoto>/ (`HEAD:main`, `+main`,
# `refs/heads/main`, `heads/main` —git lo resuelve a refs/heads/main—, `main:main`); `main-fix` y
# `feature/main` no casan.
PUSH_MAIN='push[[:space:]]+([^;&|]*([[:space:]:+"'"'"']|(refs/|[[:space:]:+"'"'"'])heads/|refs/remotes/[^/[:space:]]+/))?(main|master)([[:space:]:]|$|[;&|)"'"'"'`])'
# main/master como destino: palabra suelta o tras `:`, `+` o `/` de un refspec; `main-fix` no casa.
MAIN_REF='(^|[[:space:]:+"'"'"']|(refs/|[[:space:]:+"'"'"'])heads/|refs/remotes/[^/[:space:]]+/)(main|master)([[:space:]:;&|)"'"'"'`]|$)'

_push_checks() { # $1 = orden con las continuaciones ya unidas → sale 2 si bloquea
  local COMMAND="$1" IS_FORCE_WITH_LEASE=no IS_BARE_FORCE=no IS_PUSH_TO_MAIN=no
# Bloquear force push (permite --force-with-lease en ramas no-main)
# --force-with-lease es más seguro: falla si el remoto avanzó sin nuestro conocimiento.
# Requerido en flujo de rebase de PRs en cola (SPEC-105).

if echo "$COMMAND" | grep -iE "${GIT_AT}push[[:space:]]+.*--force-with-lease" > /dev/null; then
  IS_FORCE_WITH_LEASE=yes
fi
if echo "$COMMAND" | grep -iE "${GIT_AT}push[[:space:]]+([^;&|]*[[:space:]])?((--force|--mirror|-[A-Za-z]*f[A-Za-z]*)${END}|[\"']?\+[^[:space:]])" > /dev/null; then
  IS_BARE_FORCE=yes
fi
# Sin GIT_AT a propósito: solo cuenta junto a IS_FORCE_WITH_LEASE (anclado), así que el lease y la mención de
# main pueden estar en órdenes distintas de la misma línea (lado seguro). No «arreglarlo» sin probar la paridad TS.
# --all actualiza también main sin nombrarla; con lease cuenta como push a main.
if echo "$COMMAND" | grep -iE "git[[:space:]]+push[[:space:]]+(.*${MAIN_REF}|([^;&|]*[[:space:]])?--all${END})" > /dev/null; then
  IS_PUSH_TO_MAIN=yes
fi

# Bare --force (o refspec `+rama` o --mirror, que fuerzan igual: --mirror fuerza y borra refs remotas) siempre
# bloqueado. Un --force-with-lease en otra orden u otra línea no lo excusa, y en la misma orden --force anula el
# lease (SE-453, revisión #1355): la regex de force no casa con --force-with-lease, así que un yes aquí es real.
if [[ "$IS_BARE_FORCE" == "yes" ]]; then
  echo "BLOQUEADO: git push --force no está permitido. Usa --force-with-lease." >&2
  exit 2
fi

# --force-with-lease a main/master bloqueado (solo permitido en ramas feature)
if [[ "$IS_FORCE_WITH_LEASE" == "yes" && "$IS_PUSH_TO_MAIN" == "yes" ]]; then
  echo "BLOQUEADO: --force-with-lease a main/master no permitido." >&2
  exit 2
fi

# Bloquear push directo a main/master
# FIX: Add anchoring for compound command separators
if echo "$COMMAND" | grep -iE "${GIT_AT}${PUSH_MAIN}" > /dev/null; then
  echo "BLOQUEADO: Push directo a main/master no permitido. Usa rama + PR." >&2
  exit 2
fi

}

# Bloquear commit --amend sin confirmación explícita
# SE-453 (revisión #1355): --amend tiene que ser un argumento propio de ese git commit. Un tokenizador
# de shell (comillas, escapes, $(…), <(…), `…`, redirecciones como 2>&1, comentarios) parte la orden en
# órdenes simples; la regex de palabras se cortaba en $( o & y dejaba pasar --amend. Espejo de amendScan
# en .opencode/plugins/guards/block-force-push.ts: mismas reglas, mismos resultados.
# git acepta prefijos únicos de opciones largas: --am, --ame y --amen también son --amend.
# Revisión #1355 (3.ª): el tokenizador no expande, así que una palabra «opaca» (sustitución sin comillas,
# ${…}, $'…' con escapes o llaves con , o ..) lleva delante la marca \x01 y casa por subcadena: si contiene
# --am tras commit (y no es el valor de -m, -F…), bloquea, como hacía la regex vieja. git puede ir tras
# cualquier prefijo (sudo -u x, timeout 5, xargs, ssh host…), y el texto que reciben bash -c, sh -c, eval
# o ssh se tokeniza otra vez como orden propia, con el mismo presupuesto y el mismo tope de anidamiento.
# Revisión #1355 (6.ª): la exención de -m/-F solo vale si la expansión iba entre comillas dobles. Sin comillas
# el shell la parte en palabras (-m $(echo x --amend) ⇒ -m x --amend): esas palabras llevan \x01\x03 y fallan cerrado.
# Revisión #1355 (7.ª): la exención miraba solo la palabra anterior y no sabía si esa palabra ya era el valor de
# otra opción (-m -m "$(echo --amend)" ⇒ git: mensaje «-m» y luego --amend). Ahora los argumentos de commit se
# recorren como los lee git (parse-options, git commit -h): una opción con valor consume la palabra siguiente
# (separada) o el resto de su palabra (-mX, --author=X, -amX); una agrupación corta (-am) se lee letra a letra.
# Criterio de fallo cerrado: una palabra opaca con --am solo queda exenta si es, con certeza, el valor consumido
# por una opción literal conocida y es una sola palabra (entre comillas, sin \x03 ni @: "$@" da 0 o N palabras).
# Si aparece algo que no se sabe leer —palabra opaca fuera de un valor, valor opaco que puede partirse, opción
# desconocida o abreviada (--mess), letra corta desconocida o «--»—, la paridad opción/valor queda desconocida y
# ya no hay exenciones en el resto de la orden. Espejo de commitOpt/gitCommitAmend en el puerto TS.
_AMEND_SHELLS='^(bash|sh|zsh|dash|ksh|ash|mksh|csh|tcsh|fish|script|eval|ssh|su|watch)$'
# Opciones largas con valor obligatorio, y opciones largas sin valor (o con valor opcional, que solo va con =).
_AMEND_LONG_VAL='^--(message|file|reuse-message|reedit-message|fixup|squash|author|date|template|cleanup|trailer|pathspec-from-file|unified|inter-hunk-context)$'
_AMEND_LONG_FLAG='^--(no-)?(quiet|verbose|reset-author|signoff|edit|status|all|include|interactive|patch|only|verify|dry-run|short|branch|ahead-behind|porcelain|long|null|amend|post-rewrite|untracked-files|pathspec-file-nul|gpg-sign|message|file|reuse-message|reedit-message|fixup|squash|author|date|template|cleanup|trailer|pathspec-from-file)$'
# Letras cortas: con valor (m F c C t U), con valor opcional solo pegado (S u) y sin valor.
_AMEND_SHORT_VAL='mFcCtU'; _AMEND_SHORT_OPT='Su'; _AMEND_SHORT_FLAG='qvseaiponz'
_amend_commit_opt() { # palabra literal, con su caja → need=1 si consume la siguiente, unk=1 si no se sabe leer
  local o="$1" nc=0 x ch
  shopt -q nocasematch && nc=1
  shopt -u nocasematch  # git distingue -c de -C y no acepta --MESSAGE
  case "$o" in
    --) unk=1 ;;
    --*=*) [[ "${o%%=*}" =~ $_AMEND_LONG_VAL || "${o%%=*}" =~ $_AMEND_LONG_FLAG ]] || unk=1 ;;
    --*) if [[ "$o" =~ $_AMEND_LONG_VAL ]]; then need=1; elif ! [[ "$o" =~ $_AMEND_LONG_FLAG ]]; then unk=1; fi ;;
    -?*)
      for (( x = 1; x < ${#o}; x++ )); do
        ch="${o:x:1}"
        if [[ "$_AMEND_SHORT_VAL" == *"$ch"* ]]; then (( x + 1 == ${#o} )) && need=1; break
        elif [[ "$_AMEND_SHORT_OPT" == *"$ch"* ]]; then break
        elif [[ "$_AMEND_SHORT_FLAG" != *"$ch"* ]]; then unk=1; break
        fi
      done ;;
  esac
  (( nc )) && shopt -s nocasematch
  return 0
}
_amend_git_commit() { # índice tras git (usa w y n de _amend_is_commit) → 0 si sigue commit … --amend
  local k="$1" s need=0 unk=0
  while (( k < n )) && [[ "${w[k]}" == -* ]]; do
    case "${w[k],,}" in -c|--git-dir|--work-tree|--namespace|--config-env|--attr-source|--super-prefix) k=$((k+1)) ;; esac
    k=$((k+1))
  done
  (( k < n )) || return 1
  # Una palabra opaca se compara sin { } $ ,: -{-,}amend y co${x}mmit también casan.
  s="${w[k],,}"
  [[ "$s" == commit || ( "$s" == $'\x01'* && "${s//[\{\}\$,]/}" == *commit* ) ]] || return 1
  for (( k = k + 1; k < n; k++ )); do
    s="${w[k],,}"
    [[ "$s" =~ ^--am(e(nd?)?)?$ ]] && return 0
    if [[ "$s" == $'\x01'* ]]; then
      # Valor consumido con certeza: una sola palabra (sin \x03 ni @) tras una opción leída sin dudas.
      if (( need && ! unk )) && [[ "$s" != $'\x01\x03'* && "$s" != *@* ]]; then need=0; continue; fi
      [[ "${s//[\{\}\$,]/}" == *--am* ]] && return 0
      need=0; unk=1; continue
    fi
    if (( need )); then need=0; continue; fi
    _amend_commit_opt "${w[k]}"
  done
  return 1
}
_amend_is_commit() { # palabras de una orden simple → 0 es git … commit … --amend, 1 no, 2 no se puede tokenizar
  local -a w=("$@"); local n=$# m b t
  for (( m = 0; m < n; m++ )); do
    b="${w[m]#$'\x01'}"; b="${b#$'\x03'}"; b="${b,,}"; b="${b##*/}"
    if [[ "$b" == git || ( "${w[m]}" == $'\x01'* && "$b" == *git* ) ]]; then
      _amend_git_commit $((m+1)) && return 0
    elif [[ "$b" =~ $_AMEND_SHELLS ]] && (( m + 1 < n )); then
      t="${w[*]:m+1}"; t="${t//$'\x01'/}"; t="${t//$'\x03'/}"
      _amend_scan_text "$t"
      (( AMEND_R == 1 )) && return 0
      (( AMEND_R == 2 )) && return 2
    fi
  done
  return 1
}
_amend_scan_text() { # texto → AMEND_R, tokenizado con su propio AMEND_CH (el de fuera se restaura)
  local -a saved=("${AMEND_CH[@]}"); local c
  AMEND_CH=()
  while IFS= read -r -n1 -d '' c; do AMEND_CH+=("$c"); done < <(printf '%s' "$1")
  _amend_scan 0 "${#AMEND_CH[@]}"
  AMEND_CH=("${saved[@]}")
}
# El tokenizador recorre AMEND_CH (un carácter por elemento) por índices: ${s:i:1} es O(i) en bash
# y una orden de 30 KB tardaba más que el timeout del hook (5 s), que en PreToolUse no bloquea.
# Revisión #1355 (P1): cada nivel de $(…) se vuelve a recorrer al tokenizar su interior, así que el coste es
# O(n·profundidad) y 200 niveles en 1,6 KB tardaban 8-20 s: pasaba sin evaluar. Todo bucle gasta del
# presupuesto AMEND_STEPS y la recursión no pasa de AMEND_MAX_NEST; al agotarse, AMEND_J=-1 / AMEND_R=2
# y la coincidencia gruesa falla cerrado. Mismos topes y mismos puntos de cuenta que el puerto TS.
_amend_close_bq() { # i end → AMEND_J: índice tras la ` de cierre, o -1
  local i="$1" e="$2"
  while (( i < e )); do
    (( ++AMEND_STEPS > AMEND_MAX_STEPS )) && { AMEND_J=-1; return; }
    case "${AMEND_CH[i]}" in
      '\') i=$((i+2)); continue ;;
      '`') AMEND_J=$((i+1)); return ;;
    esac
    i=$((i+1))
  done
  AMEND_J=-1
}
_amend_close_sq() { # i end → AMEND_J: índice tras la ' de cierre, o -1
  local i="$1" e="$2"
  while (( i < e )); do
    (( ++AMEND_STEPS > AMEND_MAX_STEPS )) && { AMEND_J=-1; return; }
    [[ "${AMEND_CH[i]}" == "'" ]] && { AMEND_J=$((i+1)); return; }
    i=$((i+1))
  done
  AMEND_J=-1
}
_amend_close_ansi() { # i end → AMEND_J: índice tras la ' que cierra $'…' (\' no cierra), o -1; AMEND_ESC=1 si hay \
  local i="$1" e="$2"; AMEND_ESC=0
  while (( i < e )); do
    (( ++AMEND_STEPS > AMEND_MAX_STEPS )) && { AMEND_J=-1; return; }
    case "${AMEND_CH[i]}" in
      '\') AMEND_ESC=1; i=$((i+2)); continue ;;
      "'") AMEND_J=$((i+1)); return ;;
    esac
    i=$((i+1))
  done
  AMEND_J=-1
}
_amend_close_dq() { # i end → AMEND_J: índice tras la " de cierre, o -1
  local i="$1" e="$2"
  while (( i < e )); do
    (( ++AMEND_STEPS > AMEND_MAX_STEPS )) && { AMEND_J=-1; return; }
    case "${AMEND_CH[i]}" in
      '\') i=$((i+2)); continue ;;
      '"') AMEND_J=$((i+1)); return ;;
      '$') if [[ "${AMEND_CH[i+1]:-}" == '(' ]]; then _amend_close_subst $((i+2)) "$e"; (( AMEND_J < 0 )) && return; i=$AMEND_J; continue; fi ;;
      '`') _amend_close_bq $((i+1)) "$e"; (( AMEND_J < 0 )) && return; i=$AMEND_J; continue ;;
    esac
    i=$((i+1))
  done
  AMEND_J=-1
}
_amend_close_brace() { # i end → AMEND_J: índice tras la } que cierra un ${ abierto antes de i, o -1
  local i="$1" e="$2" depth=1
  while (( i < e )); do
    (( ++AMEND_STEPS > AMEND_MAX_STEPS )) && { AMEND_J=-1; return; }
    case "${AMEND_CH[i]}" in
      '\') i=$((i+2)); continue ;;
      "'") _amend_close_sq $((i+1)) "$e"; (( AMEND_J < 0 )) && return; i=$AMEND_J; continue ;;
      '"') _amend_close_dq $((i+1)) "$e"; (( AMEND_J < 0 )) && return; i=$AMEND_J; continue ;;
      '`') _amend_close_bq $((i+1)) "$e"; (( AMEND_J < 0 )) && return; i=$AMEND_J; continue ;;
      '$') if [[ "${AMEND_CH[i+1]:-}" == '(' ]]; then _amend_close_subst $((i+2)) "$e"; (( AMEND_J < 0 )) && return; i=$AMEND_J; continue; fi ;;
      '{') depth=$((depth+1)) ;;
      '}') depth=$((depth-1)); (( depth == 0 )) && { AMEND_J=$((i+1)); return; } ;;
    esac
    i=$((i+1))
  done
  AMEND_J=-1
}
_amend_close_subst() { # i end → AMEND_J: índice tras la ) que cierra un $( / <( / >( abierto antes de i, o -1
  (( AMEND_NEST >= AMEND_MAX_NEST )) && { AMEND_J=-1; return; }
  AMEND_NEST=$((AMEND_NEST+1)); _amend_close_subst_in "$@"; AMEND_NEST=$((AMEND_NEST-1))
}
_amend_close_subst_in() {
  local i="$1" e="$2" depth=1
  while (( i < e )); do
    (( ++AMEND_STEPS > AMEND_MAX_STEPS )) && { AMEND_J=-1; return; }
    case "${AMEND_CH[i]}" in
      '\') i=$((i+2)); continue ;;
      '$') if [[ "${AMEND_CH[i+1]:-}" == "'" ]]; then _amend_close_ansi $((i+2)) "$e"; (( AMEND_J < 0 )) && return; i=$AMEND_J; continue; fi ;;
      "'") _amend_close_sq $((i+1)) "$e"; (( AMEND_J < 0 )) && return; i=$AMEND_J; continue ;;
      '"') _amend_close_dq $((i+1)) "$e"; (( AMEND_J < 0 )) && return; i=$AMEND_J; continue ;;
      '`') _amend_close_bq $((i+1)) "$e"; (( AMEND_J < 0 )) && return; i=$AMEND_J; continue ;;
      '(') depth=$((depth+1)) ;;
      ')') depth=$((depth-1)); (( depth == 0 )) && { AMEND_J=$((i+1)); return; } ;;
    esac
    i=$((i+1))
  done
  AMEND_J=-1
}
_amend_word_add() { # i j → añade AMEND_CH[i..j) a la palabra en curso
  local k
  for (( k = $1; k < $2; k++ )); do
    (( ++AMEND_STEPS > AMEND_MAX_STEPS )) && break
    word+="${AMEND_CH[k]}"
  done
  inword=1; redir=0
}
_amend_scan() { # i end → AMEND_R: 1 alguna orden simple es git … commit … --amend, 0 ninguna, 2 no se puede tokenizar
  (( AMEND_NEST >= AMEND_MAX_NEST )) && { AMEND_R=2; return; }
  AMEND_NEST=$((AMEND_NEST+1)); _amend_scan_in "$@"; AMEND_NEST=$((AMEND_NEST-1))
}
_amend_scan_in() {
  # redir=1: la palabra acaba en < o > sin comillas (echo ">"|git … no es una redirección >|).
  # opaque=1: la palabra lleva algo que el shell expande y aquí no se ve (marca \x01); ubrace: { sin comillas.
  # usplit=1: esa expansión va sin comillas y el shell puede partirla en varias palabras (marca \x03).
  local i="$1" n="$2" c j k word="" inword=0 redir=0 opaque=0 ubrace=0 usplit=0
  local -a words=()
  while (( i < n )); do
    (( ++AMEND_STEPS > AMEND_MAX_STEPS )) && { AMEND_R=2; return; }
    c="${AMEND_CH[i]}"
    if [[ "$c" == '\' ]]; then
      if (( i + 1 < n )) && [[ "${AMEND_CH[i+1]}" != $'\n' ]]; then word+="${AMEND_CH[i+1]}"; inword=1; redir=0; fi
      i=$((i+2)); continue
    fi
    if [[ "$c" == "'" ]]; then
      _amend_close_sq $((i+1)) "$n"; (( AMEND_J < 0 )) && { AMEND_R=2; return; }
      j=$AMEND_J; _amend_word_add $((i+1)) $((j-1)); i=$j; continue
    fi
    if [[ "$c" == '$' && "${AMEND_CH[i+1]:-}" == "'" ]]; then  # $'…': comillas ANSI-C; con \ la palabra es opaca
      _amend_close_ansi $((i+2)) "$n"; (( AMEND_J < 0 )) && { AMEND_R=2; return; }
      j=$AMEND_J; _amend_word_add $((i+2)) $((j-1)); (( AMEND_ESC )) && opaque=1; i=$j; continue
    fi
    if [[ "$c" == '$' && "${AMEND_CH[i+1]:-}" == '"' ]]; then i=$((i+1)); continue; fi  # $"…" es "…"
    if [[ "$c" == '"' ]]; then
      k=$((i+1)); inword=1; redir=0
      while (( k < n )) && [[ "${AMEND_CH[k]}" != '"' ]]; do
        (( ++AMEND_STEPS > AMEND_MAX_STEPS )) && { AMEND_R=2; return; }
        if [[ "${AMEND_CH[k]}" == '\' ]] && (( k + 1 < n )) && [[ '"\$`' == *"${AMEND_CH[k+1]}"* ]]; then word+="${AMEND_CH[k+1]}"; k=$((k+2)); continue; fi
        if [[ "${AMEND_CH[k]}" == '$' && "${AMEND_CH[k+1]:-}" == '{' ]]; then
          _amend_close_brace $((k+2)) "$n"; (( AMEND_J < 0 )) && { AMEND_R=2; return; }
          j=$AMEND_J; _amend_scan $((k+2)) $((j-1)); (( AMEND_R != 0 )) && return
          _amend_word_add "$k" "$j"; opaque=1; k=$j; continue
        fi
        if [[ "${AMEND_CH[k]}" == '$' && "${AMEND_CH[k+1]:-}" == '(' ]]; then
          _amend_close_subst $((k+2)) "$n"; (( AMEND_J < 0 )) && { AMEND_R=2; return; }
          j=$AMEND_J; _amend_scan $((k+2)) $((j-1)); (( AMEND_R != 0 )) && return
          _amend_word_add "$k" "$j"; opaque=1; k=$j; continue
        fi
        if [[ "${AMEND_CH[k]}" == '`' ]]; then
          _amend_close_bq $((k+1)) "$n"; (( AMEND_J < 0 )) && { AMEND_R=2; return; }
          j=$AMEND_J; _amend_scan $((k+1)) $((j-1)); (( AMEND_R != 0 )) && return
          _amend_word_add "$k" "$j"; opaque=1; k=$j; continue
        fi
        [[ "${AMEND_CH[k]}" == '$' && "${AMEND_CH[k+1]:-}" == [A-Za-z0-9_@*#?\$!-] ]] && opaque=1
        word+="${AMEND_CH[k]}"; k=$((k+1))
      done
      (( k >= n )) && { AMEND_R=2; return; }
      i=$((k+1)); continue
    fi
    if [[ "$c" == '$' || "$c" == '<' || "$c" == '>' ]] && [[ "${AMEND_CH[i+1]:-}" == '(' ]]; then
      _amend_close_subst $((i+2)) "$n"; (( AMEND_J < 0 )) && { AMEND_R=2; return; }
      j=$AMEND_J; _amend_scan $((i+2)) $((j-1)); (( AMEND_R != 0 )) && return
      _amend_word_add "$i" "$j"; [[ "$c" == '$' ]] && { opaque=1; usplit=1; }; i=$j; continue
    fi
    if [[ "$c" == '$' && "${AMEND_CH[i+1]:-}" == '{' ]]; then  # ${…}: el texto de dentro se mira como orden
      _amend_close_brace $((i+2)) "$n"; (( AMEND_J < 0 )) && { AMEND_R=2; return; }
      j=$AMEND_J; _amend_scan $((i+2)) $((j-1)); (( AMEND_R != 0 )) && return
      _amend_word_add "$i" "$j"; opaque=1; usplit=1; i=$j; continue
    fi
    if [[ "$c" == '`' ]]; then
      _amend_close_bq $((i+1)) "$n"; (( AMEND_J < 0 )) && { AMEND_R=2; return; }
      j=$AMEND_J; _amend_scan $((i+1)) $((j-1)); (( AMEND_R != 0 )) && return
      _amend_word_add "$i" "$j"; opaque=1; usplit=1; i=$j; continue
    fi
    if [[ "$c" == ' ' || "$c" == $'\t' ]]; then
      _amend_flush; i=$((i+1)); continue
    fi
    if [[ "$c" == '#' ]] && (( ! inword )); then
      while (( i < n )) && [[ "${AMEND_CH[i]}" != $'\n' ]]; do
        (( ++AMEND_STEPS > AMEND_MAX_STEPS )) && { AMEND_R=2; return; }
        i=$((i+1))
      done
      continue
    fi
    # Las redirecciones (2>&1, >&2, &>f, >|f) son parte de la palabra, no un separador.
    if { [[ "$c" == '&' ]] && { [[ "${AMEND_CH[i+1]:-}" == '>' ]] || (( redir )); }; } || { [[ "$c" == '|' ]] && (( redir )); }; then
      word+="$c"; inword=1; redir=0; i=$((i+1)); continue
    fi
    if [[ "$c" == [\;\&\|\(\)] || "$c" == $'\n' ]]; then
      _amend_flush; _amend_end_cmd; (( AMEND_R != 0 )) && return
      i=$((i+1)); continue
    fi
    # $var, $1, $@…: el valor no se ve, la palabra es opaca (--amend$x, 4.ª revisión).
    [[ "$c" == '$' && "${AMEND_CH[i+1]:-}" == [A-Za-z0-9_@*#?\$!-] ]] && { opaque=1; usplit=1; }
    # Expansión de llaves sin comillas ({a,b}, {1..3}) y ${…}: el shell las expande, la palabra es opaca.
    [[ "$c" == '{' ]] && ubrace=1
    (( ubrace )) && [[ "$c" == ',' || ( "$c" == '.' && "${AMEND_CH[i+1]:-}" == '.' ) ]] && { opaque=1; usplit=1; }
    word+="$c"; inword=1; i=$((i+1))
    if [[ "$c" == [\<\>] ]]; then redir=1; else redir=0; fi
  done
  (( AMEND_STEPS > AMEND_MAX_STEPS )) && { AMEND_R=2; return; }  # _amend_word_add cortó la palabra
  _amend_flush; _amend_end_cmd
}
_amend_flush() { # cierra la palabra en curso de _amend_scan_in (opaca: con la marca \x01, y \x03 si se parte)
  if (( inword )); then
    (( opaque && usplit )) && word=$'\x03'"$word"
    (( opaque )) && word=$'\x01'"$word"
    words+=("$word"); word=""; inword=0; redir=0
  fi
  opaque=0; ubrace=0; usplit=0
}
_amend_end_cmd() { # evalúa la orden simple de _amend_scan_in → AMEND_R (1 casa, 2 no se sabe, 0 no)
  local rc=1
  (( ${#words[@]} )) && { _amend_is_commit "${words[@]}"; rc=$?; }
  words=()
  case $rc in 0) AMEND_R=1 ;; 2) AMEND_R=2 ;; *) AMEND_R=0 ;; esac
}
amend_scan() { # orden → AMEND_R (ver _amend_scan). Más de AMEND_MAX_CHARS: 2, para fallar cerrado en tiempo acotado.
  local LC_ALL=C c
  AMEND_CH=(); AMEND_STEPS=0; AMEND_NEST=0
  if (( ${#1} > AMEND_MAX_CHARS )); then AMEND_R=2; return; fi
  while IFS= read -r -n1 -d '' c; do AMEND_CH+=("$c"); done < <(printf '%s' "$1")
  _amend_scan 0 "${#AMEND_CH[@]}"
}
AMEND_J=-1; AMEND_R=0; AMEND_MAX_CHARS=16384; AMEND_CH=()
AMEND_STEPS=0; AMEND_MAX_STEPS=$((2 * AMEND_MAX_CHARS)); AMEND_NEST=0; AMEND_MAX_NEST=32
_amend_reset_checks() { # $1 = orden con las continuaciones ya unidas → sale 2 si bloquea
  local COMMAND="$1" AMEND_FAST
  AMEND_R=0
  shopt -s nocasematch
  # Vía rápida: sin «commit» y «--am» en la orden ninguna palabra puede casar; el tokenizador es O(n²) en bash.
  # Se mira sin \ ' " $ { } ni , porque git co\mmit --"am"end, -$'-amend' y -{-,}amend también son --amend.
  # Falla cerrado: si la vía rápida casó y la orden no se puede tokenizar (topes, comilla o sustitución
  # abierta), se bloquea sin regex. La coincidencia gruesa sobre la orden cruda la esquivaban --"amend" y
  # co\mmit, y su backtracking no tenía tope (4.ª revisión #1355).
  AMEND_FAST="${COMMAND//[\\\'\"\$\{\},]/}"
  [[ "$AMEND_FAST" == *commit*--am* ]] && amend_scan "$COMMAND"
  if (( AMEND_R == 1 || AMEND_R == 2 )); then
    echo "BLOQUEADO: git commit --amend puede destruir commits anteriores. Crea un commit nuevo." >&2
    exit 2
  fi
  shopt -u nocasematch

  # Bloquear reset --hard
  # FIX: Add anchoring for compound command separators
  if echo "$COMMAND" | grep -iE "${GIT_AT}reset[[:space:]]+--hard" > /dev/null; then
    echo "BLOQUEADO: git reset --hard puede perder trabajo. Usa git stash o git revert." >&2
    exit 2
  fi
}

_push_checks "$COMMAND"
_amend_reset_checks "$COMMAND"
if [[ "$COMMAND_NOSP" != "$COMMAND" ]]; then
  _push_checks "$COMMAND_NOSP"
  _amend_reset_checks "$COMMAND_NOSP"
fi
# Fallar cerrado: también las líneas sin unir (echo \\\⏎git push origin main y # nota \⏎git push …).
if [[ "$COMMAND_RAW" != "$COMMAND" && "$COMMAND_RAW" != "$COMMAND_NOSP" ]]; then
  _push_checks "$COMMAND_RAW"
  _amend_reset_checks "$COMMAND_RAW"
fi

exit 0
