# Proxmox snapshots of a server's VM/CT, taken before it is updated.
# Guests are mapped in GUESTS (svs.conf); snapshots are named svsupd_<YYYYmmdd>_<HHMM>.

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
  local lock
  lock=$(ssh_run "$G_NODE" "$G_TOOL config $G_VMID | sed -n 's/^lock: //p'" 2>/dev/null)
  if [ -n "$lock" ]; then
    echo "guest $G_VMID is locked ($lock) — is a backup running?"
    return 1
  fi
  # keep Proxmox's own words: "failed" alone doesn't say whether it's a full pool, a
  # lock or a guest that can't be snapshotted
  local err
  # one snapshot at a time per node (several runs may want one at the same moment)
  exec 4> "$LOCK_DIR/snap.$G_NODE"
  flock -w 300 4
  err=$(ssh_run "$G_NODE" "$G_TOOL snapshot $G_VMID $SNAP_NAME --description 'manage-svs: before update'" 2>&1 >/dev/null) \
    || { exec 4>&-; echo "'$G_TOOL snapshot' failed on $G_NODE: $(grep -v '^[[:space:]]*$' <<< "${err:-no message}" | tail -n1 | tr -d '\r' | cut -c1-200)"; return 1; }
  exec 4>&-
}

# snap_rollback <server> — revert the guest to this run's snapshot and start it again
snap_rollback() {
  guest_info "$1" || return 1
  ssh_run "$G_NODE" "
    $G_TOOL status $G_VMID | grep -q running && $G_TOOL stop $G_VMID
    $G_TOOL rollback $G_VMID $SNAP_NAME && $G_TOOL start $G_VMID
  " 2>&1 | tee -a "$LOG_FILE"
}

# Proxmox nodes that hold the guests in GUESTS (after probe_nodes: only the reachable ones)
snap_nodes() {
  local entry node
  for entry in "${GUESTS[@]}"; do echo "${entry%% *}"; done | sort -u | while read -r node; do
    [ "${NODE_UP[$node]}" = 0 ] || echo "$node"
  done
}

# probe_nodes — try each node once (in parallel), so a node that's down costs one
# SSH timeout instead of one per call. Sets NODE_UP[node]=1|0 and DOWN_NODES.
declare -A NODE_UP
DOWN_NODES=()
probe_nodes() {
  local node dir
  dir=$(mktemp -d)
  for node in $(snap_nodes); do
    ( ssh_run "$node" true &>/dev/null && touch "$dir/$node" ) &
  done
  wait
  for node in $(snap_nodes); do
    if [ -e "$dir/$node" ]; then NODE_UP[$node]=1; else NODE_UP[$node]=0; DOWN_NODES+=("$node"); fi
  done
  rm -rf "$dir"
}

# snap_list_all — SNAP|<node>|<qm|pct>|<vmid>|<guest name>|<snapshot> for every svsupd_*
# snapshot on every node (also guests that aren't in GUESTS anymore)
snap_list_all() {
  local node
  for node in $(snap_nodes); do
    remote "$node" snapshots 2>/dev/null | sed -n "s/^SNAP|/SNAP|$node|/p"
  done
}

# pool_usage — one line per thin pool: "<node> <vg>/<pool>: <used>% of <size>"
pool_usage() {
  local node vg lv pct size
  for node in $(snap_nodes); do
    while IFS='|' read -r vg lv pct size; do
      [ -n "$lv" ] && echo "$node $vg/$lv: ${pct}% of $size"
    done <<< "$(remote "$node" pool-usage 2>/dev/null)"
  done
}

# snap_delete <node> <qm|pct> <vmid> <snapshot>
snap_delete() {
  ssh_run "$1" "$2 delsnapshot $3 $4" 2>&1 | tee -a "$LOG_FILE" >/dev/null
  return "${PIPESTATUS[0]}"
}

# snap_cleanup <server> — delete this script's snapshots older than SNAPSHOT_KEEP_DAYS
snap_cleanup() {
  guest_info "$1" || return 0
  local cutoff snap
  cutoff=$(date -d "-$SNAPSHOT_KEEP_DAYS days" +%Y%m%d)
  for snap in $(ssh_run "$G_NODE" "$G_TOOL listsnapshot $G_VMID" 2>/dev/null \
                  | grep -o 'svsupd_[0-9]\{8\}_[0-9]\{4\}' | sort -u); do
    if [ "${snap:7:8}" -lt "$cutoff" ]; then
      ssh_run "$G_NODE" "$G_TOOL delsnapshot $G_VMID $snap" &>/dev/null \
        && say 8 "  removed old snapshot $snap"
    fi
  done
}
