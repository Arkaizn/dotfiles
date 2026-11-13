#!/bin/bash
# SVS Server Manager — update, health-check and manage the homelab servers.
#
#   ./manage-svs.sh                  interactive menu
#   ./manage-svs.sh update --auto    unattended update of everything pending (cron)
#   ./manage-svs.sh --help           all commands and options
#
# This is the program only: it lives in the Quickshell config (scripts/servers) and
# is synced with it. Everything of yours is kept outside the config, on this machine
# only, in the data folder ($SVS_DATA, default ~/.local/share/quickshell/servers):
#   servers.json   servers, groups, health checks (lib/servers.sh)
#   svs.conf       behaviour and secrets (optional; svs.conf.sample shows every setting)
#   state/ logs/ reports/
# --json makes the output machine-readable for the Quickshell "Servers" app (lib/json.sh).

set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
REMOTE_SH="$SCRIPT_DIR/lib/remote.sh"
DATA_DIR="${SVS_DATA:-${XDG_DATA_HOME:-$HOME/.local/share}/quickshell/servers}"
mkdir -p "$DATA_DIR" && chmod 700 "$DATA_DIR" 2>/dev/null

# Defaults; svs.conf overrides them
declare -A PORTS GUESTS CHECKS
SERVERS=()
NO_REBOOT_SERVERS=()
NO_SNAPSHOT_SERVERS=()
EXCLUDE_CONTAINERS=()
WAVES=()
MAX_PARALLEL=4
STOP_ON_FAILURE=yes
CHECK_TIMEOUT=10
VERIFY_TIMEOUT=300
WATCHTOWER_IMAGE="ghcr.io/nicholas-fedor/watchtower:1.21.2"   # updates `docker run` containers (run once, per container)
SCAN_PULL=no                # yes = a scan downloads new images (the old way) instead of asking the registries
VERIFY_TIMEOUT_REBOOT=600   # the same wait after a reboot: everything starts at once
VERIFY_INTERVAL=15
REBOOT_WAIT_TIMEOUT=600
SNAPSHOT_KEEP_DAYS=3
ROLLBACK_KEEP_DAYS=7
LOG_KEEP_DAYS=60
AUTO_REBOOT=no
AUTO_ROLLBACK=containers
ASK_TIMEOUT=1800            # --json --ask: seconds to wait for an answer before the policy above applies
SNAPSHOT_REQUIRED=yes
NOTIFY_URL=""
NOTIFY_TYPE=ntfy
NOTIFY_TOKEN=""
NOTIFY_ON=always
REPORT_DIR="$DATA_DIR/reports"
LOG_DIR="$DATA_DIR/logs"

