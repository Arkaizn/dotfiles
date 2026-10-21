import QtQuick
import QtQuick.Layouts
import qs.components
import qs.services
import qs.services.lib
import ".."
import "../network"

// Add a Jellyfin server through the bridge (jellyfin.servers.add; only shown
// when the bridge has that API). Test checks the address first (jellyfin.test).
NetRow {
    id: add
    wide: true
    label: "Add a server"
    desc: add.message !== "" ? add.message
        : add.urlProblem !== "" && url.text !== "" ? add.urlProblem
        : "A short name (used in session IDs) and the server's address; log in afterwards"
    descError: add.messageError || (add.urlProblem !== "" && url.text !== "")
    property bool busy: false
    property string message: ""
    property bool messageError: false
    readonly property string urlProblem: MediaSources.serverUrl(url.text)
    readonly property string nameProblem: MediaSources.serverName(name.text.trim())

    RowLayout {
        Layout.fillWidth: true
        spacing: 8
        SearchField { id: name; Layout.preferredWidth: 130; icon: ""; clearable: false; placeholderText: "home" }
        SearchField { id: url; Layout.fillWidth: true; icon: "󰖟"; clearable: false; placeholderText: "https://jellyfin.example.org" }
        ActionButton {
            icon: "󰓅"; text: "Test"
            interactive: !add.busy && add.urlProblem === ""
            onClicked: {
                add.busy = true
                MediaSync.testServer(url.text.trim(), (err, res) => {
                    add.busy = false
                    add.messageError = !!err
                    add.message = err ? MediaSources.errorText(err) : "Reachable: " + (res.server_name ?? "Jellyfin") + " " + (res.server_version ?? "")
                })
            }
        }
        ActionButton {
            icon: "󰐕"; text: "Add"; primary: true
            interactive: !add.busy && add.urlProblem === "" && add.nameProblem === ""
            onClicked: {
                add.busy = true
                MediaSync.addServer({ name: name.text.trim(), url: url.text.trim() }, err => {
                    add.busy = false
                    add.messageError = !!err
                    add.message = err ? MediaSources.errorText(err) : "Added; log in below"
                    if (!err) { name.text = ""; url.text = "" }
                })
            }
        }
    }
}
