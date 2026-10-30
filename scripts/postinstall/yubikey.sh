#!/bin/bash
# Password OR a YubiKey at every PAM prompt that uses system-auth (sudo, login, lockscreen,
# polkit; not su: Arch's /etc/pam.d/su only has pam_unix).
# One of two modes is active (setting one up replaces the other):
#   FIDO2 (pam_u2f, recommended): offline, the key is touched. A prompt asks for the
#     password first; to use the key, press Enter on the empty prompt, then touch it.
#     The Quickshell lockscreen also listens for a touch right away (pam/u2f.conf).
#   OTP (pam_yubico, YubiCloud): the key types its OTP + Enter into the password field;
#     PAM checks the input as the password first, then as an OTP (needs internet).
# The password always works: the key is only tried after pam_unix failed.
#
#   yubikey.sh                   status, then a menu (set up, add a key, test, disable, restore)
#   yubikey.sh --status [--json] status only: no prompts, no sudo, what needs root is "unknown"
#                                (the Quickshell settings app reads the JSON)
#
# The auth block in /etc/pam.d/system-auth (pam_faillock counts failures, [success=N]
# jumps over the lines below a success):
#   auth   required                    pam_faillock.so  preauth
#   -auth  [success=3 default=ignore]  pam_systemd_home.so
#   auth   [success=2 default=ignore]  pam_unix.so      try_first_pass nullok nodelay
#   -auth  [success=1 default=ignore]  pam_u2f.so | pam_yubico.so …
#   auth   [default=die]               pam_faillock.so  authfail
#   …
# "-auth": if the module is missing (package removed), the line is skipped instead of
# failing every login. pam_u2f deliberately has no "nouserok": in this place it would
# make a user without a linked key pass with any wrong password.
#
# FIDO2, key plugged in but not touched: pam_u2f first checks whether a linked key is
# there at all (no key: it fails at once, nothing waits). With one plugged in it waits
# for the touch until the key gives up (a YubiKey after about 15-30 s); that only
# happens after Enter on an empty prompt, and then counts as one failed attempt
# (3 within 15 min lock the account for 10 min: faillock --user "$USER" --reset).

source "$(dirname "$0")/../lib.sh"

PAM_FILE=/etc/pam.d/system-auth
U2F_MAPPINGS=/etc/u2f_mappings
OTP_MAPPINGS=/etc/yubikey_mappings
DROPIN_DIR=/etc/systemd/system/polkit-agent-helper@.service.d
OTP_DROPIN=$DROPIN_DIR/yubico-otp.conf
U2F_DROPIN=$DROPIN_DIR/yubikey-u2f.conf
PACKAGES=(pam-u2f yubico-pam libfido2 yubikey-manager)
# the relying party pam_u2f uses by default (pam://$HOSTNAME); keys are registered for it,
# so renaming the machine means linking the keys again
ORIGIN="pam://$(uname -n)"

# --- status --------------------------------------------------------------------

# which key module the auth lines of system-auth use: none | fido2 | otp | both | unknown
pam_mode() {
    local auth u2f=0 otp=0
    [[ -r "$PAM_FILE" ]] || { echo unknown; return; }
    auth=$(grep -E '^[[:space:]]*-?auth[[:space:]]' "$PAM_FILE")
    grep -q 'pam_u2f\.so' <<< "$auth" && u2f=1
    grep -q 'pam_yubico\.so' <<< "$auth" && otp=1
    case "$u2f$otp" in
        11) echo both ;; 10) echo fido2 ;; 01) echo otp ;; *) echo none ;;
    esac
}

# keys linked to $USER in a mappings file ("user:key1:key2..."): a number, or "unknown"
linked_keys() {
    local file=$1
    [[ -e "$file" ]] || { echo 0; return; }
    [[ -r "$file" ]] || { echo unknown; return; }
    awk -F: -v u="$USER" '$1 == u { n = NF - 1 } END { print n + 0 }' "$file"
}