CONFIG="${SVS_CONFIG:-$DATA_DIR/svs.conf}"
# optional: without it the defaults above apply
# shellcheck source=svs.conf.sample
[ -f "$CONFIG" ] && source "$CONFIG"
# nothing is ever written into the program's own folder (it is synced to a public repo)
case "$REPORT_DIR/" in "$SCRIPT_DIR"/*) REPORT_DIR="$DATA_DIR/reports" ;; esac
case "$LOG_DIR/" in "$SCRIPT_DIR"/*) LOG_DIR="$DATA_DIR/logs" ;; esac

for lib in ui checks snapshot report parallel servers json; do
  # shellcheck source=/dev/null
  source "$SCRIPT_DIR/lib/$lib.sh"
done

TS=$(date +%Y%m%d_%H%M)
# Names of this run's log and report: to the second, and unique when two runs start
# in the same one (several updates can run side by side)
RUN_TAG=$(date +%Y%m%d_%H%M%S)
LOCK_DIR="$DATA_DIR/state/locks"
mkdir -p "$LOCK_DIR"
SNAP_NAME="svsupd_$TS"
ROLLBACK_TAG="${TS/_/-}"
RUN_DIR=$(mktemp -d)
trap 'rm -rf "$RUN_DIR"' EXIT

SSH_OPTS=(-o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new
          -o ServerAliveInterval=15 -o ServerAliveCountMax=8)

port_of() { echo "${PORTS[$1]:-22}"; }

# remote <server> <command> [args...] — run a lib/remote.sh command on a server
remote() {
  local server="$1"
  shift
  ssh "${SSH_OPTS[@]}" -p "$(port_of "$server")" "$(dest_of "$server")" "bash -s -- $(printf '%q ' "$@")" < "$REMOTE_SH"
}

# ssh_run <server> <shell command> — plain non-interactive SSH command
ssh_run() {
  local server="$1"
  shift
  ssh -n "${SSH_OPTS[@]}" -p "$(port_of "$server")" "$(dest_of "$server")" "$@"
}

# Start time of PID 1 — changes when a VM or container has rebooted
boot_marker() { ssh_run "$1" 'ps -o lstart= -p 1' 2>/dev/null; }

# wait_for_boot <server> <old boot marker> — wait until the server is back after a reboot
wait_for_boot() {
  local server="$1" old="$2" deadline=$((SECONDS + REBOOT_WAIT_TIMEOUT)) now
  sleep 15
  while ((SECONDS < deadline)); do
    now=$(boot_marker "$server")
    [ -n "$now" ] && [ "$now" != "$old" ] && return 0
    aborted "$server" && return 2
    sleep 5
  done
  return 1
}

# --- SSH Key Setup ---

# Generate a local ed25519 SSH key if none exists yet
ensure_ssh_key() {
  if ! ls ~/.ssh/id_*.pub &>/dev/null; then
    gum style --foreground 3 "No SSH key found. Generating ed25519 key..."
    ssh-keygen -t ed25519 -C "$(whoami)@$(hostname)" -f ~/.ssh/id_ed25519 -N ""
    gum style --foreground 2 "SSH key generated."
  fi
}

# Copy the local SSH public key to a server if key-based auth isn't working yet.
# Skips silently if the key is already authorized.
copy_ssh_key_if_needed() {
  local SERVER="$1"
  local PORT="$2"
  local DEST
  DEST=$(dest_of "$SERVER")

  # Test passwordless login first — if it works, nothing to do
  if ssh -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=no \
       -p "$PORT" "$DEST" true 2>/dev/null; then
    gum style --foreground 2 "✓ $SERVER — key already authorized, skipping."
    return 0
  fi

  gum style --foreground 3 "⚠ $SERVER — no key auth, running ssh-copy-id (enter password once)."

  # Pick the first available public key
  local PUBKEY
  PUBKEY=$(ls ~/.ssh/id_*.pub 2>/dev/null | head -n1)

  if [ -z "$PUBKEY" ]; then
    gum style --foreground 1 "No public key found. Skipping $SERVER."
    return 1
  fi

  if ssh-copy-id -i "$PUBKEY" -p "$PORT" "$DEST"; then
    gum style --foreground 2 "✓ Key copied to $SERVER."
  else
    # ssh-copy-id can exit non-zero even when the key was already present —
    # do a final connectivity check before declaring failure
    if ssh -o BatchMode=yes -o ConnectTimeout=5 -p "$PORT" "$DEST" true 2>/dev/null; then
      gum style --foreground 2 "✓ $SERVER — key already present, all good."
    else
      gum style --foreground 1 "✗ Failed to copy key to $SERVER."
      return 1
    fi
  fi
}

# Only bother the user (ssh-copy-id) for servers where key auth doesn't work yet
ensure_ssh_access() {
  local s
  ensure_ssh_key
  for s in "$@"; do
    ssh_run "$s" true &>/dev/null || copy_ssh_key_if_needed "$s" "$(port_of "$s")"
  done
}

# --- Server selection ---

# Present an interactive multi-select list of all servers and return the chosen ones.
# All servers are pre-selected by default.
select_servers() {
  local SELECTED_FLAGS=()
  for S in "${SERVERS[@]}"; do
    SELECTED_FLAGS+=(--selected "$S")
  done

  mapfile -t PICKED < <(
    gum choose --no-limit \
      --header "Select servers:" \
      --unselected-prefix "○ " \
      --selected-prefix "● " \
      "${SELECTED_FLAGS[@]}" \
      "${SERVERS[@]}"
  )

  # Strip any stray whitespace/control characters from gum output before returning
  local CLEANED=()
  for item in "${PICKED[@]}"; do
    item="${item// /}"
    item="${item//[$'\t\r\n']/}"
    [[ -n "$item" ]] && CLEANED+=("$item")
  done

  printf '%s\n' "${CLEANED[@]}"
}

# Present an interactive single-select list of all servers and return the chosen one.
# Used for the connect mode where only one server is picked at a time.
select_single_server() {
  local PICKED
  PICKED=$(
    gum choose \
      --header "Select a server to connect to:" \
      "${SERVERS[@]}"
  )

  # Strip stray whitespace/control characters
  PICKED="${PICKED// /}"
  PICKED="${PICKED//[$'\t\r\n']/}"

  printf '%s' "$PICKED"
}

# Fills TARGETS from --servers, the interactive picker, or all servers
resolve_targets() {
  TARGETS=()
  if [ -n "$SERVER_ARG" ]; then
    local s
    IFS=',' read -ra TARGETS <<< "$SERVER_ARG"
    for s in "${TARGETS[@]}"; do
      in_list "$s" "${SERVERS[@]}" || { say 1 "Unknown server '$s' (not in servers.json / SERVERS in svs.conf, or archived)"; return 1; }
    done
  elif use_gum; then
    mapfile -t TARGETS < <(select_servers)
  else
    TARGETS=("${SERVERS[@]}")
  fi
  [ ${#TARGETS[@]} -gt 0 ] || { say 1 "No servers selected, exiting."; return 1; }
}

# Ask how reboots should be handled for this run (only when not set by --reboot).
#   none   -> never reboot, just report "reboot pending"
#   ask    -> ask for each server that actually needs a reboot
#   auto   -> reboot every server that needs it
select_reboot_mode() {
  [ -n "$REBOOT_MODE" ] && return
  if ! use_gum; then
    if [ "$AUTO_REBOOT" = yes ]; then REBOOT_MODE=auto; else REBOOT_MODE=none; fi
    return
  fi
  case "$(gum choose --header "How should reboots be handled? (NO_REBOOT_SERVERS are never rebooted)" \
            "Ask me for each server that needs one" \
            "No reboots (just report them as pending)" \
            "Reboot automatically when needed")" in
    "No reboots"*) REBOOT_MODE=none ;;
    "Reboot automatically"*) REBOOT_MODE=auto ;;
    *) REBOOT_MODE=ask ;;
  esac
}

# --- Scanning ---

declare -A REACHABLE OS_PENDING SEC_PENDING CT_PENDING REBOOT_PENDING IS_PROXMOX PM_OF SEL_OS SEL_CT CT_PLAIN PLAIN_PENDING SEL_PLAIN

# Scan servers in parallel (pending packages, new container images, reboot needed).
# Raw results land in $RUN_DIR/scan.<server>
scan_servers() {
  local s
  say 8 "Scanning $# server(s)$([ "$SCAN_PULL" = yes ] && echo " — this pulls new container images and can take a few minutes")..."
  for s in "$@"; do
    (
      echo "$BASHPID" > "$RUN_DIR/scanpid.$s"
      remote "$s" scan $([ "$SCAN_PULL" = yes ] && echo pull) > "$RUN_DIR/scan.$s" 2> "$RUN_DIR/scan.$s.err"
      rc=$?
      aborted "$s" && exit 0            # its ssh was killed: the main loop reports it
      if [ $rc -eq 255 ]; then
        echo "UNREACHABLE|$(tail -n1 "$RUN_DIR/scan.$s.err")" > "$RUN_DIR/scan.$s"
        say 1 "  ✗ $s unreachable"
      else
        say 8 "  ✓ $s"
      fi
      scan_json "$s" "$RUN_DIR/scan.$s" > "$RUN_DIR/scanjson.$s"
      [ "$JSON" = 1 ] && cat "$RUN_DIR/scanjson.$s" >&3
    ) &
  done
  # wait for them; a server the user aborts (a scan that hangs) is cut off: its last
  # scan stays as it was
  local p
  while [ -n "$(jobs -rp)" ]; do
    for s in "$@"; do
      if aborted "$s" && [ -s "$RUN_DIR/scanpid.$s" ] && [ ! -e "$RUN_DIR/scanjson.$s" ]; then
        p=$(cat "$RUN_DIR/scanpid.$s")
        rm -f "$RUN_DIR/scanpid.$s"
        pkill -TERM -P "$p" 2>/dev/null
        say 3 "  ⊘ $s aborted"
        emit --arg s "$s" '{event: "aborted", server: $s}'
      fi
    done
    sleep 1
  done
  wait
  # the latest scan of every server, for the Servers app (state/last-scan.json)
  local files=()
  for s in "$@"; do [ -s "$RUN_DIR/scanjson.$s" ] && files+=("$RUN_DIR/scanjson.$s"); done
  state_merge last-scan.json "${files[@]}"
}

parse_scan() {
  local s="$1" line
  REACHABLE[$s]=1
  REBOOT_PENDING[$s]=0
  while IFS= read -r line; do
    case "$line" in
      UNREACHABLE\|*) REACHABLE[$s]=0; r_add R_ISSUES "$s" "unreachable via SSH: ${line#UNREACHABLE|}" ;;
      PKG\|*)         r_add OS_PENDING "$s" "${line#PKG|}" ;;
      SEC\|*)         r_add SEC_PENDING "$s" "${line#SEC|}" ;;
      PM\|*)          PM_OF[$s]=${line#PM|} ;;
      REBOOT\|1)      REBOOT_PENDING[$s]=1 ;;
      PROXMOX\|1)     IS_PROXMOX[$s]=1 ;;
      CTUPD\|*)       r_add CT_PENDING "$s" "${line#CTUPD|}" ;;
      CTSKIP\|*\|missing\|*) r_add R_NOTES "$s" "container $(awk -F'|' '{ print $2 ": " $4 }' <<< "$line")" ;;
      PLAINUPD\|*)   r_add PLAIN_PENDING "$s" "${line#PLAINUPD|}" ;;
      CTSKIP\|*\|plain\|*)   r_add CT_PLAIN "$s" "$(cut -d'|' -f2 <<< "$line")" ;;
      WARN\|*)        r_add R_NOTES "$s" "${line#WARN|}" ;;
    esac
  done < "$RUN_DIR/scan.$s"
}

# ct_desc <CTUPD payload> — "name (old -> new)" using image versions where available
ct_desc() {
  local name project service ref oldid newid oldver newver from to
  IFS='|' read -r name project service ref oldid newid oldver newver _ <<< "$1"
  from=${oldid#sha256:}; from=${from:0:12}
  to=${newid#sha256:}; to=${to:0:12}
  [ -n "$to" ] || to="newer image"      # a scan that didn't download it
  if [ -n "$oldver" ] && [ -n "$newver" ] && [ "$oldver" != "$newver" ]; then
    from=$oldver
    to=$newver
  fi
  echo "$name ($from -> $to)"
}

ct_name() { echo "${1%%|*}"; }

show_overview() {
  local s p
  title "Pending updates"
  {
    echo "SERVER|PACKAGES|CONTAINERS|REBOOT PENDING"
    for s in "$@"; do
      if [ "${REACHABLE[$s]}" = 0 ]; then
        echo "$s|unreachable|-|-"
        continue
      fi
      echo "$s|$(count_lines "${OS_PENDING[$s]}")|$(count_lines "${CT_PENDING[$s]}")|$([ "${REBOOT_PENDING[$s]}" = 1 ] && echo yes || echo -)"
    done
  } | table
  for s in "$@"; do
    while IFS= read -r p; do
      [ -n "$p" ] && say 8 "  $s › $(ct_desc "$p")"
    done <<< "${CT_PENDING[$s]}"
  done
  for s in "$@"; do
    while IFS= read -r p; do
      [ -n "$p" ] && say 3 "  ⚠ $s: $p"
    done <<< "${R_NOTES[$s]}"
  done
}

# Decide what gets updated: interactive pickers, or everything (minus excludes) in --auto
select_updates() {
  local s p label picked=()
  local ct_labels=() ct_selected=() os_labels=() os_selected=()
  declare -A ct_map os_map

  for s in "$@"; do
    while IFS= read -r p; do
      [ -n "$p" ] || continue
      [ "$ONLY" = security ] || [ "$ONLY" = os ] && continue   # containers aren't part of this run
      # this server's containers are left alone / only get their images downloaded
      case "$(ct_mode "$s")" in
        never) [ "$RESTART_PULLED" = 1 ] || continue ;;
        pull)  [ "$RESTART_PULLED" = 1 ] || [ "${p##*|}" != pulled ] || continue ;;   # already downloaded: nothing left to do
      esac
      label="$s › $(ct_desc "$p" | tr ',' ';')"
      ct_labels+=("$label")
      ct_map[$label]="$s"$'\t'"$p"
      if [ -n "$CT_PICK" ] && [[ ",$CT_PICK," != *",$s:$(ct_name "$p"),"* ]]; then
        :                                   # --containers: only the listed ones
      elif excluded_ct "$s" "$(ct_name "$p")"; then
        use_gum || r_add R_NOTES "$s" "not updated (EXCLUDE_CONTAINERS): $(ct_desc "$p")"
      else
        ct_selected+=(--selected "$label")
      fi
    done <<< "${CT_PENDING[$s]}"
    # `docker run` containers: only where the server allows it, and never "pull only"
    if in_list "$s" "${PLAIN_OK[@]}" && [ "$ONLY" != security ] && [ "$ONLY" != os ] && [ "$(ct_mode "$s")" = update ]; then
      while IFS='|' read -r p _; do
        [ -n "$p" ] || continue
        excluded_ct "$s" "$p" && continue
        [ -n "$CT_PICK" ] && [[ ",$CT_PICK," != *",$s:$p,"* ]] && continue
        r_add SEL_PLAIN "$s" "$p"
      done <<< "${PLAIN_PENDING[$s]}"
    fi
    if [ "$ONLY" = containers ]; then
      :
    elif [ "$ONLY" = security ]; then
      if [ -n "${SEC_PENDING[$s]}" ]; then
        label="$s ($(count_lines "${SEC_PENDING[$s]}") security packages)"
        os_labels+=("$label")
        os_selected+=(--selected "$label")
        os_map[$label]=$s
      fi
    elif [ -n "${OS_PENDING[$s]}" ]; then
      label="$s ($(count_lines "${OS_PENDING[$s]}") packages)"
      os_labels+=("$label")
      os_selected+=(--selected "$label")
      os_map[$label]=$s
    fi
  done

  if ! use_gum; then
    picked=()
    for ((i = 1; i < ${#ct_selected[@]}; i += 2)); do picked+=("${ct_selected[i]}"); done
  elif [ ${#ct_labels[@]} -gt 0 ]; then
    mapfile -t picked < <(gum choose --no-limit --height 25 \
      --header "Containers to update (space = toggle, enter = confirm):" \
      "${ct_selected[@]}" "${ct_labels[@]}") || return 1
  fi
  for label in "${picked[@]}"; do
    [ -n "${ct_map[$label]}" ] || continue
    IFS=$'\t' read -r s p <<< "${ct_map[$label]}"
    r_add SEL_CT "$s" "$p"
  done

  picked=()
  if ! use_gum; then
    picked=("${os_labels[@]}")
  elif [ ${#os_labels[@]} -gt 0 ]; then
    mapfile -t picked < <(gum choose --no-limit \
      --header "System package updates (space = toggle, enter = confirm):" \
      "${os_selected[@]}" "${os_labels[@]}") || return 1
  fi
  for label in "${picked[@]}"; do
    [ -n "${os_map[$label]}" ] && SEL_OS[${os_map[$label]}]=1
  done
  return 0
}

# --- Updating ---

reboot_allowed() {
  [ "$REBOOT_MODE" != none ] && [ "${IS_PROXMOX[$1]}" != 1 ] && ! in_list "$1" "${NO_REBOOT_SERVERS[@]}"
}

handle_reboot() {
  local s="$1" marker
  if [ "$(remote "$s" reboot-needed 2>/dev/null)" != "REBOOT|1" ]; then
    R_REBOOT[$s]="-"
    return 0
  fi
  # Proxmox VE/PBS machines are never rebooted by this script, whatever the reboot mode
  # (lib/remote.sh refuses it as well)
  if [ "${IS_PROXMOX[$s]}" = 1 ] || remote "$s" is-proxmox &>/dev/null; then
    say 3 "⚠ $s needs a reboot — Proxmox machines are never rebooted by this script, reboot it manually."
    R_REBOOT[$s]=manual
    return 0
  fi
  if in_list "$s" "${NO_REBOOT_SERVERS[@]}"; then
    say 3 "Reboot needed, but $s is in NO_REBOOT_SERVERS — reboot it yourself."
    R_REBOOT[$s]=pending
    return 0
  fi
  case "$REBOOT_MODE" in
    none)
      say 3 "Reboot needed (skipped, reboot mode is 'none')."
      R_REBOOT[$s]=pending
      return 0
      ;;
    ask)
      if ! ask "$s needs a reboot. Reboot now?"; then
        R_REBOOT[$s]=pending
        return 0
      fi
      ;;
  esac

  marker=$(boot_marker "$s")
  phase "rebooting"
  say 3 "Rebooting $s..."
  if ! remote "$s" reboot &>/dev/null; then
    say 1 "✗ $s refused the reboot — reboot it manually."
    R_REBOOT[$s]=manual
    return 0
  fi
  local brc
  wait_for_boot "$s" "$marker"
  brc=$?
  if [ $brc -eq 0 ]; then
    say 2 "✓ $s is back up."
    R_REBOOT[$s]=rebooted
  elif [ $brc -eq 2 ]; then
    say 3 "Stopped waiting for $s to come back (aborted)."
    R_REBOOT[$s]=rebooted
    r_add R_NOTES "$s" "rebooted, but the wait for it to come back was aborted"
  else
    say 1 "✗ $s did not come back within ${REBOOT_WAIT_TIMEOUT}s."
    R_REBOOT[$s]=failed
    r_add R_ISSUES "$s" "did not come back after reboot"
  fi
}

# rollback_containers <server> — put the containers updated in this run back on their old image
rollback_containers() {
  local s="$1" payloads
  mapfile -t payloads < <(printf '%s' "${SEL_CT[$s]}")
  remote "$s" ct-rollback "${payloads[@]}" 2>&1 | grep -v '^[A-Z]*|' | tee -a "$LOG_FILE"
}

# handle_failure <server> <problems> — offer (or, with --auto, apply AUTO_ROLLBACK) a rollback
handle_failure() {
  local s="$1" problems="$2" choice="" options=() marker after
  local opt_ct="Roll back the updated containers"
  local opt_snap="Roll back the whole server to snapshot $SNAP_NAME (undoes ALL changes since)"
  local opt_keep="Keep it as is"

  [ -n "${SEL_CT[$s]}" ] && options+=("$opt_ct")
  [ "${R_SNAP[$s]}" = "$SNAP_NAME" ] && options+=("$opt_snap")
  options+=("$opt_keep")

  # why one would roll back, and when not (shown with the question in the Servers app)
  ASK_DETAIL="Not healthy after the update of $s:
$(sed 's/^/  • /' <<< "$problems")

Roll back when these worked before and the update broke them:$([ -n "${SEL_CT[$s]}" ] && printf '\n  • containers: the updated ones go back to their previous images (packages stay updated)')$([ "${R_SNAP[$s]}" = "$SNAP_NAME" ] && printf '\n  • snapshot: the whole server goes back to before the update, packages too (it restarts)')
Keep it as is when the cause is something else (a slow start, DNS / VPN down, another server it needs) or you want to fix it by hand: nothing is undone, the server counts as failed."
  if ! choice=$(prompt_choice "Verification failed on $s ($(count_lines "$problems") problem(s)). What now?" "${options[@]}"); then
    case "$AUTO_ROLLBACK" in
      containers) in_list "$opt_ct" "${options[@]}" && choice=$opt_ct ;;
      snapshot)
        if in_list "$opt_snap" "${options[@]}"; then choice=$opt_snap
        elif in_list "$opt_ct" "${options[@]}"; then choice=$opt_ct
        fi
        ;;
    esac
  fi
  ASK_DETAIL=""

  case "$choice" in
    "$opt_ct")
      phase "rolling back containers"
      say 3 "Rolling back containers on $s..."
      rollback_containers "$s"
      r_add R_NOTES "$s" "containers rolled back to their previous images"
      ;;
    "$opt_snap")
      phase "rolling back to snapshot"
      say 3 "Rolling back $s to $SNAP_NAME..."
      marker=$(boot_marker "$s")
      snap_rollback "$s"
      wait_for_boot "$s" "$marker" || say 1 "✗ $s did not come back after the rollback."
      r_add R_NOTES "$s" "server rolled back to snapshot $SNAP_NAME (package and container updates undone)"
      ;;
    *)
      R_STATUS[$s]=failed
      while IFS= read -r p; do r_add R_ISSUES "$s" "$p"; done <<< "$problems"
      return
      ;;
  esac

  phase "verifying after rollback"
  say 8 "Verifying after rollback..."
  while IFS= read -r p; do r_add R_ISSUES "$s" "after update: $p"; done <<< "$problems"
  local arc
  after=$(verify "$s")
  arc=$?
  if [ $arc -eq 0 ]; then
    say 2 "✓ Checks pass again after the rollback."
    R_STATUS[$s]=rolled-back
  elif [ $arc -eq 2 ]; then
    say 3 "Stopped verifying after the rollback (aborted)."
    R_STATUS[$s]=aborted
    r_add R_NOTES "$s" "rolled back; the verification after it was aborted, not healthy at that moment: $(paste -sd ';' <<< "$after")"
  else
    say 1 "✗ Still failing after the rollback:"
    say 1 "$(sed 's/^/  /' <<< "$after")"
    R_STATUS[$s]=failed
    while IFS= read -r p; do r_add R_ISSUES "$s" "after rollback: $p"; done <<< "$after"
  fi
}

# pull_images <server> — download the new images of the selected containers. Fills in
# the new image id / version of containers a scan only knew as "the registry has a newer one".
pull_images() {
  local s="$1" out payloads p name id ver new=()
  mapfile -t payloads < <(printf '%s' "${SEL_CT[$s]}")
  phase "downloading ${#payloads[@]} image(s)"
  say 212 "Downloading ${#payloads[@]} new image(s)..."
  out=$(remote "$s" ct-pull "${payloads[@]}" 2>&1)
  grep -v '^[A-Z]*|' <<< "$out" | tee -a "$LOG_FILE"
  while IFS='|' read -r _ p; do
    [ -n "$p" ] && r_add R_ISSUES "$s" "downloading the images of compose project $p failed"
  done <<< "$(grep '^PULLFAIL|' <<< "$out")"
  for p in "${payloads[@]}"; do
    name=$(ct_name "$p")
    IFS='|' read -r _ _ id ver <<< "$(grep -m1 "^NEW|$name|" <<< "$out")"
    [ -n "$id" ] && p=$(awk -F'|' -v OFS='|' -v id="$id" -v ver="$ver" '{ $6 = id; $8 = ver; print }' <<< "$p")
    new+=("$p")
  done
  SEL_CT[$s]=$(printf '%s\n' "${new[@]}")
  SEL_CT[$s]=${SEL_CT[$s]%$'\n'}
}

# update_plain <server> — the selected `docker run` containers, through Watchtower
update_plain() {
  local s="$1" out names line kind name id ver
  [ -n "${SEL_PLAIN[$s]}" ] || return 0
  mapfile -t names < <(printf '%s' "${SEL_PLAIN[$s]}")
  phase "updating ${#names[@]} plain container(s)"
  say 212 "Updating ${#names[@]} container(s) started with docker run (Watchtower, once)..."
  out=$(remote "$s" plain-update "$ROLLBACK_TAG" "$WATCHTOWER_IMAGE" "${names[@]}" 2>&1)
  grep -v '^[A-Z]*|' <<< "$out" | tee -a "$LOG_FILE"
  while IFS='|' read -r kind name id ver; do
    case "$kind" in
      PLAINOK)   r_add R_CT "$s" "$name (plain container${ver:+, now $ver})" ;;
      PLAINSAME) r_add R_NOTES "$s" "plain container $name: Watchtower found nothing newer" ;;
      PLAINFAIL) r_add R_ISSUES "$s" "updating the plain container $name failed — see the log"; R_STATUS[$s]=failed ;;
    esac
  done <<< "$(grep '^PLAIN[A-Z]*|' <<< "$out")"
  r_add R_NOTES "$s" "plain containers can't be rolled back by the tool; the old images are kept as svs-rollback/<name>:$ROLLBACK_TAG"
}

# update_containers <server> — recreate the selected containers on their new images
update_containers() {
  local s="$1" out p payloads failed_projects
  update_plain "$s"
  [ -n "${SEL_CT[$s]}" ] || return 0
  phase "updating $(count_lines "${SEL_CT[$s]}") container(s)"
  say 212 "Updating $(count_lines "${SEL_CT[$s]}") container(s)..."
  mapfile -t payloads < <(printf '%s' "${SEL_CT[$s]}")
  out=$(remote "$s" ct-update "$ROLLBACK_TAG" "${payloads[@]}" 2>&1)
  grep -v '^[A-Z]*|' <<< "$out" | tee -a "$LOG_FILE"
  failed_projects=$(grep '^UPDFAIL|' <<< "$out" | cut -d'|' -f2)
  for p in "${payloads[@]}"; do
    if grep -qxF "$(cut -d'|' -f2 <<< "$p")" <<< "$failed_projects"; then
      r_add R_ISSUES "$s" "container update failed: $(ct_desc "$p")"
      R_STATUS[$s]=failed
    else
      r_add R_CT "$s" "$(ct_desc "$p")"
    fi
  done
}

update_server() {
  local s="$1" out rc p problems prefail payloads failed_projects
  local has_updates=0
  # (only downloading images changes nothing that runs: no snapshot for that alone)
  if [ "${SEL_OS[$s]}" = 1 ] || [ -n "${SEL_PLAIN[$s]}" ] || { [ -n "${SEL_CT[$s]}" ] && { [ "$RESTART_PULLED" = 1 ] || [ "$(ct_mode "$s")" != pull ]; }; }; then has_updates=1; fi

  box "Updating $s"
  R_STATUS[$s]=ok
  # at a safe point: stop here when the user aborted this server (or the run)
  stop_here() {
    aborted "$s" || return 1
    say 3 "⊘ $s aborted before $1."
    R_STATUS[$s]=aborted
    r_add R_NOTES "$s" "aborted before $1"
    return 0
  }

  # 1. Baseline: whatever already fails now won't be blamed on the update
  phase "baseline checks"
  say 8 "Baseline health checks..."
  run_checks "$s" pre
  prefail=$({ failed_checks "$s" pre; unhealthy_containers "$s" pre; })
  if [ -n "$prefail" ]; then
    say 3 "Already failing before the update:"
    say 3 "$(sed 's/^/  /' <<< "$prefail")"
    while IFS= read -r p; do r_add R_NOTES "$s" "already failing before the update: $p"; done <<< "$prefail"
  fi

  stop_here "anything was changed" && return

  # 2. Snapshot of the VM/CT
  if [ "$has_updates" = 0 ]; then
    R_SNAP[$s]="-"
  elif [ -z "${GUESTS[$s]}" ]; then
    R_SNAP[$s]="n/a"
  elif [ "$NO_SNAPSHOT" = 1 ]; then
    R_SNAP[$s]="disabled"
  elif in_list "$s" "${NO_SNAPSHOT_SERVERS[@]}"; then
    # e.g. an LXC container with a bind mount: Proxmox can't snapshot it
    R_SNAP[$s]="off for this server"
  elif phase "snapshot" && out=$(snap_create "$s"); then
    R_SNAP[$s]=$SNAP_NAME
    say 2 "✓ Snapshot $SNAP_NAME taken"
  else
    R_SNAP[$s]=failed
    say 1 "✗ Snapshot failed: $out"
    if [ "$SNAPSHOT_OPTIONAL" = 1 ]; then
      say 3 "Updating $s without a snapshot (--snapshot-optional)."
    elif can_prompt; then
      ASK_DETAIL="The Proxmox snapshot of $s couldn't be taken: $out
Without it there is no way back to before the update if something breaks (its containers can still be rolled back)."
      if ! ask "Continue updating $s without a snapshot?"; then
        ASK_DETAIL=""
        R_STATUS[$s]=skipped
        r_add R_NOTES "$s" "skipped: snapshot failed ($out)"
        return
      fi
      ASK_DETAIL=""
    elif [ "$SNAPSHOT_REQUIRED" = yes ]; then
      R_STATUS[$s]=skipped
      r_add R_ISSUES "$s" "not updated: snapshot failed ($out)"
      return
    fi
  fi

  stop_here "the update started (the snapshot stays)" && return

  # 3. Containers. New images are downloaded first, while everything still runs. Then:
  #    - "pull only" (a server that must never restart by itself): that's all. The
  #      images wait until the containers are restarted by hand (--restart-pulled).
  #    - the server may reboot in this run: its containers are taken down right before
  #      the reboot and come up on the new images after it — down once, not twice.
  #    - otherwise containers before packages: once Arch upgrades the kernel, the running
  #      kernel's modules are gone until reboot, which can break recreating containers.
  local ctmode late=0
  ctmode=$(ct_mode "$s")
  [ "$RESTART_PULLED" = 1 ] && ctmode=update
  if [ -n "${SEL_CT[$s]}${SEL_PLAIN[$s]}" ]; then
    [ -n "${SEL_CT[$s]}" ] && pull_images "$s"
    if [ "$ctmode" = pull ] && [ -n "${SEL_CT[$s]}" ]; then
      mapfile -t payloads < <(printf '%s' "${SEL_CT[$s]}")
      r_add R_NOTES "$s" "new images downloaded, containers not restarted (this server's containers are \"pull only\"): $(for p in "${payloads[@]}"; do ct_name "$p"; done | paste -sd, | sed 's/,/, /g')"
      r_add R_NOTES "$s" "restart them when it suits you: $(basename "$0") update --servers $s --only containers --restart-pulled"
      SEL_CT[$s]=""               # nothing of them was touched: nothing to verify or roll back
    elif [ -n "${SEL_CT[$s]}" ] && [ "$REBOOT_MODE" = auto ] && reboot_allowed "$s" && { [ "${SEL_OS[$s]}" = 1 ] || [ "${REBOOT_PENDING[$s]}" = 1 ]; }; then
      late=1
    else
      update_containers "$s"
    fi
  fi

  # 4. System packages
  if [ "${SEL_OS[$s]}" = 1 ] && stop_here "the packages (containers are updated)"; then
    return
  elif [ "${SEL_OS[$s]}" = 1 ]; then
    local done_pkgs=${OS_PENDING[$s]} sec=()
    if [ "$ONLY" = security ] && [ "${PM_OF[$s]}" != pacman ]; then
      # just the security packages (Arch has no safe partial upgrade: full upgrade there)
      mapfile -t sec < <(printf '%s' "${SEC_PENDING[$s]}")
      done_pkgs=$(awk 'NR == FNR { sec[$1] = 1; next } ($1 in sec)' <(printf '%s\n' "${sec[@]}") <(printf '%s' "${OS_PENDING[$s]}"))
      phase "updating ${#sec[@]} security package(s)"
      say 212 "Updating security packages: ${sec[*]}"
      remote "$s" os-update-only "${sec[@]}" 2>&1 | tee -a "$LOG_FILE"
    else
      phase "updating $(count_lines "${OS_PENDING[$s]}") package(s)"
      say 212 "Updating system packages..."
      remote "$s" os-update 2>&1 | tee -a "$LOG_FILE"
    fi
    rc=${PIPESTATUS[0]}
    if [ "$rc" -eq 0 ]; then
      R_PKGS[$s]=$done_pkgs
      say 2 "✓ System packages updated."
    else
      say 1 "✗ System update failed (exit $rc)."
      r_add R_ISSUES "$s" "system update failed (exit $rc) — see the log"
      R_STATUS[$s]=failed
    fi
  fi

  # 5. Reboot if the update needs one
  if stop_here "the reboot check and the verification$([ "$late" = 1 ] && echo " (the containers are not updated yet)" || echo " (the update itself is done)")"; then return; fi
  if [ "$late" = 1 ]; then
    if [ "$(remote "$s" reboot-needed 2>/dev/null)" = "REBOOT|1" ]; then
      mapfile -t payloads < <(printf '%s' "${SEL_CT[$s]}")
      phase "stopping ${#payloads[@]} container(s) for the reboot"
      say 212 "Stopping ${#payloads[@]} container(s): they come back on the new images after the reboot..."
      remote "$s" ct-down "$ROLLBACK_TAG" "${payloads[@]}" 2>&1 | grep -v '^[A-Z]*|' | tee -a "$LOG_FILE"
      handle_reboot "$s"
      # also when the reboot was refused or the wait was cut short: they must come back
      [ "${R_REBOOT[$s]}" = failed ] || update_containers "$s"
    else
      update_containers "$s"
      R_REBOOT[$s]="-"
    fi
  else
    handle_reboot "$s"
  fi

  # 6. Verify against the baseline
  phase "verifying"
  say 8 "Verifying (waiting up to ${VERIFY_TIMEOUT}s for everything to come back)..."
  local vrc
  problems=$(verify "$s")
  vrc=$?
  if [ $vrc -eq 2 ]; then
    # the user stopped the wait: nothing is rolled back, it's reported as it is
    say 3 "⊘ Verification of $s aborted. Not healthy at that moment:"
    say 3 "$(sed 's/^/  /' <<< "$problems")"
    R_STATUS[$s]=aborted
    r_add R_NOTES "$s" "updated; the verification was aborted, not healthy at that moment: $(paste -sd ';' <<< "$problems")"
  elif [ $vrc -eq 0 ]; then
    say 2 "✓ All checks passed."
    # 7. Clean up old rollback images and snapshots (never the ones from this run)
    if [ "${R_STATUS[$s]}" = ok ]; then
      phase "cleaning up old rollback images/snapshots"
      remote "$s" cleanup "$ROLLBACK_KEEP_DAYS" 2>&1 | tee -a "$LOG_FILE"
      snap_cleanup "$s"
      # --drop-snapshot: this run's snapshot isn't needed any more (the update and its checks passed)
      if [ "$DROP_SNAPSHOT" = 1 ] && [ "${R_SNAP[$s]}" = "$SNAP_NAME" ] && guest_info "$s"; then
        if node_snap_delete "$G_NODE" "$G_TOOL" "$G_VMID" "$SNAP_NAME" &>/dev/null; then
          say 8 "  removed this run's snapshot $SNAP_NAME (update passed)"
          R_SNAP[$s]="$SNAP_NAME (deleted after success)"
        else
          say 3 "  couldn't remove snapshot $SNAP_NAME — it's deleted after SNAPSHOT_KEEP_DAYS"
        fi
      fi
    fi
  else
    split_problems "$s" "$problems"
    if [ -z "$HARD" ]; then
      # nothing here is something this update changed: rolling back wouldn't help and
      # would only restart what works. Left as it is, for a person to look at.
      say 3 "⚠ Not healthy yet, but not because of this update:"
      say 3 "$(sed 's/^/  /' <<< "$SOFT")"
      say 3 "Nothing was rolled back. Check again later: $(basename "$0") check --servers $s"
      R_STATUS[$s]=needs-look
      while IFS= read -r p; do r_add R_NOTES "$s" "needs a look: $p"; done <<< "$SOFT"
      r_add R_NOTES "$s" "nothing was rolled back (none of this was changed by the update)"
    else
      say 1 "✗ Problems after the update:"
      say 1 "$(sed 's/^/  /' <<< "$problems")"
      handle_failure "$s" "$problems"
    fi
  fi
}

# --- Modes ---

run_update() {
  local s pending=() todo=()
  [ "$DRY_RUN" = 1 ] && RUN_MODE=scan || RUN_MODE=update
  title "=== Server Update$([ "$DRY_RUN" = 1 ] && echo " (dry run — nothing will be changed)") ==="

  resolve_targets || return 1
  emit_start "$RUN_MODE"
  use_gum && ensure_ssh_access "${TARGETS[@]}"

  scan_servers "${TARGETS[@]}"
  for s in "${TARGETS[@]}"; do
    parse_scan "$s"
    R_ORDER+=("$s")
    if [ ! -e "$RUN_DIR/scanjson.$s" ] && aborted "$s"; then
      R_STATUS[$s]=aborted                # its scan was cut off: nothing known, nothing done
    elif [ "${REACHABLE[$s]}" = 0 ]; then
      R_STATUS[$s]=unreachable
    elif [ -n "${OS_PENDING[$s]}${CT_PENDING[$s]}" ] || [ "${REBOOT_PENDING[$s]}" = 1 ] \
         || { [ -n "${PLAIN_PENDING[$s]}" ] && in_list "$s" "${PLAIN_OK[@]}"; }; then
      pending+=("$s")
    else
      R_STATUS[$s]=up-to-date
    fi
  done
  show_overview "${TARGETS[@]}"

  if [ "$DRY_RUN" = 1 ]; then
    for s in "${pending[@]}"; do
      R_STATUS[$s]=pending
      R_PKGS[$s]=${OS_PENDING[$s]}
      while IFS= read -r p; do [ -n "$p" ] && r_add R_CT "$s" "$(ct_desc "$p")"; done <<< "${CT_PENDING[$s]}"
      [ "${REBOOT_PENDING[$s]}" = 1 ] && R_REBOOT[$s]=pending
    done
    finish_report
    return
  fi

  if [ ${#pending[@]} -eq 0 ]; then
    say 2 "Everything is up to date."
    finish_report
    return
  fi

  select_updates "${pending[@]}" || { say 1 "Cancelled."; return 1; }
  select_reboot_mode

  # Servers with selected updates, or with only a pending reboot that may be done now
  for s in "${pending[@]}"; do
    if [ -n "${SEL_CT[$s]}${SEL_OS[$s]}${SEL_PLAIN[$s]}" ] || { [ "${REBOOT_PENDING[$s]}" = 1 ] && reboot_allowed "$s"; }; then
      todo+=("$s")
    else
      R_STATUS[$s]=skipped
      [ "${REBOOT_PENDING[$s]}" = 1 ] && R_REBOOT[$s]=pending
    fi
  done

  if [ ${#todo[@]} -eq 0 ]; then
    say 3 "Nothing selected."
    finish_report
    return
  fi
  build_waves "${todo[@]}"
  emit --args '{event: "plan", waves: ($ARGS.positional | map(split(" ")))}' "${WAVE_LIST[@]}"
  title "Plan (max $MAX_PARALLEL servers at once, next wave starts when the previous one is done)"
  local i
  for i in "${!WAVE_LIST[@]}"; do
    say 8 "  Wave $((i + 1)): ${WAVE_LIST[$i]}"
  done
  if use_gum && ! ask "Update ${#todo[@]} server(s) now?"; then
    say 1 "Cancelled."
    return 1
  fi

  run_parallel "${todo[@]}"
  state_mark_stale "${todo[@]}"
  finish_report
}

run_check() {
  local s
  RUN_MODE=check
  title "=== Health Check ==="
  resolve_targets || return 1
  emit_start check

  # every server at once, each in its own process; its result fields come back
  # through a file (like the update workers)
  for s in "${TARGETS[@]}"; do
    R_ORDER+=("$s")
    (
      check_server "$s"
      save_result "$s" > "$RUN_DIR/checkres.$s.tmp" && mv "$RUN_DIR/checkres.$s.tmp" "$RUN_DIR/checkres.$s"
    ) &
  done
  wait

  local events=()
  for s in "${TARGETS[@]}"; do
    if [ -f "$RUN_DIR/checkres.$s" ]; then
      # shellcheck source=/dev/null
      source "$RUN_DIR/checkres.$s"
    else
      R_STATUS[$s]=unhealthy
      r_add R_ISSUES "$s" "the health check ended unexpectedly"
    fi
    [ -s "$RUN_DIR/checkjson.$s" ] && events+=("$RUN_DIR/checkjson.$s")
  done
  state_merge last-check.json "${events[@]}"
  finish_report
}

# check_server <server> — its health checks: sets R_STATUS / R_ISSUES, prints the result
# line, writes (and with --json emits) its check event
check_server() {
  local s="$1" issues n_ct p reach=1
  if ! ssh_run "$s" true &>/dev/null; then
    reach=0
    R_STATUS[$s]=unreachable
    r_add R_ISSUES "$s" "unreachable via SSH"
    # the http/tcp/dns checks don't need SSH: still run them
    NO_SSH[$s]=1
    run_checks "$s" pre
    say 1 "✘ $s — unreachable via SSH"
  else
    run_checks "$s" pre
    issues=$({ failed_checks "$s" pre; unhealthy_containers "$s" pre; })
    if [ -z "$issues" ]; then
      R_STATUS[$s]=healthy
      n_ct=$(count_lines "${CTSTATE[pre|$s]}")
      say 2 "✔ $s — $(check_lines "$s" | grep -c .) checks ok$([ "$n_ct" -gt 0 ] && echo ", $n_ct containers ok")"
    else
      R_STATUS[$s]=unhealthy
      say 1 "✘ $s
$(sed 's/^/    /' <<< "$issues")"
      while IFS= read -r p; do r_add R_ISSUES "$s" "$p"; done <<< "$issues"
    fi
  fi
  check_json "$s" "$reach" > "$RUN_DIR/checkjson.$s"
  [ "$JSON" = 1 ] && cat "$RUN_DIR/checkjson.$s" >&3
  return 0
}

# Snapshot cleanup: list every snapshot this script made (svsupd_*) on all Proxmox
# nodes and bulk-delete the chosen ones. Manual snapshots are never touched.
run_snapshots() {
  local line node tool vmid name snap label age lines=() labels=() selected=() picked=()
  declare -A snap_map
  RUN_MODE=snapshots
  title "=== Update Snapshots ==="
  probe_nodes
  [ ${#DOWN_NODES[@]} -gt 0 ] && say 1 "Unreachable, skipped: ${DOWN_NODES[*]}"

  say 8 "Storage before:"
  while IFS= read -r line; do [ -n "$line" ] && say 8 "  $line"; done <<< "$(pool_usage)"

  mapfile -t lines < <(snap_list_all)
  if [ "$JSON" = 1 ]; then
    run_snapshots_json "${lines[@]}"
    return
  fi
  if [ ${#lines[@]} -eq 0 ]; then
    say 2 "No update snapshots found."
    return 0
  fi

  local rows="GUEST|VMID|NODE|SNAPSHOT|AGE"
  for line in "${lines[@]}"; do
    IFS='|' read -r _ node tool vmid name snap <<< "$line"
    age=$(( ($(date +%s) - $(date -d "${snap:7:8}" +%s)) / 86400 ))
    rows+=$'\n'"$name|$vmid|$node|$snap|${age}d"
    label="$name ($vmid on $node) › $snap"
    labels+=("$label")
    snap_map[$label]="$node|$tool|$vmid|$snap"
    [ "$age" -ge "${OLDER_THAN:-0}" ] && selected+=(--selected "$label")
  done
  table <<< "$rows"

  if use_gum; then
    mapfile -t picked < <(gum choose --no-limit --height 25 \
      --header "Snapshots to delete (space = toggle, enter = confirm):" \
      "${selected[@]}" "${labels[@]}") || { say 1 "Cancelled."; return 1; }
    [ ${#picked[@]} -gt 0 ] || { say 3 "Nothing selected."; return 0; }
    ask "Delete ${#picked[@]} snapshot(s)? Rollback to them is no longer possible afterwards." \
      || { say 1 "Cancelled."; return 1; }
  elif [ "$DELETE" = 1 ]; then
    for ((i = 1; i < ${#selected[@]}; i += 2)); do picked+=("${selected[i]}"); done
  else
    say 8 "List only — add --delete (optionally --older-than DAYS) to remove them."
    return 0
  fi

  local deleted=0 failed=0
  for label in "${picked[@]}"; do
    [ -n "${snap_map[$label]}" ] || continue
    IFS='|' read -r node tool vmid snap <<< "${snap_map[$label]}"
    if snap_delete "$node" "$tool" "$vmid" "$snap"; then
      say 2 "  ✓ deleted $label"
      deleted=$((deleted + 1))
    else
      say 1 "  ✗ failed to delete $label (see log)"
      failed=$((failed + 1))
    fi
  done

  say 8 "Storage after:"
  while IFS= read -r line; do [ -n "$line" ] && say 8 "  $line"; done <<< "$(pool_usage)"
  say "$([ "$failed" -eq 0 ] && echo 2 || echo 1)" "Deleted $deleted snapshot(s)$([ "$failed" -gt 0 ] && echo ", $failed failed")."
  [ "$failed" -eq 0 ]
}

# --json: list the snapshots; with --delete --ids node:tool:vmid:snapshot,… delete
# exactly those (only ones that are in the list, i.e. svsupd_* snapshots)
run_snapshots_json() {
  local line node tool vmid name snap id now ok failed=0
  now=$(date +%s)
  for line in "$@"; do
    IFS='|' read -r _ node tool vmid name snap <<< "$line"
    jq -cn --arg node "$node" --arg tool "$tool" --arg vmid "$vmid" --arg name "$name" --arg snap "$snap" \
      --argjson age "$(( (now - $(date -d "${snap:7:8}" +%s)) / 86400 ))" \
      '{id: "\($node):\($tool):\($vmid):\($snap)", node: $node, tool: $tool, vmid: ($vmid | tonumber),
        name: $name, snapshot: $snap, ageDays: $age}'
  done | jq -sc --arg pools "$(pool_usage)" --arg down "${DOWN_NODES[*]}" '{event: "snapshots", snapshots: .,
      pools: ($pools | split("\n") | map(select(length > 0))), unreachable: ($down | split(" ") | map(select(length > 0)))}' >&3
  [ "$DELETE" = 1 ] || return 0
  local ids=()
  IFS=',' read -ra ids <<< "$IDS"
  for id in "${ids[@]}"; do
    IFS=':' read -r node tool vmid snap <<< "$id"
    ok=false
    for line in "$@"; do
      IFS='|' read -r _ n t v _ sn <<< "$line"
      if [ "$n|$t|$v|$sn" = "$node|$tool|$vmid|$snap" ]; then
        snap_delete "$node" "$tool" "$vmid" "$snap" && ok=true
        break
      fi
    done
    [ "$ok" = true ] || failed=$((failed + 1))
    emit --arg id "$id" --argjson ok "$ok" '{event: "deleted", id: $id, ok: $ok}'
  done
  [ "$failed" -eq 0 ]
}

# emit_start <mode> — the start event (--json)
emit_start() {
  emit --arg mode "$1" --arg log "$LOG_FILE" --arg ctl "$RUN_DIR" --args '{event: "start", mode: $mode, servers: $ARGS.positional, log: $log, ctl: $ctl}' "${TARGETS[@]}"
}

# SSH key copy mode: only ensure the local key is authorized on each selected
# server, without running any updates.
run_ssh_copy() {
  gum style --foreground 212 --bold "=== SSH Key Copy Mode ==="

  resolve_targets || return

  ensure_ssh_key
  gum style --foreground 212 --bold "Checking SSH keys for ${#TARGETS[@]} server(s): ${TARGETS[*]}"

  for SERVER in "${TARGETS[@]}"; do
    PORT=$(port_of "$SERVER")
    echo ""
    gum style --foreground 212 --border rounded --padding "0 1" " Checking: $SERVER (port $PORT)"
    copy_ssh_key_if_needed "$SERVER" "$PORT"
  done

  echo ""
  gum style --foreground 2 --bold "SSH key check complete!"
}

# Connect mode: pick a single server and open an interactive SSH session.
# If key auth isn't set up yet, handles that first.
run_connect() {
  gum style --foreground 212 --bold "=== Connect to Server ==="

  local SERVER
  SERVER=$(select_single_server)

  if [ -z "$SERVER" ]; then
    gum style --foreground 1 "No server selected, exiting."
    return
  fi

  local PORT
  PORT=$(port_of "$SERVER")

  gum style --foreground 212 --border rounded --padding "0 1" " Connecting to: $SERVER (port $PORT)"

  ensure_ssh_key
  copy_ssh_key_if_needed "$SERVER" "$PORT"

  gum style --foreground 3 "Opening SSH session to $SERVER... (type 'exit' or press Ctrl+D to return)"
  echo ""

  ssh -p "$PORT" "$(dest_of "$SERVER")"

  echo ""
  gum style --foreground 2 "Session to $SERVER closed."
}

# pve-pin --url https://host:8006 — the key of the certificate that host shows right now
# (what curl is told to insist on from then on) and its fingerprint, for you to compare
# with the one in the Proxmox web interface before trusting it:
#   { event: "pin", pin: "sha256//…", fingerprint: "AA:BB:…" } | { event: "error", error }
run_pve_pin() {
  local hp=${URL_ARG#https://} cert pin fp
  hp=${hp%%/*}
  [[ "$hp" == *:* ]] || hp="$hp:8006"
  [[ "$hp" =~ ^[A-Za-z0-9.-]+:[0-9]+$ ]] || { jq -cn '{event: "error", error: "the address isn\u0027t https://host:port"}'; return 1; }
  cert=$(echo | timeout 12 openssl s_client -connect "$hp" -servername "${hp%%:*}" 2>/dev/null | openssl x509 2>/dev/null)
  [ -n "$cert" ] || { jq -cn --arg h "$hp" '{event: "error", error: "no answer from \($h) (is the address right, is the host up?)"}'; return 1; }
  pin=$(openssl x509 -pubkey -noout <<< "$cert" | openssl pkey -pubin -outform der 2>/dev/null | openssl dgst -sha256 -binary | base64)
  fp=$(openssl x509 -noout -fingerprint -sha256 <<< "$cert" | cut -d= -f2)
  jq -cn --arg p "sha256//$pin" --arg f "$fp" '{event: "pin", pin: $p, fingerprint: $f}'
}

# pve-info --servers <host> — can the tool work with this Proxmox host the way it is set
# up (SSH or API token), and its guests:
#   { event: "pve", host, access, node, nodes: [..], checks: [{ key, ok, text, hint }],
#     guests: [{ type, vmid, name }] }
run_pve_info() {
  local h=${SERVER_ARG%%,*} checks=() ver nodes="" node="" perms p missing=() out glist="" good=1 access=ssh user
  in_list "$h" "${KNOWN[@]}" || { jq -cn --arg h "$h" '{event: "error", error: "no server called \($h)"}'; return 1; }
  add() { checks+=("$(jq -cn --arg k "$1" --argjson ok "$2" --arg t "$3" --arg h "$4" '{key: $k, ok: $ok, text: $t, hint: $h}')"); [ "$2" = true ] || good=0; }
  if uses_api "$h"; then
    access=api
    node=$(api_node "$h")
    if ver=$(pve_api "$h" GET /version 2>&1); then
      add api true "The API answers (Proxmox VE $(jq -r '.version // "?"' <<< "$ver")) and accepts the token" ""
      nodes=$(pve_api "$h" GET /nodes 2>/dev/null | jq -r '.[].node' | paste -sd' ')
      if [ -n "$node" ] && [[ " $nodes " == *" $node "* ]]; then add node true "Its node is called $node" ""
      else add node false "Which node is it? It has: ${nodes:-none it may see}" "Pick this host's node below, then check again."
      fi
      perms=$(pve_api "$h" GET /access/permissions --get --data-urlencode "path=/vms" 2>/dev/null | jq -r '[.[]? | to_entries[] | select(.value == 1) | .key] | unique | join(" ")')
      for p in VM.Audit VM.Snapshot VM.Snapshot.Rollback; do [[ " $perms " == *" $p "* ]] || missing+=("$p"); done
      if [ ${#missing[@]} -eq 0 ]; then add rights true "The token may look at guests, snapshot them and roll them back" ""
      else add rights false "The token is missing: ${missing[*]}" "Give its role these privileges on /vms (the commands are shown in the dialog)."
      fi
    else
      add api false "The API doesn't work with this token" "${ver#API: }"
    fi
  else
    if out=$(ssh_run "$h" 'echo "USER|$(id -un)|$(id -u)"; command -v pveversion >/dev/null 2>&1 && echo "PVE|$(pveversion 2>/dev/null | head -n1)"; qm list >/dev/null 2>&1 && echo "QM|ok"; pct list >/dev/null 2>&1 && echo "PCT|ok"; command -v proxmox-backup-manager >/dev/null 2>&1 && echo "PBS|1"; true' 2>&1) && grep -q '^USER|' <<< "$out"; then
      user=$(sed -n 's/^USER|\([^|]*\)|.*/\1/p' <<< "$out")
      add ssh true "SSH login works, as $user" ""
      if grep -q '^PVE|.' <<< "$out"; then add pve true "$(sed -n 's/^PVE|//p' <<< "$out")" ""
      elif grep -q '^PBS|' <<< "$out"; then add pve false "Not a Proxmox VE host" "It is a Proxmox Backup Server: set \"What is it\" to that (it has no guests)."
      else add pve false "Not a Proxmox VE host" "pveversion isn't there. Is this the right machine?"
      fi
      if grep -q '^QM|ok' <<< "$out" && grep -q '^PCT|ok' <<< "$out"; then add qm true "Can list and snapshot its VMs and containers" ""
      elif [ "$user" = root ]; then add qm false "Can't use qm / pct" "They failed although the login is root: look at the host."
      else add qm false "Can't use qm / pct" "They need root. Set the server's user to root (Edit → User), give this user passwordless sudo for qm and pct, or use an API token."
      fi
    else
      add ssh false "Can't log in over SSH" "$(tail -n1 <<< "$out" | cut -c1-200). The tool only uses SSH keys: copy yours to it (the card's menu → Copy SSH key to it), or use an API token."
    fi
  fi
  [ "$good" = 1 ] && glist=$(node_guests "$h" 2>/dev/null)
  printf '%s\n' "${checks[@]}" | jq -sc --arg h "$h" --arg a "$access" --arg n "$node" --arg nodes "$nodes" --arg g "$glist" '
    {event: "pve", host: $h, access: $a, node: $n, nodes: ($nodes | split(" ") | map(select(length > 0))), checks: .,
     guests: [$g | split("\n")[] | select(length > 0) | capture("^(?<type>qemu|lxc) (?<vmid>[0-9]+) ?(?<name>.*)$") | .vmid |= tonumber]}'
}

