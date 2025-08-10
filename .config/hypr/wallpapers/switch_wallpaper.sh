#!/usr/bin/env bash
# Single-file wallpaper switcher with color pipeline:
# - Pick via wofi
# - swww transition
# - pywal -> hook tasks (Kitty, Firefox, hyprlock cache)
# - Push “punched” colors to OpenRGB and OpenLinkHub (darker profile)
# - Gentle cooldown to ignore double-taps
#
# deps: swww, wofi, wal, awk, bc, ImageMagick (optional), pywalfox (optional)
# optional rootless sudo for: systemctl restart openlinkhub + file writes

set -Eeuo pipefail

# ── CONFIG ─────────────────────────────────────────────────────────────────────
WALLPAPER_DIR="${HOME}/.config/hypr/wallpapers/wal"
LOCKFILE="/tmp/.wallpaper_switch.lock"
COOLDOWN="0.5"                            # seconds
WOFI_CONFIG="${HOME}/.config/wofi/config1"
WOFI_STYLE="${HOME}/.config/wofi/style1.css"

KITTY_CURRENT_THEME="${HOME}/.config/kitty/current-theme.conf"
HYPRLOCK_COLORS_CACHE="${HOME}/.cache/wal/hyprlock_colors"
PYWALLPAPER_DST="${HOME}/.config/hypr/wallpapers/pywallpaper.png"

# Which wal key to sample for RGB (adjust if you prefer another slot)
WAL_COLOR_KEY="color11"

# OpenLinkHub tuning
OLH_DIR_DEFAULT="/var/lib/openlinkhub/database/rgb"
OLH_BRIGHTNESS="0.5"                       # feels right for your hub
OLH_PROFILE="dark"                         # dark = heavier sat + darker value

# ── UTILS ──────────────────────────────────────────────────────────────────────
now_ts() { date +%s.%N; }

log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*" >&2; }

need() { command -v "$1" >/dev/null 2>&1 || { echo "Missing: $1" >&2; exit 1; }; }

# ── COOLDOWN ───────────────────────────────────────────────────────────────────
throttle_check() {
  local last_ts cur_ts diff
  if [[ -f "$LOCKFILE" ]]; then
    last_ts="$(<"$LOCKFILE")"
  else
    last_ts="0"
  fi
  cur_ts="$(now_ts)"
  diff="$(echo "$cur_ts - $last_ts" | bc -l || echo 999)"
  if (( $(echo "$diff < $COOLDOWN" | bc -l) )); then
    log "cooldown hit; exiting"
    exit 0
  fi
  echo "$cur_ts" > "$LOCKFILE"
}

# ── MENU ───────────────────────────────────────────────────────────────────────
menu() {
  # prefix entries with "img:" so we can strip reliably
  find "$WALLPAPER_DIR" -type f \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.gif' \) \
    | sed 's|^|img:|'
}

pick_wall() {
  local choice
  choice="$(menu | wofi -c "$WOFI_CONFIG" -s "$WOFI_STYLE" --show dmenu --prompt 'Select Wallpaper:' -n || true)"
  [[ -z "$choice" ]] && { log "no wallpaper selected"; exit 1; }
  echo "${choice#img:}"
}

# ── SWWW ───────────────────────────────────────────────────────────────────────
ensure_swww() {
  # start swww daemon if not already running
  pgrep -x swww-daemon >/dev/null 2>&1 || swww-daemon >/dev/null 2>&1 &
}

set_wallpaper() {
  local img="$1"
  swww img "$img" \
    --transition-type wipe \
    --transition-angle 210 \
    --transition-fps 60 \
    --transition-duration .5
}

# ── PYWAL + HOOKS ─────────────────────────────────────────────────────────────
run_wal() {
  local img="$1"
  wal -i "$img"
}

wal_hook_tasks() {
  # 1) Kitty theme live-swap
  if [[ -f "$HOME/.cache/wal/colors-kitty.conf" ]]; then
    cp "$HOME/.cache/wal/colors-kitty.conf" "$KITTY_CURRENT_THEME"
  fi

  # 2) Firefox (pywalfox)
  if command -v pywalfox >/dev/null 2>&1; then
    pywalfox update || true
  fi

  # 3) hyprlock_colors (export rgb() lines)
  if [[ -f "$HOME/.cache/wal/colors" ]]; then
    awk '{
      hex = substr($0,2);
      r = strtonum("0x" substr(hex,1,2));
      g = strtonum("0x" substr(hex,3,2));
      b = strtonum("0x" substr(hex,5,2));
      printf "export color%d=\"rgb(%d,%d,%d)\"\n", NR-1, r,g,b
    }' "$HOME/.cache/wal/colors" > "$HYPRLOCK_COLORS_CACHE"
  fi
}

