#!/usr/bin/env bash
# Fail-closed login lock (niri, spawned from startup.kdl): if the session isn't
# locked TIMEOUT seconds after niri started, run ACTION. A shell that is still
# starting then (a qs process runs, but neither the lock nor its "no lock
# needed" marker is there yet: the first, cold login of a boot can take ~4 s)
# gets until MAX_WAIT; without a qs process it acts at TIMEOUT as before.
#
# ACTION:
#   auto      swaylock if installed, else logout
#   swaylock  lock with swaylock (-f)
#   logout    niri msg action quit --skip-confirmation
#             (note: greetd's default_session autologins too, so this starts
#             a new, unlocked session rather than showing a login prompt)
TIMEOUT=4
MAX_WAIT=12
ACTION=auto

log() {
    logger -t lock-watchdog "$*"
    [ "${QS_LOCK_TIMING:-}" = 1 ] &&
        printf '%9.3f  lock-watchdog: %s\n' "$(cut -d' ' -f1 /proc/uptime)" "$*" >> "${XDG_CACHE_HOME:-$HOME/.cache}/lock-timing.log"
}

# niri's start (CLOCK_MONOTONIC µs; /proc/uptime is the same clock until the first suspend)
start=$(systemctl --user show niri.service -p ActiveEnterTimestampMonotonic --value 2>/dev/null)
if [ -n "$start" ] && [ "$start" != 0 ]; then
    start=$(awk -v us="$start" 'BEGIN { printf "%.3f", us / 1e6 }')
else
    start=$(cut -d' ' -f1 /proc/uptime)
fi
wait=$(awk -v s="$start" -v t="$TIMEOUT" -v now="$(cut -d' ' -f1 /proc/uptime)" 'BEGIN { w = s + t - now; printf "%.3f", (w > 0 ? w : 0) }')
sleep "$wait"

# Locked = niri logged "locking session" since it started (an unlock after
# that took the password, so that counts too), or the lockscreen says so.
locked() {
    journalctl -b --user -u niri.service -o short-monotonic --no-pager --grep 'locking session' 2>/dev/null |
        awk -v s="$start" 'match($0, /^\[ *[0-9.]+\]/) { t = substr($0, 2, RLENGTH - 2) + 0; if (t >= s) found = 1 } END { exit !found }' && return 0
    [ "$(timeout 1 qs ipc call lockscreen isLocked 2>/dev/null)" = true ]
}

# the shell decided not to lock (logged in on the login screen, greeter/): it
# writes "none <NIRI_SOCKET>" at its start (LockScreen.noteStart). Missing or
# from another niri instance → still expect the lock (fail-closed). Only from
# the private runtime dir: a file in /tmp could be put there by anyone.
no_lock_needed() {
    local want="" sock=""
    [ -n "${XDG_RUNTIME_DIR:-}" ] && { read -r want sock < "$XDG_RUNTIME_DIR/quickshell-login-lock"; } 2>/dev/null
    [ "$want" = none ] && [ -n "${NIRI_SOCKET:-}" ] && [ "$sock" = "$NIRI_SOCKET" ]
}
late() { awk -v s="$start" -v now="$(cut -d' ' -f1 /proc/uptime)" 'BEGIN { printf "%.1f", now - s }'; }

while :; do
    if no_lock_needed; then
        log "ok: no lock needed (logged in on the login screen; $(late)s after niri start)"
        exit 0
    fi
    if locked; then
        log "ok: locked within $(late)s of niri start ($start)"
        exit 0
    fi
    # still starting: a qs process of ours runs and the hard limit isn't reached
    over=$(awk -v s="$start" -v m="$MAX_WAIT" -v now="$(cut -d' ' -f1 /proc/uptime)" 'BEGIN { print (now >= s + m) ? 1 : 0 }')
    if [ "$over" = 1 ] || ! pgrep -u "$(id -u)" -x qs >/dev/null; then
        break
    fi
    sleep 0.25
done

case "$ACTION" in
    auto) command -v swaylock >/dev/null && ACTION=swaylock || ACTION=logout ;;
esac
log "NOT locked $(late)s after niri start ($start): running $ACTION"
case "$ACTION" in
    swaylock) exec swaylock -f -c 000000 ;;
    logout)   exec niri msg action quit --skip-confirmation ;;
    *)        log "unknown ACTION '$ACTION'"; exit 1 ;;
esac