# the OTP authfile system-auth points to (else the default)
otp_mappings() {
    local f
    f=$(grep -oE 'pam_yubico\.so.*authfile=[^[:space:]]+' "$PAM_FILE" 2>/dev/null | grep -oE 'authfile=[^[:space:]]+' | cut -d= -f2)
    echo "${f:-$OTP_MAPPINGS}"
}

# polkit's helper runs sandboxed: FIDO2 needs /dev/hidraw* in it, OTP needs network.
# polkit_ok fido2|otp → yes | no | unknown (the effective settings of an instance)
polkit_ok() {
    local show
    show=$(systemctl show 'polkit-agent-helper@probe.service' -p PrivateDevices -p DeviceAllow -p DevicePolicy \
           -p PrivateNetwork -p RestrictAddressFamilies 2>/dev/null)
    [[ -n "$show" ]] || { echo unknown; return; }
    if [[ $1 == fido2 ]]; then
        if grep -qx 'PrivateDevices=no' <<< "$show" && { grep -qx 'DevicePolicy=auto' <<< "$show" || grep -qx 'DeviceAllow=char-hidraw rw' <<< "$show"; }; then
            echo yes
        else
            echo no
        fi
    elif grep -qx 'PrivateNetwork=no' <<< "$show" && { grep -qx 'RestrictAddressFamilies=' <<< "$show" || grep -q 'AF_INET' <<< "$show"; }; then
        echo yes
    else
        echo no
    fi
}

