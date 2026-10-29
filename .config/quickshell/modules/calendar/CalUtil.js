.pragma library

// Date helpers for the calendar app. Weeks start on Monday, times are 24h.

const DAY = 86400000
const monthNames = ["January", "February", "March", "April", "May", "June",
                    "July", "August", "September", "October", "November", "December"]
const dayNames = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
const dayShort = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

function dayStart(d) { const x = new Date(d); x.setHours(0, 0, 0, 0); return x }
function addDays(d, n) { const x = new Date(d); x.setDate(x.getDate() + n); return x }
function addMonths(d, n) { const x = new Date(d); x.setDate(1); x.setMonth(x.getMonth() + n); return x }
function weekday(d) { return (new Date(d).getDay() + 6) % 7 }           // 0 = Monday
function weekStart(d) { return addDays(dayStart(d), -weekday(d)) }
function monthStart(d) { const x = dayStart(d); x.setDate(1); return x }
function sameDay(a, b) { return dayStart(a).getTime() === dayStart(b).getTime() }
function isToday(d) { return sameDay(d, new Date()) }
function pad(n) { return String(n).padStart(2, "0") }
function dayKey(d) { const x = new Date(d); return x.getFullYear() + "-" + pad(x.getMonth() + 1) + "-" + pad(x.getDate()) }

function fmtTime(ms) { const d = new Date(ms); return pad(d.getHours()) + ":" + pad(d.getMinutes()) }
function fmtDate(d) { d = new Date(d); return dayNames[weekday(d)] + ", " + d.getDate() + ". " + monthNames[d.getMonth()] + " " + d.getFullYear() }
function fmtShortDate(d) { d = new Date(d); return dayShort[weekday(d)] + " " + d.getDate() + ". " + monthNames[d.getMonth()].slice(0, 3) }

// ISO week number
function weekNumber(d) {
    const x = dayStart(d)
    x.setDate(x.getDate() + 3 - weekday(x))
    const jan4 = new Date(x.getFullYear(), 0, 4)
    return 1 + Math.round(((x - jan4) / DAY - 3 + weekday(jan4)) / 7)
}

// "09:00 – 10:30", "All day", "Until 12:00" … as seen from `day`
function fmtRange(ev, day) {
    if (ev.allDay) {
        const days = Math.round((ev.end - ev.start) / DAY)
        return days > 1 ? "All day · " + days + " days" : "All day"
    }
    if (day) {
        const ds = dayStart(day).getTime(), de = ds + DAY
        if (ev.start < ds && ev.end > de) return "All day"
        if (ev.start < ds) return "Until " + fmtTime(ev.end)
        if (ev.end > de) return "From " + fmtTime(ev.start)
    }
    return ev.end > ev.start ? fmtTime(ev.start) + " – " + fmtTime(ev.end) : fmtTime(ev.start)
}

// events overlapping a day (end exclusive; zero-length events count at their start)
function overlapsDay(ev, day) {
    const ds = dayStart(day).getTime(), de = ds + DAY
    return ev.start < de && (ev.end > ds || (ev.end === ev.start && ev.start >= ds))
}

// spans the whole day (all-day or multi-day timed) → goes into the all-day row
function fullDay(ev, day) {
    if (ev.allDay) return true
    const ds = dayStart(day).getTime()
    return ev.start <= ds && ev.end >= ds + DAY
}

// Side-by-side layout for overlapping timed events of one day.
// -> [{ ev, col, cols, top, bottom, reach }] in minutes since midnight: top /
// bottom are the event's real times (what's drawn); reach is at least minSpan
// minutes after top — the room a very short event's label needs — and only
// decides which events sit side by side.
function layoutDay(events, day, minSpan) {
    const ds = dayStart(day).getTime()
    const span = minSpan ?? 20
    const items = events.map(ev => {
        const top = Math.max(0, (ev.start - ds) / 60000)
        const bottom = Math.min(1440, Math.max(top, (ev.end - ds) / 60000))
        return { ev: ev, top: top, bottom: bottom, reach: Math.min(1440, Math.max(bottom, top + span)) }
    }).sort((a, b) => a.top - b.top || b.bottom - a.bottom)

    // groups of transitively overlapping events share the width
    let group = [], groupEnd = -1
    const flush = () => {
        const colsEnd = []
        for (const it of group) {
            let c = colsEnd.findIndex(end => end <= it.top)
            if (c < 0) { c = colsEnd.length; colsEnd.push(0) }
            colsEnd[c] = it.reach
            it.col = c
        }
        for (const it of group) it.cols = colsEnd.length
        group = []
    }
    for (const it of items) {
        if (group.length && it.top >= groupEnd) flush()
        group.push(it)
        groupEnd = Math.max(groupEnd, it.reach)
    }
    flush()
    return items
}

// readable text color on top of a color
function onColor(c) {
    const l = 0.299 * c.r + 0.587 * c.g + 0.114 * c.b
    return l > 0.6 ? "#1a1a1a" : "white"
}
