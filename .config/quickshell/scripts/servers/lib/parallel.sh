# Parallel updates: servers run update_server in background workers, grouped in WAVES.
#
# Each worker writes everything to its own log ($LOG_DIR/<ts>-update.<server>.log) and
# talks to the main process through files in $RUN_DIR:
#   phase.<server>     what it is doing right now (status board)
#   ask.<server>       a question for the user (header line + options), answered
#                      through answer.<server>
#   result.<server>    its R_* report fields, sourced by the main process when it ends

declare -A WORKER_PID STARTED LAST_PHASE
BOARD_LINES=0
STOP_REQUESTED=0
SPINNER=(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏)

server_log() { echo "$LOG_DIR/${RUN_TAG}-update.$1.log"; }

fmt_dur() { printf '%d:%02d' $(($1 / 60)) $(($1 % 60)); }

# The worker's report fields as bash assignments, so the main process can source them
save_result() {
  local s="$1" arr
  for arr in R_STATUS R_PKGS R_CT R_REBOOT R_SNAP R_ISSUES R_NOTES; do
    local -n field="$arr"
    [ -n "${field[$s]+set}" ] && printf '%s[%q]=%q\n' "$arr" "$s" "${field[$s]}"
    unset -n field
  done
}

# ── Running next to other runs ────────────────────────────────────────────────
# Several runs can update at the same time. What keeps them out of each other's way
# are lock files in state/locks, held by the worker of a server for as long as it
# works on it (they go away by themselves when it ends, also when it is killed):
#   server.<name>   one run per server, ever. Taken → that server is reported "busy".
#   slot.<n>        MAX_PARALLEL servers at once over all runs, not per run.
#   host.<node>     a Proxmox host is not updated while one of its guests is, and the
#                   other way round (guests share it, the host needs it alone).
#   snap.<node>     one snapshot at a time per node (lib/snapshot.sh).
# And the waves hold across runs: a server waits while a server of an earlier wave is
# being updated by any run (the proxy still goes after the Docker hosts).
lock_server() { exec 7> "$LOCK_DIR/server.$1"; flock -n 7; }

# is_locked <lock name> — someone holds it right now
is_locked() { [ -e "$LOCK_DIR/$1" ] && ! flock -n -s "$LOCK_DIR/$1" true; }

# wait_turn <server> — returns 1 when the user aborted the wait
wait_turn() {
  local s="$1" w e i mine=-1 node type vmid waited="" g
  # 1. servers of earlier waves that another run is updating
  for i in "${!WAVES[@]}"; do [[ " ${WAVES[$i]} " == *" $s "* ]] && mine=$i; done
  while :; do
    waited=""
    if [ "$mine" -gt 0 ]; then
      for ((i = 0; i < mine; i++)); do
        for e in ${WAVES[$i]}; do is_locked "server.$e" && waited+="$e "; done
      done
    fi
    [ -z "$waited" ] && break
    phase "waiting for ${waited% } (an earlier wave, in another run)"
    aborted "$s" && return 1
    sleep 2
  done
  # 2. its Proxmox host / its guests
  read -r node type vmid <<< "${GUESTS[$s]}"
  if [ -n "$node" ]; then
    exec 5> "$LOCK_DIR/host.$node"
    until flock -n -s 5; do
      phase "waiting: its Proxmox host $node is being updated"
      aborted "$s" && return 1
      sleep 2
    done
  else
    for g in "${GUESTS[@]}"; do
      [ "${g%% *}" = "$s" ] || continue
      exec 5> "$LOCK_DIR/host.$s"
      until flock -n 5; do
        phase "waiting for its guests' updates to finish"
        aborted "$s" && return 1
        sleep 2
      done
      break
    done
  fi
  # 3. a free slot
  while :; do
    for ((i = 1; i <= MAX_PARALLEL; i++)); do
      exec 6> "$LOCK_DIR/slot.$i"
      flock -n 6 && return 0
    done
    phase "waiting for a free slot (other updates are running)"
    aborted "$s" && return 1
    sleep 2
  done
}

start_worker() {
  local s="$1"
  : > "$RUN_DIR/phase.$s"
  emit --arg s "$s" --arg log "$(server_log "$s")" '{event: "phase", server: $s, text: "starting", log: $log}'
  (
    # SIGINT is ignored so Ctrl-C never kills a package manager halfway
    trap '' INT
    WORKER_SERVER=$s
    PARENT_INTERACTIVE=$INTERACTIVE
    INTERACTIVE=0
    LOG_FILE=$(server_log "$s")
    exec < /dev/null > /dev/null 2>> "$LOG_FILE"
    if ! lock_server "$s"; then
      say 3 "⧗ $s is being updated by another run right now: left alone."
      R_STATUS[$s]=busy
      r_add R_NOTES "$s" "not touched: another run is updating it right now"
    elif wait_turn "$s"; then
      update_server "$s"
    else
      R_STATUS[$s]=aborted
      r_add R_NOTES "$s" "aborted while it waited for other updates to finish"
    fi
    phase "done"
    save_result "$s" > "$RUN_DIR/result.$s.tmp" && mv "$RUN_DIR/result.$s.tmp" "$RUN_DIR/result.$s"
  ) &
  WORKER_PID[$s]=$!
  STARTED[$s]=$SECONDS
}

