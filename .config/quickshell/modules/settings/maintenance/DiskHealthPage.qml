import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.components
import qs.services
import ".."
import "../network"

// Disk health (SMART): reading it needs root, so it only runs when you click
// and asks for your password once (pkexec + smartctl for all disks).
ColumnLayout {
    id: page
    spacing: 16

    property var disks: []                  // lsblk: [{ name, model, size, tran }]
    property var smart: ({})                // name → parsed smartctl JSON
    property string error: ""
    property bool reading: false

    Component.onCompleted: Jobs.run(["lsblk", "-J", "-d", "-o", "NAME,MODEL,SIZE,TYPE,TRAN,RM"], (code, out) => {
        try {
            disks = JSON.parse(out).blockdevices
                .filter(d => d.type === "disk" && /^(nvme\d+n\d+|sd[a-z]+|vd[a-z]+|hd[a-z]+)$/.test(d.name))
                .map(d => ({ name: d.name, model: d.model ?? "", size: d.size, tran: d.tran ?? "", removable: d.rm === true || d.rm === "1" }))
        } catch (e) { error = "couldn't list the disks" }
    })

    function read() {
        if (disks.length === 0) return
        reading = true
        error = ""
        const devs = disks.map(d => "/dev/" + d.name)
        Jobs.run(["pkexec", "sh", "-c", 'for d in "$@"; do printf "@@DEV %s\\n" "$d"; smartctl -j -a -- "$d"; done', "sh"].concat(devs), (code, out, err) => {
            reading = false
            if ((code === 126 || code === 127) && !out.includes("@@DEV")) { error = "cancelled (no password given)"; return }
            if (out.trim() === "") { error = err.includes("not found") ? "smartctl isn't installed: sudo pacman -S smartmontools" : (err.trim() || "no output"); return }
            const s = {}
            for (const chunk of out.split("@@DEV ").filter(c => c.trim())) {
                const nl = chunk.indexOf("\n")
                const dev = chunk.slice(0, nl).replace("/dev/", "")
                try { s[dev] = JSON.parse(chunk.slice(nl + 1)) } catch (e) { s[dev] = null }
            }
            smart = s
        })
    }

    // the numbers that matter, for NVMe and SATA
    function facts(j) {
        if (!j) return []
        const f = []
        const nv = j.nvme_smart_health_information_log
        const attr = id => j.ata_smart_attributes?.table?.find(a => a.id === id)?.raw?.value
        if (j.temperature?.current !== undefined) f.push(["Temperature", j.temperature.current + " °C"])
        if (j.power_on_time?.hours !== undefined) f.push(["Powered on", j.power_on_time.hours + " h (" + (j.power_on_time.hours / 24 / 365).toFixed(1) + " years)"])
        if (nv) {
            f.push(["Wear (used of its rated life)", nv.percentage_used + " %"])
            f.push(["Spare blocks left", nv.available_spare + " % (warns below " + nv.available_spare_threshold + " %)"])
            f.push(["Written", PerfMon.bytes(nv.data_units_written * 512000)])
            f.push(["Read", PerfMon.bytes(nv.data_units_read * 512000)])
            f.push(["Media errors", String(nv.media_errors)])
            f.push(["Unsafe shutdowns", String(nv.unsafe_shutdowns)])
        } else {
            if (attr(5) !== undefined) f.push(["Reallocated sectors", String(attr(5))])
            if (attr(197) !== undefined) f.push(["Sectors waiting to be reallocated", String(attr(197))])
            if (attr(198) !== undefined) f.push(["Uncorrectable sectors", String(attr(198))])
            if (attr(241) !== undefined) f.push(["Written (LBAs)", String(attr(241))])
        }
        return f
    }

    NetCard {
        Layout.fillWidth: true
        title: "Disk health (SMART)"
        icon: "󰋊"
        header: ActionButton {
            icon: "󰌾"
            text: page.reading ? "Reading…" : Object.keys(page.smart).length ? "Read again" : "Read (asks for your password)"
            primary: Object.keys(page.smart).length === 0
            interactive: !page.reading && page.disks.length > 0
            onClicked: page.read()
        }
        NetRow {
            first: true
            label: page.error !== "" ? "Problem" : page.disks.length + " disks"
            desc: page.error !== "" ? page.error : "the disk's own records: errors, wear, temperature. Reading needs root (smartctl), nothing is changed."
        }
    }

    Repeater {
        model: page.disks
        NetCard {
            id: card
            required property var modelData
            readonly property var j: page.smart[modelData.name]
            readonly property bool ok: j?.smart_status?.passed === true
            Layout.fillWidth: true
            title: modelData.model + "  ·  " + modelData.size + "  ·  /dev/" + modelData.name + (modelData.tran ? "  ·  " + modelData.tran : "")
            tint: card.j === undefined ? "transparent" : card.ok ? "transparent" : Qt.rgba(0.95, 0.55, 0.66, 0.08)
            NetRow {
                first: true
                label: card.j === undefined ? "Not read yet" : card.j === null ? "No SMART data"
                     : card.j.smart_status === undefined ? "No health status (USB adapters often hide it)"
                     : card.ok ? "󰄬  Healthy (SMART passed)" : "󰀦  SMART reports a FAILURE: back up this disk now"
                desc: card.j?.smartctl?.messages?.map(m => m.string).join(" ") ?? ""
            }
            Repeater {
                model: page.facts(card.j)
                NetRow {
                    required property var modelData
                    sub: true
                    label: modelData[0]
                    Text { text: modelData[1]; color: "white"; font.pixelSize: 12; font.family: Properties.fontFamily }
                }
            }
        }
    }
}
