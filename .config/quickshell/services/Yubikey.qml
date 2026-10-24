pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// YubiKey OTP login is set up: pam_yubico is active in system-auth and the
// current user has a key in its authfile. The lockscreen re-checks on every
// lock (refresh()); the login screen gets the result through GreeterSync.
Singleton {
    id: root

    property bool present: false

    function refresh() { proc.running = true }

    Process {
        id: proc
        command: ["sh", "-c",
            "line=$(grep -E '^[[:space:]]*-?auth[[:space:]].*pam_yubico\\.so' /etc/pam.d/system-auth) || exit 1; " +
            "file=$(printf '%s' \"$line\" | grep -oE 'authfile=[^[:space:]]+' | cut -d= -f2); " +
            "grep -q \"^$USER:\" \"${file:-$HOME/.yubico/authorized_yubikeys}\" 2>/dev/null"]
        onExited: code => root.present = code === 0
    }
    Component.onCompleted: refresh()
}
