# Login screen: getting back in

The login screen (Quickshell greeter on greetd) falls back to **agreety**, a
text login on tty1, whenever it can't be used:

- its niri config can't be made or isn't valid,
- it isn't shown within 15 s (a QML error, no GPU, …),
- it crashed twice within 5 minutes (once it's simply started again),
- you pressed **Ctrl+Alt+Backspace** (the way out when it hangs; if it comes
  back once, press it again).

agreety asks for user name and password and starts niri-session (the
`--session` given to install.sh). You won't be left at a black screen
without a way in unless greetd itself doesn't run.

## From a TTY

1. **Ctrl+Alt+F2** (any of F2–F6), log in with your user and password.
2. What went wrong: `sudo /usr/local/share/quickshell-greeter/recover log`
3. Pick one:
   - text login from now on: `sudo /usr/local/share/quickshell-greeter/recover agreety`
   - greetd as before the login screen (autologin): `sudo /usr/local/share/quickshell-greeter/recover before`
   - the login screen again, after fixing it: `sudo /usr/local/share/quickshell-greeter/recover greeter`
4. It asks whether to restart greetd (ends what runs on tty1); or reboot.
5. Back to tty1: **Ctrl+Alt+F1**.

If even the recover script is gone: `sudoedit /etc/greetd/config.toml` and
set the default session to `command = "agreety --cmd niri-session"`, then
`sudo systemctl restart greetd`. The config from before the login screen is
`/etc/greetd/config.toml.before-greeter`.

## Files

| Path | What |
|---|---|
| `/etc/greetd/config.toml` | greetd: `greeter-session \|\| agreety …` as user `greeter` |
| `/usr/local/share/quickshell-greeter/` | the installed code (root), from `greeter/install.sh` |
| `/var/lib/quickshell-greeter/theme/` | colors, wallpaper, settings copy (yours, greeter can read) |
| `/var/lib/quickshell-greeter/state/last.json` | last user / session |
| `/run/user/<greeter uid>/quickshell-greeter/greeter.log` | wrapper, niri and qs log of this boot |
| journal, tag `quickshell-greeter` | the wrapper's decisions |
| `/etc/quickshell-greeter/wayvnc.conf` | VNC on the login screen (only with `install.sh --vnc`) |
