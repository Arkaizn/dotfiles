pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// Small synchronous file reads (config files, state files, /proc entries).
//   Files.read(path)   the file's text, "" if it's missing or unreadable
// The path is reset before every read so reading the same file again returns
// its current content. For big or frequently changing files use a FileView of
// your own (watchChanges) instead.
//
// Each read uses a FileView of its own: with one shared reader, a binding that
// calls Files.read depended on the reader's path, so every other read re-ran it
// mid-read and it pointed the reader at its own file (the lockscreen's
// startPending read /proc/self/stat → Updates got that as the kernel version
// and always reported "reboot needed").
Singleton {
    function read(path) {
        const reader = readerComp.createObject(null, { path: path })
        const text = reader.text() ?? ""
        reader.destroy()
        return text
    }

    Component { id: readerComp; FileView { blockLoading: true; printErrors: false } }
}
