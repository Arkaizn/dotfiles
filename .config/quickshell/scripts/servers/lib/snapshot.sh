# Proxmox snapshots of a server's VM/CT, taken before it is updated.
# Guests are mapped in GUESTS (servers.json); snapshots are named svsupd_<YYYYmmdd>_<HHMM>.
#
# A Proxmox host is reached in one of two ways (servers.json "pve": { access }):
#   ssh   qm / pct on the host (needs root there). The default.
#   api   the host's API with a token that may only look at guests and snapshot them
#         (role: VM.Audit, VM.Snapshot, VM.Snapshot.Rollback). The token's secret is in
#         the keyring (secret-tool), never in a file or on a command line; the host's
#         certificate is pinned when the access is set up.
# Everything below the node_* functions is the same for both.

declare -A PVE_API            # host → "url|token id|api node name|certificate pin" (access "api")

uses_api() { [ -n "${PVE_API[$1]}" ]; }
api_node() { local n; IFS='|' read -r _ _ n _ <<< "${PVE_API[$1]}"; echo "$n"; }
api_kind() { [ "$1" = pct ] && echo lxc || echo qemu; }

# pve_api <host> <METHOD> <path> [curl data args…] — the answer's "data" as JSON on
# stdout; on failure a one-line reason on stderr. The secret goes to curl through
# stdin (-H @-): it is never an argument, so it never shows in a process list.
pve_api() {
  local host="$1" method="$2" path="$3" url tok node pin secret out code msg
  shift 3
  IFS='|' read -r url tok node pin <<< "${PVE_API[$host]}"
  [ -n "$pin" ] || { echo "the certificate of $host isn't pinned yet: run its access check in the Servers app" >&2; return 1; }
  secret=$(secret-tool lookup service quickshell-servers kind pve-token host "$host" 2>/dev/null)
  [ -n "$secret" ] || { echo "no API token for $host in the keyring (Servers app: $host → Access and guests)" >&2; return 1; }
  out=$(printf 'Authorization: PVEAPIToken=%s=%s\n' "$tok" "$secret" \
        | curl -sS -m 60 -k --pinnedpubkey "$pin" -H @- -X "$method" -w '\n%{http_code}' "$@" "${url%/}/api2/json$path" 2>&1)
  code=${out##*$'\n'}
  out=${out%$'\n'*}
  if [ "$code" != 200 ]; then
    msg=$(jq -r '(.message // empty), ((.errors // {}) | to_entries[]? | "\(.key): \(.value)")' <<< "$out" 2>/dev/null | paste -sd' ' | cut -c1-200)
    case "$code" in
      401) msg="the token was refused (wrong secret, or it was deleted) ${msg}" ;;
      403) msg="the token isn't allowed to do that ${msg}" ;;
      000|"") msg="no answer from $url ($(tail -n1 <<< "$out" | cut -c1-160))" ;;
    esac
    echo "API: ${msg:-HTTP $code}" >&2
    return 1
  fi
  jq -c '.data' <<< "$out"
}

# pve_task <host> <upid> — wait until that task is over; fails with its exit status
pve_task() {
  local host="$1" upid st i
  upid=$(jq -rn --arg u "$2" '$u | @uri')
  for ((i = 0; i < 150; i++)); do
    st=$(pve_api "$host" GET "/nodes/$(api_node "$host")/tasks/$upid/status") || return 1
    if [ "$(jq -r '.status' <<< "$st")" = stopped ]; then
      [ "$(jq -r '.exitstatus' <<< "$st")" = OK ] && return 0
      jq -r '.exitstatus' <<< "$st" >&2
      return 1
    fi
    sleep 2
  done
  echo "the task didn't finish in time" >&2
  return 1
}

# pve_do <host> <METHOD> <path> [data…] — a call that starts a task: wait for it
pve_do() {
  local host="$1" upid
  upid=$(pve_api "$@") || return 1
  pve_task "$host" "$(jq -r '.' <<< "$upid")"
}

# ── One host, either way ──────────────────────────────────────────────────────
node_up() {
  if uses_api "$1"; then pve_api "$1" GET /version &>/dev/null; else ssh_run "$1" true &>/dev/null; fi
}

