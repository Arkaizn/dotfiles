import Quickshell
import QtQuick
import qs.services

// Desktop pets (services/Pets.qml) at the bottom of the screen: one thin strip
// along the bottom of every monitor that shows them (PetStrip). Normally they
// live on the bar instead (PetRun, loaded by the Bar); this is for "at the
// bottom of the screen" in the settings, and for a bar on the left / right.
Scope {
    Variants {
        model: Pets.active && !Pets.onBar ? Quickshell.screens.filter(s => Pets.showsOnScreen(s)) : []
        PetStrip {}
    }
}
