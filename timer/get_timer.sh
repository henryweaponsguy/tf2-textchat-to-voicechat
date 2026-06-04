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
}

# Exit cleanly on CTRL+C and system shutdown
trap exit_cleanup SIGINT SIGTERM EXIT


sound_dir="${script_dir}/sounds"
word_list="${script_dir}/word_list.txt"
timer_pid_file="/tmp/timer.pid"
timer_running_state_file="/tmp/timer.running"


start_timer() {
    if [ -e "$timer_running_state_file" ]; then
        trap - SIGINT SIGTERM EXIT
        return
    fi

    touch "$timer_running_state_file"
    >"$word_list"

    duration="$1"

    [[ "$duration" =~ ^[0-9]+$ ]] && (( duration >= 1 && duration <= 3600 )) || return

    echo "file '${sound_dir}/intro.wav'" >> "$word_list"

    {
        for ((i=0; i<duration; i++)); do
            printf "file '%s/loop.wav'\n" "$sound_dir"
        done
    } >> "$word_list"

    echo "file '${sound_dir}/spin.wav'" >> "$word_list"
    echo "file '${sound_dir}/explode.wav'" >> "$word_list"

    audio_file="$(mktemp /tmp/timer_voice-XXXXXXXXXX.wav)"

    ffmpeg -hide_banner -loglevel error -f concat -safe 0 -i "$word_list" \
        -ar 22050 -ac 1 -c copy -y "$audio_file"

    paplay --device=virtual_speaker --client-name=timer "$audio_file" >/dev/null 2>&1
    rm -f "$audio_file" "$word_list" "$timer_running_state_file"
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
