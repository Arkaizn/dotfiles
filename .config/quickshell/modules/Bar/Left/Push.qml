import QtQuick
import qs.services
import qs.components

// push.sh in a terminal: ~/.config into the repo's working tree, nothing is
// committed (Dotfiles service: repo and profile from Settings → Dotfiles).
// First click arms ("Click again"), a second within 3 s runs it.
BarButton {
    ConfirmArm { id: arm }
    readonly property bool armed: arm.armed !== ""

    text: Icons.get("push") + (armed ? " Click again" : "")
    textColor: armed ? Colors.red : Properties.color
    onClicked: if (arm.confirm("push")) Dotfiles.pushInTerminal(Settings.dotfiles.profile ?? "default")
}
