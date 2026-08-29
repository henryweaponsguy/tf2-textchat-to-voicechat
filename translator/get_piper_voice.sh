#!/bin/bash

piper_server="http://tf2-translator-tts:5000/synthesize"


speak_text() {
    text="$1"
    [[ -z "$text" ]] && return

    audio_file="$(mktemp /tmp/piper_voice-XXXXXXXXXX.wav)"

    data="$(
cat <<EOF
{
    "text": "$text",
    "voice": "en_US-joe-medium",
    "length_scale": "1"
}
EOF
)"

    curl -X POST -H "Content-Type: application/json" --data "$data" \
    --silent --show-error --output "$audio_file" "$piper_server"

    (
        #paplay --device=virtual_speaker --client-name=piper "$audio_file" >/dev/null 2>&1
        paplay --client-name=piper "$audio_file" >/dev/null 2>&1
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