usage() {
  cat << EOF
Usage: $(basename "$0") [command] [options]

Commands (no command = interactive menu):
  update      scan for updates, then update only what has updates, verify, report
  scan        show what would be updated (same as: update --dry-run)
  check       run the health checks only, change nothing
  snapshots   list the pre-update snapshots and bulk-delete them (interactive picker;
              unattended: --delete [--older-than DAYS])
  ssh-copy    make sure your SSH key is on the servers
  connect     open an SSH session to a server
  migrate     move the server lists from svs.conf into servers.json (--force overwrites it)
  pve-info    --servers HOST: can the tool work with that Proxmox host, and its guests (JSON)
  pve-pin     --url https://HOST:8006: the certificate key of that host, to pin (JSON)
  conf-json   print what servers.json would get from svs.conf (SVS_CONFIG=other.conf), change nothing

Options:
  -s, --servers a,b   only these servers (default: pick interactively / all)
  -a, --auto          unattended: no prompts, update everything pending except
                      EXCLUDE_CONTAINERS; reboots per AUTO_REBOOT, rollbacks per
                      AUTO_ROLLBACK (svs.conf)
  -n, --dry-run       scan and report only. Installs, recreates, snapshots and reboots
                      nothing (it does refresh package lists and pull new images)
  -r, --reboot MODE   none | ask | auto — Proxmox VE/PBS machines are NEVER rebooted,
                      in any mode: the report tells you to reboot them manually
      --no-snapshot   don't take Proxmox snapshots before updating
      --drop-snapshot delete a server's snapshot again once its update and checks passed
      --snapshot-optional  update a server even when its snapshot fails (overrides
                      SNAPSHOT_REQUIRED for this run)
      --delete        snapshots: delete without asking (for scripts/cron)
      --older-than N  snapshots: only (pre)select snapshots at least N days old
      --no-notify     don't send the webhook notification
      --containers L  update: of the pending containers only these (server:name,server:name)
      --restart-pulled  update: also restart containers on servers whose containers are
                      "pull only" / "never" (their images were downloaded, they still run the old ones)
      --only WHAT     update: security (just the security packages; full upgrade on Arch),
                      os (packages, no containers) or containers (no packages)
      --json          machine-readable JSON lines on stdout (for the Quickshell app);
                      no prompts: update needs --auto
      --ask           with --json: questions (roll back? go on without a snapshot? next
                      wave after a failure?) go out as "ask" events and wait for an answer
                      file; none within --ask-timeout SECONDS (default 1800): svs.conf decides
      --ids a,b       snapshots --delete --json: delete exactly these (node:tool:vmid:snapshot)
  -h, --help          this help

Examples:
  $(basename "$0") update --auto                  # nightly cron run
  $(basename "$0") check --servers svs-docker01   # quick health check
  $(basename "$0") snapshots                      # pick snapshots to delete
EOF
}

