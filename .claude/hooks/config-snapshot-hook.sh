#!/usr/bin/env bash
set -uo pipefail
# config-snapshot-hook.sh — PreToolUse Edit|Write (SE-405 Slice 2).
#
# Antes de editar un fichero de configuración vigilado guarda una copia con
# scripts/config-snapshot.sh. Nunca bloquea: exit 0 siempre.
# Vigilados: .claude/settings.json, .claude/settings.local.json, opencode.json,
# ~/.savia/preferences.yaml.
# Ref: docs/specs/SE-405-harness-observability-increments.spec.md

ROOT="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
command -v jq >/dev/null 2>&1 || { source "$(dirname "${BASH_SOURCE[0]}")/lib/hook-input.sh"; hook_unmeasured_exit config-snapshot-hook; }
path=$(jq -r '.tool_input.file_path // .tool_input.filePath // empty' 2>/dev/null) || exit 0
[[ -z "$path" ]] && exit 0
case "$path" in
  */.claude/settings.json|*/.claude/settings.local.json|*/opencode.json|"$HOME/.savia/preferences.yaml") ;;
  *) exit 0 ;;
esac
[[ -f "$path" ]] || exit 0
bash "$ROOT/scripts/config-snapshot.sh" snapshot "$path" >/dev/null 2>&1 || true
exit 0