# node_guest_lock <host> <qm|pct> <vmid> — the guest's lock ("backup", …) or nothing
node_guest_lock() {
  if uses_api "$1"; then pve_api "$1" GET "/nodes/$(api_node "$1")/$(api_kind "$2")/$3/config" 2>/dev/null | jq -r '.lock // empty'
  else ssh_run "$1" "$2 config $3 | sed -n 's/^lock: //p'" 2>/dev/null
  fi
}

# node_snap_create <host> <qm|pct> <vmid> <name> — on failure: the reason, in Proxmox's words
node_snap_create() {
  local err
  if uses_api "$1"; then
    err=$(pve_do "$1" POST "/nodes/$(api_node "$1")/$(api_kind "$2")/$3/snapshot" \
            --data-urlencode "snapname=$4" --data-urlencode "description=manage-svs: before update" 2>&1) && return 0
  else
    err=$(ssh_run "$1" "$2 snapshot $3 $4 --description 'manage-svs: before update'" 2>&1 >/dev/null) && return 0
  fi
  grep -v '^[[:space:]]*$' <<< "${err:-no message}" | tail -n1 | tr -d '\r' | cut -c1-200
  return 1
}

# node_snap_names <host> <qm|pct> <vmid> — this script's snapshots of that guest
node_snap_names() {
  if uses_api "$1"; then pve_api "$1" GET "/nodes/$(api_node "$1")/$(api_kind "$2")/$3/snapshot" 2>/dev/null | jq -r '.[].name'
  else ssh_run "$1" "$2 listsnapshot $3" 2>/dev/null
  fi | grep -o 'svsupd_[0-9]\{8\}_[0-9]\{4\}' | sort -u
}

node_snap_delete() {
  if uses_api "$1"; then pve_do "$1" DELETE "/nodes/$(api_node "$1")/$(api_kind "$2")/$3/snapshot/$4"
  else ssh_run "$1" "$2 delsnapshot $3 $4"
  fi
}

# node_rollback <host> <qm|pct> <vmid> <name> — back to the snapshot, and running again
node_rollback() {
  local base
  if uses_api "$1"; then
    base="/nodes/$(api_node "$1")/$(api_kind "$2")/$3"
    [ "$(pve_api "$1" GET "$base/status/current" | jq -r '.status')" = running ] && pve_do "$1" POST "$base/status/stop"
    pve_do "$1" POST "$base/snapshot/$4/rollback" && pve_do "$1" POST "$base/status/start"
  else
    ssh_run "$1" "
      $2 status $3 | grep -q running && $2 stop $3
      $2 rollback $3 $4 && $2 start $3
    "
  fi
}

