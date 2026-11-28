#!/usr/bin/env bats
# SE-539 S2 (D4, D5, AC-9, AC-10) — el agente de front consulta las guías locales
# antes de un patrón de interfaz; Sonora declara su objetivo de navegador.
AGENT=".claude/agents/frontend-developer.md"
MIRROR=".opencode/agents/frontend-developer.md"
SONORA="projects/savia-sonora/CLAUDE.md"

@test "AC-9: el protocolo de inicio incluye el paso de consulta" {
  run grep -F 'bash scripts/web-guidance.sh search' "$AGENT"
  [ "$status" -eq 0 ]
}

@test "AC-9: el informe cita la guía aplicada y en qué se apartó" {
  run grep -E 'guía.*aplicó|aplicó.*guía' "$AGENT"
  [ "$status" -eq 0 ]
  run grep -E 'apart' "$AGENT"
  [ "$status" -eq 0 ]
}

@test "AC-9: cláusula de prioridad, spec y reglas por encima de la guía" {
  run grep -E 'spec aprobada.*reglas del workspace.*por encima de la guía' "$AGENT"
  [ "$status" -eq 0 ]
}

@test "AC-9: las guías built-in-ai no se recomiendan" {
  run grep -F 'built-in-ai' "$AGENT"
  [ "$status" -eq 0 ]
}

@test "AC-9: el paso de consulta está dentro del protocolo de inicio, antes de Convenciones" {
  start=$(grep -n '^## Protocolo de inicio' "$AGENT" | cut -d: -f1)
  step=$(grep -n 'web-guidance.sh search' "$AGENT" | head -1 | cut -d: -f1)
  end=$(grep -n '^## Convenciones' "$AGENT" | cut -d: -f1)
  [ "$start" -lt "$step" ]
  [ "$step" -lt "$end" ]
}

@test "AC-9: el agente respeta el tope de 150 líneas" {
  [ "$(wc -l < "$AGENT")" -le 150 ]
}

@test "AC-9: el espejo de OpenCode lleva el mismo paso" {
  run grep -F 'bash scripts/web-guidance.sh search' "$MIRROR"
  [ "$status" -eq 0 ]
  [ "$(wc -l < "$MIRROR")" -le 150 ]
}

@test "AC-9: el script que el agente invoca existe y busca sin red" {
  [ -x scripts/web-guidance.sh ] || [ -f scripts/web-guidance.sh ]
  run bash scripts/web-guidance.sh search dialog
  [ "$status" -eq 0 ]
}

@test "AC-10: Sonora declara Browser Support con el Chromium de Qt WebEngine fijado" {
  run grep -E '^\*\*Browser Support:\*\*.*Chromium 130.*Qt WebEngine 6\.9\.2.*Pyloid 0\.27\.2' "$SONORA"
  [ "$status" -eq 0 ]
}

@test "AC-10: la declaración de Sonora no pide polyfills" {
  run grep -E '^\*\*Browser Support:\*\*.*polyfill' "$SONORA"
  [ "$status" -eq 0 ]
}
