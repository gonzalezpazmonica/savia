#!/usr/bin/env bats
# tests/test-legal-compliance.bats
# Calibración de la skill legal-compliance contra el comportamiento real
# de scripts/legalize-es.sh, con un mini corpus de fixture (sin red).
# Ref: .claude/skills/legal-compliance/SKILL.md
# Ref: docs/rules/domain/radical-honesty.md
#
# Contrato de exit codes que se verifica:
#   0 resultado encontrado · 1 sin resultados o norma/artículo inexistente
#   2 uso o argumento inválido · 3 corpus no disponible

SCRIPT="scripts/legalize-es.sh"

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  TMPDIR_T="$(mktemp -d)"
  # Ruta con espacios y corchetes: rompe expansiones sin comillas.
  CORPUS="$TMPDIR_T/corpus legal [es]"
  mkdir -p "$CORPUS/es" "$CORPUS/es-ct"

  cat > "$CORPUS/es/BOE-A-2018-16673.md" <<'EOF'
---
title: "Ley Orgánica 3/2018, de 5 de diciembre, de Protección de Datos Personales"
identifier: "BOE-A-2018-16673"
rank: "ley_organica"
last_updated: "2025-12-27"
status: "in_force"
source: "https://www.boe.es/eli/es/lo/2018/12/05/3"
---

# Preámbulo

Como dispone el artículo 13 del Reglamento, texto de preámbulo.

###### Artículo 1. Objeto de la ley.

Texto del artículo uno sobre datos personales.

###### Artículo 10. Tratamiento de datos de naturaleza penal.

Texto del artículo diez.

###### Artículo 13. Derecho de acceso.

Texto del artículo trece, derecho de acceso.

###### Artículo 13 bis. Artículo ficticio de prueba.

Texto bis.
EOF

  cat > "$CORPUS/es/BOE-A-1999-23750.md" <<'EOF'
---
title: "Ley Orgánica 15/1999, de Protección de Datos de Carácter Personal"
identifier: "BOE-A-1999-23750"
rank: "ley_organica"
status: "repealed"
---

Texto derogado sobre datos personales. Nota editorial: status: "in_force"
EOF

  cat > "$CORPUS/es/BOE-A-2002-13758.md" <<'EOF'
---
title: Ley 34/2002, de servicios de la sociedad de la información
identifier: BOE-A-2002-13758
rank: ley
status: in_force
---

###### Artículo 22. Cookies.

Texto sobre cookies (dispositivos de almacenamiento).
EOF

  cat > "$CORPUS/es/BOE-A-2020-1.md" <<'EOF'
---
title: "Norma sin estado declarado"
identifier: "BOE-A-2020-1"
---

Texto sin estado.
EOF

  cat > "$CORPUS/es-ct/DOGC-A-2010-1.md" <<'EOF'
---
title: "Llei catalana de prova"
identifier: "DOGC-A-2010-1"
status: "in_force"
---

Text sobre cookies autonòmiques.
EOF

  export LEGALIZE_ES_PATH="$CORPUS"
  cd "$REPO_ROOT"
}

teardown() {
  rm -rf "$TMPDIR_T"
}

@test "script: existe, es bash y usa set -uo pipefail" {
  [ -f "$SCRIPT" ]
  head -1 "$SCRIPT" | grep -q bash
  grep -q "set -uo pipefail" "$SCRIPT"
  bash -n "$SCRIPT"
}

# --- search: cmd_search, require_corpus, fm_field, rank_priority -------------

@test "search positivo: encuentra norma vigente en ruta con espacios" {
  run bash "$SCRIPT" search "datos personales"
  [ "$status" -eq 0 ]
  [[ "$output" == *"BOE-A-2018-16673"* ]]
}

@test "search: el identificador sale sin comillas YAML" {
  run bash "$SCRIPT" search "datos personales"
  [ "$status" -eq 0 ]
  [[ "$output" != *'"BOE-A-2018-16673"'* ]]
}

@test "search reject: excluye norma derogada aunque el cuerpo cite in_force" {
  run bash "$SCRIPT" search "datos personales"
  [[ "$output" != *"BOE-A-1999-23750"* ]]
}

