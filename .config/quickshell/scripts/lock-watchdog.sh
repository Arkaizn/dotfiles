#!/usr/bin/env bash
# Fail-closed login lock (niri, spawned from startup.kdl): if the session isn't
# locked TIMEOUT seconds after niri started, run ACTION.
#
# ACTION:
#   auto      swaylock if installed, else logout
#   swaylock  lock with swaylock (-f)
#   logout    niri msg action quit --skip-confirmation
#             (note: greetd's default_session autologins too, so this starts
#             a new, unlocked session rather than showing a login prompt)
TIMEOUT=4
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

if locked; then
    log "ok: locked within ${TIMEOUT}s of niri start ($start)"
    exit 0
fi

case "$ACTION" in
    auto) command -v swaylock >/dev/null && ACTION=swaylock || ACTION=logout ;;
esac
log "NOT locked ${TIMEOUT}s after niri start ($start): running $ACTION"
case "$ACTION" in
    swaylock) exec swaylock -f -c 000000 ;;
    logout)   exec niri msg action quit --skip-confirmation ;;
    *)        log "unknown ACTION '$ACTION'"; exit 1 ;;
esac
