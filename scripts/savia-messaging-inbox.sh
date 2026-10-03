#!/bin/bash
# savia-messaging-inbox.sh — Inbox, read, and reply operations
# Sourced by savia-messaging.sh — do NOT run directly.

# ── Inbox: fetch from exchange, list personal messages ────────────
do_inbox() {
  local repo_dir handle
  repo_dir=$(get_repo)
  handle=$(get_handle)

  # Fetch pending messages from exchange
  bash "$SCRIPTS_DIR/savia-branch.sh" fetch-messages "$repo_dir" "$handle" >/dev/null \
    || log_warn "Some pending messages could not be delivered (see error above)"

  echo -e "${CYAN}━━━ Inbox — @$handle ━━━${NC}"

  # Unread messages (list from user/:handle/inbox/unread on user branch)
  local unread_count=0
  echo -e "\n${YELLOW}📬 Unread:${NC}"
  local unread_files
  unread_files=$(bash "$SCRIPTS_DIR/savia-branch.sh" list "$repo_dir" "user/$handle" "inbox/unread") || unread_files=""
  if [ -n "$unread_files" ]; then
    while IFS= read -r msg_file; do
      # list returns full paths; .gitkeep and other non-messages are skipped
      msg_file=$(basename "$msg_file")
      [[ "$msg_file" == *.md ]] || continue
      local content
      content=$(bash "$SCRIPTS_DIR/savia-branch.sh" read "$repo_dir" "user/$handle" "inbox/unread/$msg_file") || continue
      unread_count=$((unread_count + 1))
      local from subject date priority
      from=$(echo "$content" | portable_yaml_field "from" /dev/stdin)
      [ -z "$from" ] && from="?"
      subject=$(echo "$content" | portable_yaml_field "subject" /dev/stdin)
      [ -z "$subject" ] && subject="(no subject)"
      date=$(echo "$content" | portable_yaml_field "date" /dev/stdin)
      [ -z "$date" ] && date="?"
      priority=$(echo "$content" | portable_yaml_field "priority" /dev/stdin)
      [ -z "$priority" ] && priority="normal"
      local pri_icon=""
      [ "$priority" = "high" ] && pri_icon="🔴 "
      echo "  ${pri_icon}[$date] $from: $subject  (${msg_file%.md})"
    done <<< "$unread_files"
  fi
  [ "$unread_count" -eq 0 ] && echo "  (no unread messages)"

  # Company announcements from main:company/inbox/
  echo -e "\n${CYAN}📢 Company Announcements:${NC}"
  local ann_count=0
  touch "$READ_LOG"
  local ann_files
  ann_files=$(bash "$SCRIPTS_DIR/savia-branch.sh" list "$repo_dir" main "company/inbox") || ann_files=""
  if [ -n "$ann_files" ]; then
    while IFS= read -r ann_file; do
      ann_file=$(basename "$ann_file")
      [[ "$ann_file" == *.md ]] || continue
      local ann_id
      ann_id="${ann_file%.md}"
      local is_read="false"
      grep -q "$ann_id" "$READ_LOG" 2>/dev/null && is_read="true"
      if [ "$is_read" = "false" ]; then
        local content
        content=$(bash "$SCRIPTS_DIR/savia-branch.sh" read "$repo_dir" main "company/inbox/$ann_file") || continue
        ann_count=$((ann_count + 1))
        local from subject date
        from=$(echo "$content" | portable_yaml_field "from" /dev/stdin)
        [ -z "$from" ] && from="@admin"
        subject=$(echo "$content" | portable_yaml_field "subject" /dev/stdin)
        [ -z "$subject" ] && subject="(no subject)"
        date=$(echo "$content" | portable_yaml_field "date" /dev/stdin)
        [ -z "$date" ] && date="?"
        echo "  🆕 [$date] $from: $subject  ($ann_id)"
      fi
    done <<< "$ann_files"
  fi
  [ "$ann_count" -eq 0 ] && echo "  (no new announcements)"

  echo -e "\n  Total: $unread_count unread · $ann_count new announcements"
}