# ── COLOR “PUNCH” (HSV + contrast + gamma) ────────────────────────────────────
# Reusable transformer; profiles just pass different params.
punch_hex_custom() {
  # $1=hex (#AABBCC or AABBCC)
  # $2=s_floor  $3=s_mult  $4=v_mult  $5=v_cap  $6=contrast  $7=gamma
  local in="${1#\#}"
  local s_floor="${2:-0.55}" s_mult="${3:-1.25}" v_mult="${4:-1.10}" v_cap="${5:-0.92}"
  local contrast="${6:-1.00}" gamma="${7:-1.00}"

  awk -v hex="$in" -v s_floor="$s_floor" -v s_mult="$s_mult" -v v_mult="$v_mult" -v v_cap="$v_cap" \
      -v contrast="$contrast" -v gamma="$gamma" '
    function clamp(x,a,b){ return x<a?a:(x>b?b:x) }
    function tohex(x){ x=int(x+0.5); return sprintf("%02X", x) }
    function abs(x){ return x<0? -x:x }
    function pow(a,b){ if (a<=0) return 0; return exp(b*log(a)) }

    BEGIN{
      r=strtonum("0x" substr(hex,1,2))/255.0
      g=strtonum("0x" substr(hex,3,2))/255.0
      b=strtonum("0x" substr(hex,5,2))/255.0

      max=r; if(g>max)max=g; if(b>max)max=b
      min=r; if(g<min)min=g; if(b<min)min=b
      d=max-min; v=max
      if (v==0){ print toupper(hex); exit }
      s=(d==0)?0:(d/v)
      if (d==0){ print toupper(hex); exit }

      if (max==r)      h=((g-b)/d + (g<b?6:0))/6.0
      else if (max==g) h=((b-r)/d + 2)/6.0
      else             h=((r-g)/d + 4)/6.0

      s=clamp(s*s_mult, s_floor, 1.0)
      v=clamp(v*v_mult, 0.0, v_cap)

      h6=h*6.0; i=int(h6); f=h6-i
      c=v*s; x=c*(1.0 - abs(2.0*f-1.0)); m=v-c

      if (i==0){ rp=c; gp=x; bp=0 }
      else if (i==1){ rp=x; gp=c; bp=0 }
      else if (i==2){ rp=0; gp=c; bp=x }
      else if (i==3){ rp=0; gp=x; bp=c }
      else if (i==4){ rp=x; gp=0; bp=c }
      else { rp=c; gp=0; bp=x }

      R=rp+m; G=gp+m; B=bp+m

      if (contrast!=1.0){
        R=clamp((R-0.5)*contrast+0.5, 0, 1)
        G=clamp((G-0.5)*contrast+0.5, 0, 1)
        B=clamp((B-0.5)*contrast+0.5, 0, 1)
      }
      if (gamma!=1.0){
        R=pow(R,gamma); G=pow(G,gamma); B=pow(B,gamma)
      }

      printf "%02X%02X%02X\n", int(R*255+0.5), int(G*255+0.5), int(B*255+0.5)
    }'
}

punch_profile_rgb() {      punch_hex_custom "$1" 0.55 1.25 1.10 0.92 1.05 1.00; }  # subtle pop
punch_profile_olh_dark() { punch_hex_custom "$1" 0.70 1.75 0.58 0.80 1.10 1.25; }  # heavier + darker
punch_profile_olh_bright(){ punch_hex_custom "$1" 0.65 1.60 1.22 0.98 1.20 0.85; }  # punchy, brighter

# ── COLOR SOURCING ─────────────────────────────────────────────────────────────
get_wal_hex() {
  # Pull hex from ~/.cache/wal/colors.sh (e.g., color11)
  local key="$1"
  local raw
  raw="$(grep -m1 "^${key}=" "${HOME}/.cache/wal/colors.sh" || true)"
  [[ -z "$raw" ]] && { echo ""; return 1; }
  raw="${raw#*\#}"; raw="${raw%\'*}"
  echo "$raw"
}

# ── OPENRGB ────────────────────────────────────────────────────────────────────
set_openrgb() {
  local base hex
  base="$(get_wal_hex "$WAL_COLOR_KEY")" || { log "OpenRGB: ${WAL_COLOR_KEY} not found"; return 1; }
  hex="$(punch_profile_rgb "$base")"
  log "OpenRGB: base #$base -> #$hex"
  openrgb --color "$hex" || log "OpenRGB: command failed"
}

