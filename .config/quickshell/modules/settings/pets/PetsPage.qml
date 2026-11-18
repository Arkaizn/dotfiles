import QtQuick
import QtQuick.Layouts
import qs.components
import qs.services
import qs.services.lib
import "../../desktop"

// Settings → Desktop pets (services/Pets.qml) and the offline game
// (services/OfflineGame.qml): which animals in which coat, where they live, when they sleep;
// the game on / off. The animals come from Pets.animals,
// so a new one shows up here by itself.
ColumnLayout {
    id: page
    spacing: Tokens.space.s16

    function opt(key, def) { return Settings.pets[key] ?? def }
    function setOpt(key, v) { Settings.set("pets", key, v) }

    // every preview on the page steps together, and only while the page shows
    property int beat: 0
    Timer { interval: 140; repeat: true; running: page.visible && Anim.ambient; onTriggered: page.beat++ }

    Section {
        Layout.fillWidth: true
        title: "Desktop pets"
        icon: "󰄛"
        SettingRow {
            first: true
            label: "Show desktop pets"
            desc: "Small pixel animals on the bar. They mostly nap, take a short walk now and then, and come when you click or drag them: each in its own way"
            ToggleSwitch { checked: Pets.enabled; onToggled: v => Pets.setEnabled(v) }
        }
        Repeater {
            model: Pets.animals
            SettingRow {
                id: row
                required property var modelData
                readonly property bool on: Pets.chosenIds.includes(modelData.id)
                label: modelData.name
                desc: "Call it and it " + modelData.petted
                RowLayout {
                    spacing: Tokens.space.s12
                    // it walks while it's switched on, and sits while it isn't
                    PixelSprite {
                        rows: PixelArt.frame(row.modelData, row.on && Pets.enabled ? PixelArt.frameAt(row.modelData, "walk", page.beat * 140)
                                                                                  : PixelArt.frameAt(row.modelData, "sit", 0))
                        palette: Pets.paletteOf(row.modelData)
                        px: 2
                        opacity: row.on && Pets.enabled ? 1 : Tokens.alpha.disabled
                        Behavior on opacity { NumberAnimation { duration: Anim.normal; easing.type: Anim.standard } }
                    }
                    // its coat
                    Dropdown {
                        options: row.modelData.coats.map(c => ({ label: c.name, value: c.id, color: c.colors.o }))
                        value: Pets.coatOf(row.modelData)
                        onEdited: v => Pets.setCoat(row.modelData.id, v)
                    }
                    ToggleSwitch {
                        interactive: Pets.enabled
                        checked: row.on
                        onToggled: v => Pets.setAnimal(row.modelData.id, v)
                    }
                }
            }
        }
    }

    Section {
        Layout.fillWidth: true
        title: "Where and how"
        icon: "󰍹"
        SettingRow {
            first: true
            label: "They live"
            desc: PanelGeometry.barVertical && Pets.place === "bar" ? "The bar is on the side, where there's no row to walk along: they are at the bottom of the screen until it's at the top or bottom again"
                : "On the bar: as high as its buttons, resting between them. At the bottom of the screen: bigger, over or under the windows"
            Segmented {
                options: [{ label: "On the bar", value: "bar" }, { label: "Bottom of the screen", value: "screen" }]
                value: Pets.place
                onEdited: v => page.setOpt("place", v)
            }
        }
        SettingRow {
            label: "Show them on"
            desc: "Each monitor has its own pets"
            wide: true
            MonitorChips {
                Layout.fillWidth: true
                value: Pets.monitors
                onEdited: v => page.setOpt("monitors", v ?? [])
            }
        }
        SettingRow {
            visible: !Pets.onBar
            sub: true
            label: "Size"
            desc: "On the bar they are always as high as a button"
            Segmented {
                options: [{ label: "Small", value: "small" }, { label: "Medium", value: "medium" }, { label: "Large", value: "large" }]
                value: Pets.size
                onEdited: v => page.setOpt("size", v)
            }
        }
        SettingRow {
            visible: !Pets.onBar
            sub: true
            label: "Over or under windows"
            desc: "Over: always in sight, hidden by fullscreen windows. On the desktop: below every window, like the widgets"
            Segmented {
                options: [{ label: "Over windows", value: "top" }, { label: "On the desktop", value: "bottom" }]
                value: Pets.layer
                onEdited: v => page.setOpt("layer", v)
            }
        }
        SettingRow {
            label: "Everyone asleep after"
            desc: "Minutes without a key or the pointer. They nap a lot anyway; this is when all of them sleep until you're back"
            Segmented {
                options: ["1", "3", "5", "10", "20"]
                value: String(Pets.sleepAfter)
                onEdited: v => page.setOpt("sleepAfter", parseInt(v))
            }
        }
        SettingRow {
            label: "Look up at notifications"
            desc: "A new mail or any other notification that pops up; not with do not disturb on"
            ToggleSwitch { checked: Pets.react; onToggled: v => page.setOpt("react", v) }
        }
    }

    Section {
        Layout.fillWidth: true
        title: "Offline game"
        icon: Icons.get("offline")
        SettingRow {
            first: true
            label: "A game while offline"
            desc: "With nothing connected, a click on the bar's offline icon opens the control center with a small runner game above the Wi-Fi list: a dino jumping over dead routers, switches and server racks. Space or a click jumps"
            ToggleSwitch { checked: OfflineGame.enabled; onToggled: v => page.setOpt("game", v) }
        }
        SettingRow {
            label: "Best score"
            desc: "Kept on this device"
            Text {
                text: OfflineGame.best > 0 ? String(OfflineGame.best) : "No run yet"
                color: Colors.textSecondary
                font { pixelSize: Tokens.font.body; family: Properties.fontFamily; features: Tokens.font.tnum }
            }
        }
    }
}
