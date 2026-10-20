import QtQuick
import qs.services
import qs.components

// pull.sh in a terminal: git pull, then the repo over ~/.config (Dotfiles service:
// repo and profile from Settings → Dotfiles)
BarButton {
    text: Icons.get("pull")
    onClicked: Dotfiles.pullUpdate(Settings.dotfiles.profile ?? "default")
}
