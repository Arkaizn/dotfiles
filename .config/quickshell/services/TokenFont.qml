import QtQuick
import qs.services

// Tokens.font.* — a type of its own (not an inline QtObject) so qmllint
// knows its members. See Tokens.qml / DESIGN.md.
QtObject {
    readonly property int base: Properties.pixelSize
    readonly property int micro: base - 3       // 10 — badges, counters, tiny timestamps
    readonly property int caption: base - 2     // 11 — hints, secondary lines, meta text
    readonly property int small: base - 1       // 12 — buttons, list rows, dense labels
    readonly property int body: base            // 13 — text fields, primary row text
    readonly property int label: base + 1       // 14 — card titles, icon glyphs in buttons
    readonly property int subtitle: base + 3    // 16 — section headings, big glyphs
    readonly property int title: base + 5       // 18 — window and dialog titles
    readonly property int titleLarge: base + 7  // 20 — big glyphs, app headers
    readonly property int headline: base + 9    // 22 — big numbers, hero headings
    readonly property int page: base + 11       // 24 — the title of an app page (AppHeader)
    readonly property int display: base + 15    // 28 — hero numbers (wizard, polkit, stats)

    // font.features: Tokens.font.tnum — digits of one width for numbers that
    // change or sit in a column (no visible effect with a mono font, matters
    // as soon as the Font setting is a proportional one)
    readonly property var tnum: ({ "tnum": 1 })
}
