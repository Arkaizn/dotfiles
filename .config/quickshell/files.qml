//@ pragma UseQApplication

import Quickshell
import QtQuick
import qs.services
import "modules/files"

// The file manager: its own Quickshell process next to the shell (same
// folder, so qs.services / qs.components and settings.json are shared).
// A stuck folder, a dead share or a crash here can't freeze the bar or the
// lockscreen, and editing modules/files/ reloads only this process.
// Started through scripts/files/files.sh (never by hand: it also makes sure
// there is only one). Its IPC target: qs ipc -p ~/.config/quickshell/files.qml call files …
ShellRoot {
    // settings.json belongs to the main shell: this process only reads it and
    // hands its changes over (Settings.remote; files.sh sets it too, before start)
    Component.onCompleted: Settings.remote = true

    FilesApp {}
}
