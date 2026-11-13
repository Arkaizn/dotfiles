# Servers from servers.json (written by the Quickshell "Servers" app or by hand).
# When the file exists it replaces the server lists of svs.conf (SERVERS, PORTS,
# NO_REBOOT_SERVERS, GUESTS, CHECKS, EXCLUDE_CONTAINERS, WAVES); svs.conf keeps the
# behaviour settings and secrets. Archived servers are left out of everything.
#
#   { "version": 1,
#     "groups":   [{ "id", "name", "icon" }],
#     "servers":  [{ "name", "host", "port", "user", "groups": [ids], "tags": [], "notes",
#                    "archived", "sftp", "noReboot", "noSnapshot",
#                    "guest": { "node", "type": "qemu" | "lxc", "vmid" } | null,
#                    "checks": [{ "type", "name", "target", "expect" }],
#                    "excludeContainers": [], "wol", "links": [], "tunnels": [] }],
#     "waves":    [["server", …], …],
#     "commands": [{ "id", "name", "script" }] }
#
# "name" is the server's key and, unless "host" is set, also what ssh connects to.

SERVERS_FILE="${SVS_SERVERS:-$DATA_DIR/servers.json}"

declare -A SSH_DEST EXCL_CT

# The ssh destination of a server: [user@]host, default the name itself
dest_of() { echo "${SSH_DEST[$1]:-$1}"; }

# Is container <name> excluded on <server>? (global EXCLUDE_CONTAINERS or the server's own list)
excluded_ct() {
  in_list "$2" "${EXCLUDE_CONTAINERS[@]}" && return 0
  [ -n "${EXCL_CT[$1]}" ] && grep -qxF "$2" <<< "${EXCL_CT[$1]}"
}

# ct_mode <server> — what an update does with its containers: update (recreate them on
# the new image) | pull (only download the image; they restart when you say so) | never.
# servers.json "containers"; without it a server that must never reboot is "pull".
declare -A CT_MODE
KNOWN=()                    # every server in servers.json that isn't archived (SERVERS: the ones scanned and updated)
PVE_KIND=()                 # servers said to be a Proxmox VE host / Backup Server (servers.json "kind": pve | pbs)
PLAIN_OK=()                 # servers whose `docker run` containers may be updated (servers.json "plainContainers")
ct_mode() {
  if [ -n "${CT_MODE[$1]}" ]; then echo "${CT_MODE[$1]}"
  elif in_list "$1" "${NO_REBOOT_SERVERS[@]}"; then echo pull
  else echo update
  fi
}

