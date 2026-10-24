#!/usr/bin/env bash
# adapter-interface.sh — Common interface for backlog sync adapters
# Provides shared functions: diff, conflict resolution, logging.
# Sourced by provider-specific adapters (azure-devops, jira, github).
# ─────────────────────────────────────────────────────────────────
set -uo pipefail

SYNC_LOG="${PROJECT_ROOT:-.}/output/.sync-log.jsonl"
mkdir -p "$(dirname "$SYNC_LOG")" 2>/dev/null || true

# ── Logging ──
sync_log() {
  local action="$1" provider="$2" pbi_id="$3" result="$4"
  local ts; ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  echo "{\"ts\":\"$ts\",\"action\":\"$action\",\"provider\":\"$provider\",\"pbi\":\"$pbi_id\",\"result\":\"$result\"}" \
    >> "$SYNC_LOG"
}

# ── Extract frontmatter field from PBI file ──
get_pbi_field() {
  local file="$1" field="$2"
  grep "^${field}:" "$file" 2>/dev/null | head -1 | sed "s/${field}: *//;s/^\"//;s/\"$//"
}

# ── Set frontmatter field in PBI file ──
set_pbi_field() {
  local file="$1" field="$2" value="$3"
  if grep -q "^${field}:" "$file" 2>/dev/null; then
    sed -i "s/^${field}:.*/${field}: ${value}/" "$file"
  fi
  sed -i "s/^updated:.*/updated: $(date +%Y-%m-%d)/" "$file"
}

# ── Diff local vs remote (returns: local_only, remote_only, both_changed, in_sync) ──
compute_sync_status() {
  local local_updated="$1" remote_updated="$2" local_hash="$3" remote_hash="$4"
  if [ "$local_hash" = "$remote_hash" ]; then
    echo "in_sync"
  elif [ -z "$remote_updated" ]; then
    echo "local_only"
  elif [ -z "$local_updated" ]; then
    echo "remote_only"
  elif [[ "$local_updated" > "$remote_updated" ]]; then
    echo "local_newer"
  elif [[ "$remote_updated" > "$local_updated" ]]; then
    echo "remote_newer"
  else
    echo "both_changed"
  fi
}

# ── Map local state to provider state ──
map_state_to_provider() {
  local state="$1" provider="$2"
  case "$provider" in
    azure-devops)
      case "$state" in
        New) echo "New" ;; Active) echo "Active" ;;
        Resolved) echo "Resolved" ;; Closed) echo "Closed" ;;
        *) echo "$state" ;;
      esac ;;
    jira)
      case "$state" in
        New) echo "To Do" ;; Active) echo "In Progress" ;;
        Resolved) echo "Done" ;; Closed) echo "Done" ;;
        *) echo "$state" ;;
      esac ;;
    github)
      case "$state" in
        New|Active) echo "open" ;;
        Resolved|Closed) echo "closed" ;;
        *) echo "$state" ;;
      esac ;;
    *) echo "map_state_to_provider: unknown provider '$provider'" >&2; return 1 ;;
  esac
}

# ── Map provider state to local state ──
map_state_from_provider() {
  local state="$1" provider="$2"
  case "$provider" in
    azure-devops) echo "$state" ;;
    jira)
      case "$state" in
        "To Do") echo "New" ;; "In Progress") echo "Active" ;;
        "Done") echo "Resolved" ;; *) echo "$state" ;;
      esac ;;
    github)
      case "$state" in
        open) echo "Active" ;; closed) echo "Closed" ;; *) echo "$state" ;;
      esac ;;
  esac
}