# fills the st_* variables (nothing here needs root)
collect_status() {
    local p out
    st_mode=$(pam_mode)
    st_pkgs=()
    for p in "${PACKAGES[@]}"; do
        if pacman -Q "$p" &>/dev/null; then st_pkgs+=("$p:yes"); else st_pkgs+=("$p:no"); fi
    done
    # plugged in: Yubico's USB vendor id; serials from ykman when it's there
    st_present=no
    grep -qx 1050 /sys/bus/usb/devices/*/idVendor 2>/dev/null && st_present=yes
    st_serials=()
    st_pin=unknown
    if [[ $st_present == yes ]] && command -v ykman &>/dev/null; then
        mapfile -t st_serials < <(timeout 5 ykman list --serials 2>/dev/null | grep -E '^[0-9]+$')
        # the FIDO2 PIN of the (first) key: "N attempt(s) remaining" = set
        case "$(timeout 6 ykman fido info 2>/dev/null | grep -E '^PIN:')" in
            *"Not set"*) st_pin=no ;;
            *attempt*|*[Bb]locked*) st_pin=yes ;;
        esac
    fi
    st_u2f_linked=$(linked_keys "$U2F_MAPPINGS")
    st_otp_linked=$(linked_keys "$(otp_mappings)")
    st_polkit_fido2=$(polkit_ok fido2)
    st_polkit_otp=$(polkit_ok otp)
    st_otp_dropin=no
    [[ -e "$OTP_DROPIN" ]] && st_otp_dropin=yes
    # faillock: the valid ("V") failures in its window (/run/faillock is readable on Arch)
    st_failures=unknown
    if out=$(faillock --user "$USER" 2>/dev/null); then
        st_failures=$(awk 'NR > 2 && $NF == "V"' <<< "$out" | wc -l)
    fi
    st_backups=$(compgen -G "$PAM_FILE.bak.*" | wc -l)

    st_warnings=()
    case "$st_mode" in
        both) st_warnings+=("OTP and FIDO2 are both in $PAM_FILE: set up one of them again to clean it up") ;;
        unknown) st_warnings+=("$PAM_FILE isn't readable") ;;
        fido2)
            pacman -Q pam-u2f &>/dev/null || st_warnings+=("pam-u2f isn't installed: the key line is skipped, only the password works")
            [[ $st_u2f_linked == 0 ]] && st_warnings+=("no key is linked to $USER in $U2F_MAPPINGS: only the password works")
            [[ $st_polkit_fido2 == no ]] && st_warnings+=("polkit's helper can't reach the key (/dev/hidraw*): polkit prompts only take the password")
            ;;
        otp)
            pacman -Q yubico-pam &>/dev/null || st_warnings+=("yubico-pam isn't installed: the key line is skipped, only the password works")
            [[ $st_otp_linked == 0 ]] && st_warnings+=("no key is linked to $USER in $(otp_mappings): only the password works")
            [[ $st_polkit_otp == no ]] && st_warnings+=("polkit's helper has no network: OTPs fail in polkit prompts")
            ;;
    esac
    [[ $st_mode != otp && $st_otp_dropin == yes ]] && st_warnings+=("leftover OTP drop-in (network for polkit's helper): $OTP_DROPIN")
    [[ $st_failures =~ ^[0-9]+$ && $st_failures -ge 3 ]] && st_warnings+=("$st_failures failed logins: the account may be locked (faillock --user $USER --reset)")
    return 0
}

json_str() {
    local s=${1//\\/\\\\}
    s=${s//\"/\\\"}
    printf '"%s"' "$s"
}
# yes/no/unknown → true/false/null; numbers stay numbers
json_val() {
    case "$1" in
        yes) printf true ;;
        no) printf false ;;
        unknown|"") printf null ;;
        *) if [[ $1 =~ ^[0-9]+$ ]]; then printf '%s' "$1"; else json_str "$1"; fi ;;
    esac
}
json_list() {
    local first=1 x
    printf '['
    for x in "$@"; do
        ((first)) || printf ','
        json_str "$x"
        first=0
    done
    printf ']'
}

# one JSON object; never contains the OTP API key or a key handle
status_json() {
    local p first=1
    printf '{"mode":%s,"packages":{' "$(json_str "$st_mode")"
    for p in "${st_pkgs[@]}"; do
        ((first)) || printf ','
        printf '%s:%s' "$(json_str "${p%%:*}")" "$(json_val "${p##*:}")"
        first=0
    done
    printf '},"keyPresent":%s,"serials":%s,"pin":%s' "$(json_val "$st_present")" "$(json_list "${st_serials[@]}")" "$(json_val "$st_pin")"
    printf ',"linked":{"fido2":%s,"otp":%s}' "$(json_val "$st_u2f_linked")" "$(json_val "$st_otp_linked")"
    printf ',"polkit":{"fido2":%s,"otp":%s}' "$(json_val "$st_polkit_fido2")" "$(json_val "$st_polkit_otp")"
    printf ',"failures":%s,"backups":%s,"origin":%s,"user":%s' "$(json_val "$st_failures")" "$(json_val "$st_backups")" \
        "$(json_str "$ORIGIN")" "$(json_str "$USER")"
    printf ',"warnings":%s}\n' "$(json_list "${st_warnings[@]}")"
}

show_status() {
    local p
    title "YubiKey login"
    case "$st_mode" in
        none)  info "Mode: password only" ;;
        fido2) ok "Mode: FIDO2 (pam_u2f, touch the key)" ;;
        otp)   ok "Mode: OTP (pam_yubico, YubiCloud)" ;;
        both)  err "Mode: OTP and FIDO2 at once" ;;
        *)     err "Mode: unknown ($PAM_FILE not readable)" ;;
    esac
    for p in "${st_pkgs[@]}"; do
        if [[ ${p##*:} == yes ]]; then ok "${p%%:*}"; else info "${p%%:*} not installed"; fi
    done
    if [[ $st_present == yes ]]; then
        ok "YubiKey plugged in${st_serials[*]:+ (serial ${st_serials[*]})}"
    else
        info "No YubiKey plugged in"
    fi
    case "$st_pin" in
        yes) ok "FIDO2 PIN is set" ;;
        no)  info "No FIDO2 PIN set (ykman fido access change-pin)" ;;
        *)   info "FIDO2 PIN: unknown" ;;
    esac
    info "Linked to $USER: $st_u2f_linked FIDO2 key(s) ($U2F_MAPPINGS), $st_otp_linked OTP key(s) ($(otp_mappings))"
    if [[ $st_polkit_fido2 == yes ]]; then ok "polkit helper can reach FIDO2 keys"; else info "polkit helper can't reach FIDO2 keys"; fi
    if [[ $st_polkit_otp == yes ]]; then ok "polkit helper has network (OTP)"; else info "polkit helper has no network (only needed for OTP)"; fi
    info "faillock: $st_failures recent failure(s) · $st_backups backup(s) of $PAM_FILE"
    for p in "${st_warnings[@]}"; do err "$p"; done
}

# --- system-auth ---------------------------------------------------------------

# the auth block for a mode; auth_block none|fido2|otp [pam_yubico options]
auth_block() {
    local key
    case "$1" in
        none)
            # Arch's default
            cat <<'PAM'
auth       required                    pam_faillock.so      preauth
-auth      [success=2 default=ignore]  pam_systemd_home.so
auth       [success=1 default=bad]     pam_unix.so          try_first_pass nullok
auth       [default=die]               pam_faillock.so      authfail
auth       optional                    pam_permit.so
auth       required                    pam_env.so
auth       required                    pam_faillock.so      authsucc
PAM
            return ;;
        fido2) key="pam_u2f.so           authfile=$U2F_MAPPINGS cue" ;;
        otp)   key="pam_yubico.so        $2" ;;
    esac
    cat <<PAM
auth       required                    pam_faillock.so      preauth
-auth      [success=3 default=ignore]  pam_systemd_home.so
auth       [success=2 default=ignore]  pam_unix.so          try_first_pass nullok nodelay
-auth      [success=1 default=ignore]  $key
auth       [default=die]               pam_faillock.so      authfail
auth       optional                    pam_permit.so
auth       required                    pam_env.so
auth       required                    pam_faillock.so      authsucc
PAM
}

# write_pam none|fido2|otp [pam_yubico options]: replace the auth block, keep account/
# password/session; a timestamped backup first. Prints the backup's path, nothing when
# the file already looked like that (messages go to stderr).
write_pam() {
    local tmp block backup
    tmp=$(mktemp)
    block=$(auth_block "$@")
    sudo cat "$PAM_FILE" | awk -v block="$block" '
        /^[[:space:]]*-?auth[[:space:]]/ { if (!done) { print block; done = 1 } next }
        { print }' > "$tmp"
    if sudo cmp -s "$tmp" "$PAM_FILE"; then
        rm -f "$tmp"
        ok "$PAM_FILE is already set up like that" >&2
        return 0
    fi
    # timestamped, so a second run doesn't overwrite the original backup
    backup="$PAM_FILE.bak.$(date +%Y%m%d-%H%M%S)"
    sudo cp -p "$PAM_FILE" "$backup" || { rm -f "$tmp"; return 1; }
    ok "Backup: $backup" >&2
    sudo install -m 644 "$tmp" "$PAM_FILE" || { rm -f "$tmp"; return 1; }
    rm -f "$tmp"
    ok "Updated $PAM_FILE" >&2
    echo "$backup"
}

newest_backup() { sudo sh -c 'ls -1t "$1".bak.* 2>/dev/null | head -1' sh "$PAM_FILE"; }

# test through sudo (its PAM service includes system-auth; su's doesn't, it only has
# pam_unix): -k makes this one run authenticate again without dropping the cached
# credentials, so the backup can still be restored if login broke.
# test_pam <backup or ""> <mode>
test_pam() {
    local backup=$1 mode=$2 what choice
    local tests=("your password")
    case "$mode" in
        fido2) tests+=("no password: press Enter, then touch the YubiKey") ;;
        otp)   tests+=("only the YubiKey: touch it, it types the code") ;;
    esac
    for what in "${tests[@]}"; do
        while true; do
            info "Test: at the prompt, use $what"
            if sudo -k true; then
                ok "Works with $what"
                break
            fi
            err "Didn't work with $what"
            info "(3 failures lock you out for 10 min: sudo faillock --user $USER --reset)"
            if [[ -n "$backup" ]]; then
                choice=$(gum choose "Retry" "Restore backup" "Keep anyway") || choice="Restore backup"
            else
                choice=$(gum choose "Retry" "Skip") || choice="Skip"
            fi
            case "$choice" in
                "Restore backup")
                    sudo cp -p "$backup" "$PAM_FILE" && ok "Restored $PAM_FILE"
                    configure_polkit "$(pam_mode)"
                    return 1 ;;
                "Keep anyway"|"Skip") break ;;
            esac
        done
    done
}

# --- polkit --------------------------------------------------------------------

# polkit's helper runs in a sandbox (polkit-agent-helper@.service). FIDO2 needs the
# hidraw devices: pam-u2f ships a drop-in for that (PrivateDevices=no, DeviceAllow=
# char-hidraw); ours is only written when that one isn't in effect. OTP needs network
# (YubiCloud). Each mode removes what only the other one needs.
# configure_polkit none|fido2|otp|both|unknown
configure_polkit() {
    local mode=$1 changed=0
    [[ $mode == none || $mode == fido2 || $mode == otp ]] || return 0
    sudo mkdir -p "$DROPIN_DIR" || return 1
    if [[ $mode == otp ]]; then
        if [[ ! -e "$OTP_DROPIN" ]]; then
            sudo tee "$OTP_DROPIN" > /dev/null <<CONF
# pam_yubico (mode=client) checks OTPs against YubiCloud, so the helper needs network
[Service]
PrivateNetwork=no
RestrictAddressFamilies=AF_UNIX AF_INET AF_INET6 AF_NETLINK
CONF
            changed=1
        fi
    elif [[ -e "$OTP_DROPIN" ]]; then
        sudo rm -f "$OTP_DROPIN" && changed=1
    fi
    if [[ $mode == fido2 ]]; then
        if [[ $(polkit_ok fido2) != yes && ! -e "$U2F_DROPIN" ]]; then
            sudo tee "$U2F_DROPIN" > /dev/null <<CONF
# pam_u2f talks to the key over /dev/hidraw*, which the helper's sandbox hides
# (pam-u2f's own drop-in does the same; this one is for when that's missing)
[Service]
PrivateDevices=no
DeviceAllow=/dev/urandom r
DeviceAllow=char-hidraw rw
CONF
            changed=1
        fi
    elif [[ -e "$U2F_DROPIN" ]]; then
        sudo rm -f "$U2F_DROPIN" && changed=1
    fi
    if ((changed)); then
        sudo systemctl daemon-reload
        ok "polkit helper sandbox adjusted ($mode)"
    fi
    case "$mode" in
        fido2) if [[ $(polkit_ok fido2) == yes ]]; then ok "polkit helper can reach the key"; else err "polkit helper still can't reach /dev/hidraw*"; fi ;;
        otp)   if [[ $(polkit_ok otp) == yes ]]; then ok "polkit helper can reach YubiCloud"; else err "polkit helper still has no network"; fi ;;
    esac
}

# --- FIDO2 ---------------------------------------------------------------------

# a FIDO2 credential for $USER in /etc/u2f_mappings (pamu2fcfg asks for the touch, and
# for the PIN if one is set); add_u2f_key [replace]: it becomes the user's only one
add_u2f_key() {
    local replace=$1 cred tmp
    grep -qx 1050 /sys/bus/usb/devices/*/idVendor 2>/dev/null || info "Plug in the YubiKey first"
    info "Touch the YubiKey when it blinks (and enter its FIDO2 PIN if asked)"
    # -n: only the credential (":handle,key,type,options"); the user name is added below
    cred=$(pamu2fcfg -n -o "$ORIGIN" -i "$ORIGIN") || { err "pamu2fcfg failed (no key, not touched in time, or wrong PIN)"; return 1; }
    [[ "$cred" == :* ]] || cred=":$cred"
    tmp=$(mktemp)
    sudo cat "$U2F_MAPPINGS" 2>/dev/null | awk -F: -v u="$USER" -v c="$cred" -v r="$replace" '
        $1 == u { found = 1; print (r == "replace" ? u c : $0 c); next }
        { print }
        END { if (!found) print u c }' > "$tmp"
    sudo install -o root -g root -m 644 "$tmp" "$U2F_MAPPINGS" || { rm -f "$tmp"; return 1; }
    rm -f "$tmp"
    ok "Linked the key to $USER in $U2F_MAPPINGS ($(linked_keys "$U2F_MAPPINGS") key(s))"
}

