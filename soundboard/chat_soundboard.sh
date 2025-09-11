#!/bin/bash

sound_dir="/tts/sounds"

play_audio() {
    while IFS= read -r line; do
        # Trim whitespace
        clean_line=$(echo "$line" | xargs)

        # Match files
        shopt -s nullglob
        matches=(
            "$sound_dir/$clean_line."*
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

# Example: blacklisted_names="name1\|name2\|name3"
# Default: blacklisted_names="$^"
blacklisted_names="$^"

# Alternatively, a whitelist:
# Example: whitelisted_names="name1\|name2\|name3"
# Default: whitelisted_names=".*"
whitelisted_names=".*"

# Example: banned_words="nominate\|rtv\|nextmap"
# Default: banned_words="$^"
banned_words="$^"


# Continuously read the last line of the log as it is updated
stdbuf -oL tail -f -n 1 "$console_log" |
# Sanitize the message
stdbuf -o0 sed 's/["'\''$&|;`\\()]//g' |
# Search for lines containing " :  !play "
#grep --line-buffered ' :  !play ' |
grep --line-buffered ' :  ' |
# Convert the message to lowercase
perl -C -pe 'BEGIN { $| = 1 } $_ = lc' |
# Remove messages with blacklisted names
grep -v --line-buffered "$blacklisted_names" |
# Keep only messages with whitelisted names
grep --line-buffered "$whitelisted_names" |
# Extract the message
#stdbuf -o0 sed 's/^.*: *!play *//' |
stdbuf -o0 sed 's/^.*: * *//' |
# Remove duplicate messages
#stdbuf -o0 uniq |
# Replace repeating exclamation marks with a single one
# ("!!" repeats the last executed command in bash)
stdbuf -o0 sed 's/!\{2,\}/!/g' |
# Remove non-ASCII and control characters
stdbuf -o0 tr -cd '[:alnum:][:space:][:punct:]' |
# Remove messages with banned words
grep --line-buffered -v "$banned_words" |
# Play the audio file
play_audio
