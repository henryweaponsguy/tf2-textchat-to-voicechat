#!/bin/bash

# Add '-condebug' as TF2's launch parameter.
# Alternatively, add "con_logfile <logfile location>" to autoexec.cfg
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
# Search for lines containing " :  !tts "
grep --line-buffered ' :  !tts ' |
# Convert the message to lowercase
perl -C -pe 'BEGIN { $| = 1 } $_ = lc' |
# Remove messages with blacklisted names
grep -v --line-buffered "$blacklisted_names" |
# Keep only messages with whitelisted names
grep --line-buffered "$whitelisted_names" |
# Extract the message
stdbuf -o0 sed 's/^.*: *!tts *//' |
# Remove duplicate messages
#stdbuf -o0 uniq |
# Replace repeating exclamation marks with a single one
# ("!!" repeats the last executed command in bash)
stdbuf -o0 sed 's/!\{2,\}/!/g' |
# Replace certain patterns
stdbuf -o0 sed  -e 's/btw/by the way/g' \
                -e 's/wtf/what the fuck/g' \
                -e 's/idk/i don'"'"'t know/g' |
# Remove non-ASCII and control characters
stdbuf -o0 tr -cd '[:alnum:][:space:][:punct:]' |
# Remove messages with banned words
grep --line-buffered -v "$banned_words" |
# Remove messages with excessive character repetition
grep --line-buffered -v -E '(.)\1{15}' |
# Filter lines with excessive digit repetition
#grep --line-buffered -v -E '([0-9].*){9,}' |
# Speak the result aloud
/tts/get_sapi4_voice.sh