# --- Main ---

COMMAND=""
AUTO=0
DRY_RUN=0
NO_SNAPSHOT=0
DROP_SNAPSHOT=0
ASK_JSON=0
SNAPSHOT_OPTIONAL=0
NO_NOTIFY=0
REBOOT_MODE=""
SERVER_ARG=""
DELETE=0
OLDER_THAN=0
ONLY=""
URL_ARG=""
CT_PICK=""
RESTART_PULLED=0
IDS=""
FORCE=0

while [ $# -gt 0 ]; do
  case "$1" in
    update|check|scan|snapshots|ssh-copy|connect|migrate|conf-json|pve-info|pve-pin) COMMAND="$1" ;;
    --url) URL_ARG="$2"; shift ;;
    --delete) DELETE=1 ;;
    --json) JSON=1 ;;
    --ask) ASK_JSON=1 ;;
    --ask-timeout) ASK_TIMEOUT="$2"; [[ "$ASK_TIMEOUT" =~ ^[0-9]+$ ]] || { echo "--ask-timeout needs seconds" >&2; exit 1; }; shift ;;
    --force) FORCE=1 ;;
    --only) ONLY="$2"; shift ;;
    --containers) CT_PICK="$2"; shift ;;
    --restart-pulled) RESTART_PULLED=1 ;;
    --ids) IDS="$2"; shift ;;
    --older-than)
      OLDER_THAN="$2"
      [[ "$OLDER_THAN" =~ ^[0-9]+$ ]] || { echo "--older-than needs a number of days" >&2; exit 1; }
      shift
      ;;
    -s|--servers) SERVER_ARG="$2"; shift ;;
    -a|--auto) AUTO=1 ;;
    -n|--dry-run) DRY_RUN=1 ;;
    -r|--reboot) REBOOT_MODE="$2"; shift ;;
    --no-snapshot) NO_SNAPSHOT=1 ;;
    --drop-snapshot) DROP_SNAPSHOT=1 ;;
    --snapshot-optional) SNAPSHOT_OPTIONAL=1 ;;
    --no-notify) NO_NOTIFY=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 1 ;;
  esac
  shift