setup_fido2() {
    local backup n
    yay_install pam-u2f libfido2 || return 1
    n=$(linked_keys "$U2F_MAPPINGS")
    if [[ $n =~ ^[0-9]+$ && $n -gt 0 ]]; then
        info "$USER already has $n FIDO2 key(s) in $U2F_MAPPINGS"
        case "$(gum choose "Keep them" "Replace them with the plugged-in key" "Add the plugged-in key")" in
            "Replace them with the plugged-in key") add_u2f_key replace || return 1 ;;
            "Add the plugged-in key") add_u2f_key || return 1 ;;
            "") return 1 ;;
        esac
    else
        add_u2f_key replace || return 1
    fi
    backup=$(write_pam fido2) || return 1
    configure_polkit fido2
    [[ -n "$backup" ]] || backup=$(newest_backup)
    test_pam "$backup" fido2
}

# --- OTP -----------------------------------------------------------------------

# the pam_yubico options (mode=client id=… key=… authfile=… use_first_pass): from
# system-auth, or the newest backup that has them, or asked for. Never printed.
otp_options() {
    local line f client_id secret
    line=$(sudo grep -hoE 'pam_yubico\.so[[:space:]].*' "$PAM_FILE" 2>/dev/null | head -1)
    if [[ -z "$line" ]]; then
        while IFS= read -r f; do
            line=$(sudo grep -hoE 'pam_yubico\.so[[:space:]].*' "$f" 2>/dev/null | head -1)
            if [[ -n "$line" ]]; then
                gum confirm "Use the YubiCloud API key from $f?" || line=""
                break
            fi
        done < <(sudo sh -c 'ls -1t "$1".bak.* 2>/dev/null' sh "$PAM_FILE")
    fi
    if [[ -n "$line" ]]; then
        line=$(sed -E 's/^pam_yubico\.so[[:space:]]+//; s/[[:space:]]*authfile=[^[:space:]]+//; s/[[:space:]]*use_first_pass//' <<< "$line")
        echo "$line authfile=$OTP_MAPPINGS use_first_pass"
        return
    fi
    info "Get an API key at https://upgrade.yubico.com/getapikey/" >&2
    info "(enter your email, touch the YubiKey; you get a Client ID and a Secret key)" >&2
    client_id=$(gum input --header "Client ID" --placeholder "e.g. 123456") || return 1
    [[ "$client_id" =~ ^[0-9]+$ ]] || { err "Client ID must be a number" >&2; return 1; }
    secret=$(gum input --password --header "Secret key" --placeholder "base64 secret") || return 1
    [[ "$secret" =~ ^[A-Za-z0-9+/=]+$ ]] || { err "Invalid secret key" >&2; return 1; }
    echo "mode=client id=$client_id key=$secret authfile=$OTP_MAPPINGS use_first_pass"
}

