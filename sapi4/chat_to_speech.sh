#!/bin/bash

# Add '-condebug' as TF2's launch parameter.
# Alternatively, add "con_logfile <logfile location>" to autoexec.cfg
# e.g. "con_logfile console.log". This will create a console.log file in the tf/ directory
console_log="/tts/console.log"

# Example: "John\|pablo.gonzales.2007\|Engineer Gaming"
# Default: "$^"
blacklisted_names="$^"

# Alternatively, a whitelist:
# Example: "John\|pablo.gonzales.2007\|Engineer Gaming"
# Default: ".*"
whitelisted_names=".*"

# All words must be in lowercase
# Example: "nominate\|rtv\|nextmap"
# Default: "$^"
banned_words="$^"


# Continuously read the last line of the log as it is updated
stdbuf -oL tail -fn 1 "$console_log" |
# Sanitize the message
stdbuf -o0 sed 's/["'\''$&|;`\\()]//g' |
# Search for lines containing the command
grep --line-buffered ' :  !tts ' |
# Remove messages from blacklisted players
grep --line-buffered -v "^${blacklisted_names} :  !" |
# Keep messages only from whitelisted players
grep --line-buffered "^${whitelisted_names} :  !" |
# Convert the message to lowercase
perl -C -ep 'BEGIN { $| = 1 } $_ = lc' |
# Extract the message
stdbuf -o0 sed 's/^.* :  ![a-zA-Z0-9_]\+ *//' |
# Remove duplicate messages
#stdbuf -o0 uniq |
# Replace certain patterns
stdbuf -o0 sed  -e 's/btw/by the way/g' \
                -e 's/wtf/what the fuck/g' \
                -e 's/idk/i don'\''t know/g' |
# Remove non-ASCII and control characters
stdbuf -o0 tr -cd '[:alnum:][:space:][:punct:]' |
# Remove messages with banned words
grep --line-buffered -v "$banned_words" |
# Remove messages with excessive character repetition
grep --line-buffered -Ev '(.)\1{15}' |
# Remove messages with excessive digit repetition
#grep --line-buffered -Ev '([0-9].*){9,}' |
# Speak the result aloud
/tts/get_sapi4_voice.sh
