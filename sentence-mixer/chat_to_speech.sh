#!/bin/bash

# Add '-condebug' as TF2's launch parameter.
# Alternatively, add "con_logfile <logfile location>" to autoexec.cfg
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
grep --line-buffered ' :  !mix ' |
# Remove messages from blacklisted players
grep --line-buffered -v "^\(\*DEAD\*\)\?\((TEAM)\)\? \?${blacklisted_names} :  !" |
# Keep messages only from whitelisted players
grep --line-buffered "^\(\*DEAD\*\)\?\((TEAM)\)\? \?${whitelisted_names} :  !" |
# Sanitize the message
stdbuf -o0 sed 's/[$;`()\\]//g' |
# Convert the message to lowercase
perl -C -pe 'BEGIN { $| = 1 } $_ = lc' |
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
# Remove messages with blacklisted words
grep --line-buffered -v "$blacklisted_words" |
# Remove messages with excessive repetition
grep --line-buffered -Ev '(.{2,})\1{5,}' |
# Speak the result aloud
/tts/get_sentencemixed_voice.sh
