#!/bin/bash

sound_dir="/tts/sounds"


play_audio() {
    while IFS= read -r line; do
        # Trim whitespace
        clean_line=$(echo "$line" | xargs)

        # Match files
        shopt -s nullglob
        matches=(
            "$sound_dir/$clean_line".*
            "$sound_dir/$clean_line "[0-9]*.*
        )
        shopt -u nullglob

        if [[ ${#matches[@]} -gt 0 ]]; then
            selected="${matches[RANDOM % ${#matches[@]}]}"

            paplay --client-name=soundboard "$selected" >/dev/null 2>&1 &
        fi
    done
}


# Add '-condebug' as TF2's launch parameter.
# Alternatively add "con_logfile <logfile location>" to autoexec.cfg
# e.g. "con_logfile console.log". This will create a console.log file in the tf/ directory
console_log="/tts/console.log"

# User blacklist:
# Example: "John\|pablo.gonzales.2007\|Engineer Gaming"
# Default: "$^"
blacklisted_names="$^"

# Alternatively, a whitelist:
# Example: "John\|pablo.gonzales.2007\|Engineer Gaming"
# Default: ".*"
whitelisted_names=".*"

# Word blacklist (all words must be in lowercase):
# Example: "nominate\|rtv\|nextmap"
# Default: "$^"
blacklisted_words="$^"


# Continuously read the last line of the log as it is updated
stdbuf -oL tail -fn 1 "$console_log" |
# Search for lines containing the command
#grep --line-buffered ' :  !play ' |
grep --line-buffered ' :  ' |
# Remove messages from blacklisted players
# grep --line-buffered -v "^\(\*DEAD\*\)\?\((TEAM)\)\? \?${blacklisted_names} :  !" |
grep --line-buffered -v "^\(\*DEAD\*\)\?\((TEAM)\)\? \?${blacklisted_names} :  " |
# Keep messages only from whitelisted players
# grep --line-buffered "^\(\*DEAD\*\)\?\((TEAM)\)\? \?${whitelisted_names} :  !" |
grep --line-buffered "^\(\*DEAD\*\)\?\((TEAM)\)\? \?${whitelisted_names} :  " |
# Sanitize the message
stdbuf -o0 sed 's/[$;`()]//g' |
# Convert the message to lowercase
perl -C -pe 'BEGIN { $| = 1 } $_ = lc' |
# Extract the message
#stdbuf -o0 sed 's/^.* :  ![a-zA-Z0-9_]\+ *//' |
stdbuf -o0 sed 's/^.* :  *//' |
# Remove duplicate messages
#stdbuf -o0 uniq |
# Remove non-ASCII and control characters
stdbuf -o0 tr -cd '[:alnum:][:space:][:punct:]' |
# Remove messages with banned words
grep --line-buffered -v "$blacklisted_words" |
# Play the audio file
play_audio
