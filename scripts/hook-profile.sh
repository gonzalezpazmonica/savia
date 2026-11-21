#!/bin/bash
set -uo pipefail
# hook-profile.sh — Show the active SAVIA_HOOK_PROFILE and explain how to set it
# Usage: hook-profile.sh get | set <profile> | list
#
# The profile lives ONLY in the SAVIA_HOOK_PROFILE environment variable (the
# hooks read nothing else). This script never writes a file: a persisted file
# would let an agent lower the guards by writing it (K11-a, 2026-11-20).

LEGACY_FILE="${HOME}/.savia/hook-profile"
VALID_PROFILES="minimal standard strict ci"

usage() {
  cat <<EOF
hook-profile.sh — Savia Hook Profile Manager

Usage:
  hook-profile.sh get               Show active profile
  hook-profile.sh set <profile>     Validate the name and print how to export it (writes nothing)
  hook-profile.sh list              List all profiles with descriptions

Profiles:
  minimal   Only hard security blockers (no quality gates)
  standard  Security + all quality/workflow gates (default)
  strict    Standard + extra scrutiny for critical code
  ci        Same as standard but non-interactive (for CI/CD pipelines)

The active profile is read from:
  1. \$SAVIA_HOOK_PROFILE env var
  2. "standard" (default)
There is no profile file: ~/.savia/hook-profile is ignored.
EOF
}

get_profile() {
  if [[ -n "${SAVIA_HOOK_PROFILE:-}" ]]; then
    echo "$SAVIA_HOOK_PROFILE (env var)"
  else
    echo "standard (default)"
    if [[ -f "$LEGACY_FILE" ]]; then
      echo "note: $LEGACY_FILE is ignored; export SAVIA_HOOK_PROFILE instead" >&2
    fi
  fi
}

set_profile() {
  local profile="${1:-}"
  if [[ -z "$profile" ]]; then
    echo "Error: profile name required" >&2
    echo "Valid profiles: $VALID_PROFILES" >&2
    exit 1
  fi

  if ! echo "$VALID_PROFILES" | grep -qw "$profile"; then
    echo "Error: unknown profile '$profile'" >&2
    echo "Valid profiles: $VALID_PROFILES" >&2
    exit 1
  fi

  echo "Nothing was written: the profile is only read from the environment."
  echo "To apply in the current shell:  export SAVIA_HOOK_PROFILE=$profile"
  echo "For one command only:           SAVIA_HOOK_PROFILE=$profile <command>"
}

list_profiles() {
  cat <<EOF
Available hook profiles:

  minimal   Only hard security blockers (credential leak, force push, data sovereignty)
            Use for: demos, onboarding, debugging hooks

  standard  Security + all quality/workflow gates          [DEFAULT]
            Use for: daily development

  strict    Standard + extra scrutiny (agent dispatch, competence tracking)
            Use for: pre-release, critical code, security-sensitive changes

  ci        Same gates as standard but non-interactive (no prompts, exit-code only)
            Use for: CI/CD pipelines, GitHub Actions, Azure Pipelines

Current: $(get_profile)
EOF
}

case "${1:-}" in
  get)    get_profile ;;
  set)    set_profile "${2:-}" ;;
  list)   list_profiles ;;
  help|-h|--help) usage ;;
  "")     get_profile ;;
  *)
    echo "Unknown command: $1" >&2
    usage >&2
    exit 1
    ;;
esac
