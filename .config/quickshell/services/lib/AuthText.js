.pragma library

// What the lockscreen and the login screen say when a password isn't taken.
// One place, so both show the same words.
//   message: the last PAM / greetd text (pam_faillock's "The account is
//            locked due to 3 failed logins." + "(1 minute left to unlock)",
//            greetd's "pam_authenticate: MAXTRIES", …)
//   maxTries: PAM said MaxTries (lockscreen's PamResult)

// "Too many attempts, …" when the account is locked, else ""
function locked(message, maxTries) {
    const m = String(message ?? "")
    if (!maxTries && !/lock|maxtries|too many/i.test(m)) return ""
    const left = m.match(/(\d+)\s+(minute|second)s?\s+left/i)
    if (left) {
        const n = Number(left[1])
        return "Too many attempts, try again in " + n + " " + left[2].toLowerCase() + (n === 1 ? "" : "s")
    }
    return "Too many attempts, wait a moment"
}

// the text for a refused password
function failure(message, maxTries) {
    return locked(message, maxTries) || "Wrong password"
}

// the text for an error that isn't a wrong password (PAM / greetd broke)
function error() {
    return "Authentication error"
}
