#!/usr/bin/env bash
# Wallpaper Reload — apply the *current* wallpaper and re-run the full color pipeline
# - No menu, no picking. Uses pywallpaper.* (png/jpg/jpeg/webp) if present,
#   otherwise falls back to swww's currently set image.
# - Then redoes: swww transition, wal (+kitty/pywalfox/hyprlock cache), swaync,
#   OpenRGB, OpenLinkHub (sudo-nopass required for tee/systemctl as before).
#
# deps: swww, wal, awk, bc, (ImageMagick: magick/convert), pywalfox (opt), openrgb (opt)

set -Eeuo pipefail

# ── CONFIG (kept same semantics as your v2) ────────────────────────────────────
WALLPAPER_DIR="${HOME}/.config/hypr/wallpapers/wal"            # unused here but kept
LOCKFILE="/tmp/.wallpaper_switch.lock"
COOLDOWN="0.5"
KITTY_CURRENT_THEME="${HOME}/.config/kitty/current-theme.conf"
HYPRLOCK_COLORS_CACHE="${HOME}/.cache/wal/hyprlock_colors"
# We *resolve* pywallpaper dynamically (png/jpg/jpeg/webp). This is the base stem:
PYWALLPAPER_STEM="${HOME}/.config/hypr/wallpapers/pywallpaper"

# Which wal key to sample for RGB if ImageMagick not available
WAL_COLOR_KEY="color11"

# Choose where RGB base color comes from: image_dominant | image_average | wal
RGB_COLOR_SOURCE="image_dominant"

# LED punch tuning (same as your v2)
RGB_PUNCH_S_FLOOR=0.25
RGB_PUNCH_S_MULT=1.35
RGB_PUNCH_V_MULT=0.98
RGB_PUNCH_V_CAP=0.92
RGB_PUNCH_CONTRAST=1.10
RGB_PUNCH_GAMMA=1.05
NEUTRAL_S_THRESHOLD=0.10

# OpenLinkHub tuning (same as your v2)
OLH_DIR_DEFAULT="/var/lib/openlinkhub/database/rgb"
OLH_BRIGHTNESS="0.5"
OLH_PROFILE="dark"  # dark|bright

# Explain toggle
EXPLAIN=0

# ── UTILS ──────────────────────────────────────────────────────────────────────
now_ts() { date +%s.%N; }
log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*" >&2; }
need() { command -v "$1" >/dev/null 2>&1 || { echo "Missing: $1" >&2; exit 1; }; }

have_imagemagick() {
  if command -v magick >/dev/null 2>&1; then echo magick; return 0; fi
  if command -v convert >/dev/null 2>&1; then echo convert; return 0; fi
  return 1
}

