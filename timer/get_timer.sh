#!/usr/bin/bash

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"


exit_cleanup() {
    timer_pid=$(cat "$timer_pid_file" 2>/dev/null)
    if [[ -n "$timer_pid" ]]; then
        kill "$timer_pid" 2>/dev/null
        wait "$timer_pid" 2>/dev/null
        rm "$timer_pid_file"
    fi
}


# Exit cleanly on CTRL+C and system shutdown
trap exit_cleanup SIGINT SIGTERM EXIT


sound_dir="${script_dir}/sounds"


timer_pid_file="/tmp/timer.pid"

re_numbers="^[0-9]+$"


start_timer() {
    duration="$1"

    [[ "$duration" =~ $re_numbers ]] && (( duration >= 1 && duration <= 3600 )) || return

    word_list="$(mktemp /tmp/timer_word_list-XXXXXXXXXX.m3u)"

    printf "%s\n" "${sound_dir}/intro.wav" >> "$word_list"

    yes "${sound_dir}/loop.wav" | head -n "$duration" >> "$word_list"

    printf "%s\n" "${sound_dir}/spin.wav" >> "$word_list"
    printf "%s\n" "${sound_dir}/explode.wav" >> "$word_list"

    mpv \
        --audio-device=pulse/virtual_speaker \
        --audio-client-name=timer \
        --no-video \
        --gapless-audio=yes \
        --really-quiet \
        "$word_list" \
        >/dev/null 2>&1 &
    timer_pid=$!
    echo "$timer_pid" > "$timer_pid_file"
    wait "$timer_pid"
    > "$timer_pid_file"

    rm -f "$word_list"
}


# Determine mode
if [[ -n "$1" ]]; then
    # Command-line mode
    start_timer "$*"
elif ! tty -s; then
    # Streaming mode
    while IFS= read -r line; do
        start_timer "$line" &
        echo $! > "$timer_pid_file"
    done
else
    echo "Usage:"
    echo "  $0 \"<duration>\"     # Start a timer"
    echo "  echo '<duration>' | $0           # Stream from a pipe"
    exit 1
fi