# collect_worker <server> — pick up a finished worker's results and print its summary
collect_worker() {
  local s="$1" took parts=()
  wait "${WORKER_PID[$s]}" 2>/dev/null
  if [ -f "$RUN_DIR/result.$s" ]; then
    # shellcheck source=/dev/null
    source "$RUN_DIR/result.$s"
  else
    R_STATUS[$s]=failed
    r_add R_ISSUES "$s" "update process ended unexpectedly — see $(server_log "$s")"
  fi
  took=$(fmt_dur $((SECONDS - STARTED[$s])))

  [ -n "${R_CT[$s]}" ] && parts+=("$(count_lines "${R_CT[$s]}") containers")
  [ -n "${R_PKGS[$s]}" ] && parts+=("$(count_lines "${R_PKGS[$s]}") packages")
  case "${R_REBOOT[$s]}" in
    rebooted) parts+=("rebooted") ;;
    pending) parts+=("reboot pending") ;;
    manual) parts+=("REBOOT MANUALLY") ;;
  esac
  local color=2
  case "${R_STATUS[$s]}" in
    failed) color=1 ;;
    rolled-back|skipped|aborted|needs-look|busy) color=3 ;;
  esac
  say "$color" "$(status_icon "${R_STATUS[$s]}") $s finished in $took — ${R_STATUS[$s]}$(printf ' · %s' "${parts[@]}")"
  emit --argjson r "$(server_json "$s")" --arg log "$(server_log "$s")" --argjson took "$((SECONDS - STARTED[$s]))" \
    '{event: "result"} + $r + {log: $log, seconds: $took}'
  while IFS= read -r line; do
    [ -n "$line" ] && say 1 "    ✘ $line"
  done <<< "${R_ISSUES[$s]}"
  say 8 "    log: $(server_log "$s")"
  unset "WORKER_PID[$s]"
}

# answer_question <server> — show a worker's question and hand back the answer
answer_question() {
  local s="$1" lines answer
  mapfile -t lines < "$RUN_DIR/ask.$s"
  rm -f "$RUN_DIR/ask.$s"
  board_clear
  printf '\a'
  answer=$(gum choose --header "[$s] ${lines[0]}" "${lines[@]:1}") || answer=""
  log "[$s] ${lines[0]} -> ${answer:-<cancelled>}"
  printf '%s' "$answer" > "$RUN_DIR/answer.$s.tmp" && mv "$RUN_DIR/answer.$s.tmp" "$RUN_DIR/answer.$s"
}

board_clear() {
  [ "$BOARD_LINES" -gt 0 ] || return 0
  printf '\033[%dA\033[J' "$BOARD_LINES"
  BOARD_LINES=0
}

