#!/usr/bin/env bash
set -uo pipefail
# compliance-gate.sh — PreToolUse sin efecto: la verificación de compliance ya no se hace aquí.
# Profile tier: standard
#
# La verificación (.claude/compliance/runner.sh) se hace en dos sitios:
#   1. `.githooks/pre-commit` (core.hooksPath): git la ejecuta en el repo real del commit, sobre lo que de
#      verdad va en stage y solo cuando la orden se ejecuta, es decir, tras la aprobación. Vale para
#      cualquier forma de orden: git -C, cd, subshell, heredoc, script o commit -a.
#   2. CI, paso «Compliance runner» del job obligatorio «Validate workspace»: el mismo runner sobre el diff
#      de la PR. Es la autoridad de merge: un commit local que esquive el pre-commit no llega a main sin
#      pasarla. El runner sale del árbol de la PR; sus cambios piden revisión de CODEOWNERS.
#
# Antes este hook deducía del texto de la orden en qué repo se hacía el commit. No tiene solución completa:
# en #1413 hubo seis rondas de revisión y cada una encontró otra construcción de shell que evaluaba el repo
# equivocado. Además ejecutaba git en un repo elegido por la orden antes de su aprobación.
# Queda registrado para no tocar settings.json; retirar el registro es decisión de la operadora.
exit 0
