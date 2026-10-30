.pragma library

// Nerd Font (Material Design) icons of the mail app, by code point.
const c = String.fromCodePoint
const mail = c(0xF01EE), mailOpen = c(0xF01EF), inbox = c(0xF0687), send = c(0xF048A)
const reply = c(0xF045A), replyAll = c(0xF045B), forward = c(0xF0496), archive = c(0xF003C)
const trash = c(0xF01B4), star = c(0xF04CE), starOutline = c(0xF04D2), clip = c(0xF03E2)
const junk = c(0xF0029), alert = c(0xF0026), folder = c(0xF024B), draft = c(0xF03EB), search = c(0xF0349)
const download = c(0xF01DA), open = c(0xF03CC), down = c(0xF0140), right = c(0xF0142)
const left = c(0xF0141), shield = c(0xF0498), thread = c(0xF028C), back = c(0xF004D)
const plus = c(0xF0415), refresh = c(0xF0450), cog = c(0xF0493), close = c(0xF0156)
const check = c(0xF012C), unread = c(0xF0BA3), moon = c(0xF0594), sun = c(0xF05A8)

// folder role → icon
function role(r) {
    return ({ inbox: inbox, sent: send, drafts: draft, trash: trash, junk: junk, archive: archive,
              all: mailOpen, flagged: star })[r] ?? folder
}