# load_servers_json — replace svs.conf's server lists with servers.json
load_servers_json() {
  [ -f "$SERVERS_FILE" ] || return 0
  local code
  code=$(jq -r '
    def ok: type == "string" and test("^[A-Za-z0-9][A-Za-z0-9._-]*$");
    def known: [.servers[]? | select(.archived != true and (.name | ok))];
    # a Proxmox host that is only reached through its API is not scanned or updated here
    def active: known | map(select((.pve.apiOnly // false) != true or .kind != "pve" or .pve.access != "api"));
    known as $k | active as $a | ($a | map(.name)) as $names |
    "KNOWN=(" + ($k | map(.name | @sh) | join(" ")) + ")",
    # what the Servers app set in Settings → Servers (it wins over svs.conf; absent = svs.conf decides)
    ((.policy // {}) as $p |
      (if ($p.maxParallel | type) == "number" and $p.maxParallel >= 1 and $p.maxParallel <= 16 then "MAX_PARALLEL=\($p.maxParallel | floor)" else empty end),
      (if ($p.stopOnFailure | type) == "boolean" then "STOP_ON_FAILURE=\(if $p.stopOnFailure then "yes" else "no" end)" else empty end),
      (if $p.autoRollback == "none" or $p.autoRollback == "containers" or $p.autoRollback == "snapshot" then "AUTO_ROLLBACK=\($p.autoRollback)" else empty end),
      (if ($p.snapshotKeepDays | type) == "number" and $p.snapshotKeepDays >= 0 and $p.snapshotKeepDays <= 365 then "SNAPSHOT_KEEP_DAYS=\($p.snapshotKeepDays | floor)" else empty end),
      (if ($p.rollbackKeepDays | type) == "number" and $p.rollbackKeepDays >= 0 and $p.rollbackKeepDays <= 365 then "ROLLBACK_KEEP_DAYS=\($p.rollbackKeepDays | floor)" else empty end)),
    ($k[] | select(.kind == "pve" and .pve.access == "api" and ((.pve.url // "") | test("^https://[A-Za-z0-9.-]+(:[0-9]+)?$"))
                   and ((.pve.tokenId // "") | test("^[A-Za-z0-9._@!-]+$")) and ((.pve.node // "") | test("^[A-Za-z0-9-]*$"))
                   and ((.pve.pin // "") | test("^(sha256//[A-Za-z0-9+/=]+)?$")))
          | "PVE_API[\(.name | @sh)]=\("\(.pve.url)|\(.pve.tokenId)|\(.pve.node // "")|\(.pve.pin // "")" | @sh)"),
    "SERVERS=(" + ($names | map(@sh) | join(" ")) + ")",
    ($a[] | select((.port // 22) != 22) | "PORTS[\(.name | @sh)]=\(.port | tostring | @sh)"),
    ($a[] | select(((.host // "") != "") or ((.user // "") != ""))
          | "SSH_DEST[\(.name | @sh)]=\(((if (.user // "") != "" then .user + "@" else "" end) + (if (.host // "") != "" then .host else .name end)) | @sh)"),
    "NO_REBOOT_SERVERS=(" + ($a | map(select(.noReboot == true) | .name | @sh) | join(" ")) + ")",
    "NO_SNAPSHOT_SERVERS=(" + ($a | map(select(.noSnapshot == true) | .name | @sh) | join(" ")) + ")",
    ($a[] | select(.guest.vmid != null and (.guest.node | ok))
          | "GUESTS[\(.name | @sh)]=\("\(.guest.node) \(.guest.type // "qemu") \(.guest.vmid)" | @sh)"),
    ($a[] | select((.checks // []) | length > 0)
          | "CHECKS[\(.name | @sh)]=\([.checks[] | select(.type and .name and .target)
              | if .type == "cmd" then "cmd \(.name) \(.target)" else "\(.type) \(.name) \(.target) \(.expect // "")" end] | join("\n") | @sh)"),
    ($a[] | select((.excludeContainers // []) | length > 0)
          | "EXCL_CT[\(.name | @sh)]=\(.excludeContainers | join("\n") | @sh)"),
    ($a[] | "CT_MODE[\(.name | @sh)]=\((.containers // (if .noReboot == true then "pull" else "update" end)) | @sh)"),
    "PVE_KIND=(" + ($a | map(select(.kind == "pve" or .kind == "pbs") | .name | @sh) | join(" ")) + ")",
    "PLAIN_OK=(" + ($a | map(select(.plainContainers == true) | .name | @sh) | join(" ")) + ")",
    "WAVES=(" + ([.waves[]? | map(select(. as $n | $names | index($n))) | select(length > 0) | join(" ") | @sh] | join(" ")) + ")"
  ' "$SERVERS_FILE") || { echo "servers.json is not valid: $SERVERS_FILE" >&2; exit 1; }
  SERVERS=() NO_REBOOT_SERVERS=() NO_SNAPSHOT_SERVERS=() WAVES=() EXCLUDE_CONTAINERS=()
  PORTS=() GUESTS=() CHECKS=() SSH_DEST=() EXCL_CT=() CT_MODE=() PLAIN_OK=() PVE_KIND=() PVE_API=() KNOWN=()
  eval "$code"
}

# migrate_group <server> — first guess at a group for the migration
migrate_group() {
  case "$1" in
    *pve*|*pbs*) echo proxmox ;;
    *docker*)    echo docker ;;
    *proxy*|*vpn*|*dns*|*net*) echo network ;;
    *)           echo services ;;
  esac
}

# conf_json — svs.conf's server lists (as sourced) as a servers.json document on stdout
conf_json() {
  local s type name target expect

  local servers=() checks guest
  for s in "${SERVERS[@]}"; do
    checks=$(while IFS=$'\t' read -r type name target expect; do
               [ -n "$type" ] && jq -cn --arg t "$type" --arg n "$name" --arg g "$target" --arg e "$expect" \
                 '{type: $t, name: $n, target: $g, expect: $e}'
             done <<< "$(check_lines "$s")" | jq -s .)
    guest=null
    if [ -n "${GUESTS[$s]}" ]; then
      read -r g_node g_type g_vmid <<< "${GUESTS[$s]}"
      guest=$(jq -cn --arg n "$g_node" --arg t "$g_type" --argjson v "$g_vmid" '{node: $n, type: $t, vmid: $v}')
    fi
    servers+=("$(jq -cn --arg name "$s" --argjson port "$(port_of "$s")" --arg group "$(migrate_group "$s")" \
      --argjson noReboot "$(in_list "$s" "${NO_REBOOT_SERVERS[@]}" && echo true || echo false)" \
      --argjson guest "$guest" --argjson checks "$checks" '
      {name: $name, host: "", port: $port, user: "", groups: [$group], tags: [], notes: "",
       archived: false, sftp: true, noReboot: $noReboot, guest: $guest, checks: $checks,
       excludeContainers: [], wol: "", links: [], tunnels: []}')")
  done

  local waves="[]"
  [ ${#WAVES[@]} -gt 0 ] && waves=$(printf '%s\n' "${WAVES[@]}" | jq -Rc 'split(" ") | map(select(. != ""))' | jq -sc .)
  # a global EXCLUDE_CONTAINERS list applies to every server
  local excl
  excl=$(printf '%s\n' "${EXCLUDE_CONTAINERS[@]}" | jq -Rc 'select(. != "")' | jq -sc .)

  printf '%s\n' "${servers[@]}" | jq -s --argjson waves "$waves" --argjson excl "$excl" '
    map(.excludeContainers = $excl) as $s |
    { version: 1,
      groups: ([{id: "docker", name: "Docker", icon: "󰡨"}, {id: "proxmox", name: "Proxmox", icon: "󰒋"},
                {id: "network", name: "Network", icon: "󰛳"}, {id: "services", name: "Services", icon: "󰒍"}]
               | map(select(.id as $g | $s | any(.groups | index($g))))),
      servers: $s, waves: $waves, commands: [] }'
}

# run_migrate [--force] — svs.conf's server lists → servers.json, then comment them
# out in svs.conf (a copy of the old file goes to .backups/)
run_migrate() {
  if [ -f "$SERVERS_FILE" ] && [ "$FORCE" != 1 ]; then
    echo "$SERVERS_FILE already exists (use --force to overwrite it)." >&2
    return 1
  fi
  [ ${#SERVERS[@]} -gt 0 ] || { echo "No SERVERS in $CONFIG to migrate." >&2; return 1; }
  local tmp
  tmp=$(mktemp "$SERVERS_FILE.XXXX")
  conf_json > "$tmp" || { rm -f "$tmp"; return 1; }
  mv "$tmp" "$SERVERS_FILE"
  echo "Wrote $SERVERS_FILE (${#SERVERS[@]} servers)."

  # comment out the moved lists in svs.conf
  mkdir -p "$DATA_DIR/.backups"
  cp -a "$CONFIG" "$DATA_DIR/.backups/svs.conf.$TS"
  tmp=$(mktemp "$CONFIG.XXXX")
  awk '
    BEGIN { mark = "# [moved to servers.json] " }
    inlist { print mark $0; if ($0 ~ /^\)/) inlist = 0; next }
    inquote { print mark $0; if ($0 ~ /^\x27[[:space:]]*$/) inquote = 0; next }
    /^(declare -A )?(SERVERS|PORTS|NO_REBOOT_SERVERS|GUESTS|EXCLUDE_CONTAINERS|WAVES)=\(/ {
      print mark $0; if ($0 !~ /\)[[:space:]]*(#.*)?$/) inlist = 1; next }
    /^declare -A CHECKS[[:space:]]*$/ { print mark $0; next }
    /^CHECKS\[[^]]*\]=\x27/ { print mark $0; rest = substr($0, index($0, "=\x27") + 2)
      if (rest !~ /\x27[[:space:]]*$/) inquote = 1; next }
    { print }
  ' "$CONFIG" > "$tmp" && cat "$tmp" > "$CONFIG"
  rm -f "$tmp"
  echo "Commented out the server lists in $CONFIG (old copy: .backups/svs.conf.$TS)."
}
