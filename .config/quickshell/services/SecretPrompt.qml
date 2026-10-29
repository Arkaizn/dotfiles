pragma Singleton
import Quickshell
import QtQuick

// A password / PIN asked by the shell itself (modules/polkit/SecretDialog.qml,
// same look as the polkit dialog): RDP "ask" passwords, smartcard PINs.
// The answer only goes to the callback, it isn't kept anywhere.
//
//   SecretPrompt.ask({ title, message, icon, placeholder, hint, minLength, action,
//                      choices: [{ label, desc }] }, (text, choice) => …)
//   text === null: cancelled. choice: index into choices (0 without any).
// A new request cancels the one still open.
Singleton {
    id: root

    property var request: null
    property var callback: null

    function ask(req, cb) {
        if (root.request) cancel()
        root.callback = cb
        root.request = Object.assign({ title: "", message: "", icon: "󰌋", placeholder: "Password",
                                       hint: "", minLength: 1, action: "OK", choices: [] }, req)
    }

    function answer(text, choice) { finish(text, choice ?? 0) }
    function cancel() { finish(null, 0) }

    function finish(text, choice) {
        const cb = root.callback
        root.callback = null
        root.request = null
        if (cb) cb(text, choice)
    }
}
