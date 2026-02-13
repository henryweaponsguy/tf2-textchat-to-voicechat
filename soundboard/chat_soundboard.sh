#!/bin/bash

# Soundboard sounds directory
sound_dir="/tts/sounds"

# Add '-condebug' to TF2's launch parameters.
# Alternatively add "con_logfile <logfile location>" to TF2's autoexec.cfg,
# e.g. "con_logfile console.log". This will create a console.log file in the tf/ directory
console_log="/tts/console.log"

# User blacklist:
# Example: "John\|pablo.gonzales.2007\|Engineer Gaming"
# Empty: "$^"
blacklisted_names="$^"

# Alternatively, a whitelist:
# Example: "John\|pablo.gonzales.2007\|Engineer Gaming"
# Empty: ".*"
whitelisted_names=".*"

# Word blacklist:
# Example: "nominate\|rtv\|nextmap"
# Empty: "$^"
blacklisted_words="$^"


# Continuously read the last line of the log as it is updated
stdbuf -oL tail -fn 1 "$console_log" |
# Search for lines containing the command
#grep --line-buffered "^\(\*DEAD\*\)\?\((TEAM)\)\? \?.\+ :  !play " |
grep --line-buffered "^\(\*DEAD\*\)\?\((TEAM)\)\? \?.\+ :  " |
# Remove messages from blacklisted players
#grep --line-buffered -v "^\(\*DEAD\*\)\?\((TEAM)\)\? \?${blacklisted_names} :  !" |
grep --line-buffered -v "^\(\*DEAD\*\)\?\((TEAM)\)\? \?${blacklisted_names} :  " |
# Keep messages only from whitelisted players
#grep --line-buffered "^\(\*DEAD\*\)\?\((TEAM)\)\? \?${whitelisted_names} :  !" |
grep --line-buffered "^\(\*DEAD\*\)\?\((TEAM)\)\? \?${whitelisted_names} :  " |
# Sanitize the message
stdbuf -o0 sed 's/[$;`()\\]//g' |
# Extract the message
#stdbuf -o0 sed 's/^\(\*DEAD\*\)\?\((TEAM)\)\? \?.\+ :  ![a-zA-Z0-9_]\+ *//' |
stdbuf -o0 sed 's/^\(\*DEAD\*\)\?\((TEAM)\)\? \?.\+ :  *//' |
# Convert the message to lowercase
perl -C -pe 'BEGIN { $| = 1 } $_ = lc' |
# Remove messages with blacklisted words
grep --line-buffered -iv "$blacklisted_words" |
# Remove non-ASCII and control characters
stdbuf -o0 tr -cd '[:alnum:][:space:][:punct:]' |
# Trim and normalize whitespace
stdbuf -o0 sed 's/^ \+//g; s/ \+$//g; s/ \+/ /g;' |
# Remove duplicate messages
#stdbuf -o0 uniq |
# Play the audio file
while IFS= read -r line; do
    # Match files
    shopt -s nullglob
    matched_files=(
        "$sound_dir/$line".*
        "$sound_dir/$line "[0-9]*.*
    )
    shopt -u nullglob

    if [[ ${#matched_files[@]} -gt 0 ]]; then
        selected_file="${matched_files[RANDOM % ${#matched_files[@]}]}"

        paplay --client-name=soundboard "$selected_file" >/dev/null 2>&1 &
    fi
done
