#!/bin/bash
# Password OR YubiKey (OTP) at every PAM password prompt (sudo, login, lockscreen, polkit).
# The key types its OTP + Enter into the password field; PAM first checks the input as
# the password and, if that fails, as an OTP against YubiCloud (needs internet).

source "$(dirname "$0")/../lib.sh"

PAM_FILE=/etc/pam.d/system-auth
MAPPINGS=/etc/yubikey_mappings
POLKIT_DROPIN=/etc/systemd/system/polkit-agent-helper@.service.d/yubico-otp.conf

# --- PAM ---------------------------------------------------------------------

configure_pam() {
    yay_install yubico-pam || return 1

    info "Get an API key at https://upgrade.yubico.com/getapikey/"
    info "(enter your email, touch the YubiKey; you get a Client ID and a Secret key)"
    local client_id secret otp key_id
    client_id=$(gum input --header "Client ID" --placeholder "e.g. 123456") || return 1
    [[ "$client_id" =~ ^[0-9]+$ ]] || { err "Client ID must be a number"; return 1; }
    secret=$(gum input --password --header "Secret key" --placeholder "base64 secret") || return 1
    [[ -n "$secret" && ! "$secret" =~ [[:space:]] ]] || { err "Invalid secret key"; return 1; }

    otp=$(gum input --password --header "Click here and touch the YubiKey" --placeholder "OTP") || return 1
    [[ ${#otp} -ge 32 && "$otp" =~ ^[cbdefghijklnrtuv]+$ ]] || { err "That doesn't look like a YubiKey OTP"; return 1; }
    key_id=${otp:0:12}
    ok "Key ID: $key_id"

    # timestamped, so a second run doesn't overwrite the original backup
    local backup
    backup="$PAM_FILE.bak.$(date +%Y%m%d-%H%M%S)"
    sudo cp "$PAM_FILE" "$backup" || return 1
    ok "Backup: $backup"

    # mappings: "user:id1:id2...", add the key to the user's line if it isn't there yet
    local tmp
    tmp=$(mktemp)
    sudo cat "$MAPPINGS" 2>/dev/null | awk -F: -v u="$USER" -v k="$key_id" '
        $1 == u { found = 1; for (i = 2; i <= NF; i++) if ($i == k) { print; next } print $0 ":" k; next }
        { print }
        END { if (!found) print u ":" k }' > "$tmp"
    sudo install -m 644 "$tmp" "$MAPPINGS" || { rm -f "$tmp"; return 1; }
    ok "Linked key to $USER in $MAPPINGS"

    # replace the auth block, keep account/password/session as they are
    awk -v id="$client_id" -v key="$secret" -v map="$MAPPINGS" '
        /^-?auth[[:space:]]/ {
            if (!done) {
                print "auth       required                    pam_faillock.so      preauth"
                print "-auth      [success=3 default=ignore]  pam_systemd_home.so"
                print "auth       [success=2 default=ignore]  pam_unix.so          try_first_pass nullok nodelay"
                print "auth       [success=1 default=ignore]  pam_yubico.so        mode=client id=" id " key=" key " authfile=" map " use_first_pass"
                print "auth       [default=die]               pam_faillock.so      authfail"
                print "auth       optional                    pam_permit.so"
                print "auth       required                    pam_env.so"
                print "auth       required                    pam_faillock.so      authsucc"
                done = 1
            }
            next
        }
        { print }' "$backup" > "$tmp"
    sudo install -m 644 "$tmp" "$PAM_FILE" || { rm -f "$tmp"; return 1; }
    rm -f "$tmp"
    ok "Updated $PAM_FILE"

    test_pam "$backup"
}

# test via su (its own PAM service, also includes system-auth) so the sudo
# timestamp stays valid and we can still restore the backup if login broke
test_pam() {
    local backup=$1 what choice
    for what in "your password" "only the YubiKey (touch it)"; do
        while true; do
            info "Test: at the prompt, enter $what"
            if su "$USER" -c true; then
                ok "Works with $what"
                break
            fi
            err "Didn't work with $what"
            info "(3 failures lock you out for 10 min: sudo faillock --user $USER --reset)"
            choice=$(gum choose "Retry" "Restore backup" "Keep anyway") || choice="Restore backup"
            case "$choice" in
                "Restore backup")
                    sudo cp "$backup" "$PAM_FILE" && ok "Restored $PAM_FILE"
                    return 1 ;;
                "Keep anyway") break ;;
            esac
        done
    done
}

# --- polkit --------------------------------------------------------------------

# polkit 127 runs its PAM helper in a sandbox without network, so pam_yubico can't
# reach YubiCloud there (password works, the key doesn't). Give it network back.
configure_polkit() {
    sudo mkdir -p "$(dirname "$POLKIT_DROPIN")" || return 1
    sudo tee "$POLKIT_DROPIN" > /dev/null <<CONF
# pam_yubico (mode=client) checks OTPs against YubiCloud, so the helper needs network
[Service]
PrivateNetwork=no
RestrictAddressFamilies=AF_UNIX AF_INET AF_INET6 AF_NETLINK
CONF
    sudo systemctl daemon-reload
    ok "Polkit helper can reach YubiCloud ($POLKIT_DROPIN)"
}

# --- main ----------------------------------------------------------------------

if sudo grep -q pam_yubico "$PAM_FILE"; then
    info "pam_yubico is already set up in $PAM_FILE"
    if gum confirm "Reconfigure it (new API key / add another key)?" --default=false; then
        configure_pam || exit 1
    fi
else
    gum confirm "Set up password OR YubiKey (OTP) login?" || exit 1
    configure_pam || exit 1
fi

configure_polkit || exit 1
ok "YubiKey login configured (the YubiKey needs internet, the password always works)"
