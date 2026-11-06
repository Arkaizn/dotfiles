.pragma library

// Glyphs (Nerd Font, Material Design set) for the file manager: an item's icon
// by its content type, the sidebar's places, the toolbar.
//   item(i)      the glyph of a listing item
//   tone(i)      which Colors role tints it: "accent" folders, "muted" the rest
//   place(kind)  home, desktop, documents, downloads, music, pictures, videos, drive, usb, root, bookmark

var g = {
    folder: "\u{F024B}", folderOpen: "\u{F0770}", home: "\u{F02DC}", desktop: "\u{F0379}",
    documents: "\u{F19F6}", downloads: "\u{F024D}", music: "\u{F1359}", pictures: "\u{F024F}", videos: "\u{F19FA}",
    drive: "\u{F02CA}", usb: "\u{F0553}", eject: "\u{F01EA}", bookmark: "\u{F00C0}", trash: "\u{F0A79}",
    file: "\u{F0214}", text: "\u{F0219}", image: "\u{F021F}", audio: "\u{F0223}", video: "\u{F022B}",
    pdf: "\u{F0226}", archive: "\u{F05C4}", code: "\u{F022E}", sheet: "\u{F021B}", doc: "\u{F022C}",
    slides: "\u{F0227}", script: "\u{F018D}", book: "\u{F00BA}", key: "\u{F0306}", database: "\u{F01BC}",
    calendar: "\u{F00ED}", mail: "\u{F01EE}", font: "\u{F06D6}", disc: "\u{F05EE}",
    link: "\u{F0337}", lock: "\u{F033E}", alert: "\u{F0026}",
    back: "\u{F004D}", forward: "\u{F0054}", up: "\u{F005D}", down: "\u{F0045}", refresh: "\u{F0450}", list: "\u{F0572}",
    grid: "\u{F0570}", sort: "\u{F04BA}", eye: "\u{F0208}", eyeOff: "\u{F0209}", search: "\u{F0349}",
    chevron: "\u{F0142}", cog: "\u{F0493}", newFolder: "\u{F0B9D}",
    tab: "\u{F04E9}", window: "\u{F05AF}", menu: "\u{F01D9}", columns: "\u{F0835}", selectAll: "\u{F0486}"
}

var codeTypes = ["application/json", "application/xml", "application/javascript", "application/x-yaml",
                 "application/toml", "application/x-php", "application/sql", "application/x-perl",
                 "application/x-ruby", "application/x-python", "application/x-desktop"]
var archiveTypes = ["application/zip", "application/x-7z-compressed", "application/x-rar", "application/vnd.rar",
                    "application/gzip", "application/x-xz", "application/x-bzip2", "application/zstd",
                    "application/x-zstd-compressed-tar", "application/x-compressed-tar", "application/x-bzip2-compressed-tar",
                    "application/x-xz-compressed-tar", "application/x-tar", "application/x-lzma", "application/java-archive",
                    "application/vnd.debian.binary-package", "application/x-rpm", "application/x-iso9660-image",
                    "application/vnd.android.package-archive"]

function item(i) {
    if (i.dir) return g.folder
    if (i.broken) return g.link
    const t = i.type || ""
    if (t.startsWith("image/")) return g.image
    if (t.startsWith("audio/")) return g.audio
    if (t.startsWith("video/")) return g.video
    if (t.startsWith("font/") || t.startsWith("application/x-font") || t === "application/vnd.ms-opentype") return g.font
    if (t === "application/pdf") return g.pdf
    if (t === "application/x-iso9660-image" || t === "application/x-cd-image") return g.disc
    if (archiveTypes.indexOf(t) >= 0) return g.archive
    if (t === "application/epub+zip" || t === "application/x-mobipocket-ebook") return g.book
    if (t.includes("spreadsheet") || t.includes("ms-excel") || t === "text/csv") return g.sheet
    if (t.includes("presentation") || t.includes("ms-powerpoint")) return g.slides
    if (t.includes("wordprocessing") || t === "application/msword" || t.includes("opendocument.text") || t === "application/rtf") return g.doc
    if (t === "text/calendar") return g.calendar
    if (t === "message/rfc822") return g.mail
    if (t.includes("x-sqlite") || t === "application/vnd.sqlite3") return g.database
    if (t.includes("pgp") || t.includes("x-x509") || t.includes("pkcs") || t.includes("pem-file") || t.includes("ssh-key")) return g.key
    if (t.endsWith("shellscript") || t === "application/x-executable" || t === "application/x-pie-executable" || t === "application/x-sharedlib") return g.script
    if (t.startsWith("text/x-") || t === "text/html" || t === "text/css" || t === "text/javascript" || codeTypes.indexOf(t) >= 0) return g.code
    if (t.startsWith("text/")) return g.text
    if (i.exec) return g.script
    return g.file
}

// the icon theme's names for an item, best first (freedesktop icon naming: "text/x-python" →
// "text-x-python", then the generic one of its kind)
function themeNames(i) {
    if (i.dir) return ["folder"]
    const t = i.type || ""
    const top = t.slice(0, t.indexOf("/"))
    const out = []
    if (t) out.push(t.replace("/", "-"))
    if (i.exec && top === "application") out.push("application-x-executable")
    if (["text", "image", "audio", "video", "font"].indexOf(top) >= 0) out.push(top + "-x-generic")
    if (t.indexOf("zip") >= 0 || t.indexOf("tar") >= 0 || t.indexOf("7z") >= 0) out.push("package-x-generic")
    out.push("text-x-generic")
    return out
}

function tone(i) {
    return i.dir ? "accent" : "muted"
}

function place(kind) {
    return ({ home: g.home, desktop: g.desktop, documents: g.documents, downloads: g.downloads, music: g.music,
              pictures: g.pictures, videos: g.videos, drive: g.drive, usb: g.usb, root: g.drive,
              bookmark: g.folder, trash: g.trash })[kind] || g.folder
}
