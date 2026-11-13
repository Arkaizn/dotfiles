# --json: machine-readable output for the Quickshell "Servers" app.
#
# stdout carries only JSON lines (one object per line, each with an "event" key);
# everything a person would read goes to the run log instead. Events:
#   start      { mode, servers, waves?, log, ctl }   ctl: the run's control folder: create
#                abort.<server> (or abort._all) in it to stop at the next safe point
#   log        { level: info|ok|warn|error|title, text, server? }
#   phase      { server, text }                       (update: what a server is doing)
#   ask        { id, server, question, detail, options: [labels], answer: <file to write the
#                chosen label into>, timeout }      (--ask: answer by writing that file)
#   asked      { id, server, answer, timeout }       (the question is settled)
#   aborted    { server }                            (its scan was cut off by the user)
#   scan       { server, reachable, error, pm, os: { id, name }, docker, proxmox, reboot, packages: [{ name, old,
#                new, security }], containers: [{ name, project, service, image,
#                oldVersion, newVersion, oldId, newId, state: pulled | remote }],
#                plain: [{ name, image, oldId, oldVersion }] (docker run containers with a newer image),
#                skipped: [{ name, kind: plain | aio | missing, reason }], warnings, time }
#   check      { server, reachable, checks: [{ type, name, target, ok, detail }],
#                containers: [{ name, status, health }], issues, time }
#   result     { server, status, summary (one sentence), look: [{ kind, name }], reboot, snapshot, packages, containers, problems,
#                notes, log }                         (update: one per finished server)
#   snapshots  { snapshots: [{ id, node, tool, vmid, name, snapshot, ageDays }], pools }
#   deleted    { id, ok }
#   error      { error }
#   done       { mode, result, report?, exit }
# The latest scan / check of every server is also kept in state/last-scan.json and
# state/last-check.json ({ servers: { <name>: <scan / check event> } }).

JSON=0
STATE_DIR="$DATA_DIR/state"

# emit <jq args…> <filter> — print one JSON event (only with --json). fd 3 is the
# real stdout: in --json mode fd 1 goes to the run log so stray output can't mix in.
emit() {
  [ "$JSON" = 1 ] || return 0
  jq -cn "$@" >&3
}

# say's colours → a level
level_of() {
  case "$1" in
    1) echo error ;; 2) echo ok ;; 3) echo warn ;; title) echo title ;; *) echo info ;;
  esac
}

emit_log() { # emit_log <colour|title> <text>
  emit --arg l "$(level_of "$1")" --arg t "$2" --arg s "${WORKER_SERVER:-}" \
    '{event: "log", level: $l, text: $t} + (if $s != "" then {server: $s} else {} end)'
}

# scan_json <server> <raw scan file> — the scan event of one server
scan_json() {
  jq -Rnc --arg s "$1" --arg time "$(date -Iseconds)" '
    [inputs] as $l |
    def f($t): $l | map(select(startswith($t + "|")) | .[($t | length) + 1:]);
    f("SEC") as $sec |
    { event: "scan", server: $s, time: $time,
      reachable: (f("UNREACHABLE") | length == 0),
      error: (f("UNREACHABLE")[0] // null | if . then gsub("[\\r\\n]+$"; "") else . end),
      pm: (f("PM")[0] // null),
      os: (f("OS")[0] // "" | split("|") | {id: (.[0] // ""), name: (.[1:] | join("|"))}),
      docker: (f("DOCKER") | length > 0),
      proxmox: (f("PROXMOX") | length > 0),
      pbs: (f("PBS") | length > 0),
      reboot: (f("REBOOT")[0] == "1"),
      packages: [f("PKG")[] | (capture("^(?<name>\\S+) (?<old>\\S+) -> (?<new>\\S+)") // {name: ., old: "", new: ""})
                 | . + {security: (.name as $n | $sec | any(. == $n))}],
      containers: [f("CTUPD")[] | split("|")
                   | {name: .[0], project: .[1], service: .[2], image: .[3], oldId: .[4], newId: .[5],
                      oldVersion: .[6], newVersion: .[7], state: (.[10] // "pulled")}],
      plain: [f("PLAINUPD")[] | split("|") | {name: .[0], image: .[1], oldId: .[2], oldVersion: .[3]}],
      skipped: [f("CTSKIP")[] | split("|") | {name: .[0], kind: .[1], reason: (.[2:] | join("|"))}],
      warnings: f("WARN") }' < "$2"
}

# check_json <server> <reachable 0|1> — the check event of one server (after run_checks … pre)
check_json() {
  local s="$1" type name target expect st
  {
    while IFS=$'\t' read -r type name target expect; do
      [ -n "$type" ] || continue
      st=${CHECK[pre|$s|$name]}
      jq -cn --arg t "$type" --arg n "$name" --arg g "$target" --arg st "$st" \
        '{kind: "check", type: $t, name: $n, target: $g, ok: ($st == "ok"), detail: ($st | sub("^fail: "; ""))}'
    done <<< "$(check_lines "$s")"
    printf '%s\n' "${CTSTATE[pre|$s]}" | jq -Rc 'select(startswith("STATE|")) | split("|")
      | {kind: "ct", name: .[1], status: .[2], health: .[3]}'
  } | jq -sc --arg s "$s" --argjson r "$([ "$2" = 1 ] && echo true || echo false)" \
       --arg issues "${R_ISSUES[$s]}" --arg time "$(date -Iseconds)" '
    { event: "check", server: $s, time: $time, reachable: $r,
      checks: [.[] | select(.kind == "check") | del(.kind)],
      containers: [.[] | select(.kind == "ct") | del(.kind)],
      issues: ($issues | split("\n") | map(select(length > 0))) }'
}

# state_merge <file name> <event file…> — merge events into state/<file> by server
state_merge() {
  local file="$STATE_DIR/$1" tmp
  shift
  [ $# -gt 0 ] || return 0
  mkdir -p "$STATE_DIR"
  (
    flock 8
    tmp=$(mktemp "$file.XXXX")
    { [ -s "$file" ] && cat "$file" || echo '{"servers": {}}'; cat "$@"; } \
      | jq -s '.[0] as $old | reduce .[1:][] as $e ($old; .servers[$e.server] = $e)' > "$tmp" \
      && mv "$tmp" "$file" || rm -f "$tmp"
  ) 8> "$STATE_DIR/.lock"
}

# state_mark_stale <server…> — after an update: the last scan of these is out of date
state_mark_stale() {
  local file="$STATE_DIR/last-scan.json" tmp
  [ -s "$file" ] && [ $# -gt 0 ] || return 0
  (
    flock 8
    tmp=$(mktemp "$file.XXXX")
    jq --args '.servers |= with_entries(if (.key | IN($ARGS.positional[])) then .value.stale = true else . end)' \
      "$@" < "$file" > "$tmp" && mv "$tmp" "$file" || rm -f "$tmp"
  ) 8> "$STATE_DIR/.lock"
}
