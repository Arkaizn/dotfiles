#!/bin/sh
# Screen recording for services/Capture.qml. Runs detached, so it survives a
# shell restart.
#
#   record.sh <state file> <file> <audio> outputs <name@x,y,w,h>...
#       one monitor (wf-recorder), or several: each is recorded on its own and
#       merged at the end, placed like in the monitor layout (ffmpeg)
#   record.sh <state file> <file> <audio> window
#       a window, picked in the screen-share dialog (gpu-screen-recorder)
#
# audio: both | desktop | mic | none. "both" with wf-recorder goes through a
# temporary null sink + two loopbacks (wf-recorder takes one device only).
# The state file holds the recorder pids, the file and the start time; Capture
# reads it, and stops the recording with SIGINT to those pids.

st=$1; f=$2; audio=$3; mode=$4; shift 4
log=$st.log
: > "$log"
mods=""; pids=""; parts=""

sink=$(pactl get-default-sink 2>/dev/null)
src=$(pactl get-default-source 2>/dev/null)
case $src in *.monitor) src="" ;; esac

# ── recorders ────────────────────────────────────────────────────────────────
if [ "$mode" = window ]; then
    case $audio in
        both) ga="default_output|default_input" ;;
        desktop) ga=default_output ;;
        mic) ga=default_input ;;
        *) ga="" ;;
    esac
    gpu-screen-recorder -w portal -f 60 ${ga:+-a "$ga"} -o "$f" >/dev/null 2>>"$log" &
    pids=$!
    # it records only once a window is picked in the share dialog, and writes
    # the file from then on: wait for that, so the bar's timer starts with the
    # recording (and doesn't show at all when the dialog is cancelled)
    echo 1 > "$st.pending"
    while kill -0 "$pids" 2>/dev/null && [ ! -s "$f" ]; do sleep 0.2; done
    rm -f "$st.pending"
else
    wfa=""
    case $audio in
        mic) wfa="--audio" ;;
        desktop) wfa="--audio${sink:+=$sink.monitor}" ;;
        both)
            if [ -n "$sink" ] && [ -n "$src" ]; then
                # leftovers of a crashed recording
                pactl list short modules | awk '/qs-rec/ {print $1}' | while read -r m; do pactl unload-module "$m"; done
                m=$(pactl load-module module-null-sink sink_name=qs-rec-mix 'sink_properties=device.description="Recording\ mix" node.passive=true priority.session=0 priority.driver=0') && mods="$m $mods"
                m=$(pactl load-module module-loopback source="$sink.monitor" sink=qs-rec-mix latency_msec=30 sink_input_properties=node.name=qs-rec-desktop source_output_properties=node.name=qs-rec-desktop-in) && mods="$m $mods"
                m=$(pactl load-module module-loopback source="$src" sink=qs-rec-mix latency_msec=30 sink_input_properties=node.name=qs-rec-mic source_output_properties=node.name=qs-rec-mic-in) && mods="$m $mods"
                wfa="--audio=qs-rec-mix.monitor"
            else
                wfa="--audio${sink:+=$sink.monitor}"
            fi ;;
    esac

    if [ $# -eq 1 ]; then
        wf-recorder -y -o "${1%@*}" $wfa -f "$f" >/dev/null 2>>"$log" &
        pids=$!
    else
        i=0
        for o in "$@"; do
            p="${f%.*}.part$i.mkv"
            # the sound goes with the first monitor's part
            if [ $i -eq 0 ]; then a=$wfa; else a=""; fi
            wf-recorder -y -o "${o%@*}" $a -f "$p" >/dev/null 2>>"$log" &
            pids="$pids $!"; parts="$parts $p"; i=$((i+1))
        done
    fi
fi

printf "%s\n%s\n%s\n" "$pids" "$f" "$(date +%s)" > "$st"
code=0
for p in $pids; do wait "$p" || code=$?; done
for m in $mods; do pactl unload-module "$m"; done
rm -f "$st"

# ── several monitors: merge the parts, placed like the monitor layout ────────
if [ -n "$parts" ]; then
    notify-send -a Recording -i video-x-generic "Recording stopped" "Merging the screens…"
    inputs=""; filter=""; layout=""; i=0
    minx=""; miny=""
    for o in "$@"; do
        g=${o#*@}; x=${g%%,*}; y=$(echo "$g" | cut -d, -f2)
        [ -z "$minx" ] || [ "$x" -lt "$minx" ] && minx=$x
        [ -z "$miny" ] || [ "$y" -lt "$miny" ] && miny=$y
    done
    for o in "$@"; do
        g=${o#*@}
        x=$(echo "$g" | cut -d, -f1); y=$(echo "$g" | cut -d, -f2)
        w=$(echo "$g" | cut -d, -f3); h=$(echo "$g" | cut -d, -f4)
        filter="${filter}[$i:v]scale=$w:$h,setsar=1[v$i];"
        layout="$layout${layout:+|}$((x - minx))_$((y - miny))"
        i=$((i+1))
    done
    stack=""; j=0
    while [ $j -lt $i ]; do stack="${stack}[v$j]"; j=$((j+1)); done
    for p in $parts; do inputs="$inputs -i $p"; done
    # shellcheck disable=SC2086
    if ffmpeg -y -loglevel error $inputs -filter_complex "${filter}${stack}xstack=inputs=$i:layout=$layout:fill=black[v]" \
            -map "[v]" -map "0:a?" -c:v libx264 -preset veryfast -crf 20 -pix_fmt yuv420p -c:a aac "$f" 2>>"$log"; then
        rm -f $parts
    else
        code=1
        rm -f "$f"
        notify-send -a Recording -i dialog-error "Merging failed" "The single screens are kept:$(printf '\n%s' $parts)"
    fi
fi

if [ -s "$f" ]; then
    a=$(notify-send -a Recording -i video-x-generic -A default=Open -A folder="Open folder" "Recording saved" "$f")
    case $a in default) xdg-open "$f" ;; folder) xdg-open "${f%/*}" ;; esac
elif [ "$mode" = window ] && [ ! -e "$f" ]; then
    notify-send -a Recording -i video-x-generic "Recording cancelled" "No window was picked$(tail -n 1 "$log" | sed "s/^/ — /")"
elif [ -z "$parts" ]; then
    notify-send -a Recording -i dialog-error "Recording failed" "$(tail -n 3 "$log") (exit $code)"
fi
rm -f "$log"
