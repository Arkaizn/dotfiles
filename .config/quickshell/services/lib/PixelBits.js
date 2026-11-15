.pragma library
// Small pixel art that isn't an animal: what floats up from a pet (heart, z,
// "!") and the offline game's world (dead network gear: router, switch, a
// stack of switches, a server rack; clouds). Format:
// PixelArt.js. The palette names roles; whoever draws a frame says which
// colours they are (the scheme's): i ink, a accent, m muted, r red.

var def = {
    id: "bits", name: "Bits", w: 18, h: 16,
    palette: { i: "ink", a: "accent", m: "muted", r: "red" },
    parts: {
        heart: [
            ".rr.rr.",
            "rrrrrrr",
            "rrrrrrr",
            ".rrrrr.",
            "..rrr..",
            "...r..."],
        z: [
            "iiiii",
            "...i.",
            "..i..",
            ".i...",
            "iiiii"],
        bang: [
            "aa",
            "aa",
            "aa",
            "aa",
            "..",
            "aa"],
        // a router with nothing coming out of its antennas
        router: [
            ".i............i.",
            ".i............i.",
            ".i............i.",
            "iiiiiiiiiiiiiiii",
            "i..............i",
            "i.a.m.m.m......i",
            "i..............i",
            "iiiiiiiiiiiiiiii",
            ".ii..........ii."],
        // a network switch: one row of ports
        netswitch: [
            "iiiiiiiiiiiiiiiiii",
            "i................i",
            "i.i.i.i.i.i.i..a.i",
            "i.i.i.i.i.i.i....i",
            "iiiiiiiiiiiiiiiiii"],
        // three switches on top of each other
        stack: [
            ".iiiiiiiiiiiiiii.",
            ".i.i.i.i.i.i..ai.",
            ".iiiiiiiiiiiiiii.",
            "iiiiiiiiiiiiiiiii",
            "i.i.i.i.i.i.i..mi",
            "iiiiiiiiiiiiiiiii",
            ".iiiiiiiiiiiiiii.",
            ".i.i.i.i.i.i..ai.",
            ".iiiiiiiiiiiiiii.",
            "iiiiiiiiiiiiiiiii",
            "i.i.i.i.i.i.i..mi",
            "iiiiiiiiiiiiiiiii"],
        // a rack full of servers
        rack: [
            "iiiiiiiiiii",
            "i.........i",
            "i.a.mmmmm.i",
            "i.........i",
            "i.iiiiiii.i",
            "i.........i",
            "i.m.mmmmm.i",
            "i.........i",
            "i.iiiiiii.i",
            "i.........i",
            "i.a.mmmmm.i",
            "i.........i",
            "i.iiiiiii.i",
            "i.........i",
            "iiiiiiiiiii",
            "ii.......ii"],
        cloud: [
            "....mmmm.....",
            "..mmmmmmmm...",
            ".mmmmmmmmmmm.",
            "mmmmmmmmmmmmm"]
    },
    frames: {
        heart: [["heart", 0, 0]], z: [["z", 0, 0]], bang: [["bang", 0, 0]],
        router: [["router", 0, 0]], netswitch: [["netswitch", 0, 0]], stack: [["stack", 0, 0]], rack: [["rack", 0, 0]], cloud: [["cloud", 0, 0]]
    },
    anims: {}
}

// the size of a part in pixels: { w, h }
function size(name) {
    var p = def.parts[name]
    return p ? { w: p[0].length, h: p.length } : { w: 0, h: 0 }
}

// what stands in the way in the offline game (one is picked at random each time)
var obstacles = ["router", "netswitch", "stack", "rack"]
