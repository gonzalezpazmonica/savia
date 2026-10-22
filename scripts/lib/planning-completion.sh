#!/usr/bin/env bash
# Shared completion-evidence validation for SE-396 P01.

planning_completion_shape_valid() {
  local completion="$1"
  jq -e '
    type == "object" and
    (.merge_pr | type == "number" and . > 0 and . == floor) and
    (.acceptance_evidence | type == "array" and length > 0) and
    all(.acceptance_evidence[];
      type == "object" and
      (.criterion | type == "string" and length > 0) and
      (.file | type == "string" and length > 0))
  ' <<<"$completion" >/dev/null 2>&1
}

planning_evidence_file_valid() {
  local root="$1" reference="$2" part root_real file_real
  local -a parts
  [[ -n "$reference" && "$reference" != /* ]] || return 1
  IFS='/' read -r -a parts <<<"$reference"
  for part in "${parts[@]}"; do
    [[ "$part" != ".." ]] || return 1
  done
  root_real=$(realpath -e -- "$root") || return 1
  file_real=$(realpath -e -- "$root/$reference") || return 1
  [[ "$file_real" == "$root_real/"* && -f "$file_real" ]]
}

planning_acceptance_evidence_valid() {
  local root="$1" completion="$2" reference
  planning_completion_shape_valid "$completion" || return 1
  while IFS= read -r reference; do
    planning_evidence_file_valid "$root" "$reference" || return 1
  done < <(jq -r '.acceptance_evidence[].file' <<<"$completion")
}

planning_human_review_approved() {
  local completion="$1"
  jq -e '
    (.human_review | type == "object") and
    (.human_review.status == "APPROVED") and
    (.human_review.evidence | type == "string" and length > 0)
  ' <<<"$completion" >/dev/null 2>&1
}

planning_pr_merged() {
  local root="$1" main_ref="$2" pr="$3"
  # El número entra en una regex: solo dígitos, o cualquier metacarácter casaría con medio historial.
  [[ "$pr" =~ ^[0-9]+$ ]] || return 1
  # En un clon superficial el merge puede quedar fuera: avisar en vez de dar un falso negativo mudo.
  if [[ "$(git -C "$root" rev-parse --is-shallow-repository 2>/dev/null)" == "true" ]]; then
    echo "AVISO planning_pr_merged: clon superficial; #$pr puede estar fusionado fuera del historial visible" >&2
  fi
  # Sin grep -q: cortaría la tubería y, con pipefail, el SIGPIPE de git (141) daría falso negativo.
  # Historial completo: una ventana fija (antes -200) caduca sola cuando main crece y rompe specs viejas.
  # Solo cuentan los formatos de merge reales (merge commit o squash), no las menciones sueltas.
  # Límites: un PR fusionado y después revertido sigue contando como fusionado, y «rebase and merge»
  # no deja el número en el asunto (Savia fusiona con merge commit).
  git -C "$root" log --format='%s' "$main_ref" 2>/dev/null |
    grep -E "^Merge pull request #${pr}( |$)|\(#${pr}\)$" >/dev/null
}

# SE-444: autoridad del verificador. Solo informa; no altera planning_acceptance_evidence_valid.
# Imprime "criterio<TAB>estado<TAB>obtenida<TAB>requerida" por cada AC con autoridad ausente
# (estado "ausente") o inferior a la requerida (estado "insuficiente"). Orden: estatica < simulada < real.
planning_unverified_authority_list() {
  local completion="$1"
  jq -r '
    def rank: {"estatica":1,"simulada":2,"real":3}[.] // 0;
    (.acceptance_evidence // [])[]
    | select(type == "object")
    | (.authority // "") as $got
    | (.authority_required // "") as $req
    | (if $got == "" then "ausente"
       elif ($req != "" and ($got | rank) < ($req | rank)) then "insuficiente"
       else empty end) as $state
    | [(.criterion // "?"), $state, (if $got == "" then "-" else $got end), (if $req == "" then "-" else $req end)]
    | @tsv
  ' <<<"$completion" 2>/dev/null
}