# ── Read: move message from unread to read on user branch ──────────
do_read() {
  local msg_id="${1:?Uso: savia-messaging.sh read <message_id>}"
  local repo_dir handle
  repo_dir=$(get_repo)
  handle=$(get_handle)

  if [[ ! "$msg_id" =~ ^[A-Za-z0-9_.-]+$ ]]; then
    log_error "Invalid message id: $msg_id"
    return 1
  fi

  # A missing file makes "read" return 1; under set -e that would abort
  # the lookup before trying the next folder, hence the "|| content=".
  local content="" in_unread="false"
  content=$(bash "$SCRIPTS_DIR/savia-branch.sh" read "$repo_dir" "user/$handle" "inbox/unread/${msg_id}.md" 2>/dev/null) \
    && in_unread="true" || content=""
  [ -z "$content" ] && { content=$(bash "$SCRIPTS_DIR/savia-branch.sh" read "$repo_dir" "user/$handle" "inbox/read/${msg_id}.md" 2>/dev/null) || content=""; }
  [ -z "$content" ] && { content=$(bash "$SCRIPTS_DIR/savia-branch.sh" read "$repo_dir" main "company/inbox/${msg_id}.md" 2>/dev/null) || content=""; }

  if [ -z "$content" ]; then
    log_error "Message $msg_id not found"
    return 1
  fi

  echo "$content"

  # Move from unread/ to read/ on user branch (one commit, file leaves unread/)
  if [ "$in_unread" = "true" ]; then
    bash "$SCRIPTS_DIR/savia-branch.sh" move "$repo_dir" "user/$handle" \
      "inbox/unread/${msg_id}.md" "inbox/read/${msg_id}.md" \
      "[user/$handle] read: moved $msg_id to read folder" \
      || { log_error "Could not mark $msg_id as read"; return 1; }
  fi

  # Mark announcements as read in log
  if bash "$SCRIPTS_DIR/savia-branch.sh" read "$repo_dir" main "company/inbox/${msg_id}.md" 2>/dev/null | grep -q .; then
    touch "$READ_LOG"
    grep -q "$msg_id" "$READ_LOG" 2>/dev/null || \
      echo "$(date -u +%Y-%m-%dT%H:%M:%SZ)|$msg_id" >> "$READ_LOG"
  fi
}

# ── Reply: respond to a message ────────────────────────────────────
do_reply() {
  local msg_id="${1:?Uso: savia-messaging.sh reply <msg_id> <body> [--encrypt]}"
  local body="${2:?Falta body}"
  shift 2

  local repo_dir handle
  repo_dir=$(get_repo)
  handle=$(get_handle)

  local orig_content=""
  orig_content=$(bash "$SCRIPTS_DIR/savia-branch.sh" read "$repo_dir" "user/$handle" "inbox/unread/${msg_id}.md" 2>/dev/null) || orig_content=""
  [ -z "$orig_content" ] && { orig_content=$(bash "$SCRIPTS_DIR/savia-branch.sh" read "$repo_dir" "user/$handle" "inbox/read/${msg_id}.md" 2>/dev/null) || orig_content=""; }
  [ -z "$orig_content" ] && { orig_content=$(bash "$SCRIPTS_DIR/savia-branch.sh" read "$repo_dir" main "company/inbox/${msg_id}.md" 2>/dev/null) || orig_content=""; }

  if [ -z "$orig_content" ]; then
    log_error "Original message $msg_id not found"
    return 1
  fi

  local orig_from orig_subject orig_thread
  orig_from=$(echo "$orig_content" | portable_yaml_field "from" /dev/stdin)
  orig_subject=$(echo "$orig_content" | portable_yaml_field "subject" /dev/stdin)
  orig_thread=$(echo "$orig_content" | portable_yaml_field "thread" /dev/stdin)
  [ -z "$orig_thread" ] && orig_thread="$msg_id"

  # Remove @ prefix if present
  orig_from="${orig_from#@}"

  do_send "$orig_from" "Re: $orig_subject" "$body" --thread "$orig_thread" --reply-to "$msg_id" "$@"
}
