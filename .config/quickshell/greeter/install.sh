#!/usr/bin/env bash
# Installs / updates the Quickshell login screen (greetd greeter). Run it with
# sudo from your own account (it reads the code from your config):
#
#   sudo ~/.config/quickshell/greeter/install.sh [options]
#
#   (no options)          code + folders only; greetd's config isn't touched
#   --switch MODE         also write /etc/greetd/config.toml (old one kept once
#                         as config.toml.before-greeter):
#                           greeter          login screen at boot and after logout
#                           autologin-boot   autologin once per boot (no login
#                                            screen at boot, e.g. for VNC after a
#                                            reboot), login screen after logout
#   --session CMD         what agreety / autologin start (default niri-session)
#   --vnc                 VNC on the login screen: /etc/quickshell-greeter/wayvnc.conf
#                         (asks for a password; root:greeter 640)
#   --no-vnc              remove that file again
#   --dry-run             only print what it would do
#
# What it installs:
#   /usr/local/share/quickshell-greeter/   root, 755: shell/ (greeter/build.sh),
#                                          greeter-session, runner, niri-config, recover
#   /var/lib/quickshell-greeter/theme/     you:greeter 2750 (the shell writes it,
#                                          the greeter reads it)
#   /var/lib/quickshell-greeter/state/     greeter 700 (last user / session)
# It never restarts greetd: reboot (or see RECOVERY.md) to use it.
set -euo pipefail

SRC=$(cd "$(dirname "$(readlink -f "$0")")" && pwd)
SHARE=/usr/local/share/quickshell-greeter
VAR=/var/lib/quickshell-greeter
ETC=/etc/quickshell-greeter
switch="" session=niri-session vnc="" dry=""
while [ $# -gt 0 ]; do
    case "$1" in
        --switch)  switch=${2:?}; shift ;;
        --session) session=${2:?}; shift ;;
        --vnc)     vnc=on ;;
        --no-vnc)  vnc=off ;;
        --dry-run) dry=1 ;;
        *) sed -n '2,30p' "$0"; exit 2 ;;
    esac
    shift
done
case "$switch" in ""|greeter|autologin-boot) ;; *) echo "--switch is greeter or autologin-boot" >&2; exit 2 ;; esac
[[ $session =~ ^[A-Za-z0-9/._-]+$ ]] || { echo "--session: a command without spaces or quotes" >&2; exit 2; }

run() { if [ -n "$dry" ]; then printf '  would run: %s\n' "$*"; else "$@"; fi; }
say() { printf '%s\n' "$*"; }

[ -n "$dry" ] || [ "$(id -u)" = 0 ] || { echo "run with sudo" >&2; exit 1; }
owner=${SUDO_USER:-}
[ -n "$dry" ] && [ -z "$owner" ] && owner=$USER
[ -n "$owner" ] && [ "$owner" != root ] || { echo "run with sudo from your account (SUDO_USER is the theme folder's owner)" >&2; exit 1; }
getent passwd greeter >/dev/null || { echo "no 'greeter' user: install greetd first" >&2; exit 1; }
for bin in greetd agreety niri qs jq magick; do
    command -v "$bin" >/dev/null || { echo "missing: $bin" >&2; exit 1; }
done

say "== code → $SHARE"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
ver=$("$SRC/build.sh" "$tmp/shell")
say "   version $ver (was $(cat "$SHARE/shell/VERSION" 2>/dev/null || echo none))"
run install -d -o root -g root -m 755 "$SHARE"
run rm -rf "$SHARE/shell.new"
run cp -r "$tmp/shell" "$SHARE/shell.new"
run chown -R root:root "$SHARE/shell.new"
run chmod -R u=rwX,go=rX "$SHARE/shell.new"
run rm -rf "$SHARE/shell.old"
[ -d "$SHARE/shell" ] && run mv "$SHARE/shell" "$SHARE/shell.old"
run mv "$SHARE/shell.new" "$SHARE/shell"
run rm -rf "$SHARE/shell.old"
for f in greeter-session runner niri-config recover; do
    run install -o root -g root -m 755 "$SRC/system/$f" "$SHARE/$f"
done

say "== folders → $VAR"
run install -d -o root -g root -m 755 "$VAR"
run install -d -o "$owner" -g greeter -m 2750 "$VAR/theme"
run install -d -o greeter -g greeter -m 700 "$VAR/state"

if [ "$vnc" = on ]; then
    say "== VNC on the login screen → $ETC/wayvnc.conf"
    if [ -z "$dry" ]; then
        read -rp "   VNC user name [$owner]: " vuser; vuser=${vuser:-$owner}
        read -rsp "   VNC password: " p1; echo; read -rsp "   again: " p2; echo
        [ -n "$p1" ] && [ "$p1" = "$p2" ] || { echo "passwords empty or not the same" >&2; exit 1; }
        install -d -o root -g greeter -m 750 "$ETC"
        umask 027
        printf 'address=0.0.0.0\nport=5900\nenable_auth=true\nusername=%s\npassword=%s\n' "$vuser" "$p1" > "$ETC/wayvnc.conf"
        chown root:greeter "$ETC/wayvnc.conf"; chmod 640 "$ETC/wayvnc.conf"
    else
        say "  would write $ETC/wayvnc.conf (asks for user + password)"
    fi
elif [ "$vnc" = off ]; then
    run rm -f "$ETC/wayvnc.conf"
fi

if [ -n "$switch" ]; then
    say "== greetd → $switch"
    cfg=/etc/greetd/config.toml
    [ -f "$cfg.before-greeter" ] || run cp -p "$cfg" "$cfg.before-greeter"
    new="[terminal]
vt = 1

# Quickshell login screen; agreety (text login) when it can't start
# (~/.config/quickshell/greeter/RECOVERY.md)
[default_session]
command = \"$SHARE/greeter-session || agreety --cmd $session\"
user = \"greeter\"
"
    if [ "$switch" = autologin-boot ]; then
        new+="
# once per boot: straight into your session (no login screen at boot)
[initial_session]
command = \"$session\"
user = \"$owner\"
"
    fi
    if [ -n "$dry" ]; then printf '  would write %s:\n%s\n' "$cfg" "$new" | sed 's/^/    /'
    else printf '%s' "$new" > "$cfg.new" && chmod 644 "$cfg.new" && mv "$cfg.new" "$cfg"; fi
fi

say ""
say "Done. Next:"
say "  - Settings → Login screen → Update now (writes the theme copy; the shell keeps it up to date)"
[ -n "$switch" ] && say "  - reboot to see it. If it can't start you get agreety (text login);"
[ -n "$switch" ] && say "    from a TTY: sudo $SHARE/recover   (see greeter/RECOVERY.md)"
exit 0
