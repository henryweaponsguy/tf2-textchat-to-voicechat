#!/bin/bash

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"


exit_cleanup() {
    if [ -e "$timer_running_state_file" ]; then
        rm "$timer_running_state_file"
    fi

    timer_pid=$(cat "$timer_pid_file" 2>/dev/null)
    if [ -n "$timer_pid" ]; then
        kill "$timer_pid" 2>/dev/null
        wait "$timer_pid" 2>/dev/null
        rm "$timer_pid_file"
    fi

    if [ -e "$timer_socket" ]; then
        rm "$timer_socket"
    fi
}

# Exit cleanly on CTRL+C and system shutdown
trap exit_cleanup SIGINT SIGTERM EXIT


sound_dir="${script_dir}/sounds"
timer_pid_file="/tmp/timer.pid"
timer_running_state_file="/tmp/timer.running"
timer_socket="/tmp/timer.socket"

IFS=$'\t' read intro_duration < <(
    ffprobe \
        -v error \
        -select_streams a:0 \
        -show_entries \
        format=duration \
        -of json \
        "${sound_dir}/intro.wav" |
    jq -r '[.format.duration] | @tsv'
)

start_timer() {
    if [ -e "$timer_running_state_file" ]; then
        trap - SIGINT SIGTERM EXIT
        return
    fi

    touch "$timer_running_state_file"

    duration="$1"

    [[ "$duration" =~ ^[0-9]+$ ]] && (( duration >= 1 && duration <= 3600 )) || return

    mpv \
        --audio-device=pulse/virtual_speaker \
        --no-video \
        --gapless-audio=yes \
        --idle=yes \
        --input-ipc-server="$timer_socket" \
        --really-quiet \
        >/dev/null 2>&1 &
    echo $! > "$timer_pid_file"

    # Wait for mpv to start
    sleep 0.2

    # Play intro once
    echo '{ "command": ["loadfile", "'"${sound_dir}/intro.wav"'", "replace"] }' |
        socat - "$timer_socket" >/dev/null 2>&1

    # Queue loop to start immediately after intro
    echo '{ "command": ["loadfile", "'"${sound_dir}/loop.wav"'", "append-play"] }' |
        socat - "$timer_socket" >/dev/null 2>&1

    sleep "$(awk -v a="$intro_duration" 'BEGIN {print a+0.1}')"

    # Enable looping
    echo '{ "command": ["set_property", "loop-file", "inf"] }' |
        socat - "$timer_socket" >/dev/null 2>&1

    sleep "$(awk -v a="$duration" 'BEGIN {print a-1}')"

    # Play outro
    echo '{ "command": ["loadfile", "'"${sound_dir}/spin.wav"'", "append-play"] }' |
    socat - "$timer_socket" >/dev/null 2>&1

    echo '{ "command": ["loadfile", "'"${sound_dir}/explode.wav"'", "append-play"] }' |
    socat - "$timer_socket" >/dev/null 2>&1

    # Disable looping
    echo '{ "command": ["set_property", "loop-file", "no"] }' |
        socat - "$timer_socket" >/dev/null 2>&1

    # Wait until mpv finishes playing the outro
    while echo '{ "command": ["get_property", "playback-time"] }' |
        socat - "$timer_socket" 2>/dev/null |
        grep -q '"data"'
    do
        sleep 0.1
    done

    # Quit mpv
    echo '{ "command": ["quit"] }' |
        socat - "$timer_socket" >/dev/null 2>&1

    rm -f "$timer_running_state_file"
}


# Determine mode
if [ -n "$1" ]; then
    # Command-line mode
    start_timer "$*"
elif ! tty -s; then
    # Streaming mode
    while IFS= read -r line; do
        start_timer "$line" &
    done
else
    echo "Usage:"
    echo "  $0 \"<duration>\"     # Start a timer"
    echo "  echo '<duration>' | $0           # Stream from a pipe"
    exit 1
fi