add_otp_key() {
    local otp key_id tmp
    otp=$(gum input --password --header "Click here and touch the YubiKey" --placeholder "OTP") || return 1
    [[ ${#otp} -ge 32 && "$otp" =~ ^[cbdefghijklnrtuv]+$ ]] || { err "That doesn't look like a YubiKey OTP"; return 1; }
    key_id=${otp:0:12}
    ok "Key ID: $key_id"
    # mappings: "user:id1:id2...", add the key to the user's line if it isn't there yet
    tmp=$(mktemp)
    sudo cat "$OTP_MAPPINGS" 2>/dev/null | awk -F: -v u="$USER" -v k="$key_id" '
        $1 == u { found = 1; for (i = 2; i <= NF; i++) if ($i == k) { print; next } print $0 ":" k; next }
        { print }
        END { if (!found) print u ":" k }' > "$tmp"
    sudo install -o root -g root -m 644 "$tmp" "$OTP_MAPPINGS" || { rm -f "$tmp"; return 1; }
    rm -f "$tmp"
    ok "Linked key to $USER in $OTP_MAPPINGS"
}

setup_otp() {
    local opts backup n
    yay_install yubico-pam || return 1
    opts=$(otp_options) || return 1
    n=$(linked_keys "$OTP_MAPPINGS")
    if ! [[ $n =~ ^[0-9]+$ && $n -gt 0 ]] || gum confirm "Link the plugged-in key too?" --default=false; then
        add_otp_key || return 1
    fi
    backup=$(write_pam otp "$opts") || return 1
    configure_polkit otp
    [[ -n "$backup" ]] || backup=$(newest_backup)
    test_pam "$backup" otp
}

# --- the rest ------------------------------------------------------------------

add_key() {
    case "$(pam_mode)" in
        fido2) add_u2f_key && test_pam "" fido2 ;;
        otp)   add_otp_key && test_pam "" otp ;;
        *)     err "Set up FIDO2 or OTP first" ;;
    esac
}

