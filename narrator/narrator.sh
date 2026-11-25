#!/usr/bin/bash

shopt -s nullglob

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"


# Download voices by running: python3 -m piper.download_voices --data-dir "models/" <model name, e.g. en_US-joe-medium>
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
# Example: "John|pablo\.gonzales\.2007|Engineer Gaming"
blacklisted_users=""

# Alternatively, a whitelist:
whitelisted_users=""

# Word blacklist:
# Example: "nominate|rtv|nextmap"
blacklisted_words=""


username_voices_file="${script_dir}/username_voices.txt"

touch "$username_voices_file"

sound_dir="${script_dir}/sounds"
piper_server="http://127.0.0.1:5000/synthesize"
previous_line=""

re_line="^(\*DEAD\*|\*SPEC\*)?(\(TEAM\))? ?(.+) :   *(.+)"
re_blacklisted_users="${blacklisted_users:-$^}"
re_whitelisted_users="${whitelisted_users:-.*}"
re_blacklisted_words="${blacklisted_words:-$^}"
re_repetition="(.{2,})\1{5,}"

replacements=(
    -e "s/btw/by the way/gI"
    -e 's/wtf/what the fuck/gI'
    -e "s/idk/i don't know/gI"
)


while IFS= read -r line; do
    # Search for lines containing a message
    if [[ "$line" =~ $re_line ]]; then
        # Extract the username and the message
        username="${BASH_REMATCH[3]}"
        message="${BASH_REMATCH[4]}"
    else
        continue
    fi

    # Remove messages from blacklisted players
    if [[ "$username" =~ $re_blacklisted_users ]]; then
        continue
    fi

    # Keep messages only from whitelisted players
    if [[ ! "$username" =~ $re_whitelisted_users ]]; then
        continue
    fi

    # Remove duplicate messages
#     if [[ "$line" == "$previous_line" ]]; then
#         continue
#     fi
#     previous_line="$line"

    # Remove messages with blacklisted words
    shopt -s nocasematch
    if [[ "$message" =~ $re_blacklisted_words ]]; then
        continue
    fi
    shopt -u nocasematch

    # Replace certain patterns
    message="$(sed "${replacements[@]}" <<< "$message")"

    # Remove messages with excessive repetition
    if grep -Pq "$re_repetition" <<< "$message"; then
        continue
    fi

    # Remove non-ASCII and control characters
    message="$(LC_ALL=C tr -cd '[:alnum:][:space:][:punct:]' <<< "$message")"

    [[ -z "$message" ]] && continue

    # Convert the message to lowercase
    sound_file="${message,,}"

    # Trim and normalize whitespace
    sound_file="$(sed 's/^ \+//g; s/ \+$//g; s/ \+/ /g;' <<< "$sound_file")"

    matched_files=(
        "$sound_dir/${sound_file}".*
        "$sound_dir/${sound_file} "[0-9]*.*
    )

    # Skip the message if a soundboard sound exists
    if (( ${#matched_files[@]} )); then
        continue
    fi

    audio_file="$(mktemp /tmp/piper_voice-XXXXXXXXXX.wav)"

    if ! grep -Fq "$(printf "%s\t" "$username")" "$username_voices_file"; then
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
        username_voice=$(grep -F "$(printf "%s\t" "$username")" "$username_voices_file")
        IFS=$'\t' read -r username voice length_scale speaker <<< "$username_voice"
    fi

    if [[ -n "$speaker" ]]; then
        data="$(
cat <<EOF
{
    "text": "$message",
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
    "text": "$message",
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
# Continuously read the last line of the log as it is updated
done < <(tail -fn 1 "$console_log")
