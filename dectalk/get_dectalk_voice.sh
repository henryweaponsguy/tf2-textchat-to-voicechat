#!/bin/bash

voices=("PAUL" "HARRY" "FRANK" "DENNIS" "BETTY" "URSULA" "RITA")


speak_text() {
    input_text="$1"
    [[ -z "$input_text" ]] && return

    audio_file="$(mktemp /tmp/dectalk_voice-XXXXXXXXXX.wav)"

    #say -pre "[:phoneme on]" -e 1 -a "$input_text" -fo "$audio_file"
    say -pre "[:name ${voices[RANDOM % ${#voices[@]}]}][:phoneme on]" -e 1 -a "$input_text" -fo "$audio_file"

    (
        paplay --client-name=dectalk "$audio_file" >/dev/null 2>&1
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
    echo "  $0 \"Your text here\"     # Speak a single line"
    echo "  echo 'text' | $0           # Stream from a pipe"
    exit 1
fi
