#!/usr/bin/env bash
# Lock the session with the quickshell lockscreen.
# Retries for a few seconds so it also works right at login, before quickshell is up.
for _ in $(seq 1 40); do
    qs ipc call lockscreen lock >/dev/null 2>&1 && exit 0
    sleep 0.25
done
exit 1
