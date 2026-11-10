# Run report: summary table, Markdown + JSON export and webhook notification.
#
# Per-server results, filled in by manage-svs.sh:
#   R_STATUS  ok | busy (another run is updating that server right now) | needs-look | failed | rolled-back | skipped | aborted | up-to-date | unreachable | pending | healthy | unhealthy
#             (needs-look: updated, something isn't healthy yet, but nothing the update changed)
#   R_PKGS    package lines ("name old -> new"), R_CT container lines ("name old -> new")
#   R_REBOOT  rebooted | pending | -, R_SNAP snapshot name or why there is none
#   R_ISSUES  failing checks, R_NOTES anything else worth knowing (newline separated)

declare -A R_STATUS R_PKGS R_CT R_REBOOT R_SNAP R_ISSUES R_NOTES
R_ORDER=()

r_add() { # r_add <array> <server> <line> — append a line to a multi-line field
  local -n arr="$1"
  [ -n "$3" ] || return 0
  arr[$2]+="$3"$'\n'
}

count_lines() {
  local n=0
  [ -n "$1" ] && n=$(printf '%s' "$1" | grep -c .)
  echo "$n"
}

status_icon() {
  case "$1" in
    ok|healthy) echo "✔" ;;
    failed|unreachable|unhealthy) echo "✘" ;;
    rolled-back) echo "↺" ;;
    needs-look) echo "⚠" ;;
    aborted) echo "⊘" ;;
    busy) echo "⧗" ;;
    pending) echo "…" ;;
    *) echo "·" ;;
  esac
}

overall_status() {
  local s
  for s in "${R_ORDER[@]}"; do
    case "${R_STATUS[$s]}" in failed|unreachable|unhealthy|rolled-back) echo FAILED; return ;; esac
    [ -n "${R_ISSUES[$s]}" ] && { echo FAILED; return; }
  done
  # updated, but something that the update didn't touch isn't healthy yet
  for s in "${R_ORDER[@]}"; do
    [ "${R_STATUS[$s]}" = needs-look ] && { echo ATTENTION; return; }
  done
  echo OK
}

something_changed() {
  local s
  for s in "${R_ORDER[@]}"; do
    [ -n "${R_PKGS[$s]}${R_CT[$s]}" ] && return 0
  done
  return 1
}