disable() {
    local backup
    gum confirm "Back to password only (the key mappings are kept)?" --default=false || return 0
    backup=$(write_pam none) || return 1
    configure_polkit none
    [[ -n "$backup" ]] || backup=$(newest_backup)
    test_pam "$backup" none
}

restore_backup() {
    local pick current backups
    mapfile -t backups < <(sudo sh -c 'ls -1t "$1".bak.* 2>/dev/null' sh "$PAM_FILE")
    ((${#backups[@]})) || { info "No backups of $PAM_FILE"; return 0; }
    pick=$(gum choose --header "Restore which backup? (newest first)" "${backups[@]}") || return 0
    # its auth lines, the OTP id / key left out
    info "Its auth block:"
    sudo grep -E '^[[:space:]]*-?auth[[:space:]]' "$pick" | sed -E 's/(id|key)=[^[:space:]]+/\1=…/g'
    gum confirm "Restore $pick?" --default=false || return 0
    # the current file is backed up too, so this can be undone
    current="$PAM_FILE.bak.$(date +%Y%m%d-%H%M%S)"
    sudo cp -p "$PAM_FILE" "$current" && ok "Backup of the current file: $current"
    sudo cp -p "$pick" "$PAM_FILE" && ok "Restored $pick"
    configure_polkit "$(pam_mode)"
    test_pam "$current" "$(pam_mode)"
}

# --- main ----------------------------------------------------------------------

if [[ $1 == --status ]]; then
    collect_status
    if [[ $2 == --json ]]; then status_json; else show_status; fi
    exit 0
fi

keep_sudo_alive
while true; do
    collect_status
    show_status
    echo
    choice=$(gum choose --header "YubiKey login" \
        "Set up FIDO2 (recommended: offline, just touch)" \
        "Set up OTP (YubiCloud, the key types a code)" \
        "Add another key" "Test" "Disable (password only)" "Restore a backup" "Exit") || exit 0
    case "$choice" in
        "Set up FIDO2"*) setup_fido2 ;;
        "Set up OTP"*) setup_otp ;;
        "Add another key") add_key ;;
        "Test") test_pam "$(newest_backup)" "$(pam_mode)" ;;
        "Disable"*) disable ;;
        "Restore a backup") restore_backup ;;
        *) exit 0 ;;
    esac
    echo
done