done

case "$REBOOT_MODE" in
  ""|none|ask|auto) ;;
  *) echo "--reboot must be none, ask or auto" >&2; exit 1 ;;
esac
case "$ONLY" in
  ""|security|os|containers) ;;
  *) echo "--only must be security, os or containers" >&2; exit 1 ;;
esac

# svs.conf's server lists → servers.json (before servers.json replaces them)
if [ "$COMMAND" = migrate ]; then
  run_migrate
  exit $?
fi
# the same, read-only: what servers.json would get from a config (SVS_CONFIG=file); the app's import
if [ "$COMMAND" = conf-json ]; then
  if [ ${#SERVERS[@]} -eq 0 ]; then echo '{"version": 1, "groups": [], "servers": [], "waves": [], "commands": []}'; exit 0; fi
  conf_json
  exit $?
fi
load_servers_json
# a server that is said to be a Proxmox machine is one before any scan saw it: never rebooted
for s in "${PVE_KIND[@]}"; do IS_PROXMOX[$s]=1; done
# what the Servers app asks about a Proxmox host (JSON on stdout, nothing is changed)
if [ "$COMMAND" = pve-pin ]; then run_pve_pin; exit $?; fi
if [ "$COMMAND" = pve-info ]; then run_pve_info; exit $?; fi
[ "$COMMAND" = scan ] && { COMMAND=update; DRY_RUN=1; }
[ "$JSON" = 1 ] || ASK_JSON=0

INTERACTIVE=0
if [ "$JSON" = 0 ] && [ "$AUTO" = 0 ] && [ -t 0 ] && [ -t 1 ] && command -v gum &>/dev/null; then
  INTERACTIVE=1
fi
[ "$AUTO" = 1 ] && [ "$REBOOT_MODE" = ask ] && REBOOT_MODE=""

for dep in ssh curl jq column flock; do
  command -v "$dep" &>/dev/null || { echo "Missing dependency: $dep" >&2; exit 1; }
done

if [ "$JSON" = 1 ] && [[ -z "$COMMAND" || "$COMMAND" == ssh-copy || "$COMMAND" == connect ]]; then
  jq -cn --arg c "${COMMAND:-menu}" '{event: "error", error: "\($c) has no --json mode"}'
  exit 1
fi

if [ -z "$COMMAND" ]; then
  if ! use_gum; then
    usage
    exit 1
  fi
  gum style \
    --foreground 212 --border double --border-foreground 212 \
    --padding "1 4" --margin "1 0" \
    --bold "  SVS Server Manager  "
  case "$(gum choose --header "What do you want to do?" \
            "Update Servers" \
            "Scan for Updates (dry run)" \
            "Health Check" \
            "Clean Up Snapshots" \
            "Copy SSH Keys" \
            "Connect to Server")" in
    "Update Servers")    COMMAND=update ;;
    "Scan for Updates"*) COMMAND=update; DRY_RUN=1 ;;
    "Health Check")      COMMAND=check ;;
    "Clean Up Snapshots") COMMAND=snapshots ;;
    "Copy SSH Keys")     COMMAND=ssh-copy ;;
    "Connect to Server") COMMAND=connect ;;
    *) gum style --foreground 1 "Nothing selected, exiting."; exit 0 ;;
  esac