@test "search: acepta status sin comillas en el frontmatter" {
  run bash "$SCRIPT" search "cookies"
  [ "$status" -eq 0 ]
  [[ "$output" == *"BOE-A-2002-13758"* ]]
}

@test "search: ordena por rango normativo (ley orgánica antes que ley)" {
  run bash "$SCRIPT" search "texto"
  [ "$status" -eq 0 ]
  lo=$(grep -n "BOE-A-2018-16673" <<<"$output" | cut -d: -f1)
  ley=$(grep -n "BOE-A-2002-13758" <<<"$output" | cut -d: -f1)
  [ -n "$lo" ] && [ -n "$ley" ]
  [ "$lo" -lt "$ley" ]
}

@test "search empty: sin resultados sale 1 y avisa de que no hay fuente" {
  run bash "$SCRIPT" search "término inexistente xyz"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Sin resultados"* ]]
  [[ "$output" == *"Sin fuente"* ]]
}

@test "search: el término es literal, no regex" {
  run bash "$SCRIPT" search "datos.personales"
  [ "$status" -eq 1 ]
}

@test "search: término que empieza por guion no se toma como opción de grep" {
  run bash "$SCRIPT" search "-v"
  [ "$status" -eq 1 ]
  [[ "$output" != *"BOE-A-2018-16673"* ]]
}

@test "search error: falta el término sale 2" {
  run bash "$SCRIPT" search
  [ "$status" -eq 2 ]
}

@test "search: ámbito autonómico es-ct" {
  run bash "$SCRIPT" search "cookies" es-ct
  [ "$status" -eq 0 ]
  [[ "$output" == *"DOGC-A-2010-1"* ]]
  [[ "$output" != *"BOE-A-2002-13758"* ]]
}

@test "search invalid: ámbito inexistente sale 2 en vez de silencio" {
  run bash "$SCRIPT" search "cookies" es-zz
  [ "$status" -eq 2 ]
}

@test "search reject: ámbito con path traversal sale 2" {
  run bash "$SCRIPT" search "cookies" "../.."
  [ "$status" -eq 2 ]
}

@test "search large: avisa cuando trunca a 20 resultados" {
  for i in $(seq 1 25); do
    printf -- '---\ntitle: "Norma %s"\nidentifier: "BOE-A-2021-%s"\nstatus: "in_force"\n---\nfirma electrónica\n' "$i" "$i" \
      > "$CORPUS/es/BOE-A-2021-$i.md"
  done
  run bash "$SCRIPT" search "firma electrónica"
  [ "$status" -eq 0 ]
  [ "$(grep -c 'BOE-A-2021-' <<<"$output")" -eq 20 ]
  [[ "$output" == *"20 de 25"* ]]
}

# --- corpus ausente: require_corpus, err -------------------------------------

@test "corpus ausente: search sale 3 y no da resultados" {
  export LEGALIZE_ES_PATH="$TMPDIR_T/no existe"
  run bash "$SCRIPT" search "datos"
  [ "$status" -eq 3 ]
  [[ "$output" == *"no instalado"* ]]
}

@test "corpus vacío (directorio sin es/): search sale 3" {
  mkdir -p "$TMPDIR_T/vacio"
  export LEGALIZE_ES_PATH="$TMPDIR_T/vacio"
  run bash "$SCRIPT" search "datos"
  [ "$status" -eq 3 ]
}

@test "corpus ausente: status sale 3" {
  export LEGALIZE_ES_PATH="$TMPDIR_T/no existe"
  run bash "$SCRIPT" status
  [ "$status" -eq 3 ]
}

@test "corpus ausente: search-article y check-status salen 3" {
  export LEGALIZE_ES_PATH="$TMPDIR_T/no existe"
  run bash "$SCRIPT" search-article BOE-A-2018-16673 "Artículo 1"
  [ "$status" -eq 3 ]
  run bash "$SCRIPT" check-status BOE-A-2018-16673
  [ "$status" -eq 3 ]
}

# --- search-article: cmd_search_article, validate_id, find_norm --------------

@test "search-article: Artículo 1 no arrastra el Artículo 10" {
  run bash "$SCRIPT" search-article BOE-A-2018-16673 "Artículo 1"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Objeto de la ley"* ]]
  [[ "$output" != *"naturaleza penal"* ]]
}

