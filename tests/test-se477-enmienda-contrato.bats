#!/usr/bin/env bats
# PR #1646: el contrato de la enmienda SE-477 cubre k>0, informes sin margen y corpus reutilizado.
# Cada aserción apunta a una frase que la versión anterior de la spec no tenía o que se borra al romper la regla.

SPEC="$BATS_TEST_DIRNAME/../docs/specs/SE-477-comparison-statistics-minimum.spec.md"

@test "la spec existe (fail-closed: sin fichero, nada pasa)" {
  [ -s "$SPEC" ]
}

@test "contrato: worst_loss_95/evidence/corpus_reused con cualquier k, o con k=0" {
  grep -qF "cuando el informe afirma no inferioridad (con cualquier" "$SPEC"
  grep -qF "hay 0 tareas con pérdida (k=0), con o sin esa afirmación" "$SPEC"
}

@test "AC3 rechaza evidence sufficient con corpus reutilizado y con cota > margen" {
  grep -qF 'rechaza `evidence: sufficient` con `corpus_reused` verdadero' "$SPEC"
  grep -qF 'rechaza `evidence: sufficient` con `worst_loss_95` > δ' "$SPEC"
}

@test "AC1 tiene caso negativo k>0 sin evidence y corpus reutilizado" {
  grep -qF "(b2) k=1, n=4" "$SPEC"
  grep -qF "(b3) 0 pérdidas, n=30" "$SPEC"
}

@test "AC3 rechaza que afirme no inferioridad un informe unpaired o no binario" {
  grep -qF 'rechaza que afirme no inferioridad un informe `unpaired` o de métrica no binaria por tarea' "$SPEC"
  grep -qF "no afirmar no inferioridad con este mecanismo" "$SPEC"
}

@test "δ se declara como tasa de pérdidas, decisión de diseño" {
  grep -qF "δ mide pérdidas, no la diferencia de tasas" "$SPEC"
}

@test "negativo: el AC1 original (varianza nula da IC de ancho 0) no sigue como criterio" {
  ac1=$(grep -F "| AC1 |" "$SPEC")
  [ -n "$ac1" ]
  run grep -cF "varianza nula da IC de ancho 0" <<<"$ac1"
  [ "$output" = "0" ]
}

@test "negativo: el encabezado ya no dice que el texto se incorpora después de la fusión" {
  grep -qF "ya recoge esta enmienda en esta misma PR" "$SPEC"
  run grep -cF "queda incorporada al texto de la propuesta cuando la operadora fusione" "$SPEC"
  [ "$output" = "0" ]
}
