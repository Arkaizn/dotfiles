.pragma library

// Which network device of a kind the bar / control center show. Not simply the
// first one: NetworkManager also lists virtual adapters of the same type
// (VMware's vmnet1/8 are "ethernet", unmanaged and never connected), and a
// dock's ethernet or a USB Wi-Fi stick is added at the end of the list.
// So: a connected one, else one NetworkManager manages, else none.
function pick(devices, type) {
    const all = (devices ?? []).filter(d => d && d.type === type)
    return all.find(d => d.connected) ?? all.find(d => d.nmManaged) ?? null
}

// "Wi-Fi off while wired" (services/WiredWifi.qml): what to do with the Wi-Fi.
// Only turns back on a Wi-Fi it turned off itself, never one you switched off.
//   returns { wifi: true | false | null (leave it), turnedOff: whether we turned it off }
function wifiAction(enabled, wired, wifiOn, turnedOff) {
    if (!enabled || !wired) return turnedOff ? { wifi: true, turnedOff: false } : { wifi: null, turnedOff: false }
    if (wifiOn) return { wifi: false, turnedOff: true }
    return { wifi: null, turnedOff: turnedOff }
}
