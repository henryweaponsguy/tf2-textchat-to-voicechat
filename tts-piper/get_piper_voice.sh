#!/bin/bash

piper_server="http://localhost:5000"

# Download voices by running: python3 -m piper.download_voices --data-dir "models/" <model name, e.g. en_US-alan-medium>
# Or download them here: https://rhasspy.github.io/piper-samples
voices=(
    "en_GB-alan-medium"
    "en_GB-alba-medium"
    "en_GB-northern_english_male-medium"
    "en_US-amy-medium"
    "en_US-hfc_female-medium"
    "en_US-hfc_male-medium"
    # Lower quality voices:
    "en_GB-aru-medium"          # multi speaker
    "en_GB-semaine-medium"      # multi speaker
    "en_US-joe-medium"
    "en_US-lessac-high"         # female
)


speak_text() {
    text="$1"
    [[ -z "$text" ]] && return

    audio_file="$(mktemp /tmp/piper_voice-XXXXXXXXXX.wav)"

    # Default voice
    #voice="en_GB-alan-medium"
    #length_scale=1

    # A random voice (with a random speed) from the 'voices' array
    voice=${voices[RANDOM % ${#voices[@]}]}

    length_scale="$(printf "%.1f" "$(echo "0.7 + ($RANDOM % 8) * 0.1" | bc)")"

    # Some models support multiple voices
    speakers=""
    if [[ "$voice" == "en_GB-aru-medium" ]]; then
        speakers=(
            "03" # female
            "04" # female
            "07" # female
            "08" # female
            "10" # male
        )
    elif [[ "$voice" == "en_GB-semaine-medium" ]]; then
        speakers=(
            "poppy"     # female
            "prudence"
            "spike"     # male
        )
    fi

    if [[ -n "$speakers" ]]; then
        data="$(
cat <<EOF
{
    "text": "$text",
    "voice": "$voice",
    "speaker": "${speakers[RANDOM % ${#speakers[@]}]}",
    "length_scale": "$length_scale"
}
EOF
)"
    else
        data="$(
cat <<EOF
{
    "text": "$text",
    "voice": "$voice",
    "length_scale": "$length_scale"
}
EOF
)"
    fi

    curl -X POST -H "Content-Type: application/json" --data "$data" \
    --silent --show-error --output "$audio_file" "$piper_server"

    (
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
