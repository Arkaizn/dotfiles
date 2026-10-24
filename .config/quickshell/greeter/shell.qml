import Quickshell
import QtQuick

// Login screen (greetd greeter). Not run from here: greeter/build.sh puts
// this folder's QML together with the shared files listed in
// greeter/manifest.txt into one tree (installed to
// /usr/local/share/quickshell-greeter/shell by greeter/install.sh).
ShellRoot {
    Greeter {}
}
