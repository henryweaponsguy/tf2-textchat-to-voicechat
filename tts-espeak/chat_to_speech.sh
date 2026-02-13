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

# Word blacklist:
# Example: "nominate\|rtv\|nextmap"
# Default: "$^"
blacklisted_words="$^"


# Continuously read the last line of the log as it is updated
stdbuf -oL tail -fn 1 "$console_log" |
# Search for lines containing the command
grep --line-buffered "^\(\*DEAD\*\)\?\((TEAM)\)\? \?.\+ :  !tts " |
# Remove messages from blacklisted players
grep --line-buffered -v "^\(\*DEAD\*\)\?\((TEAM)\)\? \?${blacklisted_names} :  !" |
# Keep messages only from whitelisted players
grep --line-buffered "^\(\*DEAD\*\)\?\((TEAM)\)\? \?${whitelisted_names} :  !" |
# Sanitize the message
stdbuf -o0 sed 's/[$;`()\\]//g' |
# Extract the message
stdbuf -o0 sed 's/^\(\*DEAD\*\)\?\((TEAM)\)\? \?.\+ :  ![a-zA-Z0-9_]\+ *//' |
# Replace certain patterns
stdbuf -o0 sed  -e 's/btw/by the way/gI' \
                -e 's/wtf/what the fuck/gI' \
                -e 's/idk/i don'\''t know/gI' |
# Remove messages with blacklisted words
grep --line-buffered -iv "$blacklisted_words" |
# Remove messages with excessive repetition
grep --line-buffered -Ev '(.{2,})\1{5,}' |
# Remove non-ASCII and control characters
stdbuf -o0 tr -cd '[:alnum:][:space:][:punct:]' |
# Trim and normalize whitespace
stdbuf -o0 sed 's/^ \+//g; s/ \+$//g; s/ \+/ /g;' |
# Remove duplicate messages
#stdbuf -o0 uniq |
# Speak the result aloud
/tts/get_espeak_voice.sh
