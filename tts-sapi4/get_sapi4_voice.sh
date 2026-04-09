#!/bin/bash

sapi4_server="http://127.0.0.1:5491"

voices=(
    "Adult%20Female%20%231%2C%20American%20English%20(TruVoice)"
    "Adult%20Female%20%232%2C%20American%20English%20(TruVoice)"
    "Adult%20Male%20%231%2C%20American%20English%20(TruVoice)"
    "Adult%20Male%20%232%2C%20American%20English%20(TruVoice)"
    "Adult%20Male%20%233%2C%20American%20English%20(TruVoice)"
    "Mary"
    "Mike"
    "Sam"
)


speak_text() {
    input_text="$1"
    [[ -z "$input_text" ]] && return

    encoded_text=$(printf '%s' "$input_text" | jq -sRr @uri)

    audio_file="$(mktemp /tmp/sapi4_voice-XXXXXXXXXX.wav)"

    # BonziBUDDY voice
    #voice="Adult%20Male%20%232%2C%20American%20English%20(TruVoice)"
    #pitch="140"
    #speed="157"

    # Microsoft Sam voice
    #voice="Sam"
    #pitch="100"
    #speed="150"

    # A random voice (with a random pitch and speed) from the 'voices' array
    voice=${voices[RANDOM % ${#voices[@]}]}

    case "$voice" in
        "Mary") min_pitch="90" ;;
        "Mike") min_pitch="60" ;;
        *) min_pitch="50" ;;
    esac

    pitch=$(( (RANDOM % 16) * 10 + ${min_pitch} ))
    speed=$(( (RANDOM % 6) * 10 + 130 ))


    curl "${sapi4_server}/SAPI4/SAPI4?text=${encoded_text}\
&voice=${voice}\
&pitch=${pitch}\
&speed=${speed}" \
    --silent --show-error --output "${audio_file}"

    (
        paplay --client-name=sapi4 "$audio_file" >/dev/null 2>&1
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
    echo "  echo 'text' | $0          # Stream from a pipe"
    exit 1
fi
