#!/usr/bin/bash

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"


# The audio files need to have the same parameters (channel count, codec, sample rate),
# otherwise the output audio will come out corrupted
sound_dir="${script_dir}/sounds"


timer_pid_file="/tmp/timer.pid"

re_numbers="^[0-9]+$"


start_timer() {
    >"$word_list"

    duration="$1"

    [[ "$duration" =~ $re_numbers ]] && (( duration >= 1 && duration <= 3600 )) || return

    audio_file="$(mktemp /tmp/timer_voice-XXXXXXXXXX.wav)"
    word_list="$(mktemp /tmp/timer_word_list-XXXXXXXXXX.txt)"

    echo "file '${sound_dir}/intro.wav'" >> "$word_list"

    yes "file '${sound_dir}/loop.wav'" | head -n "$duration" >> "$word_list"

    echo "file '${sound_dir}/spin.wav'" >> "$word_list"
    echo "file '${sound_dir}/explode.wav'" >> "$word_list"

    ffmpeg \
        -hide_banner \
        -loglevel error \
        -f concat \
        -safe 0 \
        -i "$word_list" \
        -c copy \
        -y \
        "$audio_file"

    paplay --device=virtual_speaker --client-name=timer "$audio_file" >/dev/null 2>&1 &
    timer_pid=$!
    echo "$timer_pid" > "$timer_pid_file"
    wait "$timer_pid"
    > "$timer_pid_file"

    rm -f "$audio_file" "$word_list"
}


# Determine mode
if [[ -n "$1" ]]; then
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
