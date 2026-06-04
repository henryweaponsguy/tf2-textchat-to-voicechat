#!/bin/bash

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

sound_dir="${script_dir}/sounds"
piper_server="http://localhost:5000"
username_voices_file="${script_dir}/username_voices.txt"

if [ ! -f "$username_voices_file" ]; then
    touch "$username_voices_file"
fi

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


# Add '-condebug' to TF2's launch parameters.
# Alternatively, add "con_logfile <logfile location>" to TF2's autoexec.cfg,
# e.g. "con_logfile console.log". This will create a console.log file in the tf/ directory
console_log="${script_dir}/console.log"

# User blacklist:
# Example: "John\|pablo.gonzales.2007\|Engineer Gaming"
blacklisted_names=""

# Alternatively, a whitelist:
whitelisted_names=""

# Word blacklist:
# Example: "nominate\|rtv\|nextmap"
blacklisted_words=""


while IFS= read -r line; do
    username=$(sed -n 's/^\(\*DEAD\*\|\*SPEC\*\)\?\((TEAM)\)\? \?\(.\+\) : .\+/\3/p' <<< "$line")
    #text=$(sed 's/^\(\*DEAD\*\|\*SPEC\*\)\?\((TEAM)\)\? \?.\+ : ![a-zA-Z0-9_]\+ \(.\+\)/\3/' <<< "$line")
    text=$(sed -n 's/^\(\*DEAD\*\|\*SPEC\*\)\?\((TEAM)\)\? \?.\+ : \(.\+\)/\3/p' <<< "$line")

    [[ -z "$text" ]] && continue


    shopt -s nullglob
    matched_files=(
        "$sound_dir/${text,,}".*
        "$sound_dir/${text,,} "[0-9]*.*
    )
    shopt -u nullglob

    # Skip the message if a soundboard sound exists
    if [[ ${#matched_files[@]} -gt 0 ]]; then
        continue
    fi

    audio_file="$(mktemp /tmp/piper_voice-XXXXXXXXXX.wav)"

    if ! grep -Fq "$(printf '%s\t' "$username")" "$username_voices_file"; then
        # A random voice (with a random speed) from the 'voices' array
        voice=${voices[RANDOM % ${#voices[@]}]}

        length_scale="$(printf "%.1f" "$(echo "0.8 + ($RANDOM % 6) * 0.1" | bc)")"

        # Some models support multiple voices
        speakers=""
        speaker=""
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
            speaker="${speakers[RANDOM % ${#speakers[@]}]}"
        fi

        printf '%s\t%s\t%s\t%s\n' "$username" "$voice" "$length_scale" "${speaker:-}" >> "$username_voices_file"
    else
        username_voice=$(grep -F "$username" "$username_voices_file")
        IFS=$'\t' read -r username voice length_scale speaker <<< "$username_voice"
    fi

    if [[ -n "$speaker" ]]; then
        data="$(
cat <<EOF
{
    "text": "$text",
    "voice": "$voice",
    "speaker": "$speaker",
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
        #paplay --device=virtual_speaker --client-name=piper "$audio_file" >/dev/null 2>&1
        paplay --client-name=piper "$audio_file" >/dev/null 2>&1
        rm -f "$audio_file"
    ) &
done < <(
    # Continuously read the last line of the log as it is updated
    stdbuf -oL tail -fn 1 "$console_log" |
    # Search for lines containing the command
    #grep --line-buffered "^\(\*DEAD\*\|\*SPEC\*\)\?\((TEAM)\)\? \?.\+ :  !pip" |
    grep --line-buffered "^\(\*DEAD\*\|\*SPEC\*\)\?\((TEAM)\)\? \?.\+ :  " |
    # Remove messages from blacklisted players
    #grep --line-buffered -v "^\(\*DEAD\*\|\*SPEC\*\)\?\((TEAM)\)\? \?${blacklisted_names:-$^} :  !" |
    grep --line-buffered -v "^\(\*DEAD\*\|\*SPEC\*\)\?\((TEAM)\)\? \?${blacklisted_names:-$^} :  " |
    # Keep messages only from whitelisted players
    #grep --line-buffered "^\(\*DEAD\*\|\*SPEC\*\)\?\((TEAM)\)\? \?${whitelisted_names:-.*} :  !" |
    grep --line-buffered "^\(\*DEAD\*\|\*SPEC\*\)\?\((TEAM)\)\? \?${whitelisted_names:-.*} :  " |
    # Replace certain patterns
    stdbuf -o0 sed  -e 's/btw/by the way/gI' \
                    -e 's/wtf/what the fuck/gI' \
                    -e 's/( ͡° ͜ʖ ͡°)/lenny face/gI' \
                    -e 's/idk/i don'\''t know/gI' |
    # Remove messages with blacklisted words
    grep --line-buffered -iv "${blacklisted_words:-$^}" |
    # Remove messages with excessive repetition
    grep --line-buffered -Pv '(.{2,})\1{5,}' |
    # Remove non-ASCII and control characters
    stdbuf -o0 tr -cd '[:alnum:][:space:][:punct:]' |
    # Trim and normalize whitespace
    stdbuf -o0 sed 's/^ \+//g; s/ \+$//g; s/ \+/ /g;'
    # Remove duplicate messages
    #| stdbuf -o0 uniq
)