fi

if [ "$COMMAND" = update ] && [ "$DRY_RUN" = 0 ] && ! use_gum && [ "$AUTO" = 0 ]; then
  if [ "$JSON" = 1 ]; then
    jq -cn '{event: "error", error: "update --json needs --auto"}'
  else
    echo "Not running in a terminal: use 'update --auto' for unattended updates." >&2
  fi
  exit 1
fi
if ! use_gum && [[ "$COMMAND" == ssh-copy || "$COMMAND" == connect ]]; then
  echo "'$COMMAND' needs an interactive terminal with gum." >&2
  exit 1
fi

mkdir -p "$LOG_DIR"
[ -e "$LOG_DIR/${RUN_TAG}-${COMMAND}$([ "$DRY_RUN" = 1 ] && echo -dry).log" ] && RUN_TAG+="-$$"
LOG_FILE="$LOG_DIR/${RUN_TAG}-${COMMAND}$([ "$DRY_RUN" = 1 ] && echo -dry).log"
find "$LOG_DIR" -name '*.log' -mtime +"$LOG_KEEP_DAYS" -delete 2>/dev/null

# --json: fd 3 = the real stdout (events only), everything else goes to the run log
if [ "$JSON" = 1 ]; then
  exec 3>&1 1>> "$LOG_FILE"
