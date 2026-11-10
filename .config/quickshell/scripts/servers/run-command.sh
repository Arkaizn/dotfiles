#!/usr/bin/env bash
# Run a shell snippet on servers over SSH (the Servers app's "Run command").
# Prints the same JSON lines as manage-svs.sh --json, so the app's activity panel
# shows it: start, phase, log (each output line), result, done.
#
#   run-command.sh <title> <snippet> <name|dest|port>...
#
# At most 4 servers at once; BatchMode (keys only, never a password prompt).
# A server can be cut off: create abort.<name> (or abort._all) in the control folder
# ("ctl" of the start event); its ssh is killed and it's reported as aborted.
# The snippet goes to `bash -s` on the server through stdin, never into a command line.
set -uo pipefail

title=$1 snippet=$2
shift 2
command -v jq >/dev/null || { echo '{"event":"error","error":"jq is missing"}'; exit 1; }

ev() { jq -cn "$@"; }
names=()
for spec in "$@"; do names+=("${spec%%|*}"); done
ctl=$(mktemp -d)
trap 'rm -rf "$ctl"' EXIT
ev --arg t "$title" --arg ctl "$ctl" --args '{event: "start", mode: "command", title: $t, servers: $ARGS.positional, ctl: $ctl}' "${names[@]}"
is_aborted() { [ -e "$ctl/abort._all" ] || [ -e "$ctl/abort.$1" ]; }

run_one() {
  local name=$1 dest=$2 port=$3 rc start=$SECONDS
  echo "$BASHPID" > "$ctl/pid.$name"
  ev --arg s "$name" '{event: "phase", server: $s, text: "running"}'
  printf '%s\n' "$snippet" | ssh -T -o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new \
      -p "$port" -- "$dest" 'bash -s' 2>&1 \
    | while IFS= read -r line; do
        ev --arg s "$name" --arg t "$line" '{event: "log", level: "info", server: $s, text: $t}'
      done
  rc=${PIPESTATUS[1]}
  is_aborted "$name" && return 130      # cut off: the main loop reports it
  : > "$ctl/done.$name"
  ev --arg s "$name" --argjson rc "$rc" --argjson sec "$((SECONDS - start))" \
    '{event: "result", server: $s, status: (if $rc == 0 then "ok" elif $rc == 255 then "unreachable" else "failed" end),
      problems: (if $rc == 0 then [] elif $rc == 255 then ["SSH failed"] else ["exit \($rc)"] end), seconds: $sec}'
  return "$rc"
}

failed=0
pids=()
for spec in "$@"; do
  IFS='|' read -r name dest port <<< "$spec"
  [[ "$name" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ && "$port" =~ ^[0-9]+$ && -n "$dest" && "$dest" != -* ]] || {
    ev --arg s "$name" '{event: "result", server: $s, status: "failed", problems: ["bad server entry"]}'; failed=1; continue; }
  run_one "$name" "$dest" "$port" &
  pids+=($!)
  while [ "$(jobs -rp | wc -l)" -ge 4 ]; do wait -n; done
done
# wait for them; cut off the ones that get aborted
while [ -n "$(jobs -rp)" ]; do
  for name in "${names[@]}"; do
    if is_aborted "$name" && [ -s "$ctl/pid.$name" ] && [ ! -e "$ctl/done.$name" ]; then
      p=$(cat "$ctl/pid.$name"); rm -f "$ctl/pid.$name"
      pkill -TERM -P "$p" 2>/dev/null
      ev --arg s "$name" '{event: "result", server: $s, status: "aborted", problems: [], seconds: 0}'
    fi
  done
  sleep 0.5
done
for p in "${pids[@]}"; do wait "$p"; rc=$?; [ "$rc" -eq 0 ] || [ "$rc" -eq 130 ] || failed=1; done

ev --argjson f "$failed" '{event: "done", mode: "command", result: (if $f == 0 then "OK" else "FAILED" end), exit: $f}'
exit "$failed"
