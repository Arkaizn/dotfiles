import Quickshell
import QtQuick
import qs.services

// Desktop widgets (services/DesktopWidgets.qml): one small bottom-layer window
// per widget and monitor (DesktopWidgetWindow), and the live editor on every
// monitor while editing (DesktopEditor).
Scope {
    Variants {
        model: DesktopWidgets.enabled ? Quickshell.screens : []
        Scope {
            id: perScreen
            required property ShellScreen modelData
            Variants {
                model: DesktopWidgets.idsFor(perScreen.modelData.name)
                DesktopWidgetWindow {
                    required property string modelData
                    screen: perScreen.modelData
                    instId: modelData
                }
            }
        }
    }
    Variants {
        model: DesktopWidgets.editing ? Quickshell.screens : []
        DesktopEditor {}
    }
}