hex_to_rgb() { # AA11CC -> "R G B"
  local in="${1#\#}"
  printf '%d %d %d\n' $((16#${in:0:2})) $((16#${in:2:2})) $((16#${in:4:2}))
}

# ── COOLDOWN ───────────────────────────────────────────────────────────────────
throttle_check() {
  local last_ts cur_ts diff
  if [[ -f "$LOCKFILE" ]]; then last_ts="$(<"$LOCKFILE")"; else last_ts="0"; fi
  cur_ts="$(now_ts)"
  diff="$(echo "$cur_ts - $last_ts" | bc -l || echo 999)"
  if (( $(echo "$diff < $COOLDOWN" | bc -l) )); then
    log "cooldown hit; exiting"; exit 0
  fi
  echo "$cur_ts" > "$LOCKFILE"
}

# ── SOURCE: resolve current wallpaper path ─────────────────────────────────────
resolve_pywallpaper() {
  # Prefer the pywallpaper.* copy your switcher maintains
  local f
  for ext in png jpg jpeg webp; do
    f="${PYWALLPAPER_STEM}.${ext}"
    [[ -f "$f" ]] && { echo "$f"; return 0; }
  done
  # Fallback: ask swww what it’s showing
  if command -v swww >/dev/null 2>&1; then
    local cur
    cur="$(swww query 2>/dev/null | awk -F'image: ' 'NF>1{print $2; exit}')"
    if [[ -n "${cur:-}" && -f "$cur" ]]; then
      echo "$cur"; return 0
    fi
  fi
  return 1
}

# ── SWWW ───────────────────────────────────────────────────────────────────────
ensure_swww() { pgrep -x swww-daemon >/dev/null 2>&1 || swww-daemon >/dev/null 2>&1 & }

set_wallpaper() {
  local img="$1"
  swww img "$img" \
    --transition-type wipe \
    --transition-angle 210 \
    --transition-fps 60 \
    --transition-duration .5
}

# ── PYWAL + HOOKS ─────────────────────────────────────────────────────────────
run_wal() { wal -i "$1"; }

wal_hook_tasks() {
  # Kitty live-swap
  if [[ -f "$HOME/.cache/wal/colors-kitty.conf" ]]; then
    cp "$HOME/.cache/wal/colors-kitty.conf" "$KITTY_CURRENT_THEME"
  fi
  # Firefox theme
  if command -v pywalfox >/dev/null 2>&1; then pywalfox update || true; fi
  # hyprlock rgb() cache
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

# ── COLOR “PUNCH” ─────────────────────────────────────────────────────────────
punch_hex_custom() {
  local in="${1#\#}"
  local s_floor="${2:-0.55}" s_mult="${3:-1.25}" v_mult="${4:-1.10}" v_cap="${5:-0.92}"
  local contrast="${6:-1.00}" gamma="${7:-1.00}"

  awk -v hex="$in" -v s_floor="$s_floor" -v s_mult="$s_mult" -v v_mult="$v_mult" -v v_cap="$v_cap" \
      -v contrast="$contrast" -v gamma="$gamma" -v s_neutral="${NEUTRAL_S_THRESHOLD:-0.10}" '
    function clamp(x,a,b){ return x<a?a:(x>b?b:x) }
    function abs(x){ return x<0? -x:x }
    function pow(a,b){ if (a<=0) return 0; return exp(b*log(a)) }

    BEGIN{
      r=strtonum("0x" substr(hex,1,2))/255.0
      g=strtonum("0x" substr(hex,3,2))/255.0
      b=strtonum("0x" substr(hex,5,2))/255.0

      max=r; if(g>max)max=g; if(b>max)max=b
      min=r; if(g<min)min=g; if(b<min)min=b
      d=max-min; v=max
      if (v==0){ printf "%s\n", toupper(hex); exit }
      s=(d==0)?0:(d/v)

      if (d>0){
        if (max==r)      h=((g-b)/d + (g<b?6:0))/6.0
        else if (max==g) h=((b-r)/d + 2)/6.0
        else             h=((r-g)/d + 4)/6.0
      } else h=0.0

      if (s < s_neutral) s = 0.0; else s = clamp(s*s_mult, s_floor, 1.0)
      v = clamp(v*v_mult, 0.0, v_cap)

      if (s == 0.0) { R=v; G=v; B=v }
      else {
        h6=h*6.0; i=int(h6); f=h6-i
        c=v*s; x=c*(1.0 - abs(2.0*f-1.0)); m=v-c
        if (i==0){ rp=c; gp=x; bp=0 }
        else if (i==1){ rp=x; gp=c; bp=0 }
        else if (i==2){ rp=0; gp=c; bp=x }
        else if (i==3){ rp=0; gp=x; bp=c }
        else if (i==4){ rp=x; gp=0; bp=c }
        else { rp=c; gp=0; bp=x }
        R=rp+m; G=gp+m; B=bp+m
      }

      if (contrast!=1.0){
        R=clamp((R-0.5)*contrast+0.5, 0, 1)
        G=clamp((G-0.5)*contrast+0.5, 0, 1)
        B=clamp((B-0.5)*contrast+0.5, 0, 1)
      }
      if (gamma!=1.0){ R=pow(R,gamma); G=pow(G,gamma); B=pow(B,gamma) }

      printf "%02X%02X%02X\n", int(R*255+0.5), int(G*255+0.5), int(B*255+0.5)
    }'
}

punch_profile_rgb() {
  punch_hex_custom "$1" \
    "$RGB_PUNCH_S_FLOOR" "$RGB_PUNCH_S_MULT" "$RGB_PUNCH_V_MULT" "$RGB_PUNCH_V_CAP" \
    "$RGB_PUNCH_CONTRAST" "$RGB_PUNCH_GAMMA"
}
punch_profile_olh_dark()  { punch_hex_custom "$1" 0.70 1.75 0.58 0.80 1.10 1.25; }
punch_profile_olh_bright(){ punch_hex_custom "$1" 0.65 1.60 1.22 0.98 1.20 0.85; }

# ── COLOR SOURCING ─────────────────────────────────────────────────────────────
get_wal_hex() {
  local key="$1" raw
  raw="$(grep -m1 "^${key}=" "$HOME/.cache/wal/colors.sh" 2>/dev/null || true)"
  [[ -z "$raw" ]] && { echo ""; return 1; }
  raw="${raw#*#}"; raw="${raw%\'*}"
  echo "$raw"
}

im_avg_hex() {
  local IM_BIN; IM_BIN="$(have_imagemagick)" || return 1
  local out
  if [[ "$IM_BIN" == magick ]]; then
    out="$(magick "$1" -alpha off -resize 1x1! -format '%[pixel:p{0,0}]' info:-)"
  else
    out="$(convert "$1" -alpha off -resize 1x1! -format '%[pixel:p{0,0}]' info:-)"
  fi
  local r g b
  r="${out#*srgb(}"; r="${r%%,*}"; g="${out#*,}"; g="${g%%,*}"; b="${out##*,}"; b="${b%)*}"
  printf '%02X%02X%02X\n' "$r" "$g" "$b"
}

im_dominant_hex() {
  local IM_BIN; IM_BIN="$(have_imagemagick)" || return 1
  local hist
  if [[ "$IM_BIN" == magick ]]; then
    hist="$(magick "$1" -alpha off -resize 400x400^ -gravity center -extent 400x400 -colors 8 -colorspace sRGB -format %c histogram:info:-)"
  else
    hist="$(convert "$1" -alpha off -resize 400x400^ -gravity center -extent 400x400 -colors 8 -colorspace sRGB -format %c histogram:info:-)"
  fi
  awk '
    function clamp(x,a,b){ return x<a?a:(x>b?b:x) }
    function abs(x){ return x<0? -x:x }
    function hsv_from_rgb(R,G,B,   r,g,b,max,min,d,h,s,v){
      r=R/255.0; g=G/255.0; b=B/255.0
      max=r; if(g>max)max=g; if(b>max)max=b
      min=r; if(g<min)min=g; if(b<min)min=b
      d=max-min; v=max; s = (v==0)?0: (d==0?0:(d/v))
      if (d==0){ h=0 } else if (max==r){ h=((g-b)/d + (g<b?6:0))/6.0 }
      else if (max==g){ h=((b-r)/d + 2)/6.0 } else { h=((r-g)/d + 4)/6.0 }
      return s ":" v
    }
    BEGIN{ best=-1; besthex="" }
    /^[[:space:]]*[0-9]+:.*#[0-9A-Fa-f]{6}/ {
      match($0, /^[[:space:]]*([0-9]+):.*#([0-9A-Fa-f]{6})/, m)
      cnt=m[1]; hex=toupper(m[2])
      R=strtonum("0x" substr(hex,1,2)); G=strtonum("0x" substr(hex,3,2)); B=strtonum("0x" substr(hex,5,2))
      split(hsv_from_rgb(R,G,B), hv, ":"); s=hv[1]+0; v=hv[2]+0
      if (s < 0.12) next
      if (v < 0.18 || v > 0.95) next
      score = cnt * (0.6 + s) * (1.0 - abs(v-0.55))
      if (score > best){ best=score; besthex=hex }
    }
    END{ if (besthex!="") print besthex }' <<< "$hist"
}

choose_image_hex() {
  local img="$1" hex
  hex="$(im_dominant_hex "$img" || true)"
  [[ -z "${hex:-}" ]] && hex="$(im_avg_hex "$img" || true)"
  echo "$hex"
}

choose_rgb_base_hex() {
  local img="$1" src="${RGB_COLOR_SOURCE}"
  case "$src" in
    image_dominant)   choose_image_hex "$img" ;;
    image_average)    im_avg_hex "$img" ;;
    wal)              get_wal_hex "$WAL_COLOR_KEY" ;;
    *)                choose_image_hex "$img" ;;
  esac
}

