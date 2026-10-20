#!/usr/bin/env bash
# git-env-clean.sh — aísla el proceso del repo/config git del entorno.
# Un agente en un worktree exporta GIT_DIR/GIT_WORK_TREE; sin limpiar, `git init`/`git commit`
# de un test en un repo temporal operan sobre el repo real (commits "init", core.worktree).
# Uso: source scripts/lib/git-env-clean.sh; git_env_clean [--isolate-config]
git_env_clean() {
  local v
  for v in $(compgen -e | grep -E '^GIT_(DIR|WORK_TREE|INDEX_FILE|COMMON_DIR|OBJECT_DIRECTORY|ALTERNATE_OBJECT_DIRECTORIES|NAMESPACE|PREFIX|CEILING_DIRECTORIES|CONFIG|CONFIG_COUNT|CONFIG_PARAMETERS|CONFIG_KEY_[0-9]+|CONFIG_VALUE_[0-9]+)$'); do
    unset "$v"
  done
  if [[ "${1:-}" == "--isolate-config" ]]; then
    export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null GIT_CONFIG_NOSYSTEM=1
    export GIT_AUTHOR_NAME=s GIT_AUTHOR_EMAIL=s@s GIT_COMMITTER_NAME=s GIT_COMMITTER_EMAIL=s@s
  fi
}
