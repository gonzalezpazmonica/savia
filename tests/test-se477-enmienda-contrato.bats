#!/usr/bin/env bats
# PR #1646: el contrato de la enmienda SE-477 cubre k>0, informes sin margen y corpus reutilizado.

SPEC="${SE477_SPEC:-docs/specs/SE-477-comparison-statistics-minimum.spec.md}"

@test "contrato: worst_loss_95/evidence obligatorios si afirma no inferioridad, con cualquier k" {
  run grep -c "afirma no inferioridad \*\*o\*\* hay 0" "$SPEC"
  [ "$output" -ge 1 ]
}

@test "AC3 rechaza evidence sufficient con corpus reutilizado y con cota > margen" {
  grep -q "rechaza \`evidence: sufficient\` con \`corpus_reused\` verdadero" "$SPEC"
  grep -q "rechaza \`evidence: sufficient\` con \`worst_loss_95\` > δ" "$SPEC"
}

@test "AC1 tiene caso negativo k>0 sin evidence y corpus reutilizado" {
  grep -q "(b2) k=1, n=4" "$SPEC"
  grep -q "(b3) 0 pérdidas, n=30" "$SPEC"
}

@test "ámbito: binario por tarea, pérdida definida, unpaired excluido" {
  grep -q "Ámbito y «pérdida»" "$SPEC"
  grep -q "unpaired" "$SPEC"
}

@test "negativo: el encabezado ya no promete incorporar el texto después de la fusión" {
  run grep -c "queda incorporada al texto de la propuesta cuando la operadora fusione" "$SPEC"
  [ "$output" -eq 0 ]
}
