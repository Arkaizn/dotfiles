.pragma library

// Paths in the file manager: always absolute, no trailing slash ("/" alone
// for the root), "." and ".." resolved by name like the path bar shows them.
//   normalize(p) · parent(p) · base(p) · join(dir, name) · under(p, dir)
//   crumbs(p, home)  the path bar's parts: [{ label, path, home }]
//   fromArg(s)       an absolute path or a file:// URI from outside → path, "" if neither
//   url(p)           a file:// URL for Qt (Image, drag and drop)
//   validName(n, fs) "" or why it can't be a file name (fs: the folder's file system type;
//                    FAT / NTFS refuse more characters) — the same rules as filesd's ops.name_error
//   nameWarning(n)   "" or something to know before using it (a dot makes it hidden, spaces at the ends)

function normalize(p) {
    const out = []
    for (const part of String(p).split("/")) {
        if (part === "" || part === ".") continue
        if (part === "..") out.pop()
        else out.push(part)
    }
    return "/" + out.join("/")
}

function parent(p) {
    const i = p.lastIndexOf("/")
    return i <= 0 ? "/" : p.slice(0, i)
}

function base(p) {
    return p === "/" ? "/" : p.slice(p.lastIndexOf("/") + 1)
}

function join(dir, name) {
    return dir === "/" ? "/" + name : dir + "/" + name
}

function under(p, dir) {
    return p === dir || dir === "/" || p.startsWith(dir + "/")
}

function crumbs(p, home) {
    const out = []
    let at = "/"
    if (home && home !== "/" && under(p, home)) {
        out.push({ label: "Home", path: home, home: true })
        at = home
    } else {
        out.push({ label: "/", path: "/", home: false })
    }
    const rest = p.slice(at.length).split("/").filter(s => s !== "")
    for (const s of rest) {
        at = join(at, s)
        out.push({ label: s, path: at, home: false })
    }
    return out
}

function fromArg(s) {
    s = String(s)
    if (s.startsWith("file://")) {
        // file:///x or file://localhost/x; the rest is percent-encoded
        let rest = s.slice(7)
        if (rest.startsWith("localhost/")) rest = rest.slice(9)
        if (!rest.startsWith("/")) return ""
        try { rest = decodeURIComponent(rest) } catch (e) { return "" }
        return rest.includes("\0") ? "" : normalize(rest)
    }
    return s.startsWith("/") && !s.includes("\0") ? normalize(s) : ""
}

function url(p) {
    return "file://" + p.split("/").map(encodeURIComponent).join("/")
}

var fatLike = ["vfat", "msdos", "exfat", "ntfs", "ntfs3", "fuseblk"]

function utf8Length(s) {
    let n = 0
    for (const ch of s) {
        const c = ch.codePointAt(0)
        n += c < 0x80 ? 1 : c < 0x800 ? 2 : c < 0x10000 ? 3 : 4
    }
    return n
}

function validName(n, fs) {
    if (n === "" || n.trim() === "") return "Enter a name"
    if (n === "." || n === "..") return "“" + n + "” isn't a file name"
    if (n.includes("/")) return "A name can't contain “/”"
    if (n.includes("\0")) return "A name can't contain a null character"
    if (utf8Length(n) > 255) return "That name is too long"
    if (fatLike.indexOf(fs) >= 0 && (/[<>:"\\|?*]/.test(n) || /[ .]$/.test(n)))
        return "This drive doesn't allow < > : \" \\ | ? * or a space / dot at the end"
    return ""
}

function nameWarning(n) {
    if (n.startsWith(".") && n !== "." && n !== "..") return "A name starting with a dot makes it hidden"
    if (n !== n.trim()) return "The name starts or ends with a space"
    return ""
}