@test "search-article: Artículo 13 ignora la cita del preámbulo" {
  run bash "$SCRIPT" search-article BOE-A-2018-16673 "Artículo 13"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Derecho de acceso"* ]]
  [[ "$output" != *"preámbulo"* ]]
  [[ "$output" != *"Texto bis"* ]]
}

@test "search-article: acepta número suelto y sufijo bis" {
  run bash "$SCRIPT" search-article BOE-A-2018-16673 "13 bis"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Texto bis"* ]]
  [[ "$output" != *"Derecho de acceso"* ]]
}

@test "search-article not found: artículo inexistente sale 1" {
  run bash "$SCRIPT" search-article BOE-A-2018-16673 "Artículo 99"
  [ "$status" -eq 1 ]
  [[ "$output" == *"no encontrado"* ]]
}

@test "search-article not found: norma inexistente sale 1" {
  run bash "$SCRIPT" search-article BOE-A-1900-1 "Artículo 1"
  [ "$status" -eq 1 ]
}

@test "search-article reject: identificador con comodín no resuelve otra norma" {
  run bash "$SCRIPT" search-article "BOE-A-*" "Artículo 1"
  [ "$status" -eq 2 ]
  [[ "$output" != *"Objeto de la ley"* ]]
}

@test "search-article error: faltan argumentos sale 2" {
  run bash "$SCRIPT" search-article BOE-A-2018-16673
  [ "$status" -eq 2 ]
}

# --- check-status: cmd_check_status, validate_id, fm_field -------------------

@test "check-status: norma vigente" {
  run bash "$SCRIPT" check-status BOE-A-2018-16673
  [ "$status" -eq 0 ]
  [[ "$output" == *"VIGENTE"* ]]
}

@test "check-status: norma derogada" {
  run bash "$SCRIPT" check-status BOE-A-1999-23750
  [ "$status" -eq 0 ]
  [[ "$output" == *"DEROGADA"* ]]
}

@test "check-status null: sin campo status lo dice explícitamente" {
  run bash "$SCRIPT" check-status BOE-A-2020-1
  [ "$status" -eq 0 ]
  [[ "$output" == *"DESCONOCIDO"* ]]
}

@test "check-status reject: identificador con barra sale 2" {
  run bash "$SCRIPT" check-status "../es/BOE-A-2018-16673"
  [ "$status" -eq 2 ]
}

# --- history: cmd_history ----------------------------------------------------

@test "history: lista commits en corpus git con ruta con espacios y corchetes" {
  git -C "$CORPUS" init -q
  git -C "$CORPUS" -c user.email=t@t -c user.name=t add -A
  git -C "$CORPUS" -c user.email=t@t -c user.name=t commit -q -m "Reforma de prueba"
  run bash "$SCRIPT" history BOE-A-2018-16673
  [ "$status" -eq 0 ]
  [[ "$output" == *"Reforma de prueba"* ]]
}

@test "history error: corpus sin git avisa en vez de salir en blanco" {
  run bash "$SCRIPT" history BOE-A-2018-16673
  [ "$status" -eq 1 ]
  [[ "$output" == *"sin historial git"* ]]
}

# --- uso: usage, cmd_install, cmd_status, cmd_update -------------------------

@test "uso: comando desconocido sale 2; help sale 0" {
  run bash "$SCRIPT" comando-invalido
  [ "$status" -eq 2 ]
  run bash "$SCRIPT" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"search-article"* ]]
}

@test "install: corpus ya clonado no toca la red y sale 0" {
  mkdir -p "$CORPUS/.git"
  run bash "$SCRIPT" install
  [ "$status" -eq 0 ]
  [[ "$output" == *"ya instalado"* ]]
}

@test "status: corpus presente sin git cuenta normas y lo indica" {
  run bash "$SCRIPT" status
  [ "$status" -eq 0 ]
  [[ "$output" == *"Normas estatales: 4"* ]]
  [[ "$output" == *"Comunidades autónomas: 1"* ]]
  [[ "$output" == *"sin historial git"* ]]
}

@test "update error: corpus sin repositorio git sale 3 sin tocar la red" {
  run bash "$SCRIPT" update
  [ "$status" -eq 3 ]
  [[ "$output" == *"no instalado"* ]]
}
