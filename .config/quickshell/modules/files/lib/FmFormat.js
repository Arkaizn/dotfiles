.pragma library

// Text for the file manager's columns and status line.
//   when(mtime, now)   "14:05" today, "Yesterday 14:05", "Mon 14:05" this week, "3 Nov", "3 Nov 2025"
//   typeLabel(item)    "Folder", "PNG image", "Text", "PDF document", "Archive" …
//   items(n)           "1 item", "12 items"
//   shown(name)        a name for display: a newline as ↵, other control characters as �

var months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
var days = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

function pad2(n) { return String(n).padStart(2, "0") }

function when(mtime, now) {
    const d = new Date(mtime * 1000), n = new Date(now)
    const hm = pad2(d.getHours()) + ":" + pad2(d.getMinutes())
    const start = new Date(n.getFullYear(), n.getMonth(), n.getDate()).getTime()
    const t = d.getTime()
    if (t >= start && t < start + 86400000) return hm
    if (t >= start - 86400000 && t < start) return "Yesterday " + hm
    if (t >= start - 6 * 86400000 && t < start) return days[d.getDay()] + " " + hm
    return d.getDate() + " " + months[d.getMonth()] + (d.getFullYear() === n.getFullYear() ? "" : " " + d.getFullYear())
}

var named = {
    "application/pdf": "PDF document", "application/zip": "ZIP archive", "application/x-7z-compressed": "7-Zip archive",
    "application/x-compressed-tar": "Tar archive (gzip)", "application/x-xz-compressed-tar": "Tar archive (xz)",
    "application/x-zstd-compressed-tar": "Tar archive (zstd)", "application/x-bzip2-compressed-tar": "Tar archive (bzip2)",
    "application/x-tar": "Tar archive", "application/x-shellscript": "Shell script", "text/x-shellscript": "Shell script",
    "application/x-executable": "Program", "application/x-pie-executable": "Program", "application/x-sharedlib": "Library",
    "application/x-desktop": "App launcher", "application/x-ms-dos-executable": "Windows program", "application/json": "JSON", "application/x-iso9660-image": "Disk image",
    "application/x-zerosize": "Empty file", "application/octet-stream": "Binary", "text/plain": "Text",
    "text/markdown": "Markdown", "text/html": "Web page", "text/csv": "CSV table", "text/calendar": "Calendar",
    "message/rfc822": "Mail", "inode/symlink": "Broken link", "inode/fifo": "Pipe", "inode/socket": "Socket",
    "inode/blockdevice": "Block device", "inode/chardevice": "Character device",
    "application/vnd.oasis.opendocument.text": "Document", "application/vnd.oasis.opendocument.spreadsheet": "Spreadsheet",
    "application/vnd.openxmlformats-officedocument.wordprocessingml.document": "Word document",
    "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet": "Excel spreadsheet",
    "application/vnd.openxmlformats-officedocument.presentationml.presentation": "PowerPoint presentation"
}
var kinds = { image: "image", audio: "audio", video: "video", font: "font" }

function typeLabel(item) {
    if (item.dir) return "Folder"
    const t = item.type || ""
    if (named[t]) return named[t]
    const slash = t.indexOf("/")
    const top = t.slice(0, slash), sub = t.slice(slash + 1).replace(/^(x-|vnd\.)/, "").split(/[.+;-]/)[0]
    if (kinds[top]) return sub.toUpperCase() + " " + kinds[top]
    if (top === "text") return sub === "plain" ? "Text" : sub.charAt(0).toUpperCase() + sub.slice(1) + " source"
    return sub ? sub.toUpperCase() + " file" : "File"
}

function items(n) {
    return n + (n === 1 ? " item" : " items")
}

function shown(name) {
    return String(name).replace(/\n/g, "\u21B5").replace(/[\x00-\x1f\x7f]/g, "\uFFFD")
}
