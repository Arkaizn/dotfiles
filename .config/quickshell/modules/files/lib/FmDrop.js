.pragma library

// Drag and drop between the file manager and other apps.
//   mime(paths, toUri)      the data a drag out carries: text/uri-list (CRLF), text/plain (paths),
//                           x-special/gnome-copied-files; toUri(path) → URI, "" to leave a path out
//   webLink(url, title)     what a dropped web link becomes: { name, text } (a .desktop link file;
//                           not executable — the file manager opens http(s) links itself)
//   b64(bytes)              base64 of a Uint8Array (a browser's image)
//   imageType(formats)      the image/* format to save, "" if none; ext(format) "png", "jpg" …

function mime(paths, toUri) {
    const uris = paths.map(toUri).filter(u => u !== "")
    return { "text/uri-list": uris.join("\r\n") + "\r\n", "text/plain": paths.join("\n"),
             "x-special/gnome-copied-files": "copy\n" + uris.join("\n") }
}

function host(url) {
    const m = /^[a-z][a-z0-9+.-]*:\/\/([^/?#]+)/i.exec(url)
    return m ? m[1].replace(/^.*@/, "").replace(/:\d+$/, "") : ""
}

function clean(s) {
    // a file name from a page title: no "/", control characters or edge spaces, not too long
    return String(s).replace(/[\/\x00-\x1f\x7f]/g, " ").replace(/\s+/g, " ").trim().slice(0, 120)
}

function webLink(url, title) {
    const t = clean(title || "") || host(url) || "link"
    const safe = String(url).replace(/[\r\n]/g, "")
    return { name: "Saved from web — " + t + ".desktop",
             text: "[Desktop Entry]\nType=Link\nName=" + clean(title || host(url) || safe) + "\nURL=" + safe + "\nIcon=text-html\n" }
}

var chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
function b64(bytes) {
    let out = ""
    for (let i = 0; i < bytes.length; i += 3) {
        const a = bytes[i], b = bytes[i + 1], c = bytes[i + 2]
        out += chars[a >> 2] + chars[((a & 3) << 4) | ((b ?? 0) >> 4)]
             + (b === undefined ? "=" : chars[((b & 15) << 2) | ((c ?? 0) >> 6)])
             + (c === undefined ? "=" : chars[c & 63])
    }
    return out
}

var imageOrder = ["image/png", "image/jpeg", "image/webp", "image/gif", "image/avif", "image/bmp"]
function imageType(formats) {
    for (const f of imageOrder) if (formats.indexOf(f) >= 0) return f
    return ""
}
function ext(format) {
    return ({ "image/jpeg": "jpg" })[format] || format.split("/")[1] || "bin"
}
