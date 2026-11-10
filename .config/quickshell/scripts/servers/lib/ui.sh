# Output helpers: gum when running interactively, plain text otherwise (cron, pipes),
# JSON log events with --json (lib/json.sh).
# Everything printed through these is also appended to the run log.

use_gum() { [ "$INTERACTIVE" = 1 ]; }

log() { printf '%s %s\n' "$(date '+%F %T')" "$*" >> "$LOG_FILE"; }

# say <color> <text> — colors: 1 red, 2 green, 3 yellow, 8 grey, 212 pink
say() {
  local color="$1"
  shift
  log "$*"
  if [ "$JSON" = 1 ]; then
    emit_log "$color" "$*"
  elif use_gum; then
    gum style --foreground "$color" "$*"
  else
    printf '%s\n' "$*"
  fi
}

title() {
  log "== $* =="
  if [ "$JSON" = 1 ]; then
    emit_log title "$*"
  elif use_gum; then
    gum style --foreground 212 --bold "$*"
  else
    printf '\n== %s ==\n' "$*"
  fi
}

box() {
  log "--- $* ---"
  if [ "$JSON" = 1 ]; then
    emit_log title "$*"
  elif use_gum; then
    echo ""
    gum style --foreground 212 --border rounded --padding "0 1" "$*"
  else
    printf '\n--- %s ---\n' "$*"
  fi
}

# Can we ask the user something? Inside a parallel worker (WORKER_SERVER set) the
# question is handed to the main process, which asks it between status board refreshes.
can_prompt() { use_gum || [ "$ASK_JSON" = 1 ] || { [ -n "$WORKER_SERVER" ] && [ "$PARENT_INTERACTIVE" = 1 ]; }; }

# aborted [server] — did the user ask to abort this server (or the whole run)? The
# Servers app puts abort.<server> / abort._all into the run's control folder ($RUN_DIR,
# "ctl" of the start event). Checked at safe points only: a package install or a
# container recreate is never cut off half way.
aborted() {
  local s="${1:-$WORKER_SERVER}"
  [ -e "$RUN_DIR/abort._all" ] || { [ -n "$s" ] && [ -e "$RUN_DIR/abort.$s" ]; }
}

# prompt_choice <header> <option>... — prints the chosen option (empty if cancelled);
# returns 1 when nobody can be asked (cron)
#
# --json --ask (the Servers app): the question goes out as an "ask" event (with
# ASK_DETAIL, the why and what each option does) and the answer comes back as a file
# (its path is in the event). No answer within ASK_TIMEOUT seconds, or the server is
# aborted meanwhile: returns 1, and the caller falls back to the svs.conf policy.
prompt_choice() {
  local header="$1"
  shift
  if [ -n "$WORKER_SERVER" ] || [ "$ASK_JSON" = 1 ]; then
    [ "$PARENT_INTERACTIVE" = 1 ] || [ "$ASK_JSON" = 1 ] || return 1
    local id="${WORKER_SERVER:-_run}"
    local q="$RUN_DIR/ask.$id" a="$RUN_DIR/answer.$id" deadline=$((SECONDS + ASK_TIMEOUT)) got
    rm -f "$a"
    printf '%s\n' "$header" "$@" > "$q.tmp" && mv "$q.tmp" "$q"
    if [ "$ASK_JSON" = 1 ]; then
      emit --arg id "$id" --arg s "${WORKER_SERVER:-}" --arg q "$header" --arg d "${ASK_DETAIL:-}" --arg a "$a" \
        --argjson t "$ASK_TIMEOUT" --args \
        '{event: "ask", id: $id, server: $s, question: $q, detail: $d, options: $ARGS.positional, answer: $a, timeout: $t}' "$@"
    fi
    phase "waiting for your answer"
    until [ -f "$a" ]; do
      if [ "$ASK_JSON" = 1 ] && { ((SECONDS >= deadline)) || aborted; }; then
        rm -f "$q"
        emit --arg id "$id" --arg s "${WORKER_SERVER:-}" '{event: "asked", id: $id, server: $s, answer: "", timeout: true}'
        log "[$id] $header -> <no answer>"
        return 1
      fi
      sleep 1
    done
    got=$(cat "$a")
    rm -f "$a" "$q"
    [ "$ASK_JSON" = 1 ] && emit --arg id "$id" --arg s "${WORKER_SERVER:-}" --arg g "$got" '{event: "asked", id: $id, server: $s, answer: $g, timeout: false}'
    [ "$ASK_JSON" = 1 ] && log "[$id] $header -> $got"
    printf '%s' "$got"
    return 0
  fi
  use_gum || return 1
  gum choose --header "$header" "$@"
}

# ask <question> — always "no" when nobody can be asked
ask() {
  if [ -n "$WORKER_SERVER" ] || [ "$ASK_JSON" = 1 ]; then
    [ "$(prompt_choice "$1" Yes No)" = Yes ]
    return
  fi
  use_gum && gum confirm "$1"
}

# phase <text> — what a parallel worker is doing right now (shown on the status board)
phase() {
  log "[phase] $*"
  [ -n "$WORKER_SERVER" ] && echo "$*" > "$RUN_DIR/phase.$WORKER_SERVER"
  [ -n "$WORKER_SERVER" ] && emit --arg s "$WORKER_SERVER" --arg t "$*" '{event: "phase", server: $s, text: $t}'
  return 0
}

# Print '|' separated rows as an aligned table (UTF-8 locale so icons aren't escaped under cron)
table() {
  if [ "$JSON" = 1 ]; then LC_ALL=C.UTF-8 column -t -s '|' >> "$LOG_FILE"
  else LC_ALL=C.UTF-8 column -t -s '|' | tee -a "$LOG_FILE"; fi
}

in_list() {
  local needle="$1" item
  shift
  for item in "$@"; do [ "$item" = "$needle" ] && return 0; done
  return 1
}