print_summary() {
  local s
  title "Summary ($RUN_MODE) — $(overall_status)"
  if [ "$RUN_MODE" != check ]; then
    {
      echo "SERVER|RESULT|PACKAGES|CONTAINERS|REBOOT|SNAPSHOT"
      for s in "${R_ORDER[@]}"; do
        echo "$s|$(status_icon "${R_STATUS[$s]}") ${R_STATUS[$s]}|$(count_lines "${R_PKGS[$s]}")|$(count_lines "${R_CT[$s]}")|${R_REBOOT[$s]:--}|${R_SNAP[$s]:--}"
      done
    } | table
  fi
  for s in "${R_ORDER[@]}"; do
    [ -n "${R_ISSUES[$s]}" ] && say 1 "$s: $(printf '%s' "${R_ISSUES[$s]}" | paste -sd ';' | sed 's/;/; /g')"
  done
  local manual=() pending=()
  for s in "${R_ORDER[@]}"; do
    case "${R_REBOOT[$s]}" in
      manual) manual+=("$s") ;;
      pending) pending+=("$s") ;;
    esac
  done
  [ ${#manual[@]} -gt 0 ] && say 3 "⚠ Reboot manually (Proxmox, never rebooted by this script): ${manual[*]}"
  [ ${#pending[@]} -gt 0 ] && say 3 "⚠ Reboot pending: ${pending[*]}"
}

write_markdown() {
  local file="$1" s
  {
    echo "# Homelab $RUN_MODE — $(date -d "${TS:0:8} ${TS:9:2}:${TS:11:2}" '+%Y-%m-%d %H:%M')"
    echo ""
    echo "**Result: $(overall_status)** · log: \`$LOG_FILE\`"
    echo ""
    echo "| Server | Result | Packages | Containers | Reboot | Snapshot |"
    echo "|---|---|---|---|---|---|"
    for s in "${R_ORDER[@]}"; do
      echo "| $s | $(status_icon "${R_STATUS[$s]}") ${R_STATUS[$s]} | $(count_lines "${R_PKGS[$s]}") | $(count_lines "${R_CT[$s]}") | ${R_REBOOT[$s]:--} | ${R_SNAP[$s]:--} |"
    done
    for s in "${R_ORDER[@]}"; do
      [ -n "${R_PKGS[$s]}${R_CT[$s]}${R_ISSUES[$s]}${R_NOTES[$s]}" ] || continue
      echo ""
      echo "## $s"
      if [ -n "${R_ISSUES[$s]}" ]; then
        echo ""; echo "**Problems**"; echo ""
        printf '%s' "${R_ISSUES[$s]}" | sed 's/^/- /'
      fi
      if [ -n "${R_CT[$s]}" ]; then
        echo ""; echo "**Containers**"; echo ""
        printf '%s' "${R_CT[$s]}" | sed 's/^/- /'
      fi
      if [ -n "${R_PKGS[$s]}" ]; then
        echo ""; echo "**Packages ($(count_lines "${R_PKGS[$s]}"))**"; echo ""
        printf '%s' "${R_PKGS[$s]}" | sed 's/^/- /'
      fi
      if [ -n "${R_NOTES[$s]}" ]; then
        echo ""; echo "**Notes**"; echo ""
        printf '%s' "${R_NOTES[$s]}" | sed 's/^/- /'
      fi
      if [ -f "$(server_log "$s")" ]; then
        echo ""; echo "Log: \`$(server_log "$s")\`"
      fi
    done
  } > "$file"
}

# server_json <server> — one server's report fields as a JSON object
server_json() {
  local s="$1"
  jq -cn --arg server "$s" --arg status "${R_STATUS[$s]}" --arg reboot "${R_REBOOT[$s]}" \
    --arg snapshot "${R_SNAP[$s]}" --arg pkgs "${R_PKGS[$s]}" --arg cts "${R_CT[$s]}" \
    --arg issues "${R_ISSUES[$s]}" --arg notes "${R_NOTES[$s]}" '
    def lines: split("\n") | map(select(length > 0));
    {server: $server, status: $status, reboot: $reboot, snapshot: $snapshot,
     packages: ($pkgs | lines), containers: ($cts | lines),
     problems: ($issues | lines), notes: ($notes | lines)}'
}

write_json() {
  local file="$1" s
  for s in "${R_ORDER[@]}"; do
    server_json "$s"
  done | jq -s --arg mode "$RUN_MODE" --arg time "$(date -Iseconds)" --arg result "$(overall_status)" \
      --arg log "$LOG_FILE" '{mode: $mode, time: $time, result: $result, log: $log, servers: .}' > "$file"
}

# Short plain-text version for chat/push notifications
notify_text() {
  local s line
  for s in "${R_ORDER[@]}"; do
    line="$(status_icon "${R_STATUS[$s]}") $s: ${R_STATUS[$s]}"
    [ -n "${R_PKGS[$s]}" ] && line+=", $(count_lines "${R_PKGS[$s]}") pkgs"
    [ -n "${R_CT[$s]}" ] && line+=", $(count_lines "${R_CT[$s]}") containers"
    [ "${R_REBOOT[$s]}" = pending ] && line+=", reboot pending"
    [ "${R_REBOOT[$s]}" = manual ] && line+=", REBOOT MANUALLY"
    echo "$line"
    [ -n "${R_ISSUES[$s]}" ] && printf '%s' "${R_ISSUES[$s]}" | sed 's/^/    /'
  done
}

notify() {
  local json_file="$1" result title body
  [ -n "$NOTIFY_URL" ] || return 0
  [ "$NO_NOTIFY" = 1 ] && return 0
  result=$(overall_status)
  case "$NOTIFY_ON" in
    failure) [ "$result" = FAILED ] || return 0 ;;
    changes) [ "$result" = FAILED ] || something_changed || return 0 ;;
  esac

  title="Homelab $RUN_MODE: $result"
  body=$(notify_text)
  local curl_opts=(-fsS -m 20 -o /dev/null)
  case "$NOTIFY_TYPE" in
    ntfy)
      [ -n "$NOTIFY_TOKEN" ] && curl_opts+=(-H "Authorization: Bearer $NOTIFY_TOKEN")
      curl "${curl_opts[@]}" -H "Title: $title" \
        -H "Priority: $([ "$result" = FAILED ] && echo high || echo default)" \
        -H "Tags: $([ "$result" = FAILED ] && echo rotating_light || echo white_check_mark)" \
        --data-binary "$body" "$NOTIFY_URL"
      ;;
    gotify)
      curl "${curl_opts[@]}" "${NOTIFY_URL%/}/message?token=$NOTIFY_TOKEN" \
        -F "title=$title" -F "message=$body" -F "priority=$([ "$result" = FAILED ] && echo 8 || echo 4)"
      ;;
    discord)
      jq -n --arg c "**$title**"$'\n'"\`\`\`"$'\n'"${body:0:1800}"$'\n'"\`\`\`" '{content: $c}' \
        | curl "${curl_opts[@]}" -H 'Content-Type: application/json' --data-binary @- "$NOTIFY_URL"
      ;;
    json)
      curl "${curl_opts[@]}" -H 'Content-Type: application/json' --data-binary @"$json_file" "$NOTIFY_URL"
      ;;
    *) say 1 "Unknown NOTIFY_TYPE '$NOTIFY_TYPE'"; return 1 ;;
  esac && say 8 "Notification sent ($NOTIFY_TYPE)." || say 1 "Sending the notification failed."
}

finish_report() {
  mkdir -p "$REPORT_DIR"
  local base="$REPORT_DIR/${RUN_TAG}-${RUN_MODE}"
  print_summary
  write_markdown "$base.md"
  write_json "$base.json"
  say 8 "Report: $base.md (+ .json) · log: $LOG_FILE"
  REPORT_FILE="$base.json"
  notify "$base.json"
}