# node_snap_lines <host> — SNAP|<qm|pct>|<vmid>|<guest name>|<snapshot> for every svsupd_*
# snapshot on it (also of guests that aren't in GUESTS any more)
node_snap_lines() {
  local kind tool id name snap
  if ! uses_api "$1"; then remote "$1" snapshots 2>/dev/null | grep '^SNAP|'; return; fi
  for kind in qemu lxc; do
    [ "$kind" = lxc ] && tool=pct || tool=qm
    while IFS=$'\t' read -r id name; do
      [ -n "$id" ] || continue
      for snap in $(node_snap_names "$1" "$tool" "$id"); do echo "SNAP|$tool|$id|$name|$snap"; done
    done <<< "$(pve_api "$1" GET "/nodes/$(api_node "$1")/$kind" 2>/dev/null | jq -r '.[] | "\(.vmid)\t\(.name // "")"')"
  done
}

# node_guests <host> — "<qemu|lxc> <vmid> <name>" for every guest on it
node_guests() {
  local kind
  if uses_api "$1"; then
    for kind in qemu lxc; do
      pve_api "$1" GET "/nodes/$(api_node "$1")/$kind" | jq -r --arg k "$kind" '.[] | "\($k) \(.vmid) \(.name // "")"' || return 1
    done
  else
    ssh_run "$1" 'qm list 2>/dev/null | awk '"'"'NR>1 {print "qemu", $1, $2}'"'"'; pct list 2>/dev/null | awk '"'"'NR>1 {print "lxc", $1, $NF}'"'"
  fi
}

# ── A server's snapshot ───────────────────────────────────────────────────────
# guest_info <server> — sets G_NODE, G_TOOL (qm|pct) and G_VMID; returns 1 if unmapped
guest_info() {
  local type
  read -r G_NODE type G_VMID <<< "${GUESTS[$1]}"
  [ -n "$G_VMID" ] || return 1
  if [ "$type" = lxc ]; then G_TOOL=pct; else G_TOOL=qm; fi
}

# snap_create <server> — prints the reason on failure
snap_create() {
  guest_info "$1" || { echo "no guest mapping"; return 1; }
  local lock err
  lock=$(node_guest_lock "$G_NODE" "$G_TOOL" "$G_VMID")
  if [ -n "$lock" ]; then
    echo "guest $G_VMID is locked ($lock) — is a backup running?"
    return 1
  fi
  # one snapshot at a time per node (several runs may want one at the same moment)
  exec 4> "$LOCK_DIR/snap.$G_NODE"
  flock -w 300 4
  # keep Proxmox's own words: "failed" alone doesn't say whether it's a full pool, a
  # lock or a guest that can't be snapshotted
  err=$(node_snap_create "$G_NODE" "$G_TOOL" "$G_VMID" "$SNAP_NAME") \
    || { exec 4>&-; echo "the snapshot failed on $G_NODE: $err"; return 1; }
  exec 4>&-
}

# snap_rollback <server> — revert the guest to this run's snapshot and start it again
snap_rollback() {
  guest_info "$1" || return 1
  node_rollback "$G_NODE" "$G_TOOL" "$G_VMID" "$SNAP_NAME" 2>&1 | tee -a "$LOG_FILE"
}

# Proxmox nodes that hold the guests in GUESTS (after probe_nodes: only the reachable ones)
snap_nodes() {
  local entry node
  for entry in "${GUESTS[@]}"; do echo "${entry%% *}"; done | sort -u | while read -r node; do
    [ "${NODE_UP[$node]}" = 0 ] || echo "$node"
  done
}

# probe_nodes — try each node once (in parallel), so a node that's down costs one
# timeout instead of one per call. Sets NODE_UP[node]=1|0 and DOWN_NODES.
declare -A NODE_UP
DOWN_NODES=()
probe_nodes() {
  local node dir
  dir=$(mktemp -d)
  for node in $(snap_nodes); do
    ( node_up "$node" && touch "$dir/$node" ) &
  done
  wait
  for node in $(snap_nodes); do
    if [ -e "$dir/$node" ]; then NODE_UP[$node]=1; else NODE_UP[$node]=0; DOWN_NODES+=("$node"); fi
  done
  rm -rf "$dir"
}

# snap_list_all — SNAP|<node>|<qm|pct>|<vmid>|<guest name>|<snapshot> for every svsupd_*
# snapshot on every node
snap_list_all() {
  local node
  for node in $(snap_nodes); do
    node_snap_lines "$node" | sed -n "s/^SNAP|/SNAP|$node|/p"
  done
}

# pool_usage — one line per thin pool: "<node> <vg>/<pool>: <used>% of <size>"
# (over SSH only: a snapshot token isn't allowed to look at the storage)
pool_usage() {
  local node vg lv pct size
  for node in $(snap_nodes); do
    uses_api "$node" && continue
    while IFS='|' read -r vg lv pct size; do
      [ -n "$lv" ] && echo "$node $vg/$lv: ${pct}% of $size"
    done <<< "$(remote "$node" pool-usage 2>/dev/null)"
  done
}

# snap_delete <node> <qm|pct> <vmid> <snapshot>
snap_delete() {
  node_snap_delete "$1" "$2" "$3" "$4" 2>&1 | tee -a "$LOG_FILE" >/dev/null
  return "${PIPESTATUS[0]}"
}

# snap_cleanup <server> — delete this script's snapshots older than SNAPSHOT_KEEP_DAYS
snap_cleanup() {
  guest_info "$1" || return 0
  local cutoff snap
  cutoff=$(date -d "-$SNAPSHOT_KEEP_DAYS days" +%Y%m%d)
  for snap in $(node_snap_names "$G_NODE" "$G_TOOL" "$G_VMID"); do
    if [ "${snap:7:8}" -lt "$cutoff" ]; then
      node_snap_delete "$G_NODE" "$G_TOOL" "$G_VMID" "$snap" &>/dev/null \
        && say 8 "  removed old snapshot $snap"
    fi
  done
}
