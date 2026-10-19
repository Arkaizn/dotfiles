pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// Small synchronous file reads (config files, state files, /proc entries).
//   Files.read(path)   the file's text, "" if it's missing or unreadable
// The path is reset before every read so reading the same file again returns
// its current content. For big or frequently changing files use a FileView of
// your own (watchChanges) instead.
Singleton {
    function read(path) {
        reader.path = ""
        reader.path = path
        return reader.text() ?? ""
    }

    FileView { id: reader; blockLoading: true; printErrors: false }
}