# board_draw <header> <server>... — live status of running and queued servers
board_draw() {
  local header="$1" s cur last width spin
  shift
  width=$(tput cols 2>/dev/null || echo 120)
  spin=${SPINNER[SECONDS % ${#SPINNER[@]}]}
  local out
  out=$(printf '\033[1;35m%s\033[0m' "$header")
  for s in "$@"; do
    if [ -n "${WORKER_PID[$s]}" ]; then
      cur=$(cat "$RUN_DIR/phase.$s" 2>/dev/null)
      last=$(tail -n1 "$(server_log "$s")" 2>/dev/null \
        | sed -E 's/^[0-9-]{10} [0-9:]{8} //' | tr -d '\r\033' | tr '\t' ' ')
      last=${last:0:$((width > 70 ? width - 66 : 0))}
      out+=$(printf '\n\033[35m%s\033[0m %-15s %6s  %-40.40s \033[90m%s\033[0m' \
        "$spin" "$s" "$(fmt_dur $((SECONDS - STARTED[$s])))" "$cur" "$last")
    else
      out+=$(printf '\n\033[90m· %-15s %6s  queued\033[0m' "$s" "")
    fi
  done
  board_clear
  printf '%s\n' "$out"
  BOARD_LINES=$(($# + 1))
}

# Without a terminal (cron): print phase changes as plain log lines instead of a board
board_log() {
  local s cur
  for s in "$@"; do
    [ -n "${WORKER_PID[$s]}" ] || continue
    cur=$(cat "$RUN_DIR/phase.$s" 2>/dev/null)
    if [ -n "$cur" ] && [ "$cur" != "${LAST_PHASE[$s]}" ]; then
      LAST_PHASE[$s]=$cur
      say 8 "  $s: $cur"
    fi
  done
}

# run_wave <header> <server>... — update the servers, at most MAX_PARALLEL at a time
run_wave() {
  local header="$1" s
  shift
  local queue=("$@") running=() still=()
  while [ ${#queue[@]} -gt 0 ] || [ ${#running[@]} -gt 0 ]; do
    # the whole run was aborted (Servers app): nothing new starts
    if [ -e "$RUN_DIR/abort._all" ] && [ "$STOP_REQUESTED" != 1 ]; then
      STOP_REQUESTED=1
      say 3 "Abort: the running servers stop at their next safe point, nothing new is started."
    fi
    if [ "$STOP_REQUESTED" = 1 ] && [ ${#queue[@]} -gt 0 ]; then
      for s in "${queue[@]}"; do
        R_STATUS[$s]=skipped
        r_add R_NOTES "$s" "not updated: run was interrupted"
      done
      queue=()
    fi
    while [ ${#running[@]} -lt "$MAX_PARALLEL" ] && [ ${#queue[@]} -gt 0 ]; do
      start_worker "${queue[0]}"
      running+=("${queue[0]}")
      queue=("${queue[@]:1}")
    done

    still=()
    for s in "${running[@]}"; do
      if [ -f "$RUN_DIR/ask.$s" ] && use_gum; then
        answer_question "$s"
      fi
      if kill -0 "${WORKER_PID[$s]}" 2>/dev/null; then
        still+=("$s")
      else
        use_gum && board_clear
        collect_worker "$s"
      fi
    done
    running=("${still[@]}")

    if [ ${#running[@]} -gt 0 ]; then
      if use_gum; then
        board_draw "$header · ${#running[@]} running$([ ${#queue[@]} -gt 0 ] && echo ", ${#queue[@]} queued")" \
          "${running[@]}" "${queue[@]}"
      else
        [ "$JSON" = 1 ] || board_log "${running[@]}"
      fi
      sleep 1
    fi
  done
  use_gum && board_clear
  return 0
}

# build_waves <server>... — WAVE_LIST: one space-separated server list per wave, in
# WAVES order, holding only the given servers. Unlisted servers form a final wave.
build_waves() {
  local wave s rest=() listed=() members
  WAVE_LIST=()
  for wave in "${WAVES[@]}"; do
    members=()
    for s in $wave; do
      listed+=("$s")
      in_list "$s" "$@" && members+=("$s")
    done
    [ ${#members[@]} -gt 0 ] && WAVE_LIST+=("${members[*]}")
  done
  for s in "$@"; do
    in_list "$s" "${listed[@]}" || rest+=("$s")
  done
  [ ${#rest[@]} -gt 0 ] && WAVE_LIST+=("${rest[*]}")
  return 0
}

# run_parallel <server>... — all waves, stopping (or asking) after a wave with failures
run_parallel() {
  local i s failed=() servers
  build_waves "$@"
  trap 'STOP_REQUESTED=1; say 3 "Ctrl-C: running servers will finish, nothing new is started."' INT

  for i in "${!WAVE_LIST[@]}"; do
    read -ra servers <<< "${WAVE_LIST[$i]}"
    if [ "$STOP_REQUESTED" = 1 ] || [ ${#failed[@]} -gt 0 ]; then
      for s in "${servers[@]}"; do
        R_STATUS[$s]=skipped
        if [ "$STOP_REQUESTED" = 1 ]; then
          r_add R_NOTES "$s" "not updated: run was interrupted"
        else
          r_add R_ISSUES "$s" "not updated: stopped after failures on ${failed[*]}"
        fi
      done
      continue
    fi

    title "Wave $((i + 1))/${#WAVE_LIST[@]}: ${servers[*]}"
    run_wave "Wave $((i + 1))/${#WAVE_LIST[@]}" "${servers[@]}"

    for s in "${servers[@]}"; do
      [ "${R_STATUS[$s]}" = failed ] && failed+=("$s")
    done
    if [ ${#failed[@]} -gt 0 ] && [ $((i + 1)) -lt ${#WAVE_LIST[@]} ]; then
      if use_gum; then
        ask "Failures on ${failed[*]}. Continue with the remaining waves anyway?" && failed=()
      elif [ "$ASK_JSON" = 1 ]; then
        # the Servers app: ask; no answer → the svs.conf policy
        local opt_go="Continue with the remaining waves" opt_stop="Stop here" answer
        ASK_DETAIL="Failed: ${failed[*]}.
Still to do: $(printf '%s; ' "${WAVE_LIST[@]:$((i + 1))}")
Continue if the failure only concerns that server. Stop if it could hit the others too (a broken package, DNS or the network)."
        if answer=$(prompt_choice "A server failed. Go on with the next waves?" "$opt_go" "$opt_stop"); then
          [ "$answer" = "$opt_go" ] && failed=()
        elif [ "$STOP_ON_FAILURE" != yes ]; then
          failed=()
        fi
        ASK_DETAIL=""
      elif [ "$STOP_ON_FAILURE" != yes ]; then
        failed=()
      fi
      [ ${#failed[@]} -gt 0 ] && say 1 "Stopping: the remaining waves are not started."
    fi
  done
  trap - INT
}