# ── OPENLINKHUB ────────────────────────────────────────────────────────────────
update_openlinkhub_files() {
  local target="${1:-$OLH_DIR_DEFAULT}" base hex R G B profile="${2:-$OLH_PROFILE}"
  base="$(get_wal_hex "$WAL_COLOR_KEY")" || { log "OLH: ${WAL_COLOR_KEY} not found"; return 1; }

  case "$profile" in
    dark)   hex="$(punch_profile_olh_dark "$base")" ;;
    bright) hex="$(punch_profile_olh_bright "$base")" ;;
    *)      hex="$(punch_profile_olh_dark "$base")" ;; # default
  esac

  R=$((16#${hex:0:2})); G=$((16#${hex:2:2})); B=$((16#${hex:4:2}))
  log "OLH: base #$base -> #$hex  (R=$R G=$G B=$B, brightness=$OLH_BRIGHTNESS)"

  shopt -s nullglob
  local files=()
  if [[ -d "$target" ]]; then files=( "$target"/* ); else files=( "$target" ); fi
  shopt -u nullglob
  (( ${#files[@]} )) || { log "OLH: no files under $target"; return 1; }

  # sed body updates both "start" and "end" blocks inside "static"
  local SED_BODY='
    /"static"/,/"minTemp"/{
      /"start"/,/\}/{
        s/("red":[[:space:]]*)[0-9]+/\1__R__/;
        s/("green":[[:space:]]*)[0-9]+/\1__G__/;
        s/("blue":[[:space:]]*)[0-9]+/\1__B__/;
        s/("brightness":[[:space:]]*)[0-9]*\.?[0-9]+/\1__BR__/;
        s/("Hex":[[:space:]]*")[^"]*"/\1#__HX__"/
      }
      /"end"/,/\}/{
        s/("red":[[:space:]]*)[0-9]+/\1__R__/;
        s/("green":[[:space:]]*)[0-9]+/\1__G__/;
        s/("blue":[[:space:]]*)[0-9]+/\1__B__/;
        s/("brightness":[[:space:]]*)[0-9]*\.?[0-9]+/\1__BR__/;
        s/("Hex":[[:space:]]*")[^"]*"/\1#__HX__"/
      }
    }'
  local SED_SCRIPT=${SED_BODY//__R__/$R}
  SED_SCRIPT=${SED_SCRIPT//__G__/$G}
  SED_SCRIPT=${SED_SCRIPT//__B__/$B}
  SED_SCRIPT=${SED_SCRIPT//__BR__/$OLH_BRIGHTNESS}
  SED_SCRIPT=${SED_SCRIPT//__HX__/$hex}

  local changed=0
  for f in "${files[@]}"; do
    [[ -f "$f" ]] || continue
    [[ "$f" == *.bak* ]] && continue
    log "OLH: updating $f"
    local tmp; tmp="$(mktemp)"
    # read w/ sudo, transform, write back w/ sudo (non-interactive)
    if sudo -n /usr/bin/cat "$f" | sed -E "$SED_SCRIPT" > "$tmp"; then
      if sudo -n /usr/bin/tee "$f" < "$tmp" >/dev/null; then
        ((changed++))
      else
        log "OLH: write failed for $f"
      fi
    else
      log "OLH: transform failed for $f"
    fi
    rm -f "$tmp"
  done

  if (( changed > 0 )); then
    log "OLH: $changed file(s) updated; restarting service"
    sudo -n /usr/bin/systemctl restart openlinkhub.service || log "OLH: restart failed"
  else
    log "OLH: nothing changed; skip restart"
    return 1
  fi
}

# ── MISC (bg stuff) ────────────────────────────────────────────────────────────
copy_current_wallpaper() {
  cp "$1" "$PYWALLPAPER_DST"
}

reload_swaync() {
  command -v swaync-client >/dev/null 2>&1 && swaync-client --reload-css || true
}

# ── MAIN ───────────────────────────────────────────────────────────────────────
main() {
  need bc
  need awk
  need swww
  need wal
  need wofi

  throttle_check
  ensure_swww

  local selected
  selected="$(pick_wall)"
  set_wallpaper "$selected"

  # Fire-and-forget bits that don’t need to block the UX
  copy_current_wallpaper "$selected" &

  # wal + hooks (blocking so colors are ready)
  run_wal "$selected"
  wal_hook_tasks

  # theme consumers
  reload_swaync
  update_openlinkhub_files "${1:-$OLH_DIR_DEFAULT}" "$OLH_PROFILE" || true
  set_openrgb || true
}

main "$@"