fi

# Only one update/snapshot cleanup at a time (e.g. cron firing while you update by hand),
# and one scan at a time (the app's timer and a manual scan)
busy() {
  say 1 "$1"
  emit --arg e "$1" '{event: "error", error: $e, busy: true}'
  exit 1
}
# Updates may run side by side: each server is locked on its own (lib/parallel.sh), so
# two runs never work on the same one. Only the snapshot cleanup is one at a time, and
# one scan at a time (the app's timer and a manual scan).
if [ "$COMMAND" = snapshots ]; then
  exec 9> "$DATA_DIR/.manage-svs.lock"
  flock -n 9 || busy "Another snapshot cleanup is already running."
elif [ "$COMMAND" = update ] && [ "$DRY_RUN" = 1 ]; then
  exec 9> "$DATA_DIR/.manage-svs.scan.lock"
  flock -n 9 || busy "Another scan is already running."
fi

case "$COMMAND" in
  update)   run_update ;;
  check)    run_check ;;
  snapshots) run_snapshots ;;
  ssh-copy) run_ssh_copy ;;
  connect)  run_connect ;;
esac
status=$?

# Exit code for cron/monitoring: 0 = all good, 1 = something failed
if [ "$status" -eq 0 ] && [[ "$COMMAND" == update || "$COMMAND" == check ]] && [ ${#R_ORDER[@]} -gt 0 ]; then
  [ "$(overall_status)" = OK ] || status=1
fi
emit --arg mode "${RUN_MODE:-$COMMAND}" --arg result "$([ ${#R_ORDER[@]} -gt 0 ] && overall_status)" \
  --arg report "${REPORT_FILE:-}" --argjson exit "$status" --arg log "$LOG_FILE" \
  '{event: "done", mode: $mode, result: $result, report: $report, log: $log, exit: $exit}'
exit "$status"
