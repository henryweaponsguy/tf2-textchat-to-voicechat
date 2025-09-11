#!/bin/bash

voices=(m1 m2 m3 m4 m5 m6 m7 f1 f2 f3 f4)


speak_text() {
    local input_text="$1"
    [[ -z "$input_text" ]] && return

    audio_file="$(mktemp /tmp/espeak_voice-XXXXXXXXXX.wav)"

    #espeak -v en+m5 -w "$audio_file" "$input_text"
    espeak -v "en+$(shuf -n1 -e "${voices[@]}")" -w "$audio_file" "$input_text"

    (
        paplay --client-name=espeak "$audio_file" >/dev/null 2>&1
        rm -f "$audio_file"
    ) &
}


# Determine mode
if [ -n "$1" ]; then
    # Command-line mode
    speak_text "$*"
elif ! tty -s; then
    # Streaming mode
    while IFS= read -r line; do
        speak_text "$line"
    done
else
    echo "Usage:"
    echo "  $0 \"Your text here\"     # Speak single line"
    echo "  echo 'text' | $0           # Stream from pipe"
    exit 1
fi