# ── OPENRGB ────────────────────────────────────────────────────────────────────
set_openrgb() {
  local base="${1:-}" hex
  if [[ -z "$base" ]]; then
    base="$(choose_rgb_base_hex "$2" || true)"
    [[ -z "$base" ]] && base="$(get_wal_hex "$WAL_COLOR_KEY" || true)"
  fi
  [[ -z "$base" ]] && { log "OpenRGB: no base color"; return 1; }
  hex="$(punch_profile_rgb "$base")"
  log "OpenRGB: base #$base -> #$hex"
  openrgb --color "$hex" || log "OpenRGB: command failed"
  echo "$hex"
}

# ── OPENLINKHUB ────────────────────────────────────────────────────────────────
update_openlinkhub_files() {
  local target="${1:-$OLH_DIR_DEFAULT}" profile="${2:-$OLH_PROFILE}" base hex R G B
  base="$(choose_rgb_base_hex "$3" || true)"
  [[ -z "$base" ]] && base="$(get_wal_hex "$WAL_COLOR_KEY" || true)"
  [[ -z "$base" ]] && { log "OLH: no base color"; return 1; }

  case "$profile" in
    dark)   hex="$(punch_profile_olh_dark "$base")" ;;
    bright) hex="$(punch_profile_olh_bright "$base")" ;;
    *)      hex="$(punch_profile_olh_dark "$base")" ;;
  esac

  R=$((16#${hex:0:2})); G=$((16#${hex:2:2})); B=$((16#${hex:4:2}))
  log "OLH: base #$base -> #$hex  (R=$R G=$G B=$B, brightness=$OLH_BRIGHTNESS)"

  shopt -s nullglob
  local files=()
  if [[ -d "$target" ]]; then files=( "$target"/* ); else files=( "$target" ); fi
  shopt -u nullglob
  (( ${#files[@]} )) || { log "OLH: no files under $target"; return 1; }

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
    if sudo -n /usr/bin/cat "$f" | sed -E "$SED_SCRIPT" > "$tmp"; then
      if sudo -n /usr/bin/tee "$f" < "$tmp" >/dev/null; then ((changed++)); else log "OLH: write failed for $f"; fi
    else
      log "OLH: transform failed for $f"
    fi
    rm -f "$tmp"
  done

  if (( changed > 0 )); then
    log "OLH: $changed file(s) updated; restarting service"
    sudo -n /usr/bin/systemctl restart openlinkhub.service || log "OLH: restart failed"
  else
    log "OLH: nothing changed; skip restart"; return 1
  fi
  echo "$hex"
}

# ── MISC (bg stuff) ────────────────────────────────────────────────────────────
reload_swaync() { command -v swaync-client >/dev/null 2>&1 && swaync-client --reload-css || true; }

# ── EXPLAIN REPORT ────────────────────────────────────────────────────────────
explain_report() {
  local img="$1" wal_key="$WAL_COLOR_KEY"
  local wal_hex base_img_hex base_choice openrgb_hex olh_hex

  wal_hex="$(get_wal_hex "$wal_key" || true)"
  base_img_hex="$(choose_image_hex "$img" || true)"

  case "$RGB_COLOR_SOURCE" in
    image_dominant|image_average) base_choice="$base_img_hex" ;;
    wal)                          base_choice="$wal_hex" ;;
    *)                            base_choice="$base_img_hex" ;;
  esac

  printf '\n—— COLOR EXPLAIN ————————————————\n'
  printf 'Wallpaper:        %s\n' "$img"
  printf 'pywal %s:        #%s\n' "$wal_key" "${wal_hex:-N/A}"
  printf 'image base:       #%s (dominant→avg fallback)\n' "${base_img_hex:-N/A}"
  printf 'RGB base chosen:  #%s   (RGB_COLOR_SOURCE=%s)\n' "${base_choice:-N/A}" "$RGB_COLOR_SOURCE"

  if [[ -n "${base_choice:-}" ]]; then
    openrgb_hex="$(punch_profile_rgb "$base_choice")"
    printf 'OpenRGB final:    #%s  (punch Sfloor=%s Smult=%s Vmult=%s Vcap=%s C=%s G=%s)\n' \
      "$openrgb_hex" "$RGB_PUNCH_S_FLOOR" "$RGB_PUNCH_S_MULT" "$RGB_PUNCH_V_MULT" "$RGB_PUNCH_V_CAP" \
      "$RGB_PUNCH_CONTRAST" "$RGB_PUNCH_GAMMA"
  else
    printf 'OpenRGB final:    (no base)\n'
  fi

  if [[ -n "${base_choice:-}" ]]; then
    case "$OLH_PROFILE" in
      dark)   olh_hex="$(punch_profile_olh_dark "$base_choice")" ;;
      bright) olh_hex="$(punch_profile_olh_bright "$base_choice")" ;;
    esac
    printf 'OpenLinkHub:      #%s  (profile=%s, brightness=%s)\n' "${olh_hex:-N/A}" "$OLH_PROFILE" "$OLH_BRIGHTNESS"
  else
    printf 'OpenLinkHub:      (no base)\n'
  fi

  printf 'System:           Kitty theme: %s\n' "$KITTY_CURRENT_THEME"
  printf '                  Hyprlock cache: %s\n' "$HYPRLOCK_COLORS_CACHE"
  printf '                  pywalfox: %s\n' "$(command -v pywalfox >/dev/null 2>&1 && echo enabled || echo disabled)"
  printf '                  swaync reload: %s\n' "$(command -v swaync-client >/dev/null 2>&1 && echo yes || echo no)"
  printf '———————————————————————————————\n\n'
}

# ── ARG PARSE ─────────────────────────────────────────────────────────────────
for arg in "$@"; do
  case "$arg" in
    --explain) EXPLAIN=1 ;;
  esac
done

# ── MAIN ───────────────────────────────────────────────────────────────────────
main() {
  need bc; need awk; need swww; need wal

  throttle_check
  ensure_swww

  local selected
  if ! selected="$(resolve_pywallpaper)"; then
    log "No pywallpaper.* found and no swww fallback; aborting."
    exit 1
  fi
  log "Reloading current wallpaper: $selected"

  # Re-apply wallpaper (transition like normal)
  set_wallpaper "$selected"

  # wal + hooks (blocking so palette is ready)
  run_wal "$selected"
  wal_hook_tasks

  # theme consumers
  reload_swaync

  # Apply to hardware
  local openrgb_final olh_final
  openrgb_final="$(set_openrgb "" "$selected" || true)"
  olh_final="$(update_openlinkhub_files "$OLH_DIR_DEFAULT" "$OLH_PROFILE" "$selected" || true)"

  if (( EXPLAIN )); then
    explain_report "$selected"
  else
    if [[ -n "${openrgb_final:-}" || -n "${olh_final:-}" ]]; then
      log "APPLIED: OpenRGB=#${openrgb_final:-na}  OLH=#${olh_final:-na}"
    fi
  fi
}

main "$@"
